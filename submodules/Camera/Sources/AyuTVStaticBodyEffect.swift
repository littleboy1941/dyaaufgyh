import Foundation
import CoreImage
import CoreVideo
import Metal
import Vision

// AyuGram: "TV static" over the whole person, front camera (port of
// RoundLab `TVStaticBodyEffect.fast`, build 43). Apple person segmentation
// finds everyone in the frame, the silhouette is filled with TV snow,
// blown out at the top of the head and thinning towards the bottom, with
// a glow over the edge; the room stays as it is. The mask of each frame
// is held while it fades out (one-frame holes never show the person);
// whatever moved since the last frame close to the person is covered too
// (a blurred hand the segmentation lost); the mask is grown more around
// each head (hair). Segmentation or GPU failure covers the whole frame.
// Works on the 400x400 square of the round. Called from the camera's
// video queue only.
@available(iOS 15.0, *)
final class AyuTVStaticBodyEffect {
    private let mask = AyuPersonMask()
    var motion = true
    var headGrow: CGFloat = 0.07      // extra dilation around a head, of the face width
    var grow: CGFloat = 0.01          // mask dilation, of the frame width
    var glow: Double = 0.45           // glow strength
    var glowRadius: CGFloat = 0.02    // glow sigma, of the frame width

    func apply(to image: CIImage, faces: [CGRect], time: Double) -> CIImage {
        let extent = image.extent
        guard var person = self.mask.mask(image) else {
            return AyuRoundEffects.covered(image)
        }
        if self.motion, let moving = self.mask.motion(image, near: person) {
            person = moving.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: person])
        }
        if self.headGrow > 0.0 {
            for face in faces {
                let head = face
                    .insetBy(dx: -face.width * 0.45, dy: -face.height * 0.35)
                    .offsetBy(dx: 0.0, dy: face.height * 0.2)
                let wider = person.clampedToExtent()
                    .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: max(2.0, face.width * self.headGrow)])
                    .cropped(to: head.intersection(extent))
                person = wider.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: person])
            }
        }
        let personMask = person.cropped(to: extent)
        // Exposure runs from the top of the head (above the highest face,
        // or the top of the frame) down to the bottom of the frame.
        let top = faces.map { $0.maxY + $0.height * 0.35 }.max().map { min($0, extent.maxY) } ?? extent.maxY
        let span = CGRect(x: extent.minX, y: extent.minY, width: extent.width, height: top - extent.minY)
        guard let snow = AyuTVStaticGPU.shared.run(size: extent.size, face: span, time: time)?
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY)) else {
            return AyuRoundEffects.covered(image)
        }
        let soft = personMask.clampedToExtent()
            .applyingFilter("CIMorphologyMaximum", parameters: [
                kCIInputRadiusKey: max(2.0, extent.width * self.grow)
            ])
            .applyingGaussianBlur(sigma: 1.0)
            .cropped(to: extent)
        let black = CIImage(color: .black).cropped(to: extent)
        let masked = snow.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: black,
            kCIInputMaskImageKey: soft
        ])
        let halo = masked.clampedToExtent()
            .applyingGaussianBlur(sigma: Double(max(extent.width * self.glowRadius, 2.0)))
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: CGFloat(self.glow) * 0.9, y: 0.0, z: 0.0, w: 0.0),
                "inputGVector": CIVector(x: 0.0, y: CGFloat(self.glow) * 0.95, z: 0.0, w: 0.0),
                "inputBVector": CIVector(x: 0.0, y: 0.0, z: CGFloat(self.glow), w: 0.0)
            ])
            .cropped(to: extent)
        return snow.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: image,
            kCIInputMaskImageKey: soft
        ])
        .applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: halo])
        .cropped(to: extent)
    }
}

// Person segmentation (Vision) as a grey mask the size of the frame:
// white = person. Every frame is segmented on its own (Vision's own
// smoothing between frames trails behind motion) and a pixel seen as
// person stays covered while it fades out over a few frames (`fade` per
// frame).
@available(iOS 15.0, *)
final class AyuPersonMask {
    var fade = 0.55

    private let request = VNGeneratePersonSegmentationRequest()
    private var history: [UInt8] = []
    private var buffers: [CVPixelBuffer] = []
    private var next = 0
    // Motion: the frame shrunk to `motionWidth` px, this and the last one.
    var motionWidth = 120
    var motionThreshold = 0.09        // mean RGB change that counts as motion
    var motionReach: CGFloat = 0.06   // how far from the person, of the frame width
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var frames: [CVPixelBuffer] = []
    private var frameIndex = 0
    private var hasPrevious = false

    init() {
        self.request.qualityLevel = .balanced
        self.request.outputPixelFormat = kCVPixelFormatType_OneComponent8
    }

