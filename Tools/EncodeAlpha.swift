import Foundation
import AVFoundation
import CoreVideo

// ffmpeg decodes the existing VP9-alpha originals to BGRA on stdin.
let args = CommandLine.arguments
if args.count != 5 { fputs("usage: encode-alpha output.mov width height fps\n", stderr); exit(2) }
let url = URL(fileURLWithPath: args[1]), width = Int(args[2])!, height = Int(args[3])!, fps = Int32(args[4])!
try? FileManager.default.removeItem(at: url)
let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.hevcWithAlpha,
    AVVideoWidthKey: width, AVVideoHeightKey: height,
    AVVideoCompressionPropertiesKey: [AVVideoQualityKey: 0.9, AVVideoExpectedSourceFrameRateKey: fps]
])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
    kCVPixelBufferIOSurfacePropertiesKey as String: [:]
])
input.expectsMediaDataInRealTime = false
writer.add(input)
guard writer.startWriting() else { fatalError(writer.error!.localizedDescription) }
writer.startSession(atSourceTime: .zero)
let frameSize = width * height * 4
var frame: Int64 = 0
while true {
    var data = Data()
    while data.count < frameSize {
        guard let chunk = try FileHandle.standardInput.read(upToCount: frameSize - data.count), !chunk.isEmpty else { break }
        data.append(chunk)
    }
    if data.isEmpty { break }
    guard data.count == frameSize else { fatalError("incomplete BGRA frame") }
    while !input.isReadyForMoreMediaData {
        if writer.status == .failed { fatalError(writer.error!.localizedDescription) }
        Thread.sleep(forTimeInterval: 0.002)
    }
    autoreleasepool {
        var buffer: CVPixelBuffer?
        guard let pool = adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let pixel = buffer else { fatalError("pixel buffer allocation failed") }
        CVPixelBufferLockBaseAddress(pixel, [])
        let stride = CVPixelBufferGetBytesPerRow(pixel)
        data.withUnsafeBytes { bytes in
            let source = bytes.baseAddress!
            let target = CVPixelBufferGetBaseAddress(pixel)!
            for y in 0..<height { memcpy(target.advanced(by: y * stride), source.advanced(by: y * width * 4), width * 4) }
        }
        CVPixelBufferUnlockBaseAddress(pixel, [])
        guard adaptor.append(pixel, withPresentationTime: CMTime(value: frame, timescale: fps)) else { fatalError(writer.error?.localizedDescription ?? "append failed") }
    }
    frame += 1
}
input.markAsFinished()
let semaphore = DispatchSemaphore(value: 0)
writer.finishWriting { semaphore.signal() }
semaphore.wait()
guard writer.status == .completed else { fatalError(writer.error?.localizedDescription ?? "encode failed") }
print("encoded \(frame) frames to \(url.lastPathComponent)")
