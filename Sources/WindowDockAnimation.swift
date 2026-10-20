import SwiftUI
import AppKit

struct WindowDockTransition {
    let from: CGRect
    let to: CGRect
    let edge: DockEdge
    let docking: Bool
    let workArea: CGRect
    var morphing: Bool { from.size != to.size }
    var fromCompact: Bool { !docking || !morphing }
    var stage: CGRect { from.union(to).insetBy(dx: -18, dy: -18) }
    var full: CGRect { docking ? from : to }
    var mini: CGRect { docking ? to : from }
    func local(_ frame: CGRect) -> CGRect {
        CGRect(x: frame.minX - stage.minX, y: stage.maxY - frame.maxY, width: frame.width, height: frame.height)
    }
    func body(_ frame: CGRect, compact: Bool) -> CGRect {
        let localFrame = local(frame)
        return compact ? WindowCompactLayout.body.offsetBy(dx: localFrame.minX, dy: localFrame.minY) : localFrame.insetBy(dx: 28, dy: 28)
    }

}

/// Live content recedes while one uninterrupted surface and clock change shape.
/// The AppKit window holds the union frame until the material has settled.
struct MagneticWindowMorph: View {
    @ObservedObject var store: PomodoroStore
    @ObservedObject var presentation: WindowPresentation
    let transition: WindowDockTransition
    private var palette: Palette { Palette(dark: store.dark) }
    private var t: Double { presentation.transitionProgress }
    private var q: CGFloat { CGFloat(WindowDockMotion.response(t)) }
    private var phase: CGFloat { transition.morphing ? (transition.docking ? q : 1 - q) : 1 }
    private var full: CGRect { transition.local(transition.full) }
    private var mini: CGRect { transition.local(transition.mini) }
    private var surface: CGRect {
        let a = transition.body(transition.from, compact: transition.fromCompact)
        let b = transition.body(transition.to, compact: transition.docking)
        return CGRect(x: a.minX + (b.minX - a.minX) * q, y: a.minY + (b.minY - a.minY) * q, width: a.width + (b.width - a.width) * q, height: a.height + (b.height - a.height) * q)
    }
    private var silhouette: MagneticSurface {
        let area = transition.local(transition.workArea)
        let distance: CGFloat
        switch transition.edge {
        case .left: distance = max(0, surface.minX - area.minX)
        case .right: distance = max(0, area.maxX - surface.maxX)
        case .top: distance = max(0, surface.minY - area.minY)
        case .bottom: distance = max(0, area.maxY - surface.maxY)
        }
        // Only docking reaches for the screen; expansion keeps a clean outline.
        let contact = CGFloat(sin(.pi * WindowDockMotion.fade(t, from: 0.04, to: 0.93)))
        return MagneticSurface(rect: surface, radius: 24 - 6 * phase, edge: transition.edge,
                               pull: transition.docking ? min(46, distance + 9) * contact : 0)
    }
    var body: some View {
        ZStack(alignment: .topLeading) {
            silhouette.fill(palette.paper)
                .shadow(color: .black.opacity(store.dark ? 0.24 : 0.10), radius: 7 - 3 * phase, y: 3)
            if transition.morphing {
                ZStack(alignment: .topLeading) {
                    FocusRootView(store: store, presentation: presentation)
                        .frame(width: 446, height: 476)
                        .scaleEffect(x: surface.width / 390, y: surface.height / 420)
                        .position(x: surface.midX, y: surface.midY)
                }
                .frame(width: transition.stage.width, height: transition.stage.height)
                .mask { silhouette.fill(.white).shadow(color: .white, radius: 10, y: 3) }
                .opacity(fullOpacity)
            }
            silhouette.stroke(palette.line.opacity(0.8), lineWidth: 1)
            CompactTimerView(store: store, presentation: presentation)
                .frame(width: WindowCompactLayout.size.width, height: WindowCompactLayout.size.height)
                .position(x: surface.midX, y: surface.midY + WindowCompactLayout.size.height / 2 - WindowCompactLayout.body.midY)
                .opacity(miniOpacity)
            Text(store.timeText)
                .font(CSSFont.font(mix(store.running ? 64 : 53, 25), weight: Double(700 - 200 * phase), rounded: true))
                .monospacedDigit().tracking(-1.5 * (1 - phase))
                .foregroundStyle(palette.ink)
                .position(clockPosition)
                .opacity(1)
        }
        .frame(width: transition.stage.width, height: transition.stage.height)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
    private var fullOpacity: Double {
        transition.docking ? 1 - WindowDockMotion.fade(t, from: 0, to: 0.24) : WindowDockMotion.fade(t, from: 0.66, to: 0.96)
    }
    private var miniOpacity: Double {
        transition.morphing ? (transition.docking ? WindowDockMotion.fade(t, from: 0.68, to: 0.96) : 1 - WindowDockMotion.fade(t, from: 0, to: 0.22)) : 1
    }
    private var clockPosition: CGPoint {
        let a = CGPoint(x: full.minX + (store.running ? 223 : 293), y: full.minY + (store.running ? 295.4 : 190))
        let font = NSFont.systemFont(ofSize: 25, weight: .medium)
        let rounded = NSFont(descriptor: font.fontDescriptor.withDesign(.rounded) ?? font.fontDescriptor, size: 25) ?? font
        let textWidth = (store.timeText as NSString).size(withAttributes: [.font: rounded]).width
        let b = CGPoint(x: mini.minX + WindowCompactLayout.clockLeading + textWidth / 2, y: mini.minY + WindowCompactLayout.body.midY)
        if !transition.morphing { return CGPoint(x: surface.minX + WindowCompactLayout.clockLeading - WindowCompactLayout.body.minX + textWidth / 2, y: surface.midY) }
        return CGPoint(x: a.x + (b.x - a.x) * phase, y: a.y + (b.y - a.y) * phase)
    }
    private func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * phase }
}

