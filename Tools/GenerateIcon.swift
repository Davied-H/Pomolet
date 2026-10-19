import AppKit

// Mirrors Brand/pomolet.svg. Rasterize at each native icon size for crisp edges.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = root.appendingPathComponent(".build/Pomolet.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
func render(_ size: Int) throws -> Data {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: CGFloat(size)/1024, y: CGFloat(size)/1024)
    context.translateBy(x: 0, y: 1024); context.scaleBy(x: 1, y: -1)
    let green = CGColor(red: 8/255, green: 127/255, blue: 77/255, alpha: 1)
    let cream = CGColor(red: 1, green: 248/255, blue: 231/255, alpha: 1)
    context.setFillColor(green)
    context.addPath(CGPath(roundedRect: CGRect(x:100,y:100,width:824,height:824), cornerWidth:185, cornerHeight:185, transform:nil)); context.fillPath()
    context.setFillColor(cream)
    context.addPath(CGPath(roundedRect:CGRect(x:326,y:427,width:104,height:322),cornerWidth:52,cornerHeight:52,transform:nil)); context.fillPath()
    context.addEllipse(in:CGRect(x:326,y:235,width:410,height:410)); context.addEllipse(in:CGRect(x:430,y:339,width:202,height:202));context.fillPath(using:.evenOdd)
    let leaf=CGMutablePath();leaf.move(to:CGPoint(x:527,y:235));leaf.addCurve(to:CGPoint(x:666,y:134),control1:CGPoint(x:525,y:161),control2:CGPoint(x:583,y:126));leaf.addCurve(to:CGPoint(x:527,y:235),control1:CGPoint(x:669,y:206),control2:CGPoint(x:618,y:251));leaf.closeSubpath();context.addPath(leaf);context.fillPath()
    context.setStrokeColor(cream);context.setLineWidth(29);context.setLineCap(.round);context.move(to:CGPoint(x:531,y:440));context.addLine(to:CGPoint(x:579,y:392));context.strokePath()
    return NSBitmapImageRep(cgImage:context.makeImage()!).representation(using:.png,properties:[:])!
}
for size in [16,32,128,256,512] {
    try render(size).write(to:iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size*2).write(to:iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
try render(1024).write(to:root.appendingPathComponent("Brand/pomolet.png"))
let task=Process();task.executableURL=URL(fileURLWithPath:"/usr/bin/iconutil");task.arguments=["-c","icns",iconset.path,"-o",root.appendingPathComponent("Resources/AppIcon.icns").path];try task.run();task.waitUntilExit();guard task.terminationStatus==0 else {fatalError("iconutil failed")}
print("Pomolet icon generated")
