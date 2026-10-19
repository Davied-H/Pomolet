import SwiftUI
import AppKit

@main struct RenderChartCheck {
    @MainActor static func main() throws {
        let values: [[Double?]] = [[0,25,35,10,50,20,75],[0,1,2,1,3,1,4],[0,25,17.5,10,16.7,20,18.8],[25,100,nil,nil,nil,nil,nil]]
        let sample = VStack(spacing: 18) {
            Text("原生 Canvas 绘图校验 · 隔离样例").font(.system(size: 14)).foregroundColor(Color(hex: 0x6c756b))
            HStack(spacing: 20) {
                ForEach(0..<4) { index in MiniChart(values: values[index], bar: index == 1, progress: 1, palette: Palette(dark: false)).frame(width: 130, height: 40) }
            }
        }.padding(24).background(Color(hex: 0xf8f5ed))
        let renderer = ImageRenderer(content: sample); renderer.scale = 2
        guard let image = renderer.cgImage, let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { fatalError("chart render failed") }
        try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        print("PASS: rendered native Canvas lines, bars and week-to-date series")
    }
}