/// A single contour: the attachment is part of the material, with no overlapping
/// circles, seam or glowing border. Rotation makes all four edges identical.
struct MagneticSurface: Shape {
    var rect: CGRect
    var radius: CGFloat
    var edge: DockEdge
    var pull: CGFloat
    func path(in bounds: CGRect) -> Path {
        let vertical = edge == .top || edge == .bottom
        let w = vertical ? rect.height : rect.width
        let h = vertical ? rect.width : rect.height
        let r = min(radius, min(w, h) / 2)
        let neck = min(28, h * 0.23)
        var path = Path()
        path.move(to: CGPoint(x: r, y: 0))
        path.addLine(to: CGPoint(x: w - r, y: 0))
        path.addQuadCurve(to: CGPoint(x: w, y: r), control: CGPoint(x: w, y: 0))
        path.addLine(to: CGPoint(x: w, y: h - r))
        path.addQuadCurve(to: CGPoint(x: w - r, y: h), control: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: r, y: h))
        path.addQuadCurve(to: CGPoint(x: 0, y: h - r), control: CGPoint(x: 0, y: h))
        path.addLine(to: CGPoint(x: 0, y: h / 2 + neck))
        path.addCurve(to: CGPoint(x: -pull, y: h / 2), control1: CGPoint(x: 0, y: h / 2 + neck * 0.30), control2: CGPoint(x: -pull, y: h / 2 + 7))
        path.addCurve(to: CGPoint(x: 0, y: h / 2 - neck), control1: CGPoint(x: -pull, y: h / 2 - 7), control2: CGPoint(x: 0, y: h / 2 - neck * 0.30))
        path.addLine(to: CGPoint(x: 0, y: r))
        path.addQuadCurve(to: CGPoint(x: r, y: 0), control: .zero)
        path.closeSubpath()
        let transform: CGAffineTransform
        switch edge {
        case .left: transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
        case .right: transform = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: rect.maxX, ty: rect.minY)
        case .top: transform = CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: rect.minX, ty: rect.minY)
        case .bottom: transform = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: rect.minX, ty: rect.maxY)
        }
        return path.applying(transform)
    }
}
