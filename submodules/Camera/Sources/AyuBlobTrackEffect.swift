import Foundation
import CoreGraphics
import CoreImage
import CoreText
import CoreVideo
import simd

// AyuGram: "blob tracking" on the back camera (port of RoundLab
// `BlobTrackEffect`, build 44). Over the camera picture as it is:
//   - thin rectangles on the most detailed spots, two sizes, overlapping;
//     every 4th (by id) is inverted inside;
//   - a 4-digit number in Menlo inside each box wide enough;
//   - a small red dot in the centre of 2 boxes out of 3;
//   - thin lines from each box to the one two ids further.
// Sizes are given for a 400 px round and scaled to the square.
// Boxes are found on a 100 px grey copy on the CPU: local contrast (std
// in a 5x5 window), the top 12 % / 22 % of this frame after a blur of
// 2.5 / 0.8 px, connected spots of 3..30 px not touching the edge, up to
// 8 + 14 by area. Tracked: matched to the nearest box of the last frame
// (within 8 px), eased by 0.6, shown after 2 frames, kept 4 frames.
// Called from the camera's video queue only.
final class AyuBlobTrackEffect {
    var levels: [(sigma: Float, top: Float, limit: Int)] = [(2.5, 0.12, 8), (0.8, 0.22, 14)]
    var reach: Float = 8.0
    var ease: Float = 0.6

    private let side = 100
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var small: CVPixelBuffer?
    private var tracks: [Track] = []
    private var nextId = 0

    private struct Track {
        let id: Int
        var box: SIMD4<Float>      // x0, y0, x1, y1 on the grid, y down
        var seen = 1
        var lost = 0
        var hit = true
    }

    func apply(to image: CIImage) -> CIImage {
        let extent = image.extent
        let edge = min(extent.width, extent.height)
        let square = CGRect(x: extent.midX - edge / 2.0, y: extent.midY - edge / 2.0, width: edge, height: edge).integral
        guard let gray = self.grey(image, square: square) else {
            return image
        }
        let shown = self.track(self.find(gray))
        return self.draw(shown, over: image, square: square)
    }

    // The square shrunk to side x side, grey, rows top down.
    private func grey(_ image: CIImage, square: CGRect) -> [Float]? {
        if self.small == nil {
            CVPixelBufferCreate(nil, self.side, self.side, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as CFDictionary, &self.small)
        }
        guard let small = self.small else {
            return nil
        }
        let side = self.side
        let scale = CGFloat(side) / square.width
        self.context.render(
            image.clampedToExtent()
                .applyingGaussianBlur(sigma: Double(0.5 / scale))
                .cropped(to: square)
                .transformed(by: CGAffineTransform(translationX: -square.minX, y: -square.minY))
                .transformed(by: CGAffineTransform(scaleX: scale, y: scale)),
            to: small,
            bounds: CGRect(x: 0.0, y: 0.0, width: CGFloat(side), height: CGFloat(side)),
            colorSpace: nil
        )
        CVPixelBufferLockBaseAddress(small, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(small, .readOnly)
        }
        guard let base = CVPixelBufferGetBaseAddress(small)?.assumingMemoryBound(to: UInt8.self) else {
            return nil
        }
        let row = CVPixelBufferGetBytesPerRow(small)
        var gray = [Float](repeating: 0.0, count: side * side)
        for y in 0 ..< side {
            for x in 0 ..< side {
                let p = base + y * row + x * 4
                gray[y * side + x] = 0.114 * Float(p[0]) + 0.587 * Float(p[1]) + 0.299 * Float(p[2])
            }
        }
        return gray
    }

