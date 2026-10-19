import Foundation
import CoreImage
import CoreGraphics

@main struct VerifyAppearance {
    static func main() throws {
        let color: [UInt8] = [12,135,77]
        let alphas: [UInt8] = [0,64,128,255]
        var input = [UInt8]()
        for alpha in alphas { input += color.map { UInt8((Double($0)*Double(alpha)/255).rounded()) } + [alpha] }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let image = CIImage(bitmapData: Data(input), bytesPerRow: 16, size: CGSize(width:4,height:1), format:.RGBA8, colorSpace:space)
        var output = [UInt8](repeating:0,count:16)
        CSSVideoAppearance.context.render(CSSVideoAppearance.image(image), toBitmap:&output, rowBytes:16, bounds:CGRect(x:0,y:0,width:4,height:1), format:.RGBA8, colorSpace:space)
        let expected = 1.09 - 1.18*(0.2126*Double(color[0]) + 0.7152*Double(color[1]) + 0.0722*Double(color[2]))/255
        var rows=[[String:Any]]()
        for index in 0..<4 {
            let a=Int(output[index*4+3]), alpha=Int(alphas[index])
            guard abs(a-alpha)<=1 else { fatalError("alpha changed") }
            let expectedByte=Int((expected*Double(alpha)).rounded()),actual=Int(output[index*4])
            rows.append(["alpha":alpha,"expectedPremultipliedGray":expectedByte,"actualPremultipliedGray":actual])
            guard abs(actual-expectedByte)<=2 else { fatalError("CSS sRGB/alpha mismatch: \(rows)") }
        }
        print(String(data:try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys]),encoding:.utf8)!)
    }
}
