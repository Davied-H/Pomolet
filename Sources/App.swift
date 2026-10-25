import SwiftUI
import AppKit
import Combine
import Sparkle

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    let store: PomodoroStore
    override init() {
        if let fixture = Bundle.main.object(forInfoDictionaryKey: "FocusFixturePath") as? String,
           Bundle.main.bundleIdentifier?.hasSuffix(".parity") == true {
            store = PomodoroStore(fileURL: URL(fileURLWithPath: fixture))
        } else { store = PomodoroStore() }
        super.init()
    }
    private var updaterController: SPUStandardUpdaterController?
    private let chime = CompletionChime()
    private var window: NSWindow!
    private let presentation = WindowPresentation()
    private var moveTimer: Timer?
    private var manualWindowDrag = false
    private var dragPointer: NSPoint?
    private var proximity = WindowDockProximity()
    private var dockAnimationTimer: Timer?
    private var dockAnimationRevision = 0
    private var pendingWindowAction: (() -> Void)?
    private var changingFrame = false
    private var ignoreMovesUntilMouseDown = false
    private var expandedFrame: NSRect?
    private var dockEdge: DockEdge?
    private var pinMenuItem: NSMenuItem?
    private var snapEnabled = UserDefaults.standard.object(forKey: "windowEdgeSnap") as? Bool ?? true
    private var keyboard: Any?
    private var tokens: [NSObjectProtocol] = []
    private var languageObserver: AnyCancellable?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if Bundle.main.bundleIdentifier == "com.dong.focusnative" {
            updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        }
        buildMenu()
        languageObserver = store.$language.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.buildMenu() }
        }
        let frame = NSRect(x: 0, y: 0, width: 446, height: 476)
        window = FocusWindow(contentRect: frame, styleMask: [.borderless, .closable, .miniaturizable], backing: .buffered, defer: false)
        (window as? FocusWindow)?.onMouseDown = { [weak self] in
            guard let self else { return }
            self.ignoreMovesUntilMouseDown = false
            self.prepareWindowDrag()
        }
        window.title = Bundle.main.bundleIdentifier?.hasSuffix(".parity") == true ? "Pomolet · QA" : "Pomolet"; window.backgroundColor = .clear; window.isOpaque = false; window.hasShadow = false
        window.isMovableByWindowBackground = true; window.isReleasedWhenClosed = false; window.delegate = self
        presentation.togglePin = { [weak self] in self?.togglePin() }
        presentation.expand = { [weak self] in self?.expandWindow() }
        presentation.beginDrag = { [weak self] in self?.manualWindowDrag = true }
        presentation.updateDrag = { [weak self] pointer in self?.updateMagneticProximity(pointer: pointer) }
        presentation.finishDrag = { [weak self] moved in
            guard let self else { return }
            self.manualWindowDrag = false
            if moved { self.finishWindowDrag() }
            else { self.clearMagneticReadiness() }
        }
        applyWindowLevel()
        let host = NSHostingView(rootView: WindowContent(store: store, presentation: presentation))
        host.wantsLayer = true; host.layer?.backgroundColor = NSColor.clear.cgColor; host.layer?.masksToBounds = false
        window.contentView = host; window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        store.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        tokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.recoverWindowOnScreenChange() }
        })
        tokens.append(NotificationCenter.default.addObserver(forName: NSLocale.currentLocaleDidChangeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.store.refreshSystemLanguage() } })
        store.onCompletion = { [weak self] in self?.chime.play() }
        keyboard = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event) ? nil : event
        }
        tokens.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.store.tick() } })
        tokens.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.store.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion } })
        tokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didHideNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.store.windowVisible = false } })
        tokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didUnhideNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.updateVisibility() } })
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { window.makeKeyAndOrderFront(nil); updateVisibility(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { store.persist(); if let keyboard { NSEvent.removeMonitor(keyboard) } }
    func windowDidChangeOcclusionState(_ notification: Notification) { updateVisibility() }
    func windowDidMiniaturize(_ notification: Notification) { updateVisibility() }
    func windowDidDeminiaturize(_ notification: Notification) { updateVisibility(); store.tick() }
    func windowWillClose(_ notification: Notification) { clearMagneticReadiness(); pendingWindowAction = nil; completeWindowTransition(); store.windowVisible = false; store.persist() }
    func windowDidMove(_ notification: Notification) {
        guard !manualWindowDrag, presentation.transition == nil, !changingFrame, !ignoreMovesUntilMouseDown, NSEvent.pressedMouseButtons & 1 != 0 else { return }
        updateMagneticProximity(pointer: NSEvent.mouseLocation)
        guard moveTimer == nil else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.moveTimer != nil, NSEvent.pressedMouseButtons & 1 == 0 else { return }
                self.moveTimer?.invalidate(); self.moveTimer = nil
                self.finishWindowDrag()
            }
        }
        moveTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    private var workArea: NSRect {
        // Prefer the display under the pointer when crossing between displays.
        (NSScreen.screens.first { $0.frame.contains(dragPointer ?? NSEvent.mouseLocation) } ?? window.screen ?? NSScreen.main)?.visibleFrame ?? window.frame
    }
    private func prepareWindowDrag() {
        guard presentation.transition == nil else { return }
        manualWindowDrag = false; dragPointer = nil
        let area = workArea
        let seed = presentation.compact ? WindowDockGeometry.edge(for: window.frame, in: area, margin: 8, threshold: 56) : nil
        proximity.reset(seed: seed, area: area)
        presentation.proximityEdge = nil; presentation.proximityStrength = 0
    }
    private func updateMagneticProximity(pointer: NSPoint) {
        guard snapEnabled, presentation.transition == nil else { return }
        dragPointer = pointer
        let area = workArea, margin: CGFloat = presentation.compact ? 8 : 28
        let entered = proximity.update(frame: window.frame, area: area, margin: margin, now: ProcessInfo.processInfo.systemUptime)
        if presentation.proximityEdge != proximity.edge { presentation.proximityEdge = proximity.edge }
        if let edge = proximity.edge {
            let distance = WindowDockProximity.distance(edge, frame: window.frame, area: area, margin: margin)
            presentation.proximityStrength = Double(min(1, max(0, 1 - distance / (presentation.compact ? 56 : 60))))
            if entered {
                presentation.pulseEdge = edge
                presentation.magneticPulse += 1
                let pulse = presentation.magneticPulse
                let performer = NSHapticFeedbackManager.defaultPerformer
                performer.perform(.alignment, performanceTime: .now)
                // A second softer alignment tick makes the threshold legible on
                // Force Touch hardware without repeating while the pointer holds.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.085) { [weak self] in
                    guard let self, self.presentation.magneticPulse == pulse, self.presentation.proximityEdge == edge else { return }
                    performer.perform(.alignment, performanceTime: .now)
                }
            }
        }
    }
    private func clearMagneticReadiness() {
        proximity.reset(); dragPointer = nil
        presentation.proximityEdge = nil; presentation.proximityStrength = 0
    }
    private func finishWindowDrag() {
        moveTimer?.invalidate(); moveTimer = nil
        manualWindowDrag = false
        defer { clearMagneticReadiness() }
        guard snapEnabled, presentation.transition == nil else { return }
        let area = workArea
        proximity.update(frame: window.frame, area: area, margin: presentation.compact ? 8 : 28, now: ProcessInfo.processInfo.systemUptime)
        if presentation.compact {
            if let edge = proximity.edge {
                dockEdge = edge
                transitionWindow(to: WindowDockGeometry.docked(window.frame, edge: edge, in: area), compact: true, edge: edge, area: area)
            } else { expandWindow(at: window.frame) }
        } else if let edge = proximity.edge {
            window.makeFirstResponder(nil)
            expandedFrame = window.frame; dockEdge = edge
            store.navigate(.focus)
            transitionWindow(to: WindowDockGeometry.docked(window.frame, edge: edge, in: area), compact: true, edge: edge, area: area)
        }
    }
    private func setWindowFrame(_ frame: NSRect) {
        changingFrame = true
        ignoreMovesUntilMouseDown = true
        window.setFrame(frame, display: true)
        changingFrame = false
    }
    private func expandWindow(at draggedFrame: NSRect? = nil) {
        if presentation.transition != nil {
            pendingWindowAction = { [weak self] in self?.expandWindow(at: draggedFrame) }
            return
        }
        guard presentation.compact else { return }
        let anchor = draggedFrame ?? expandedFrame ?? window.frame
        var target = NSRect(x: anchor.midX - 223, y: anchor.midY - 238, width: 446, height: 476)
        let area = (NSScreen.screens.max { a, b in
            a.visibleFrame.intersection(anchor).width * a.visibleFrame.intersection(anchor).height < b.visibleFrame.intersection(anchor).width * b.visibleFrame.intersection(anchor).height
        } ?? window.screen)?.visibleFrame ?? workArea
        target = WindowDockGeometry.clamped(target, in: area, margin: 28)
        let edge = dockEdge ?? .left
        dockEdge = nil
        transitionWindow(to: target, compact: false, edge: edge, area: area)
    }
    private func transitionWindow(to target: NSRect, compact: Bool, edge: DockEdge, area: NSRect) {
        clearMagneticReadiness()
        completeWindowTransition()
        let source = window.frame
        guard !store.reduceMotion, window.isVisible, !window.isMiniaturized, source != target else {
            presentation.compact = compact; setWindowFrame(target); return
        }
        let transition = WindowDockTransition(from: source, to: target, edge: edge, docking: compact, workArea: area)
        presentation.transitionProgress = 0
        presentation.transition = transition
        setWindowFrame(transition.stage)
        let revision = dockAnimationRevision
        let started = ProcessInfo.processInfo.systemUptime
        let duration = compact ? 0.64 : 0.56
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.dockAnimationRevision == revision, self.presentation.transition != nil else { return }
                let elapsed = (ProcessInfo.processInfo.systemUptime - started) / duration
                if elapsed >= 1 || self.store.reduceMotion { self.completeWindowTransition() }
                else { self.presentation.transitionProgress = elapsed }
            }
        }
        dockAnimationTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    private func completeWindowTransition() {
        dockAnimationRevision += 1
        dockAnimationTimer?.invalidate(); dockAnimationTimer = nil
        guard let transition = presentation.transition else { return }
        presentation.compact = transition.docking
        presentation.transition = nil
        presentation.transitionProgress = 1
        setWindowFrame(transition.to)
        if let action = pendingWindowAction {
            pendingWindowAction = nil
            action()
        }
    }
    private func withExpandedWindow(_ action: @escaping () -> Void) {
        if presentation.transition != nil {
            pendingWindowAction = { [weak self] in self?.withExpandedWindow(action) }
        } else if presentation.compact {
            pendingWindowAction = action
            expandWindow()
            if presentation.transition == nil, let pending = pendingWindowAction { pendingWindowAction = nil; pending() }
        } else { action() }
    }
    private func recoverWindowOnScreenChange() {
        guard window != nil else { return }
        completeWindowTransition()
        let area = (window.screen ?? NSScreen.main)?.visibleFrame ?? workArea
        if presentation.compact, let edge = dockEdge { setWindowFrame(WindowDockGeometry.docked(window.frame, edge: edge, in: area)) }
        else { setWindowFrame(WindowDockGeometry.clamped(window.frame, in: area, margin: 28)) }
    }
    private func applyWindowLevel() {
        window?.level = presentation.pinned ? .floating : .normal
        pinMenuItem?.state = presentation.pinned ? .on : .off
    }
    @objc private func togglePin() {
        presentation.pinned.toggle()
        UserDefaults.standard.set(presentation.pinned, forKey: "windowAlwaysOnTop")
        applyWindowLevel()
    }
    @objc private func toggleSnap(_ sender: NSMenuItem) {
        snapEnabled.toggle(); sender.state = snapEnabled ? .on : .off
        UserDefaults.standard.set(snapEnabled, forKey: "windowEdgeSnap")
        if !snapEnabled { clearMagneticReadiness(); expandWindow() }
    }
    private func updateVisibility() { guard window != nil else { return }; store.windowVisible = window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible) && !NSApp.isHidden }
    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        let editor = NSApp.keyWindow?.firstResponder as? NSTextView
        if editor?.hasMarkedText() == true { return false }
        if presentation.transition != nil, event.keyCode == 53 { expandWindow(); return true }
        if presentation.compact, editor == nil {
            if event.keyCode == 49, FocusRouting.currentID == nil { store.toggle(); return true }
            if event.keyCode == 53 { expandWindow(); return true }
        }
        if event.keyCode == 53 {
            if store.screen == .settings { NotificationCenter.default.post(name: .focusKeyboard, object: event.keyCode) }
            else if store.screen == .statistics { store.navigate(.focus) }
            else { return false }
            return true
        }
        let focused = FocusRouting.currentID
        if store.screen == .settings {
            if store.typeMenuOpen && [125,126,115,119,36,76,49,48].contains(event.keyCode) {
                NotificationCenter.default.post(name: .focusKeyboard, object: event.keyCode, userInfo: ["shift": event.modifierFlags.contains(.shift)]); return true
            }
            if editor == nil, focused?.hasPrefix("kind:") == true, [125,126].contains(event.keyCode) {
                NotificationCenter.default.post(name: .focusKeyboard, object: event.keyCode); return true
            }
        }
        guard editor == nil, store.screen == .focus else { return false }
        if event.keyCode == 49 && focused == nil { store.toggle(); return true }
        if [123,124,115,119].contains(event.keyCode), focused?.hasPrefix("mode:") == true, !store.running {
            let index = store.modes.firstIndex { $0.id == store.selectedID } ?? 0
            let next = event.keyCode == 115 ? 0 : event.keyCode == 119 ? store.modes.count - 1 : (index + (event.keyCode == 124 ? 1 : store.modes.count - 1)) % store.modes.count
            store.setMode(store.modes[next].id); FocusRouting.request("mode:" + store.modes[next].id); return true
        }
        return false
    }
    private func buildMenu() {
        let bar = NSMenu(), appMenu = NSMenu(), fileMenu = NSMenu(), editMenu = NSMenu(), viewMenu = NSMenu(), windowMenu = NSMenu()
        func item(_ title: String, action: Selector?, key: String = "", target: AnyObject? = nil) -> NSMenuItem { let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = target; return item }
        func submenu(_ title: String, _ menu: NSMenu) { let top = NSMenuItem(title: title, action: nil, keyEquivalent: ""); top.submenu = menu; bar.addItem(top) }
        appMenu.addItem(item(store.text("关于Pomolet"), action: #selector(about), target: self)); appMenu.addItem(.separator())
        if let controller = updaterController {
            appMenu.addItem(item(store.text("检查更新…"), action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), target: controller))
            let automatic = item(store.text("自动检查更新"), action: #selector(toggleAutomaticChecks(_:)), target: self)
            automatic.state = controller.updater.automaticallyChecksForUpdates ? .on : .off
            appMenu.addItem(automatic)
            let install = item(store.text("自动下载并安装更新"), action: #selector(toggleAutomaticDownloads(_:)), target: self)
            install.state = controller.updater.automaticallyDownloadsUpdates ? .on : .off
            appMenu.addItem(install)
            appMenu.addItem(.separator())
        }
        appMenu.addItem(item(store.text("设置…"), action: #selector(openSettings), key: ",", target: self)); appMenu.addItem(.separator())
        appMenu.addItem(item(store.text("隐藏Pomolet"), action: #selector(NSApplication.hide(_:)), key: "h")); appMenu.addItem(item(store.text("显示全部"), action: #selector(NSApplication.unhideAllApplications(_:))))
        appMenu.addItem(.separator()); appMenu.addItem(item(store.text("退出Pomolet"), action: #selector(NSApplication.terminate(_:)), key: "q"))
        fileMenu.addItem(item(store.text("开始 / 暂停"), action: #selector(toggleTimer), key: "\r", target: self)); fileMenu.addItem(item(store.text("重置计时"), action: #selector(resetTimer), key: "r", target: self)); fileMenu.addItem(.separator()); fileMenu.addItem(item(store.text("关闭窗口"), action: #selector(closeWindow), key: "w", target: self))
        editMenu.addItem(item(store.text("撤销"), action: Selector(("undo:")), key: "z")); editMenu.addItem(item(store.text("重做"), action: Selector(("redo:")), key: "Z")); editMenu.addItem(.separator())
        editMenu.addItem(item(store.text("剪切"), action: #selector(NSText.cut(_:)), key: "x")); editMenu.addItem(item(store.text("复制"), action: #selector(NSText.copy(_:)), key: "c")); editMenu.addItem(item(store.text("粘贴"), action: #selector(NSText.paste(_:)), key: "v")); editMenu.addItem(item(store.text("全选"), action: #selector(NSText.selectAll(_:)), key: "a"))
        viewMenu.addItem(item(store.text("番茄钟"), action: #selector(openFocus), key: "1", target: self)); viewMenu.addItem(item(store.text("数据统计"), action: #selector(openStatistics), key: "2", target: self)); viewMenu.addItem(item(store.text("切换深浅色"), action: #selector(toggleTheme), key: "d", target: self))
        pinMenuItem = item(store.text("窗口置顶"), action: #selector(togglePin), key: "p", target: self)
        pinMenuItem?.keyEquivalentModifierMask = [.command, .option]
        pinMenuItem?.state = presentation.pinned ? .on : .off
        windowMenu.addItem(pinMenuItem!)
        let snapItem = item(store.text("边缘吸附"), action: #selector(toggleSnap(_:)), target: self)
        snapItem.state = snapEnabled ? .on : .off; windowMenu.addItem(snapItem)
        windowMenu.addItem(item(store.text("展开完整窗口"), action: #selector(expandFromMenu), target: self))
        windowMenu.addItem(.separator())
        windowMenu.addItem(item(store.text("最小化"), action: #selector(NSWindow.miniaturize(_:)), key: "m")); windowMenu.addItem(item(store.text("显示主窗口"), action: #selector(showWindow), key: "0", target: self))
        submenu("Pomolet", appMenu); submenu(store.text("文件"), fileMenu); submenu(store.text("编辑"), editMenu); submenu(store.text("显示"), viewMenu); submenu(store.text("窗口"), windowMenu)
        NSApp.mainMenu = bar; NSApp.windowsMenu = windowMenu
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleAutomaticChecks(_:)) {
            menuItem.state = updaterController?.updater.automaticallyChecksForUpdates == true ? .on : .off
        } else if menuItem.action == #selector(toggleAutomaticDownloads(_:)) {
            menuItem.state = updaterController?.updater.automaticallyDownloadsUpdates == true ? .on : .off
        }
        return true
    }
    @objc private func toggleAutomaticChecks(_ sender: NSMenuItem) {
        guard let updater = updaterController?.updater else { return }
        updater.automaticallyChecksForUpdates.toggle()
        sender.state = updater.automaticallyChecksForUpdates ? .on : .off
    }
    @objc private func toggleAutomaticDownloads(_ sender: NSMenuItem) {
        guard let updater = updaterController?.updater else { return }
        updater.automaticallyDownloadsUpdates.toggle()
        sender.state = updater.automaticallyDownloadsUpdates ? .on : .off
    }
    @objc private func about() { NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Pomolet", .version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2.0", .credits: NSAttributedString(string: store.text("专注于眼前这一件事。\n原生 macOS · SwiftUI / AppKit"))]) }
    @objc private func expandFromMenu() { expandWindow() }
    @objc private func openSettings() { withExpandedWindow { [weak self] in guard let self else { return }; self.window.makeKeyAndOrderFront(nil); self.window.makeFirstResponder(nil); self.store.navigate(.settings) } }
    @objc private func openStatistics() { withExpandedWindow { [weak self] in guard let self else { return }; self.window.makeKeyAndOrderFront(nil); self.window.makeFirstResponder(nil); self.store.navigate(.statistics) } }
    @objc private func openFocus() { withExpandedWindow { [weak self] in guard let self else { return }; self.window.makeFirstResponder(nil); self.store.navigate(.focus) } }
    @objc private func toggleTimer() { store.toggle() }
    @objc private func resetTimer() { store.reset() }
    @objc private func toggleTheme() { store.toggleTheme() }
    @objc private func closeWindow() { window.close() }
    @objc private func showWindow() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
}
final class FocusWindow: NSWindow {
    var onMouseDown: (() -> Void)?
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown { onMouseDown?() }
        super.sendEvent(event)
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
@main struct FocusApplication {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
