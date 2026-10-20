import Foundation
import CoreGraphics

@main struct WindowDockTests {
    static func main() {
        var checks = 0
        func check(_ value: Bool, _ message: String) {
            checks += 1
            precondition(value, message)
        }
        // Negative origins and vertical displays use the same geometry as the main display.
        for area in [CGRect(x: 0, y: 80, width: 1440, height: 796), CGRect(x: -1920, y: 0, width: 1920, height: 1080), CGRect(x: 200, y: 1000, width: 900, height: 1400)] {
            for edge in DockEdge.allCases {
                var full = CGRect(x: area.midX - 223, y: area.midY - 238, width: 446, height: 476)
                switch edge {
                case .left: full.origin.x = area.minX - 28
                case .right: full.origin.x = area.maxX - 446 + 28
                case .top: full.origin.y = area.maxY - 476 + 28
                case .bottom: full.origin.y = area.minY - 28
                }
                check(WindowDockGeometry.edge(for: full, in: area, margin: 28) == edge, "full window edge")
                let compact = WindowDockGeometry.docked(full, edge: edge, in: area)
                check(compact.size == WindowDockGeometry.compactSize, "compact dimensions")
                check(WindowDockGeometry.edge(for: compact, in: area, margin: 8) == edge, "compact stays on requested edge")
                check(area.contains(compact.insetBy(dx: 8, dy: 8)), "visible compact stays on screen")
                let expanded = WindowDockGeometry.clamped(full, in: area, margin: 28)
                check(area.contains(expanded.insetBy(dx: 28, dy: 28)), "expanded window stays in work area")
            }
            let center = CGRect(x: area.midX - WindowDockGeometry.compactSize.width / 2, y: area.midY - WindowDockGeometry.compactSize.height / 2, width: WindowDockGeometry.compactSize.width, height: WindowDockGeometry.compactSize.height)
            check(WindowDockGeometry.edge(for: center, in: area, margin: 8, threshold: 36) == nil, "drag away detaches")
            let lost = CGRect(x: -9000, y: 9000, width: 446, height: 476)
            check(area.contains(WindowDockGeometry.clamped(lost, in: area, margin: 28).insetBy(dx: 28, dy: 28)), "disconnected screen recovery")
        }
        check(WindowDockGeometry.edge(for: CGRect(x: -1000, y: 100, width: 446, height: 476), in: CGRect(x: 0, y: 0, width: 1440, height: 900), margin: 28) == .left, "fully overflowing the selected display still docks")
        check(WindowDockMotion.response(0) == 0 && WindowDockMotion.response(1) == 1, "motion settles on exact geometry")
        check(WindowDockMotion.response(-1) == 0 && WindowDockMotion.response(2) == 1, "motion clamps elapsed time")
        let samples = (0...1000).map { WindowDockMotion.response(Double($0) / 1000) }
        check(samples.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1.02 }, "magnetic spring overshoot is restrained")
        check(samples[500] > 0.95, "surface reaches edge promptly")
        check(abs(samples[999] - 1) < 0.0001, "settle has no terminal jump")
        check(WindowDockMotion.fade(0.1, from: 0.2, to: 0.8) == 0 && WindowDockMotion.fade(0.9, from: 0.2, to: 0.8) == 1, "content fade is bounded")
        let area = CGRect(x: 0, y: 0, width: 1440, height: 900)
        func fullAt(_ gap: CGFloat) -> CGRect { CGRect(x: gap - 28, y: 200, width: 446, height: 476) }
        var proximity = WindowDockProximity()
        check(!proximity.update(frame: fullAt(80), area: area, margin: 28, now: 1), "outside entry range has no feedback")
        check(proximity.edge == nil, "not armed outside range")
        check(proximity.update(frame: fullAt(39), area: area, margin: 28, now: 2), "entering range arms feedback before release")
        check(proximity.edge == .left, "candidate is ready while still dragging")
        check(!proximity.update(frame: fullAt(38), area: area, margin: 28, now: 3), "holding near edge does not repeat haptic")
        check(!proximity.update(frame: fullAt(55), area: area, margin: 28, now: 4) && proximity.edge == .left, "hysteresis holds ready state across boundary jitter")
        proximity.update(frame: fullAt(61), area: area, margin: 28, now: 5)
        check(proximity.edge == nil, "dragging away cancels readiness")
        check(!proximity.update(frame: fullAt(48), area: area, margin: 28, now: 6) && proximity.edge == nil, "must re-enter inner range to re-arm")
        check(proximity.update(frame: fullAt(39), area: area, margin: 28, now: 7), "intentional return produces one new tick")
        proximity.update(frame: fullAt(70), area: area, margin: 28, now: 7.05)
        check(!proximity.update(frame: fullAt(30), area: area, margin: 28, now: 7.1) && proximity.edge == .left, "rapid re-entry arms without repeated vibration")
        proximity.reset()
        check(proximity.edge == nil, "release clears preview")
        proximity.reset(seed: .left, area: area)
        let compact = CGRect(origin: CGPoint(x: -8, y: 200), size: WindowDockGeometry.compactSize)
        check(!proximity.update(frame: compact, area: area, margin: 8, now: 10), "picking up an already docked timer does not vibrate")
        for edge in DockEdge.allCases {
            var state = WindowDockProximity()
            let docked = WindowDockGeometry.docked(fullAt(0), edge: edge, in: area)
            check(state.update(frame: docked, area: area, margin: 8, now: 20) && state.edge == edge, "readiness handles every edge")
        }
        let other = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        check(proximity.update(frame: compact.offsetBy(dx: -1440, dy: 0), area: other, margin: 8, now: 30), "entering another display re-arms feedback")
        // Regression: overshooting an edge used to cancel docking because abs()
        // made overflow look like an increasing inward gap. Exercise all edges,
        // both window sizes, and displays with negative/vertical origins.
        for work in [area, other, CGRect(x: 200, y: 1000, width: 900, height: 1400)] {
            for (size, margin) in [(WindowDockGeometry.fullSize, CGFloat(28)), (WindowDockGeometry.compactSize, CGFloat(8))] {
                for edge in DockEdge.allCases {
                    func atGap(_ gap: CGFloat) -> CGRect {
                        var frame = CGRect(x: work.midX - size.width / 2, y: work.midY - size.height / 2, width: size.width, height: size.height)
                        switch edge {
                        case .left: frame.origin.x = work.minX - margin + gap
                        case .right: frame.origin.x = work.maxX - size.width + margin - gap
                        case .top: frame.origin.y = work.maxY - size.height + margin - gap
                        case .bottom: frame.origin.y = work.minY - margin + gap
                        }
                        return frame
                    }
                    for overflow in [CGFloat(1), 50, 120, 1000] {
                        var state = WindowDockProximity()
                        let frame = atGap(-overflow)
                        check(WindowDockGeometry.edge(for: frame, in: work, margin: margin) == edge, "partial/full overflow remains a docking target")
                        check(WindowDockGeometry.distance(to: edge, frame: frame, area: work, margin: margin) == -overflow, "overflow has signed outward distance")
                        check(state.update(frame: frame, area: work, margin: margin, now: 1) && state.edge == edge, "overshooting directly arms readiness")
                        check(!state.update(frame: atGap(-overflow - 100), area: work, margin: margin, now: 2) && state.edge == edge, "further overflow keeps readiness without another haptic")
                        let exitGap: CGFloat = margin == 8 ? 57 : 61
                        state.update(frame: atGap(exitGap), area: work, margin: margin, now: 3)
                        check(state.edge == nil, "only moving back inside beyond exit range cancels readiness")
                    }
                }
            }
        }
        let canvas = CGRect(origin: .zero, size: WindowCompactLayout.size)
        check(canvas.contains(WindowCompactLayout.body) && canvas.contains(WindowCompactLayout.character), "transparent canvas contains both timer and character")
        check(WindowCompactLayout.character.minY < WindowCompactLayout.body.minY, "character protrudes above the paper timer")
        check(WindowCompactLayout.character.maxX + 8 <= WindowCompactLayout.clockLeading, "character leaves clear space before the countdown")
        check(WindowCompactLayout.character.minY >= 8 && WindowCompactLayout.body.maxY <= canvas.maxY - 8, "outer clear margin prevents character clipping at screen edges")
        print("PASS: \(checks) window docking geometry checks")
    }
}
