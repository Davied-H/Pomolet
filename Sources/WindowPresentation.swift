import SwiftUI
import AppKit

/// Window-only state stays separate from the timer and its persisted session.
@MainActor final class WindowPresentation: ObservableObject {
    @Published var compact = false
    @Published var transition: WindowDockTransition?
    @Published var transitionProgress = 0.0
    @Published var proximityEdge: DockEdge?
    @Published var proximityStrength = 0.0
    @Published var magneticPulse = 0
    var pulseEdge: DockEdge = .left
    @Published var pinned = UserDefaults.standard.bool(forKey: "windowAlwaysOnTop")
    var togglePin: (() -> Void)?
    var expand: (() -> Void)?
    var finishDrag: ((Bool) -> Void)?
    var beginDrag: (() -> Void)?
    var updateDrag: ((NSPoint) -> Void)?
}

struct WindowContent: View {
    @ObservedObject var store: PomodoroStore
    @ObservedObject var presentation: WindowPresentation
    var body: some View {
        Group {
            if let transition = presentation.transition {
                MagneticWindowMorph(store: store, presentation: presentation, transition: transition)
            } else if presentation.compact { CompactTimerView(store: store, presentation: presentation) }
            else { FocusRootView(store: store, presentation: presentation) }
        }
        .modifier(MagneticReadiness(store: store, presentation: presentation))
    }
}

struct CompactTimerView: View {
    @ObservedObject var store: PomodoroStore
    @ObservedObject var presentation: WindowPresentation
    @StateObject private var media = CharacterPlayer()
    private var palette: Palette { Palette(dark: store.dark) }
    var body: some View {
        ZStack(alignment: .topLeading) {
            timerBar.offset(x: WindowCompactLayout.body.minX, y: WindowCompactLayout.body.minY)
            CharacterView(media: media, dark: store.dark, reduced: store.reduceMotion || presentation.transition != nil)
                // Remove only the source video's generous transparent padding.
                .frame(width: 153.6, height: 204.8)
                .offset(x: -38, y: -66)
                .frame(width: WindowCompactLayout.character.width, height: WindowCompactLayout.character.height, alignment: .topLeading)
                .clipped()
                .overlay { dragArea }
                .offset(x: WindowCompactLayout.character.minX, y: WindowCompactLayout.character.minY)
        }
        .frame(width: WindowCompactLayout.size.width, height: WindowCompactLayout.size.height, alignment: .topLeading)
        .environment(\.colorScheme, store.dark ? .dark : .light)
        .environment(\.locale, store.language.locale)
        .accessibilityElement(children: .contain)
        .onAppear { synchronizeMedia() }
        .onChange(of: store.running) { _, _ in synchronizeMedia() }
        .onChange(of: store.mediaResetID) { _, _ in synchronizeMedia(reset: true) }
        .onChange(of: store.dark) { _, _ in synchronizeMedia() }
        .onChange(of: store.windowVisible) { _, _ in synchronizeMedia() }
        .onChange(of: store.reduceMotion) { _, _ in synchronizeMedia() }
        .onDisappear { media.synchronize(kind: store.selected.kind, playing: false, dark: store.dark) }
    }
    private var timerBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                Color.clear.frame(width: 64)
                Text(store.timeText)
                    .font(.system(size: 25, weight: .medium, design: .rounded)).monospacedDigit()
                    .foregroundStyle(palette.ink).opacity(presentation.transition == nil ? 1 : 0)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay { dragArea }
            Button { store.toggle() } label: {
                Image(systemName: store.running ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.paper)
                    .frame(width: 34, height: 34).background(palette.accent, in: Circle())
            }.buttonStyle(.plain).focusTarget("compactPlay").help(store.controlTitle).accessibilityLabel(store.controlTitle)
            VStack(spacing: 8) {
                windowButton("arrow.up.left.and.arrow.down.right", focusID: "compactExpand", label: store.text("展开完整窗口")) { presentation.expand?() }
                windowButton(presentation.pinned ? "pin.fill" : "pin", focusID: "compactPin", label: presentation.pinned ? store.text("取消窗口置顶") : store.text("窗口置顶")) { presentation.togglePin?() }
            }
        }
        .padding(.horizontal, 16).frame(width: WindowCompactLayout.body.width, height: WindowCompactLayout.body.height)
        .background(palette.paper, in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(palette.line, lineWidth: 1).allowsHitTesting(false) }
        .shadow(color: .black.opacity(store.dark ? 0.25 : 0.12), radius: 4, y: 2)
    }
    private var dragArea: some View {
        WindowDragArea(onDragBegin: { presentation.beginDrag?() }, onDragUpdate: { presentation.updateDrag?($0) }, onDragEnd: { presentation.finishDrag?($0) })
            .help(store.text("拖离边缘恢复完整窗口"))
    }
    private func synchronizeMedia(reset: Bool = false) {
        media.synchronize(kind: store.selected.kind,
                          playing: store.running && store.windowVisible && !store.reduceMotion && presentation.transition == nil,
                          dark: store.dark, reset: reset)
    }
    private func windowButton(_ symbol: String, focusID: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(palette.sub).frame(width: 24, height: 20).contentShape(Rectangle()) }
            .buttonStyle(.plain).focusTarget(focusID).help(label).accessibilityLabel(label)
    }
}

struct WindowDragArea: NSViewRepresentable {
    var onDragBegin: () -> Void
    var onDragUpdate: (NSPoint) -> Void
    var onDragEnd: (Bool) -> Void
    func makeNSView(context: Context) -> NSView { let view = DragView(); configure(view); return view }
    func updateNSView(_ nsView: NSView, context: Context) { if let view = nsView as? DragView { configure(view) } }
    private func configure(_ view: DragView) { view.onDragBegin = onDragBegin; view.onDragUpdate = onDragUpdate; view.onDragEnd = onDragEnd }
    private final class DragView: NSView {
        var onDragBegin: (() -> Void)?
        var onDragUpdate: ((NSPoint) -> Void)?
        var onDragEnd: ((Bool) -> Void)?
        private var dragged = false
        private var dragOrigin: NSPoint?
        private var pointerOrigin: NSPoint?
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }
        override func mouseDown(with event: NSEvent) {
            dragged = false
            dragOrigin = window?.frame.origin
            pointerOrigin = window?.convertPoint(toScreen: event.locationInWindow)
            onDragBegin?()
        }
        override func mouseDragged(with event: NSEvent) {
            guard let dragOrigin, let pointerOrigin else { return }
            guard let pointer = window?.convertPoint(toScreen: event.locationInWindow) else { return }
            dragged = dragged || abs(pointer.x - pointerOrigin.x) + abs(pointer.y - pointerOrigin.y) > 2
            window?.setFrameOrigin(NSPoint(x: dragOrigin.x + pointer.x - pointerOrigin.x,
                                           y: dragOrigin.y + pointer.y - pointerOrigin.y))
            if dragged { onDragUpdate?(pointer) }
        }
        override func mouseUp(with event: NSEvent) {
            dragOrigin = nil; pointerOrigin = nil
            let moved = dragged
            dragged = false
            onDragEnd?(moved)
        }
    }
}