    private func find(_ gray: [Float]) -> [SIMD4<Float>] {
        let side = self.side
        let mean = self.boxBlur(gray, radius: 2)
        let meanSquare = self.boxBlur(gray.map { $0 * $0 }, radius: 2)
        let std = zip(meanSquare, mean).map { sqrt(max($0 - $1 * $1, 0.0)) }
        var found: [SIMD4<Float>] = []
        for level in self.levels {
            let detail = self.gaussian(std, sigma: level.sigma)
            let sorted = detail.sorted()
            let threshold = sorted[Int(Float(sorted.count - 1) * (1.0 - level.top))]
            let spots = detail.map { $0 >= threshold }
            let boxes = self.components(spots)
                .filter { box in
                    let size = max(box.x1 - box.x0, box.y1 - box.y0)
                    let touches = box.x0 <= 0 || box.y0 <= 0 || box.x1 >= side || box.y1 >= side
                    return size >= 3 && size <= 30 && box.area >= 5 && !touches
                }
                .sorted { $0.area > $1.area }
                .prefix(level.limit)
            found += boxes.map { SIMD4<Float>(Float($0.x0), Float($0.y0), Float($0.x1), Float($0.y1)) }
        }
        return found
    }

    private func track(_ boxes: [SIMD4<Float>]) -> [Track] {
        for i in self.tracks.indices {
            self.tracks[i].hit = false
        }
        for box in boxes {
            let centre = SIMD2<Float>((box.x + box.z) / 2.0, (box.y + box.w) / 2.0)
            var best: Int?
            var distance = self.reach
            for (i, candidate) in self.tracks.enumerated() where !candidate.hit {
                let other = SIMD2<Float>((candidate.box.x + candidate.box.z) / 2.0, (candidate.box.y + candidate.box.w) / 2.0)
                let d = simd_length(other - centre)
                if d < distance {
                    best = i
                    distance = d
                }
            }
            if let best {
                self.tracks[best].box += (box - self.tracks[best].box) * self.ease
                self.tracks[best].seen += 1
                self.tracks[best].lost = 0
                self.tracks[best].hit = true
            } else {
                self.tracks.append(Track(id: self.nextId, box: box))
                self.nextId += 1
            }
        }
        for i in self.tracks.indices where !self.tracks[i].hit {
            self.tracks[i].lost += 1
        }
        self.tracks.removeAll(where: { $0.lost > 4 })
        return self.tracks.filter { $0.seen >= 2 }.sorted { $0.id < $1.id }
    }

