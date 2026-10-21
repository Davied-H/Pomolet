import SwiftUI

/// One small pull-and-settle complements the trackpad's native alignment tick.
/// The window frame stays under the pointer; only its material responds.
struct MagneticReadiness: ViewModifier {
    @ObservedObject var store: PomodoroStore
    @ObservedObject var presentation: WindowPresentation
    private var direction: CGSize {
        guard !store.reduceMotion, presentation.transition == nil else { return .zero }
        switch presentation.pulseEdge {
        case .left: return CGSize(width: -1, height: 0)
        case .right: return CGSize(width: 1, height: 0)
        case .top: return CGSize(width: 0, height: -1)
        case .bottom: return CGSize(width: 0, height: 1)
        }
    }
    func body(content: Content) -> some View {
        let vector = direction
        let pulsing = !store.reduceMotion && presentation.transition == nil && presentation.proximityEdge != nil
        return content
            .keyframeAnimator(initialValue: 0.0, trigger: presentation.magneticPulse) { view, displacement in
                let amount = pulsing ? displacement : 0
                view.offset(x: vector.width * amount, y: vector.height * amount)
                    .scaleEffect(1 + amount * 0.0015)
            } keyframes: { _ in
                LinearKeyframe(3.2, duration: 0.045)
                CubicKeyframe(-1.0, duration: 0.085)
                CubicKeyframe(0.28, duration: 0.075)
                CubicKeyframe(0, duration: 0.085)
            }
            // Keep the cue outside the material's pulse transform. Remove it
            // before the native window switches to the morph's union canvas.
            .overlay {
                if presentation.transition == nil {
                    GeometryReader { proxy in
                        let edge = presentation.proximityEdge ?? presentation.pulseEdge
                        let rect = presentation.compact ? WindowCompactLayout.body : CGRect(origin: .zero, size: proxy.size).insetBy(dx: 28, dy: 28)
                        let vertical = edge == .left || edge == .right
                        let visible = presentation.proximityEdge != nil
                        ZStack {
                            ForEach(0..<3, id: \.self) { index in
                                Capsule()
                                    .fill(Palette(dark: store.dark).accent.opacity((0.18 + 0.16 * presentation.proximityStrength) / Double(index + 1)))
                                    .frame(width: vertical ? 2 : CGFloat(28 + index * 12), height: vertical ? CGFloat(28 + index * 12) : 2)
                                    .position(x: edge == .left ? rect.minX - CGFloat(index * 3) : edge == .right ? rect.maxX + CGFloat(index * 3) : rect.midX,
                                              y: edge == .top ? rect.minY - CGFloat(index * 3) : edge == .bottom ? rect.maxY + CGFloat(index * 3) : rect.midY)
                                    .blur(radius: index == 0 ? 0 : 1.2)
                            }
                            Capsule()
                                .fill(Palette(dark: store.dark).accent.opacity(0.9))
                                .frame(width: vertical ? 3 : 38, height: vertical ? 38 : 3)
                                .position(x: edge == .left ? rect.minX : edge == .right ? rect.maxX : rect.midX,
                                          y: edge == .top ? rect.minY : edge == .bottom ? rect.maxY : rect.midY)
                                .shadow(color: Palette(dark: store.dark).accent.opacity(0.6), radius: 5)
                        }
                        // Animate visibility only; rect/edge changes must never
                        // interpolate between unrelated window coordinate spaces.
                        .animation(store.reduceMotion ? nil : .easeOut(duration: 0.16)) { cue in
                            cue.opacity(visible ? 1 : 0)
                        }
                    }
                    .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
    }

}
