import SwiftUI
import CoreImage
import AppKit

/// The actual SVG chain: SourceGraphic -> Gaussian(3.6) -> alpha 19a-9 -> SourceGraphic atop liquid.
final class LiquidRaster {
    private struct Key: Equatable { var width: CGFloat; var progress: Double; var fill: Color; var stroke: Color?; var filtered: Bool }
    private static let lock = NSLock()
    private static var cachedKey: Key?
    private static var cachedImage: CGImage?
    private static let space = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let context = CIContext(options: [.workingColorSpace: space, .outputColorSpace: space])
    static func image(width: CGFloat, progress: Double, fill: Color, stroke: Color?, filtered: Bool) -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        let p = min(1,max(0,progress)), key = Key(width: width,progress: p,fill: fill,stroke: stroke,filtered: filtered)
        if cachedKey == key { return cachedImage }
        let scale = 2.0, size = CGSize(width: width + 40,height: 64)
        guard let bitmap = CGContext(data:nil,width:Int((size.width*scale).rounded()),height:128,bitsPerComponent:8,bytesPerRow:0,space:space,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        bitmap.scaleBy(x:scale,y:scale);bitmap.setAllowsAntialiasing(true);bitmap.clear(CGRect(origin:.zero,size:size))
        bitmap.setFillColor(NSColor(fill).cgColor);if let stroke { bitmap.setStrokeColor(NSColor(stroke).cgColor);bitmap.setLineWidth(1) }
        let body = CGPath(roundedRect:CGRect(x:20,y:10,width:width-54*p,height:44),cornerWidth:12,cornerHeight:12,transform:nil)
        bitmap.addPath(body);bitmap.drawPath(using:stroke == nil ? .fill : .fillStroke)
        let radius=18+4*p,x=20+width-44+22*p
        bitmap.setAlpha(min(1,p*5));bitmap.addEllipse(in:CGRect(x:x-radius,y:32-radius,width:radius*2,height:radius*2));bitmap.drawPath(using:stroke == nil ? .fill : .fillStroke)
        guard let sourceImage=bitmap.makeImage() else { return nil }
        let output:CGImage?
        if filtered {
            let source=CIImage(cgImage:sourceImage,options:[.colorSpace:space]),soft=source.applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:3.6*scale])
            let liquid=soft.applyingFilter("CIColorMatrix",parameters:["inputAVector":CIVector(x:0,y:0,z:0,w:19),"inputBiasVector":CIVector(x:0,y:0,z:0,w:-9)]).applyingFilter("CIColorClamp",parameters:["inputMinComponents":CIVector(x:0,y:0,z:0,w:0),"inputMaxComponents":CIVector(x:1,y:1,z:1,w:1)])
            let composite=source.applyingFilter("CISourceAtopCompositing",parameters:[kCIInputBackgroundImageKey:liquid])
            output=context.createCGImage(composite,from:CGRect(x:0,y:0,width:size.width*scale,height:size.height*scale),format:.RGBA8,colorSpace:space)
        } else { output=sourceImage }
        cachedKey=key;cachedImage=output;return output
    }
}
