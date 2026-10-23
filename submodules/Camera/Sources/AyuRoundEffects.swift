import Foundation
import UIKit
import AVFoundation
import CoreImage
import CoreMedia
import Vision

// AyuGram: live effects on round videos (port of the RoundLab stand,
// fff project, 2026-10-23). Front camera - TV static over the whole
// person, back camera - blob tracking. Both are switched in
// Settings ▸ AyuGram ▸ «Эффекты кружков»; the switches live in
// UserDefaults (a device setting, not an account one), the same keys are
// written by SettingsUI/AyuSettingsController.swift.
//
// The effect is applied in CameraRoundLegacyVideoFilter to the 400x400
// square of each camera before the camera crossfade, so the recording
// and the preview get the same frame. While an effect is on, nothing raw
// reaches the recording: a frame the filter could not render is dropped
// (CameraOutput.processVideoRecording) and a failed effect covers the
// frame itself (pixellated).
public enum AyuRoundEffects {
    public static let tvStaticKey = "ayu.roundEffects.tvStatic"
    public static let blobTrackKey = "ayu.roundEffects.blobTrack"

    public static var tvStaticEnabled: Bool {
        return UserDefaults.standard.bool(forKey: tvStaticKey)
    }

    public static var blobTrackEnabled: Bool {
        return UserDefaults.standard.bool(forKey: blobTrackKey)
    }

    public static var anyEnabled: Bool {
        return tvStaticEnabled || blobTrackEnabled
    }

    static func isEnabled(front: Bool) -> Bool {
        return front ? tvStaticEnabled : blobTrackEnabled
    }

    // The preview layer of the open round video screen (set on the main
    // queue, fed from the camera's video queue).
    private static let lock = NSLock()
    private static weak var previewLayer: AVSampleBufferDisplayLayer?

    static func setPreviewLayer(_ layer: AVSampleBufferDisplayLayer?) {
        lock.lock()
        previewLayer = layer
        lock.unlock()
    }

    static func deliverPreview(_ pixelBuffer: CVPixelBuffer) {
        lock.lock()
        let layer = previewLayer
        lock.unlock()
        guard let layer, let sample = makePreviewSample(pixelBuffer) else {
            return
        }
        let target: AVQueuedSampleBufferRendering
        if #available(iOS 17.0, *) {
            if layer.sampleBufferRenderer.status == .failed {
                layer.sampleBufferRenderer.flush()
            }
            target = layer.sampleBufferRenderer
        } else {
            if layer.status == .failed {
                layer.flush()
            }
            target = layer
        }
        target.enqueue(sample)
    }

    // A sample shown at once (no timebase on the layer).
    private static func makePreviewSample(_ pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixelBuffer, formatDescriptionOut: &format)
        guard let format else {
            return nil
        }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixelBuffer, formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample)
        guard let sample else {
            return nil
        }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true), CFArrayGetCount(attachments) > 0 {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dictionary,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }
        return sample
    }

    static func covered(_ image: CIImage) -> CIImage {
        return image.applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: 24]).cropped(to: image.extent)
    }
}

// The round video preview while an effect is on: the processed 400x400
// frames (the ones that go into the recording) over the raw camera
// preview. Black until the first frame, so the raw camera never shows.
public final class AyuRoundEffectPreviewView: UIView {
    override public class var layerClass: AnyClass {
        return AVSampleBufferDisplayLayer.self
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)

        self.backgroundColor = .black
        self.isUserInteractionEnabled = false
        if let layer = self.layer as? AVSampleBufferDisplayLayer {
            layer.videoGravity = .resizeAspectFill
            AyuRoundEffects.setPreviewLayer(layer)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// One per round video filter: the effect of each camera with its own
// state (tracking, held mask) and the faces for the TV static.
final class AyuRoundEffectProcessor {
    private var tvStatic: AnyObject?
    private let blobTrack = AyuBlobTrackEffect()
    private let faceRequest = VNDetectFaceRectanglesRequest()
    var minFaceConfidence: Float = 0.5
    var minFaceShare: CGFloat = 0.04          // of the frame width

    // `front` - the frame came from the front camera.
    func apply(to image: CIImage, front: Bool, time: Double) -> CIImage {
        if front {
            if #available(iOS 15.0, *) {
                let effect: AyuTVStaticBodyEffect
                if let current = self.tvStatic as? AyuTVStaticBodyEffect {
                    effect = current
                } else {
                    effect = AyuTVStaticBodyEffect()
                    self.tvStatic = effect
                }
                return effect.apply(to: image, faces: self.faces(in: image), time: time)
            } else {
                return AyuRoundEffects.covered(image)
            }
        } else {
            return self.blobTrack.apply(to: image)
        }
    }

    @available(iOS 15.0, *)
    private func faces(in image: CIImage) -> [CGRect] {
        guard (try? VNImageRequestHandler(ciImage: image, orientation: .up).perform([self.faceRequest])) != nil else {
            return []
        }
        let extent = image.extent
        return (self.faceRequest.results ?? []).compactMap { observation -> CGRect? in
            let rect = VNImageRectForNormalizedRect(observation.boundingBox, Int(extent.width), Int(extent.height))
                .offsetBy(dx: extent.minX, dy: extent.minY)
            guard observation.confidence >= self.minFaceConfidence, rect.width >= extent.width * self.minFaceShare else {
                return nil
            }
            return rect
        }
    }
}