    func mask(_ image: CIImage) -> CIImage? {
        let extent = image.extent
        guard (try? VNImageRequestHandler(ciImage: image, orientation: .up).perform([self.request])) != nil else {
            return nil
        }
        guard let segmented = self.request.results?.first?.pixelBuffer, let pixels = self.hold(segmented) else {
            return nil
        }
        let mask = CIImage(cvPixelBuffer: pixels)
        return mask
            .transformed(by: CGAffineTransform(scaleX: extent.width / mask.extent.width, y: extent.height / mask.extent.height))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            .cropped(to: extent)
    }

    // White where the frame changed since the last call, only within
    // `motionReach` of `person` (a moving room far away stays as it is);
    // nil on the first frame. Computed on the shrunk frame.
    func motion(_ image: CIImage, near person: CIImage) -> CIImage? {
        let extent = image.extent
        let scale = CGFloat(self.motionWidth) / extent.width
        let width = self.motionWidth
        let height = Int((extent.height * scale).rounded())
        if self.frames.count != 2 || CVPixelBufferGetHeight(self.frames[0]) != height {
            self.frames = (0 ..< 2).compactMap { _ in
                var buffer: CVPixelBuffer?
                CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as CFDictionary, &buffer)
                return buffer
            }
            self.hasPrevious = false
        }
        guard self.frames.count == 2 else {
            return nil
        }
        let current = self.frames[self.frameIndex]
        let previous = self.frames[self.frameIndex ^ 1]
        self.frameIndex ^= 1
        let toSmall = CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: -extent.minX, y: -extent.minY)
        let small = CGRect(x: 0.0, y: 0.0, width: CGFloat(width), height: CGFloat(height))
        self.context.render(
            image.clampedToExtent()
                .applyingGaussianBlur(sigma: Double(0.5 / scale))
                .cropped(to: extent)
                .transformed(by: toSmall),
            to: current,
            bounds: small,
            colorSpace: nil
        )
        defer {
            self.hasPrevious = true
        }
        guard self.hasPrevious else {
            return nil
        }
        let third = CGFloat(1.0) / 3.0
        let moving = CIImage(cvPixelBuffer: current)
            .applyingFilter("CIDifferenceBlendMode", parameters: [
                kCIInputBackgroundImageKey: CIImage(cvPixelBuffer: previous)
            ])
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: third, y: third, z: third, w: 0.0),
                "inputGVector": CIVector(x: third, y: third, z: third, w: 0.0),
                "inputBVector": CIVector(x: third, y: third, z: third, w: 0.0),
                "inputAVector": CIVector(x: 0.0, y: 0.0, z: 0.0, w: 0.0),
                "inputBiasVector": CIVector(x: 0.0, y: 0.0, z: 0.0, w: 1.0)
            ])
            .applyingFilter("CIColorThreshold", parameters: ["inputThreshold": self.motionThreshold])
            .clampedToExtent()
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: 2.0])
            .cropped(to: small)
        let near = person
            .transformed(by: toSmall)
            .clampedToExtent()
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: CGFloat(width) * self.motionReach])
            .cropped(to: small)
        return moving
            .applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: near])
            .transformed(by: toSmall.inverted())
            .cropped(to: extent)
    }

    // max(this frame, last result faded), into one of two own buffers.
    private func hold(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        if self.history.count != width * height {
            self.history = [UInt8](repeating: 0, count: width * height)
            self.buffers = (0 ..< 2).compactMap { _ in
                var buffer: CVPixelBuffer?
                CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_OneComponent8, [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as CFDictionary, &buffer)
                return buffer
            }
        }
        guard self.buffers.count == 2 else {
            return nil
        }
        let target = self.buffers[self.next]
        self.next ^= 1
        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(target, [])
        defer {
            CVPixelBufferUnlockBaseAddress(target, [])
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
        }
        guard let input = CVPixelBufferGetBaseAddress(source)?.assumingMemoryBound(to: UInt8.self), let output = CVPixelBufferGetBaseAddress(target)?.assumingMemoryBound(to: UInt8.self) else {
            return nil
        }
        let inRow = CVPixelBufferGetBytesPerRow(source)
        let outRow = CVPixelBufferGetBytesPerRow(target)
        let keep = UInt16(self.fade * 256.0)
        self.history.withUnsafeMutableBufferPointer { last in
            for y in 0 ..< height {
                for x in 0 ..< width {
                    let i = y * width + x
                    let value = max(input[y * inRow + x], UInt8((UInt16(last[i]) * keep) >> 8))
                    last[i] = value
                    output[y * outRow + x] = value
                }
            }
        }
        return target
    }
}

