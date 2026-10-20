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
        return content
            .overlay {
                GeometryReader { proxy in
                    let edge = presentation.proximityEdge ?? presentation.pulseEdge
                    let rect = presentation.compact ? WindowCompactLayout.body : CGRect(origin: .zero, size: proxy.size).insetBy(dx: 28, dy: 28)
                    let vertical = edge == .left || edge == .right
                    let visible = presentation.proximityEdge != nil && presentation.transition == nil
                    ZStack {
                        ForEach(0..<3, id: \.self) { index in
                            Capsule()
                                .fill(Palette(dark: store.dark).accent.opacity(visible ? (0.18 + 0.16 * presentation.proximityStrength) / Double(index + 1) : 0))
                                .frame(width: vertical ? 2 : CGFloat(28 + index * 12), height: vertical ? CGFloat(28 + index * 12) : 2)
                                .position(x: edge == .left ? rect.minX - CGFloat(index * 3) : edge == .right ? rect.maxX + CGFloat(index * 3) : rect.midX,
                                          y: edge == .top ? rect.minY - CGFloat(index * 3) : edge == .bottom ? rect.maxY + CGFloat(index * 3) : rect.midY)
                                .blur(radius: index == 0 ? 0 : 1.2)
                        }
                        Capsule()
                            .fill(Palette(dark: store.dark).accent.opacity(visible ? 0.9 : 0))
                            .frame(width: vertical ? 3 : 38, height: vertical ? 38 : 3)
                            .position(x: edge == .left ? rect.minX : edge == .right ? rect.maxX : rect.midX,
                                      y: edge == .top ? rect.minY : edge == .bottom ? rect.maxY : rect.midY)
                            .shadow(color: Palette(dark: store.dark).accent.opacity(visible ? 0.6 : 0), radius: 5)
                    }
                    .animation(.easeOut(duration: 0.16), value: presentation.proximityEdge)
                }
                .allowsHitTesting(false).accessibilityHidden(true)
            }
            .keyframeAnimator(initialValue: 0.0, trigger: presentation.magneticPulse) { view, displacement in
                view.offset(x: vector.width * displacement, y: vector.height * displacement)
                    .scaleEffect(1 + displacement * 0.0015)
            } keyframes: { _ in
                LinearKeyframe(3.2, duration: 0.045)
                CubicKeyframe(-1.0, duration: 0.085)
                CubicKeyframe(0.28, duration: 0.075)
                CubicKeyframe(0, duration: 0.085)
            }
    }

}
