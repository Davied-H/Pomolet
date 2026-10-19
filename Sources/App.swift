import SwiftUI
import AppKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store: PomodoroStore
    override init() {
        if let fixture = Bundle.main.object(forInfoDictionaryKey: "FocusFixturePath") as? String,
           Bundle.main.bundleIdentifier?.hasSuffix(".parity") == true {
            store = PomodoroStore(fileURL: URL(fileURLWithPath: fixture))
        } else { store = PomodoroStore() }
        super.init()
    }
    private let chime = CompletionChime()
    private var window: NSWindow!
    private var keyboard: Any?
    private var tokens: [NSObjectProtocol] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMenu()
        let frame = NSRect(x: 0, y: 0, width: 446, height: 476)
        window = FocusWindow(contentRect: frame, styleMask: [.borderless, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = Bundle.main.bundleIdentifier?.hasSuffix(".parity") == true ? "Pomolet · 对照校验" : "Pomolet"; window.backgroundColor = .clear; window.isOpaque = false; window.hasShadow = false
        window.isMovableByWindowBackground = true; window.isReleasedWhenClosed = false; window.delegate = self
        let host = NSHostingView(rootView: FocusRootView(store: store))
        host.wantsLayer = true; host.layer?.backgroundColor = NSColor.clear.cgColor; host.layer?.masksToBounds = false
        window.contentView = host; window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        store.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
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
    func windowWillClose(_ notification: Notification) { store.windowVisible = false; store.persist() }
    private func updateVisibility() { guard window != nil else { return }; store.windowVisible = window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible) && !NSApp.isHidden }
    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        let editor = NSApp.keyWindow?.firstResponder as? NSTextView
        if editor?.hasMarkedText() == true { return false }
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
        appMenu.addItem(item("关于Pomolet", action: #selector(about), target: self)); appMenu.addItem(.separator())
        appMenu.addItem(item("设置…", action: #selector(openSettings), key: ",", target: self)); appMenu.addItem(.separator())
        appMenu.addItem(item("隐藏Pomolet", action: #selector(NSApplication.hide(_:)), key: "h")); appMenu.addItem(item("显示全部", action: #selector(NSApplication.unhideAllApplications(_:))))
        appMenu.addItem(.separator()); appMenu.addItem(item("退出Pomolet", action: #selector(NSApplication.terminate(_:)), key: "q"))
        fileMenu.addItem(item("开始 / 暂停", action: #selector(toggleTimer), key: "\r", target: self)); fileMenu.addItem(item("重置计时", action: #selector(resetTimer), key: "r", target: self)); fileMenu.addItem(.separator()); fileMenu.addItem(item("关闭窗口", action: #selector(closeWindow), key: "w", target: self))
        editMenu.addItem(item("撤销", action: Selector(("undo:")), key: "z")); editMenu.addItem(item("重做", action: Selector(("redo:")), key: "Z")); editMenu.addItem(.separator())
        editMenu.addItem(item("剪切", action: #selector(NSText.cut(_:)), key: "x")); editMenu.addItem(item("复制", action: #selector(NSText.copy(_:)), key: "c")); editMenu.addItem(item("粘贴", action: #selector(NSText.paste(_:)), key: "v")); editMenu.addItem(item("全选", action: #selector(NSText.selectAll(_:)), key: "a"))
        viewMenu.addItem(item("番茄钟", action: #selector(openFocus), key: "1", target: self)); viewMenu.addItem(item("数据统计", action: #selector(openStatistics), key: "2", target: self)); viewMenu.addItem(item("切换深浅色", action: #selector(toggleTheme), key: "d", target: self))
        windowMenu.addItem(item("最小化", action: #selector(NSWindow.miniaturize(_:)), key: "m")); windowMenu.addItem(item("显示主窗口", action: #selector(showWindow), key: "0", target: self))
        submenu("Pomolet", appMenu); submenu("文件", fileMenu); submenu("编辑", editMenu); submenu("显示", viewMenu); submenu("窗口", windowMenu)
        NSApp.mainMenu = bar; NSApp.windowsMenu = windowMenu
    }
    @objc private func about() { NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Pomolet", .version: "1.0.0", .credits: NSAttributedString(string: "专注于眼前这一件事。\n原生 macOS · SwiftUI / AppKit")]) }
    @objc private func openSettings() { window.makeKeyAndOrderFront(nil); window.makeFirstResponder(nil); store.navigate(.settings) }
    @objc private func openStatistics() { window.makeKeyAndOrderFront(nil); window.makeFirstResponder(nil); store.navigate(.statistics) }
    @objc private func openFocus() { window.makeFirstResponder(nil); store.navigate(.focus) }
    @objc private func toggleTimer() { store.toggle() }
    @objc private func resetTimer() { store.reset() }
    @objc private func toggleTheme() { store.toggleTheme() }
    @objc private func closeWindow() { window.close() }
    @objc private func showWindow() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
}
final class FocusWindow: NSWindow {
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
