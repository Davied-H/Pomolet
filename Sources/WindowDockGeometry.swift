import Foundation
import CoreGraphics

enum DockEdge: CaseIterable { case left, right, top, bottom }

/// The character protrudes above the paper bar inside a clear native canvas.
/// Geometry uses the outer visible envelope; animation uses the paper body.
enum WindowCompactLayout {
    static let size = CGSize(width: 336, height: 128)
    static let body = CGRect(x: 8, y: 44, width: 320, height: 76)
    static let character = CGRect(x: 16, y: 8, width: 76, height: 104)
    static let clockLeading: CGFloat = 100
}

/// All coordinates use AppKit's bottom-left origin. Visible bounds exclude the
/// transparent shadow margin; snapping uses the work area, including Dock insets.
enum WindowDockGeometry {
    static let fullSize = CGSize(width: 446, height: 476)
    static let compactSize = WindowCompactLayout.size
    /// Positive means inside the target work area; negative means overflow.
    /// The caller already chooses the target display from the drag pointer.
    static func distance(to edge: DockEdge, frame: CGRect, area: CGRect, margin: CGFloat) -> CGFloat {
        let visible = frame.insetBy(dx: margin, dy: margin)
        switch edge {
        case .left: return visible.minX - area.minX
        case .right: return area.maxX - visible.maxX
        case .top: return area.maxY - visible.maxY
        case .bottom: return visible.minY - area.minY
        }
    }
    static func edge(for frame: CGRect, in area: CGRect, margin: CGFloat, threshold: CGFloat = 40) -> DockEdge? {
        DockEdge.allCases.map { ($0, distance(to: $0, frame: frame, area: area, margin: margin)) }
            .filter { $0.1 <= threshold }.min { $0.1 < $1.1 }?.0
    }
    static func clamped(_ frame: CGRect, in area: CGRect, margin: CGFloat) -> CGRect {
        var result = frame
        result.origin.x = min(max(frame.minX, area.minX - margin), max(area.minX - margin, area.maxX - frame.width + margin))
        result.origin.y = min(max(frame.minY, area.minY - margin), max(area.minY - margin, area.maxY - frame.height + margin))
        return result
    }
    static func docked(_ frame: CGRect, edge: DockEdge, in area: CGRect) -> CGRect {
        var result = CGRect(x: frame.midX - compactSize.width / 2, y: frame.midY - compactSize.height / 2, width: compactSize.width, height: compactSize.height)
        switch edge {
        case .left: result.origin.x = area.minX - 8
        case .right: result.origin.x = area.maxX - result.width + 8
        case .top: result.origin.y = area.maxY - result.height + 8
        case .bottom: result.origin.y = area.minY - 8
        }
        return clamped(result, in: area, margin: 8)
    }
}


/// One shared clock drives the surface, content and magnetic neck.
enum WindowDockMotion {
    static func response(_ time: Double) -> Double {
        let t = min(1, max(0, time))
        if t == 0 || t == 1 { return t }
        let u = max(0, (t - 0.08) / 0.92)
        return 1 - exp(-11.2 * u) * (cos(8.4 * u) + (4.0 / 3.0) * sin(8.4 * u))
    }
    static func fade(_ time: Double, from: Double, to: Double) -> Double {
        let t = min(1, max(0, (time - from) / (to - from)))
        return t * t * (3 - 2 * t)
    }
}

/// The ready state is armed while dragging, and committed only on mouse-up.
/// Separate enter/leave distances keep both the cue and haptics steady at the edge.
struct WindowDockProximity {
    private(set) var edge: DockEdge?
    private var area: CGRect?
    private var lastFeedback = -Double.infinity
    mutating func reset(seed: DockEdge? = nil, area: CGRect? = nil) {
        edge = seed; self.area = area
    }
    static func distance(_ edge: DockEdge, frame: CGRect, area: CGRect, margin: CGFloat) -> CGFloat {
        WindowDockGeometry.distance(to: edge, frame: frame, area: area, margin: margin)
    }
    @discardableResult mutating func update(frame: CGRect, area: CGRect, margin: CGFloat, now: Double) -> Bool {
        let previous = self.area == area ? edge : nil
        if self.area != area { edge = nil; self.area = area }
        let entry: CGFloat = margin == 8 ? 36 : 40
        if let current = edge, Self.distance(current, frame: frame, area: area, margin: margin) <= entry + 20 {
            // Stay on the same edge at corners and during tiny hand movements.
        } else { edge = WindowDockGeometry.edge(for: frame, in: area, margin: margin, threshold: entry) }
        guard edge != nil, edge != previous, now - lastFeedback >= 0.35 else { return false }
        lastFeedback = now
        return true
    }
}
