import Foundation
import AVFoundation
import CoreVideo
import CoreImage
import ImageIO
import UniformTypeIdentifiers

@main struct VerifyMedia {
    static func main() async throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1])
        var results: [[String: Any]] = []
        for key in ["idle", "focus-adjust", "short", "short-eyes", "long", "long-yawn"] {
            let asset = AVURLAsset(url: folder.appendingPathComponent(key + ".mov"))
            guard let track = try await asset.loadTracks(withMediaType: .video).first else { fatalError("missing video: \(key)") }
            let fps = try await track.load(.nominalFrameRate), size = try await track.load(.naturalSize), duration = try await asset.load(.duration).seconds
            guard fps > 59.9 && size == CGSize(width: 540, height: 720) else { fatalError("wrong format: \(key)") }
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            reader.add(output); reader.timeRange = CMTimeRange(start: .zero, duration: CMTime(value: 2, timescale: 60))
            guard reader.startReading(), let sample = output.copyNextSampleBuffer(), let image = CMSampleBufferGetImageBuffer(sample) else { fatalError("native decode failed: \(key) \(String(describing: reader.error))") }
            CVPixelBufferLockBaseAddress(image, .readOnly)
            let bytes = CVPixelBufferGetBaseAddress(image)!.assumingMemoryBound(to: UInt8.self), stride = CVPixelBufferGetBytesPerRow(image)
            let corners = [(0,0),(539,0),(0,719),(539,719)].map { x,y in Int(bytes[y * stride + x * 4 + 3]) }
            var opaque = 0, transparent = 0
            for y in 0..<720 { for x in 0..<540 { let alpha = bytes[y * stride + x * 4 + 3]; if alpha > 250 { opaque += 1 }; if alpha < 3 { transparent += 1 } } }
            CVPixelBufferUnlockBaseAddress(image, .readOnly)
            guard corners.allSatisfy({ $0 <= 2 }), opaque > 5000, transparent > 200000 else { fatalError("invalid alpha: \(key), \(corners), opaque \(opaque)") }
            if let png = CommandLine.arguments.dropFirst(2).first {
                let ci = CIImage(cvPixelBuffer: image), context = CIContext()
                if let cg = context.createCGImage(ci, from: ci.extent), let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: png).appendingPathComponent(key + ".png") as CFURL, UTType.png.identifier as CFString, 1, nil) { CGImageDestinationAddImage(destination, cg, nil); CGImageDestinationFinalize(destination) }
            }
            reader.cancelReading()
            results.append(["clip":key,"fps":fps,"width":540,"height":720,"duration":duration,"cornerAlpha":corners,"opaquePixels":opaque,"transparentPixels":transparent])
        }
        let json = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted,.sortedKeys]); print(String(data: json, encoding: .utf8)!)
    }
}
