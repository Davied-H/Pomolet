import SwiftUI
import AppKit

struct ModeAnchorKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}
struct SettingsView: View {
    @ObservedObject var store: PomodoroStore
    @ObservedObject var timeline: MotionTimeline
    @State private var anchors: [String: CGRect] = [:]
    @State private var menuID: String?
    @State private var menuProgress = 0.0
    @State private var menuOffset = 0.0
    @State private var menuScale = 1.0
    @State private var menuClosing = false
    @State private var menuRevision = 0
    @State private var highlighted = 0
    @State private var focusID: String?
    private var palette: Palette { Palette(dark: store.dark) }
    private var menuPlacement: (rect: CGRect, above: Bool) {
        let anchor = anchors[menuID ?? ""] ?? CGRect(x: 280, y: 100, width: 36, height: 36)
        let above = 418 - anchor.maxY - 10 < 118 && anchor.minY > 128
        let x = max(14, min(anchor.maxX - 220, 154))
        let y = max(10, min(above ? anchor.minY - 125 : anchor.maxY + 7, 290))
        return (CGRect(x: x, y: y, width: 220, height: 118), above)
    }
    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                HStack { QuietIconButton(name: "back", label: store.text("返回番茄钟"), palette: palette, size: 28, focusID: "settingsBack") { finishEditing(); closeMenu(immediate: true); store.navigate(.focus) }; Spacer() }.padding(.horizontal, 22).frame(height: 48).modifier(PagePartMotion(timeline: timeline, namespace: "settings", part: "0", axis: "y"))
                ScrollView {
                    VStack(spacing: 0) {
                        languageSelector.padding(.bottom, 12)
                        HStack { Text(store.text("计时模式")).font(.system(size: 13, weight: .semibold)); Spacer(); Text("\(store.modes.count) / 5").font(.system(size: 11)).foregroundStyle(palette.sub).monospacedDigit() }.frame(height: 30).padding(.top, 4).padding(.bottom, 2)
                        VStack(spacing: 8) {
                            ForEach(store.modes) { mode in
                                SettingsModeRow(store: store, mode: mode, palette: palette, focusRequest: focusID == mode.id, openMenu: { toggleMenu(mode.id) }) {
                                    finishEditing(); closeMenu(immediate: true)
                                    let index = store.modes.firstIndex { $0.id == mode.id } ?? 0
                                    store.removeMode(mode.id)
                                    focusID = store.modes[min(index, store.modes.count - 1)].id
                                }
                            }
                        }.padding(.top, 8)
                        Button {
                            finishEditing(); closeMenu(immediate: true); focusID = store.addMode()
                        } label: {
                            HStack(spacing: 6) { if store.modes.count < 5 { Glyph(name: "plus", size: 13) }; Text(store.modes.count < 5 ? store.text("添加模式") : store.text("已达 5 个模式上限")).font(CSSFont.font(12, weight: 550)) }.foregroundStyle(store.modes.count < 5 ? palette.accent : palette.sub).frame(maxWidth: .infinity).frame(height: 42).background(palette.wash, in: RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(.plain).focusTarget("addMode").disabled(store.modes.count >= 5).opacity(store.modes.count >= 5 ? 0.4 : 1).padding(.top, 12).padding(.bottom, 8)
                        HStack {
                            Text(store.text("结束提示音")).font(.system(size: 12)); Spacer()
                            Button { store.toggleSound() } label: {
                                ZStack(alignment: .leading) {
                                    Capsule().fill(store.sound ? palette.accent : palette.side).overlay(Capsule().stroke(store.sound ? palette.accent : palette.line, lineWidth: 1))
                                    Circle().fill(store.sound ? palette.paper : palette.sub).frame(width: 13, height: 13).offset(x: store.sound ? 17 : 4)
                                }.frame(width: 34, height: 21)
                            }.buttonStyle(.plain).focusTarget("settingsSound").accessibilityLabel(store.text("结束提示音")).accessibilityValue(store.sound ? store.text("开启") : store.text("关闭")).animation(store.reduceMotion ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 0.2), value: store.sound)
                        }.frame(height: 44).overlay(alignment: .bottom) { Rectangle().fill(palette.line).frame(height: 1) }.padding(.top, 16).modifier(PagePartMotion(timeline: timeline, namespace: "settings", part: "1", axis: "y"))
                        Text(store.settingsMessage).font(.system(size: 10)).lineSpacing(5).foregroundStyle(palette.sub).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10).modifier(PagePartMotion(timeline: timeline, namespace: "settings", part: "2", axis: "y"))
                    }.padding(.horizontal, 26).padding(.top, 8).padding(.bottom, 24)
                }.scrollIndicators(.automatic)
            }
            if let id = menuID, let selected = store.modes.first(where: { $0.id == id }) {
                menu(for: selected).frame(width: 220, height: 118)
                    .background(palette.paper, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette.line, lineWidth: 1))
                    .mask(MenuReveal(progress: menuProgress, above: menuPlacement.above))
                    .scaleEffect(menuScale, anchor: menuPlacement.above ? .bottomTrailing : .topTrailing)
                    .offset(y: menuOffset).opacity(menuProgress).shadow(color: .black.opacity(store.dark ? 0.5 : 0.14), radius: 16, y: 10)
                    .position(x: menuPlacement.rect.midX, y: menuPlacement.rect.midY).zIndex(8).allowsHitTesting(!menuClosing)
            }
        }.frame(width: 388, height: 418).foregroundStyle(palette.ink).coordinateSpace(name: "settings")
            .onPreferenceChange(ModeAnchorKey.self) { new in
                if let id = menuID, let old = anchors[id], let next = new[id], abs(old.minY - next.minY) > 1 { closeMenu(immediate: true, restoreFocus: false) }
                anchors = new
            }
            .simultaneousGesture(SpatialTapGesture().onEnded { event in
                if let id = menuID, !menuClosing, !menuPlacement.rect.contains(event.location), !(anchors[id]?.contains(event.location) ?? false) { closeMenu(restoreFocus: false) }
            })
            .onReceive(NotificationCenter.default.publisher(for: .focusKeyboard)) { note in
                guard store.screen == .settings, let key = note.object as? UInt16 else { return }
                if key == 53 { if menuID != nil && !menuClosing { closeMenu() } else { finishEditing(); store.navigate(.focus) }; return }
                if menuID == nil, [125, 126].contains(key), let target = FocusRouting.currentID, target.hasPrefix("kind:") { toggleMenu(String(target.dropFirst(5))); return }
                guard let id = menuID, !menuClosing else { return }
                switch key {
                case 125: highlighted = (highlighted + 1) % 3
                case 126: highlighted = (highlighted + 2) % 3
                case 115: highlighted = 0
                case 119: highlighted = 2
                case 36, 76, 49: store.updateKind(id, kind: ModeKind.allCases[highlighted]); closeMenu()
                case 48:
                    let backward = note.userInfo?["shift"] as? Bool ?? false
                    let index = store.modes.firstIndex { $0.id == id } ?? 0
                    let target = backward
                        ? (store.modes.count > 1 ? "delete:" + id : "minutes:" + id)
                        : (index + 1 < store.modes.count ? "name:" + store.modes[index + 1].id : store.modes.count < 5 ? "addMode" : "settingsSound")
                    closeMenu(immediate: true)
                    DispatchQueue.main.async { FocusRouting.request(target) }
                default: break
                }
                if [125,126,115,119].contains(key) { FocusRouting.request("menu:" + ModeKind.allCases[highlighted].rawValue) }
            }
            .onChange(of: store.modes.map(\.id)) { _, _ in if menuID != nil { closeMenu(immediate: true) } }
            .onChange(of: store.screen) { _, screen in if screen != .settings { finishEditing(); closeMenu(immediate: true) } }
            .onDisappear { closeMenu(immediate: true) }
    }
    private var languageSelector: some View {
        HStack {
            Text(store.text("语言")).font(.system(size: 12))
            Spacer()
            HStack(spacing: 3) {
                ForEach(AppLanguage.allCases, id: \.self) { language in
                    Button {
                        finishEditing(); closeMenu(immediate: true)
                        store.setLanguage(language)
                    } label: {
                        Text(language.nativeName).font(.system(size: 11, weight: store.language == language ? .semibold : .regular))
                            .foregroundStyle(store.language == language ? palette.accent : palette.sub)
                            .frame(width: 68, height: 28)
                            .background(store.language == language ? palette.wash : .clear, in: RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain).focusTarget("language:" + language.rawValue)
                        .accessibilityLabel(language.nativeName).accessibilityAddTraits(store.language == language ? .isSelected : [])
                }
            }.padding(3).background(palette.side, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityElement(children: .contain).accessibilityLabel(store.text("界面语言"))
                .animation(store.reduceMotion ? nil : .easeOut(duration: 0.18), value: store.language)
        }.frame(height: 40)
    }
    private func menu(for mode: TimerMode) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(ModeKind.allCases.enumerated()), id: \.element) { index, kind in
                Button { store.updateKind(mode.id, kind: kind); closeMenu() } label: {
                    HStack(spacing: 8) {
                        Glyph(name: kind.symbol, size: 18).foregroundStyle(palette.accent)
                        HStack(alignment: .firstTextBaseline, spacing: 8) { Text(store.text(kind.title)).font(CSSFont.font(12, weight: 550)).lineLimit(1).minimumScaleFactor(0.8); Spacer(minLength: 0); Text(store.text(kind.detail)).font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.75).foregroundStyle(palette.sub) }.frame(maxWidth: .infinity)
                        Glyph(name: "check", size: 15).foregroundStyle(palette.accent).opacity(mode.kind == kind ? 1 : 0)
                    }.padding(.horizontal, 8).frame(height: 36).contentShape(Rectangle()).background(mode.kind == kind ? palette.wash : highlighted == index ? palette.side : .clear, in: RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(.plain).focusTarget("menu:" + kind.rawValue).onHover { hovering in if hovering { highlighted = index } }
                    .accessibilityLabel(store.text(kind.title) + ", " + store.text(kind.detail)).accessibilityAddTraits(mode.kind == kind ? .isSelected : [])
            }
        }.padding(4).accessibilityElement(children: .contain).accessibilityLabel(store.text("类型与动画"))
    }
    private func finishEditing() { NSApp.keyWindow?.makeFirstResponder(nil) }
    private func toggleMenu(_ id: String) {
        finishEditing()
        if menuID == id && !menuClosing { closeMenu(); return }
        menuRevision += 1; menuID = id; menuClosing = false; menuProgress = 0; menuScale = 0.975; menuOffset = menuPlacement.above ? 5 : -5; store.typeMenuOpen = true
        highlighted = ModeKind.allCases.firstIndex(of: store.modes.first(where: { $0.id == id })?.kind ?? .focus) ?? 0
        let revision = menuRevision
        DispatchQueue.main.async {
            guard revision == menuRevision else { return }
            withAnimation(store.reduceMotion ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 0.24)) { menuProgress = 1; menuScale = 1; menuOffset = 0 }
            FocusRouting.request("menu:" + ModeKind.allCases[highlighted].rawValue)
        }
    }
    private func closeMenu(immediate: Bool = false, restoreFocus: Bool = true) {
        guard menuID != nil else { return }
        menuRevision += 1; let revision = menuRevision
        menuClosing = true; store.typeMenuOpen = false
        let previousID = menuID!
        if restoreFocus { FocusRouting.request("kind:" + previousID) }
        if immediate || store.reduceMotion { menuProgress = 0; menuID = nil; menuClosing = false; return }
        withAnimation(.timingCurve(0.4, 0, 1, 1, duration: 0.15)) { menuProgress = 0; menuScale = 0.985; menuOffset = menuPlacement.above ? 4 : -4 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { if revision == menuRevision { menuID = nil; menuClosing = false } }
    }
}
struct SettingsModeRow: View {
    @ObservedObject var store: PomodoroStore
    var mode: TimerMode
    var palette: Palette
    var focusRequest: Bool
    var openMenu: () -> Void
    var remove: () -> Void
    @State private var name: String
    @State private var minutes: String
    @State private var nameFocused = false
    @State private var nameHovered = false
    @State private var minutesFocused = false
    init(store: PomodoroStore, mode: TimerMode, palette: Palette, focusRequest: Bool, openMenu: @escaping () -> Void, remove: @escaping () -> Void) {
        self.store = store; self.mode = mode; self.palette = palette; self.focusRequest = focusRequest; self.openMenu = openMenu; self.remove = remove
        _name = State(initialValue: store.displayName(mode)); _minutes = State(initialValue: String(mode.minutes))
    }
    var body: some View {
        HStack(spacing: 8) {
            NativeField(text: $name, placeholder: store.text("模式名称"), label: store.text("%@的名称", store.displayName(mode)), fontSize: 18, weight: NSFont.Weight(rawValue: 0.265), tracking: -0.45, color: NSColor(palette.ink), placeholderColor: NSColor(palette.sub), limit: 24, focusRequest: focusRequest, focusID: "name:" + mode.id, onValue: { _ = store.updateName(mode.id, value: $0) }, onFocus: { nameFocused = $0 }, onEnd: { name = store.displayName(store.modes.first(where: { $0.id == mode.id }) ?? mode); store.clearSettingsError(mode.id, field: .name) }).frame(height: 48)
                .overlay(alignment: .bottom) { Rectangle().fill(nameFocused ? palette.accent : nameHovered ? palette.line : .clear).frame(height: 1) }
                .onHover { nameHovered = $0 }.animation(store.reduceMotion ? nil : .easeOut(duration: 0.18), value: nameFocused).animation(store.reduceMotion ? nil : .easeOut(duration: 0.18), value: nameHovered)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                NativeField(text: $minutes, label: store.text("%@的分钟", store.displayName(mode)), fontSize: 20, weight: NSFont.Weight(rawValue: 0.265), tracking: -0.5, color: NSColor(palette.ink), placeholderColor: NSColor(palette.sub), alignment: .right, limit: 3, numericStepper: true, focusID: "minutes:" + mode.id, onValue: { _ = store.updateMinutes(mode.id, value: $0) }, onFocus: { minutesFocused = $0 }, onEnd: { minutes = String(store.modes.first(where: { $0.id == mode.id })?.minutes ?? mode.minutes); store.clearSettingsError(mode.id, field: .minutes) }).frame(height: 28)
                Text(store.text("分")).font(.system(size: 10)).foregroundStyle(palette.sub)
            }.padding(.horizontal, 8).frame(width: 64, height: 36).background(minutesFocused ? palette.minuteFocus : palette.side, in: RoundedRectangle(cornerRadius: 8)).animation(store.reduceMotion ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 0.22), value: minutesFocused)
            Button(action: openMenu) { Glyph(name: mode.kind.symbol, size: 15).foregroundStyle(palette.accent).frame(width: 36, height: 36).contentShape(Rectangle()) }.buttonStyle(.plain).focusTarget("kind:" + mode.id).help(store.text(mode.kind.title) + " · " + store.text(mode.kind.detail)).accessibilityLabel(store.text("%@的类型与动画：%@，%@", store.displayName(mode), store.text(mode.kind.title), store.text(mode.kind.detail)))
                .background(GeometryReader { geometry in Color.clear.preference(key: ModeAnchorKey.self, value: [mode.id: geometry.frame(in: .named("settings"))]) })
            Button(action: remove) { Glyph(name: "close", size: 14).foregroundStyle(palette.sub).frame(width: 28, height: 36).contentShape(Rectangle()) }.buttonStyle(.plain).focusTarget("delete:" + mode.id).disabled(store.modes.count <= 1).opacity(store.modes.count <= 1 ? 0.4 : 1).accessibilityLabel(store.text("删除%@", store.displayName(mode)))
        }.padding(.horizontal, 10).padding(.vertical, 8).background(palette.side, in: RoundedRectangle(cornerRadius: 12))
            .onChange(of: store.displayName(mode)) { _, value in if !nameFocused { name = value } }
            .onChange(of: mode.minutes) { _, value in if !minutesFocused { minutes = String(value) } }
    }
}
