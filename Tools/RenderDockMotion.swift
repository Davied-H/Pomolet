import AppKit
import SwiftUI

@main struct RenderDockMotion {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("pomolet-motion-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fixture) }
        let store = PomodoroStore(fileURL: fixture, startTicker: false)
        store.reduceMotion = !CommandLine.arguments.contains("--running")
        if CommandLine.arguments.contains("--running") { store.toggle() }
        store.dark = CommandLine.arguments.contains("--dark")
        let presentation = WindowPresentation()
        if CommandLine.arguments.contains("--ready") || CommandLine.arguments.contains("--compact") {
            presentation.compact = CommandLine.arguments.contains("--compact")
            if !presentation.compact { presentation.proximityEdge = .left; presentation.proximityStrength = 0.65 }
            let size = presentation.compact ? WindowCompactLayout.size : WindowDockGeometry.fullSize
            let host = NSHostingView(rootView: WindowContent(store: store, presentation: presentation))
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
            window.backgroundColor = .clear; window.isOpaque = false
            window.contentView = host; host.frame = CGRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("No bitmap") }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("No PNG") }
            try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
            print(presentation.compact ? "Rendered transparent mini companion" : "Rendered ready state before release")
            return
        }
        let area = CGRect(x: 0, y: 0, width: 1512, height: 949)
        let source = CGRect(x: 12, y: 230, width: 446, height: 476)
        let target = WindowDockGeometry.docked(source, edge: .left, in: area)
        let expanding = CommandLine.arguments.contains("--expand")
        let transition = WindowDockTransition(from: expanding ? target : source, to: expanding ? source : target, edge: .left, docking: !expanding, workArea: area)
        presentation.transition = transition
        let size = transition.stage.size
        let board = NSImage(size: NSSize(width: size.width * 3, height: (size.height + 30) * 2))
        board.lockFocus()
        NSColor(calibratedWhite: 0.89, alpha: 1).setFill()
        NSRect(origin: .zero, size: board.size).fill()
        board.unlockFocus()
        for (index, time) in [0.0, 0.18, 0.34, 0.52, 0.74, 1.0].enumerated() {
            presentation.transitionProgress = time
            let host = NSHostingView(rootView: MagneticWindowMorph(store: store, presentation: presentation, transition: transition))
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.06))
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("No bitmap") }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let image = NSImage(size: size); image.addRepresentation(bitmap)
            board.lockFocus()
            let x = CGFloat(index % 3) * size.width
            let y = CGFloat(1 - index / 3) * (size.height + 30)
            image.draw(in: NSRect(x: x, y: y, width: size.width, height: size.height))
            ("\(Int(time * 640)) ms" as NSString).draw(at: NSPoint(x: x + 20, y: y + size.height + 7), withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.darkGray])
            board.unlockFocus()
            window.contentView = nil
        }
        guard let tiff = board.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { fatalError("No PNG") }
        try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        print("Rendered six magnetic docking phases")
    }
}
