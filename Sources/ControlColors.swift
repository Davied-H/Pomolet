import SwiftUI
import AppKit
import Combine

/// SVG background colors and button text have independent CSS transition durations.
@MainActor final class ControlColorMotion: ObservableObject {
    let timeline: MotionTimeline
    private var forwarding: AnyCancellable?
    private var initialized = false
    init(clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        timeline = MotionTimeline(clock: clock)
        forwarding = timeline.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
    }
    func update(palette: Palette, running: Bool, instant: Bool = false) {
        let colors: [(String, Color, Double)] = [
            ("fill", palette.controlFill(running: running), 0.2),
            ("stroke", palette.dark && running ? Color(hex: 0x3a3a3a) : .clear, 0.2),
            ("ink", palette.controlInk(running: running), 0.18)
        ]
        for (role, color, duration) in colors {
            for (component, target) in components(color).enumerated() {
                let key = role + "." + String(component)
                if instant || !initialized { timeline.set(key, target) }
                else { timeline.animate(key, to: target, duration: duration, ease: .cubic(0.25, 0.1, 0.25, 1), fallback: target) }
            }
        }
        initialized = true
    }
    func color(_ role: String, fallback: Color) -> Color {
        let target = components(fallback)
        let values = target.enumerated().map { timeline.value(role + "." + String($0.offset), fallback: $0.element) }
        let alpha = values[3]
        return Color(.sRGB, red: alpha > 0 ? values[0] / alpha : 0, green: alpha > 0 ? values[1] / alpha : 0, blue: alpha > 0 ? values[2] / alpha : 0, opacity: alpha)
    }
    private func components(_ color: Color) -> [Double] {
        let value = NSColor(color).usingColorSpace(.sRGB)!
        let alpha = Double(value.alphaComponent)
        return [Double(value.redComponent) * alpha, Double(value.greenComponent) * alpha, Double(value.blueComponent) * alpha, alpha]
    }
}

enum CompletionEnvelope {
    /// WebAudio: linear attack, exponential ramp, then hold the final gain until stop.
    static func gain(at time: Double) -> Double {
        guard time >= 0, time < 1.2 else { return 0 }
        if time < 0.02 { return 0.12 * time / 0.02 }
        if time <= 1.1 { return 0.12 * pow(0.001 / 0.12, (time - 0.02) / 1.08) }
        return 0.001
    }
}
