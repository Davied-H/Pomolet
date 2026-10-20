import SwiftUI
import AppKit

struct FocusRootView: View {
    @ObservedObject var store: PomodoroStore
    @ObservedObject var presentation: WindowPresentation
    @StateObject private var media = CharacterPlayer()
    @State private var focusProgress = 0.0
    @State private var chromeVisible = true
    @StateObject private var liquid = LiquidSpring()
    @State private var flowBusy = false
    @State private var flowInterrupted = false
    @State private var flowRevision = 0
    @StateObject private var navigation = NavigationMotion()
    @State private var taskText = ""
    @State private var taskFocused = false
    @State private var soundHover = false
    private let width = 390.0, height = 420.0
    private var palette: Palette { Palette(dark: store.dark) }
    private var layoutAnimation: Animation { .timingCurve(0.16, 1, 0.3, 1, duration: store.running ? 0.41 : 0.37) }
    @MainActor init(store: PomodoroStore, presentation: WindowPresentation) {
        self.store = store
        self.presentation = presentation
        _focusProgress = State(initialValue: store.running ? 1 : 0)
        _chromeVisible = State(initialValue: !store.running)
        _taskText = State(initialValue: store.task)
        _liquid = StateObject(wrappedValue: LiquidSpring(initial: store.roundStarted ? 1 : 0))
    }
    var body: some View {
        ZStack(alignment: .topLeading) {
            CardSurface(palette: palette)
            mainScreen.opacity(navigation.timeline.value("home.opacity", fallback: 1)).allowsHitTesting(store.screen == .focus).disabled(store.screen != .focus).accessibilityHidden(store.screen != .focus)
            if navigation.statisticsMounted {
                StatisticsView(store: store, timeline: navigation.timeline).frame(width: width - 2, height: height - 2).background(palette.paper).clipShape(RoundedRectangle(cornerRadius: 24))
                    .opacity(navigation.timeline.value("statistics.opacity")).offset(x: 1, y: 1).allowsHitTesting(store.screen == .statistics).disabled(store.screen != .statistics).accessibilityHidden(store.screen != .statistics)
            }
            if navigation.settingsMounted {
                SettingsView(store: store, timeline: navigation.timeline).frame(width: width - 2, height: height - 2).background(palette.paper).clipShape(RoundedRectangle(cornerRadius: 24))
                    .mask(CircleReveal(progress: navigation.timeline.value("settings.reveal"), origin: CGPoint(x: 347.5, y: 37))).offset(x: 1, y: 1).allowsHitTesting(store.screen == .settings).disabled(store.screen != .settings).accessibilityHidden(store.screen != .settings)
            }
            RoundedRectangle(cornerRadius: 24).strokeBorder(Color.white.opacity(store.dark ? 0.22 : 0.5), lineWidth: 1).allowsHitTesting(false)
            NativeToast(store: store).zIndex(40)
        }
        .frame(width: width, height: height)
        .environment(\.locale, store.language.locale)
        .environment(\.colorScheme, store.dark ? .dark : .light)
        .padding(28)
        .overlay(alignment: .top) {
            WindowDragArea(onDragBegin: { presentation.beginDrag?() }, onDragUpdate: { presentation.updateDrag?($0) }, onDragEnd: { presentation.finishDrag?($0) }).frame(width: width, height: 18).padding(.top, 28)
        }
        .onAppear {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { updateFocus(initial: true); updateNavigation() }
            synchronizeMedia()
        }
        .onChange(of: store.running) { _, _ in updateFocus(); synchronizeMedia() }
        .onChange(of: store.roundStarted) { _, started in if !started { liquid.setTarget(0,instant:store.reduceMotion || !store.windowVisible) }; synchronizeMedia() }
        .onChange(of: store.mediaResetID) { _, _ in synchronizeMedia(reset: true) }
        .onChange(of: store.screen) { old, next in
            updateNavigation(); synchronizeMedia()
            let delay = next == .settings ? 0.5 : 0.01
            DispatchQueue.main.asyncAfter(deadline: .now() + (store.reduceMotion ? 0 : delay)) {
                guard store.screen == next else { return }
                FocusRouting.request(next == .settings ? "settingsBack" : next == .statistics ? "statisticsBack" : store.running ? "start" : old == .settings ? "settings" : "statistics")
            }
        }
        .onChange(of: store.dark) { _, _ in synchronizeMedia() }
        .onChange(of: store.windowVisible) { _, visible in if !visible { updateFocus(initial:true) }; synchronizeMedia() }
        .onChange(of: store.reduceMotion) { _, _ in updateFocus(); updateNavigation(); synchronizeMedia() }
    }
    private var mainScreen: some View {
        ZStack(alignment: .topLeading) {
            CharacterView(media: media, dark: store.dark, reduced: store.reduceMotion || presentation.transition != nil)
                .frame(width: 255.6, height: 340.8).scaleEffect(1 + 0.2 * focusProgress)
                .position(x: 91.5 + 102.5 * focusProgress, y: 128.28 - 44.744 * focusProgress)
                .animation(store.reduceMotion ? nil : layoutAnimation.delay(flowInterrupted ? 0 : store.running ? 0.11 : 0), value: focusProgress)
                .modifier(PagePartMotion(timeline: navigation.timeline, namespace: "home", part: "character"))
            toolbar.frame(width: 336, height: 38).position(x: 194, y: 37).modifier(PagePartMotion(timeline: navigation.timeline, namespace: "home", part: "header")).modifier(ChromeMotion(visible: chromeVisible, index: 0, reduced: store.reduceMotion, interrupted: flowInterrupted))
            Text(store.status).font(.system(size: 10)).foregroundStyle(palette.sub).frame(width: 198).position(x: 264, y: 116.2)
                .modifier(PagePartMotion(timeline: navigation.timeline, namespace: "home", part: "clock"))
                .modifier(ChromeMotion(visible: chromeVisible, index: 2, reduced: store.reduceMotion, interrupted: flowInterrupted))
            FocusClock(text:store.timeText,progress:focusProgress,color:palette.ink)
                .opacity(presentation.transition == nil ? 1 : 0)
                .accessibilityLabel(store.text("剩余 %d 分 %d 秒", store.remaining / 60, store.remaining % 60))
                .animation(store.reduceMotion ? nil : layoutAnimation.delay(flowInterrupted ? 0 : store.running ? 0.135 : 0.015), value: focusProgress)
                .modifier(PagePartMotion(timeline: navigation.timeline, namespace: "home", part: "clock"))
            taskField.frame(width: 336, height: 38).position(x: 194, y: 270)
                .modifier(PagePartMotion(timeline: navigation.timeline, namespace: "home", part: "task"))
                .modifier(ChromeMotion(visible: chromeVisible, index: 1, reduced: store.reduceMotion, interrupted: flowInterrupted))
            TimerControls(store: store, palette: palette, separation: liquid.position).frame(width: 336, height: 44).position(x: 194, y: 327 + 47 * focusProgress)
                .animation(store.reduceMotion ? nil : layoutAnimation.delay(flowInterrupted ? 0 : store.running ? 0.16 : 0.03), value: focusProgress)
                .modifier(PagePartMotion(timeline: navigation.timeline, namespace: "home", part: "controls"))
            footer.frame(width: 336, height: 43).position(x: 194, y: 393.5)
                .modifier(PagePartMotion(timeline: navigation.timeline, namespace: "home", part: "footer"))
                .modifier(ChromeMotion(visible: chromeVisible, index: 3, reduced: store.reduceMotion, interrupted: flowInterrupted))
        }.frame(width: width - 2, height: height - 2).offset(x: 1, y: 1)
    }
    private var toolbar: some View {
        HStack(spacing: 8) {
            GeometryReader { geometry in
                let itemWidth = (geometry.size.width - 8) / CGFloat(store.modes.count)
                let index = store.modes.firstIndex { $0.id == store.selectedID } ?? 0
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8).fill(store.dark ? Color.white : palette.button).shadow(color: .black.opacity(store.dark ? 0 : 0.06), radius: 1.5, y: 1)
                        .frame(width: itemWidth, height: 27).offset(x: 4 + CGFloat(index) * itemWidth)
                        .animation(store.reduceMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.38), value: store.selectedID)
                    HStack(spacing: 0) {
                        ForEach(store.modes) { mode in
                            Button { store.setMode(mode.id) } label: {
                                Text(store.displayName(mode)).font(CSSFont.font(11, weight: store.selectedID == mode.id ? 650 : 400)).lineLimit(1)
                                    .foregroundStyle(store.selectedID == mode.id ? (store.dark ? Color.black : palette.accent) : palette.sub)
                                    .frame(width: itemWidth, height: 27).contentShape(Rectangle())
                            }.buttonStyle(.plain).focusable(store.selectedID == mode.id).focusTarget("mode:" + mode.id).help(store.text("%@ · %d 分钟", store.displayName(mode), mode.minutes)).accessibilityAddTraits(store.selectedID == mode.id ? .isSelected : [])
                        }
                    }.padding(.horizontal, 4)
                }.frame(height: 35)
            }.frame(height: 35)
            HStack(spacing: 4) {
                QuietIconButton(name: "chart", label: store.text("数据统计"), palette: palette, glyphOpacity: navigation.timeline.value("chartGlyph.opacity", fallback: 1), glyphScale: navigation.timeline.value("chartGlyph.scale", fallback: 1), foreground: store.screen == .statistics ? palette.accent : palette.ink, pressed: store.screen == .statistics, focusID: "statistics") { store.navigate(.statistics) }
                QuietIconButton(name: "gear", label: store.text("打开计时设置"), palette: palette, glyphRotation: store.screen == .settings ? 75 : 0, foreground: store.screen == .settings ? palette.accent : palette.ink, pressed: store.screen == .settings, reduceMotion: store.reduceMotion, focusID: "settings") { store.navigate(.settings) }
            }
        }
    }
    private var taskField: some View {
        HStack(spacing: 9) {
            Glyph(name: "pencil", size: 14).foregroundStyle(taskFocused ? palette.accent : palette.sub)
            NativeField(text: $taskText, placeholder: store.text("点击输入本次专注事项（可选）"), label: store.text("当前专注任务"), fontSize: 11, color: NSColor(palette.ink), placeholderColor: NSColor(palette.sub), focusID: "task", onValue: { store.saveTask($0) }, onFocus: { taskFocused = $0 })
        }.padding(.horizontal, 2).overlay(alignment: .bottom) { Rectangle().fill(taskFocused ? palette.accent : palette.line).frame(height: 1) }
            .animation(store.reduceMotion ? nil : .easeOut(duration: 0.18), value: taskFocused)
    }
    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(palette.line).frame(height: 1)
            HStack(spacing: 7) {
                Text(store.text("今日")).font(.system(size: 10)).foregroundStyle(palette.sub)
                HStack(spacing: 5) { ForEach(0..<4) { index in Circle().fill(index < store.todayRecords.count ? palette.accent : Color(hex: store.dark ? 0x383838 : 0xd5ddcf)).frame(width: 6, height: 6) } }
                Text("\(store.todayRecords.count) / 4").font(.system(size: 10)).foregroundStyle(palette.sub).padding(.leading, 1)
                Spacer()
                HStack(spacing: 7) {
                    QuietIconButton(name: "sound", label: store.sound ? store.text("关闭结束提示音") : store.text("开启结束提示音"), palette: palette, size: 24, height: 22, glyphSize: 14, buttonOpacity: store.sound ? 1 : 0.45, tooltip: store.sound ? store.text("结束时轻声提醒") : store.text("结束提示音已关闭"), foreground: palette.sub, customTooltip: true, reduceMotion: store.reduceMotion, focusID: "sound") { store.toggleSound() }
                    Button { presentation.togglePin?() } label: {
                        Image(systemName: presentation.pinned ? "pin.fill" : "pin").font(.system(size: 12)).foregroundStyle(presentation.pinned ? palette.accent : palette.sub).frame(width: 24, height: 22)
                    }.buttonStyle(.plain).help(presentation.pinned ? store.text("取消窗口置顶") : store.text("窗口置顶")).accessibilityLabel(presentation.pinned ? store.text("取消窗口置顶") : store.text("窗口置顶"))
                    QuietIconButton(name: "moon", label: store.text("切换深浅色"), palette: palette, size: 24, height: 22, glyphSize: 14, foreground: palette.sub, focusID: "theme") { store.toggleTheme() }
                }
            }.frame(height: 42)
        }
    }
    private func synchronizeMedia(reset: Bool = false) { media.synchronize(kind: store.selected.kind, playing: store.running && store.screen == .focus && store.windowVisible && !store.reduceMotion && presentation.transition == nil, dark: store.dark, reset: reset) }
    private func updateFocus(initial:Bool = false) {
        flowRevision += 1; let revision = flowRevision
        flowInterrupted = flowBusy; flowBusy = true
        focusProgress = store.running ? 1 : 0; chromeVisible = !store.running
        if initial || store.reduceMotion || !store.windowVisible { liquid.setTarget(store.roundStarted ? 1 : 0,instant:true);flowBusy=false;return }
        if !store.running { liquid.setTarget(store.roundStarted ? 1 : 0) }
        else {
            DispatchQueue.main.asyncAfter(deadline: .now() + (flowInterrupted ? 0.12 : 0.3)) {
                guard revision == flowRevision, store.running else { return }; liquid.setTarget(store.roundStarted ? 1 : 0)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.61) { if revision == flowRevision { flowBusy = false } }
    }
    private func updateNavigation() {
        navigation.update(to: store.screen, running: store.running, empty: store.todayRecords.isEmpty, reduced: store.reduceMotion)
    }
}
struct ChromeMotion: ViewModifier {
    var visible: Bool
    var index: Int
    var reduced: Bool
    var interrupted: Bool
    func body(content: Content) -> some View {
        content.opacity(visible ? 1 : 0).offset(y: visible ? 0 : (index == 1 || index == 3 ? 5 : -5))
            .allowsHitTesting(visible).disabled(!visible).accessibilityHidden(!visible)
            .animation(reduced ? nil : visible ? .timingCurve(0.16, 1, 0.3, 1, duration: 0.26).delay(interrupted ? 0.04 : 0.14 + Double(index) * 0.025) : .timingCurve(0.4, 0, 1, 1, duration: 0.15).delay(interrupted ? 0 : Double(index) * 0.015), value: visible)
    }
}