    private func draw(_ shown: [Track], over image: CIImage, square: CGRect) -> CIImage {
        let cell = square.width / CGFloat(self.side)
        let k = square.width / 400.0          // one px of a 400 px round
        guard let hud = CGContext(
            data: nil,
            width: Int(square.width),
            height: Int(square.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }
        hud.translateBy(x: -square.minX, y: -square.minY)
        var result = image
        var centres: [CGPoint] = []
        hud.setLineWidth(k)
        hud.textMatrix = .identity
        let white = CGColor(gray: 0.92, alpha: 1.0)
        let red = CGColor(red: 0.78, green: 0.08, blue: 0.12, alpha: 1.0)
        let font = CTFontCreateWithName("Menlo-Regular" as CFString, 10.0 * k, nil)
        for track in shown {
            let b = track.box
            let rect = CGRect(
                x: square.minX + CGFloat(b.x) * cell,
                y: square.maxY - CGFloat(b.w) * cell,
                width: CGFloat(b.z - b.x) * cell,
                height: CGFloat(b.w - b.y) * cell
            )
            .insetBy(dx: -3.0 * k, dy: -3.0 * k)
            .intersection(square)
            guard !rect.isNull, rect.width > 1.0, rect.height > 1.0 else {
                continue
            }
            if track.id % 4 == 1 {
                result = image.cropped(to: rect).applyingFilter("CIColorInvert").composited(over: result)
            }
            hud.setStrokeColor(white)
            hud.stroke(rect.insetBy(dx: k / 2.0, dy: k / 2.0))
            let centre = CGPoint(x: rect.midX, y: rect.midY)
            centres.append(centre)
            if rect.width >= 22.0 * k {
                let text = "\((track.id * 7919 + 1973) % 9000 + 1000)"
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): white
                ]))
                hud.textPosition = CGPoint(x: centre.x - 4.0 * k, y: centre.y + 4.0 * k)
                CTLineDraw(line, hud)
            }
            if track.id % 3 != 2 {
                hud.setFillColor(red)
                hud.fillEllipse(in: CGRect(x: centre.x - 2.5 * k, y: centre.y - 2.5 * k, width: 5.0 * k, height: 5.0 * k))
            }
        }
        hud.setStrokeColor(CGColor(gray: 0.78, alpha: 1.0))
        for (a, b) in zip(centres, centres.dropFirst(2)) {
            hud.move(to: a)
            hud.addLine(to: b)
        }
        hud.strokePath()
        guard let overlay = hud.makeImage() else {
            return result
        }
        return CIImage(cgImage: overlay)
            .transformed(by: CGAffineTransform(translationX: square.minX, y: square.minY))
            .composited(over: result)
            .cropped(to: image.extent)
    }

    // Mean over a (2r+1)^2 window, the edge repeated.
    private func boxBlur(_ v: [Float], radius: Int) -> [Float] {
        return self.separable(v, kernel: [Float](repeating: 1.0 / Float(2 * radius + 1), count: 2 * radius + 1))
    }

    private func gaussian(_ v: [Float], sigma: Float) -> [Float] {
        let radius = max(1, Int((sigma * 3.0).rounded(.up)))
        var kernel = (-radius ... radius).map { exp(-Float($0 * $0) / (2.0 * sigma * sigma)) }
        let sum = kernel.reduce(0.0, +)
        kernel = kernel.map { $0 / sum }
        return self.separable(v, kernel: kernel)
    }

    private func separable(_ v: [Float], kernel: [Float]) -> [Float] {
        let side = self.side
        let r = kernel.count / 2
        var across = [Float](repeating: 0.0, count: v.count)
        var out = [Float](repeating: 0.0, count: v.count)
        for y in 0 ..< side {
            for x in 0 ..< side {
                var s: Float = 0.0
                for (i, w) in kernel.enumerated() {
                    s += w * v[y * side + min(max(x + i - r, 0), side - 1)]
                }
                across[y * side + x] = s
            }
        }
        for y in 0 ..< side {
            for x in 0 ..< side {
                var s: Float = 0.0
                for (i, w) in kernel.enumerated() {
                    s += w * across[min(max(y + i - r, 0), side - 1) * side + x]
                }
                out[y * side + x] = s
            }
        }
        return out
    }

    // 8-connected spots: bounding box (end exclusive) and pixel count.
    private func components(_ on: [Bool]) -> [(x0: Int, y0: Int, x1: Int, y1: Int, area: Int)] {
        let side = self.side
        var seen = [Bool](repeating: false, count: on.count)
        var result: [(x0: Int, y0: Int, x1: Int, y1: Int, area: Int)] = []
        var stack: [Int] = []
        for start in 0 ..< on.count where on[start] && !seen[start] {
            seen[start] = true
            stack.append(start)
            var x0 = side
            var y0 = side
            var x1 = 0
            var y1 = 0
            var area = 0
            while let i = stack.popLast() {
                let x = i % side
                let y = i / side
                x0 = min(x0, x)
                y0 = min(y0, y)
                x1 = max(x1, x + 1)
                y1 = max(y1, y + 1)
                area += 1
                for dy in -1 ... 1 {
                    for dx in -1 ... 1 {
                        let nx = x + dx
                        let ny = y + dy
                        guard nx >= 0, ny >= 0, nx < side, ny < side else {
                            continue
                        }
                        let j = ny * side + nx
                        if on[j] && !seen[j] {
                            seen[j] = true
                            stack.append(j)
                        }
                    }
                }
            }
            result.append((x0: x0, y0: y0, x1: x1, y1: y1, area: area))
        }
        return result
    }
}