// One compute pass that draws the snow over the whole frame (the mask
// keeps only the person). Value noise on a grid of 4 x 2 px cells of a
// 400 px frame (scaled to the real size), reseeded every frame; red and
// blue read 2 px apart for the fringes; exposure by the `face` box (from
// the top of the head down). Texture rows follow Core Image rows (bottom
// up); the box is in screen rows (top down).
final class AyuTVStaticGPU {
    static let shared = AyuTVStaticGPU()

    private struct Params {
        var width: Float
        var height: Float
        var faceY: Float
        var faceH: Float
        var seed: UInt32
        var flicker: Float
    }

    private let queue: MTLCommandQueue?
    private let pipeline: MTLComputePipelineState?
    private var target: MTLTexture?
    private var frame: UInt32 = 0
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    private init() {
        let metal = MTLCreateSystemDefaultDevice()
        self.queue = metal?.makeCommandQueue()
        let function = metal.flatMap { try? $0.makeLibrary(source: AyuTVStaticGPU.shader, options: nil) }?.makeFunction(name: "ayuSnow")
        self.pipeline = function.flatMap { try? metal?.makeComputePipelineState(function: $0) }
    }

    func run(size: CGSize, face: CGRect, time: Double) -> CIImage? {
        let width = Int(size.width)
        let height = Int(size.height)
        guard let queue = self.queue, let pipeline = self.pipeline, width > 0, height > 0 else {
            return nil
        }
        if self.target?.width != width || self.target?.height != height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
            descriptor.usage = [.shaderRead, .shaderWrite]
            self.target = queue.device.makeTexture(descriptor: descriptor)
        }
        guard let target = self.target, let commandBuffer = queue.makeCommandBuffer(), let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return nil
        }
        self.frame &+= 1
        let hasFace = !face.isNull && face.height > 4.0
        var params = Params(
            width: Float(width),
            height: Float(height),
            faceY: hasFace ? Float(size.height - face.maxY) : 0.0,
            faceH: hasFace ? Float(face.height) : Float(height),
            seed: self.frame &* 2_654_435_761,
            flicker: 1.0 + 0.04 * Float(sin(time * 23.0) * cos(time * 7.0))
        )
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(target, index: 0)
        encoder.setBytes(&params, length: MemoryLayout<Params>.stride, index: 0)
        encoder.dispatchThreadgroups(MTLSize(width: (width + 15) / 16, height: (height + 15) / 16, depth: 1), threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else {
            return nil
        }
        return CIImage(mtlTexture: target, options: [.colorSpace: self.colorSpace])
    }

    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;

    struct Params {
        float width; float height;
        float faceY; float faceH;
        uint seed; float flicker;
    };

    uint ayuHash32(uint x) {
        x ^= x >> 16; x *= 0x7feb352du;
        x ^= x >> 15; x *= 0x846ca68bu;
        x ^= x >> 16;
        return x;
    }

    float ayuCell(int x, int y, uint seed) {
        uint h = ayuHash32(uint(x) * 73856093u ^ uint(y) * 19349663u ^ seed);
        return float(h & 0xffffu) / 65535.0;
    }

    // Smooth value noise: 4 x 2 px cells of a 400 px frame.
    float ayuNoise(float2 p, float scale, uint seed) {
        float2 q = p / (float2(4.0, 2.0) * scale);
        int2 i = int2(floor(q));
        float2 f = q - floor(q);
        f = f * f * (3.0 - 2.0 * f);
        float a = ayuCell(i.x, i.y, seed), b = ayuCell(i.x + 1, i.y, seed);
        float c = ayuCell(i.x, i.y + 1, seed), d = ayuCell(i.x + 1, i.y + 1, seed);
        return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
    }

    kernel void ayuSnow(texture2d<float, access::write> dst [[texture(0)]],
                        constant Params &prm [[buffer(0)]],
                        uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) {
            return;
        }
        float scale = prm.width / 400.0;
        float2 p = float2(float(gid.x), prm.height - 1.0 - float(gid.y));
        // Top of the head blown out, thinning to the bottom.
        float t = saturate((p.y - prm.faceY) / max(prm.faceH, 1.0));
        float gain = (2.8 - 2.0 * t) * prm.flicker;
        float cut = 0.05 + 0.45 * t;
        float3 c;
        for (int k = 0; k < 3; k++) {
            float dx = float(1 - k) * 2.0 * scale;
            float s = saturate((ayuNoise(p + float2(dx, 0.0), scale, prm.seed) - 0.5) * 1.6 + 0.5);
            c[k] = saturate((s - cut) / (1.0 - cut)) * gain;
        }
        c *= float3(1.0, 0.93, 0.97);
        c *= 0.88 + 0.12 * cos(p.x * 6.2831853 / (2.4 * scale));
        dst.write(float4(saturate(c), 1.0), gid);
    }
    """
}
