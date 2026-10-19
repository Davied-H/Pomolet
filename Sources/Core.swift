import Foundation
import Combine

enum ModeKind: String, Codable, CaseIterable {
    case focus, short, long
    var title: String { switch self { case .focus: return "专注"; case .short: return "短休息"; case .long: return "长休息" } }
    var detail: String { switch self { case .focus: return "轻调耳机"; case .short: return "喝茶 · 闭眼"; case .long: return "舒展 · 哈欠" } }
    var symbol: String { switch self { case .focus: return "leaf"; case .short: return "clock"; case .long: return "moon" } }
    var actions: [String] { switch self { case .focus: return ["focus-adjust"]; case .short: return ["short", "short-eyes"]; case .long: return ["long", "long-yawn"] } }
}
struct TimerMode: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var minutes: Int
    var kind: ModeKind
    static let defaults = [TimerMode(id: "focus", name: "专注", minutes: 25, kind: .focus), TimerMode(id: "short", name: "短休息", minutes: 5, kind: .short), TimerMode(id: "long", name: "长休息", minutes: 15, kind: .long)]
}
struct FocusRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var endedAt: Date
    var task: String
    var minutes: Int
    var modeName: String
}
struct TimerSession: Codable {
    var selectedID: String
    var running: Bool
    var deadline: Date?
    var remaining: Int
    var total: Int
    var roundStarted: Bool
}
struct SavedState: Codable {
    var schemaVersion = 1
    var modes = TimerMode.defaults
    var sound = true
    var dark = false
    var task = ""
    var records: [FocusRecord] = []
    var session: TimerSession?
    var lastFocusID: String?
}
struct StatisticsData {
    struct Day {
        var date: Date
        var count: Int
        var minutes: Int
        var average: Double { count == 0 ? 0 : Double(minutes) / Double(count) }
    }
    var days: [Day]
    var week: [Double?]
    var today: Day { days[6] }
    var weekMinutes: Int { Int(week.compactMap { $0 }.last ?? 0) }
    static func build(records: [FocusRecord], now: Date, calendar: Calendar = .current) -> StatisticsData {
        let today = calendar.startOfDay(for: now)
        let valid = records.filter { $0.minutes > 0 && $0.minutes <= 1440 }
        func day(_ date: Date) -> Day {
            let items = valid.filter { calendar.isDate($0.endedAt, inSameDayAs: date) }
            return Day(date: date, count: items.count, minutes: items.reduce(0) { $0 + $1.minutes })
        }
        let days = (-6...0).map { day(calendar.date(byAdding: .day, value: $0, to: today)!) }
        let offset = (calendar.component(.weekday, from: today) + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -offset, to: today)!
        var cumulative = 0
        let week: [Double?] = (0...6).map { index in
            guard index <= offset else { return nil }
            cumulative += day(calendar.date(byAdding: .day, value: index, to: monday)!).minutes
            return Double(cumulative)
        }
        return StatisticsData(days: days, week: week)
    }
}
enum AppScreen { case focus, statistics, settings }
enum SettingsField: CaseIterable { case name, minutes }

@MainActor final class PomodoroStore: ObservableObject {
    @Published private(set) var modes = TimerMode.defaults
    @Published private(set) var selectedID = "focus"
    @Published private(set) var remaining = 1500
    @Published private(set) var total = 1500
    @Published private(set) var running = false
    @Published private(set) var roundStarted = false
    @Published private(set) var mediaResetID = 0
    @Published private(set) var records: [FocusRecord] = []
    @Published var sound = true
    @Published var dark = false
    @Published var task = ""
    @Published var screen: AppScreen = .focus
    @Published var typeMenuOpen = false
    @Published var settingsMessage = "修改自动保存。最多 5 个模式，每个 1–120 分钟。"
    @Published var toast: String?
    @Published var windowVisible = true
    @Published var reduceMotion = false
    private(set) var deadline: Date?
    private var lastFocusID = "focus"
    private var settingsErrors: [String: [SettingsField: String]] = [:]
    private var toastGeneration = 0
    private var lastDay: Date
    private var ticker: Timer?
    private let fileURL: URL
    private let now: () -> Date
    private var storageFailureShown = false
    var onCompletion: (() -> Void)?
    var selected: TimerMode { modes.first { $0.id == selectedID } ?? modes[0] }
    var timeText: String { String(format: "%02d:%02d", remaining / 60, remaining % 60) }
    var todayRecords: [FocusRecord] { records.filter { Calendar.current.isDate($0.endedAt, inSameDayAs: now()) }.sorted { $0.endedAt > $1.endedAt } }
    var statistics: StatisticsData { StatisticsData.build(records: records, now: now()) }
    var status: String { roundStarted ? "暂停片刻，随时继续" : selected.kind == .focus ? "准备好，进入心流" : "休息，也是专注的一部分" }
    init(fileURL: URL? = nil, startTicker: Bool = true, now: @escaping () -> Date = Date.init) {
        self.now = now
        self.lastDay = Calendar.current.startOfDay(for: now())
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FocusNative/state.json")
        load()
        if startTicker {
            let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
            RunLoop.main.add(timer, forMode: .common)
            ticker = timer
        }
        tick()
    }
    func setMode(_ id: String) {
        guard let mode = modes.first(where: { $0.id == id }) else { return }
        selectedID = id
        if mode.kind == .focus { lastFocusID = id }
        running = false; deadline = nil; remaining = mode.minutes * 60; total = remaining; roundStarted = false; mediaResetID += 1
        persist()
    }
    func toggle() {
        if running {
            remaining = max(0, Int(ceil((deadline ?? now()).timeIntervalSince(now()))))
            running = false; deadline = nil
        } else {
            if remaining <= 0 { remaining = total }
            deadline = now().addingTimeInterval(Double(remaining))
            running = true; roundStarted = true
        }
        persist()
    }
    func reset() { setMode(selectedID); showToast("已重置本轮计时") }
    func tick() {
        let date = now(), day = Calendar.current.startOfDay(for: date)
        if day != lastDay { lastDay = day; objectWillChange.send() }
        guard running, let end = deadline else { return }
        let next = max(0, Int(ceil(end.timeIntervalSince(date))))
        if remaining != next { remaining = next }
        guard next == 0 else { return }
        let completed = selected
        running = false; deadline = nil
        if completed.kind == .focus {
            records.append(FocusRecord(endedAt: end, task: task.trimmingCharacters(in: .whitespacesAndNewlines), minutes: total / 60, modeName: completed.name))
            let count = records.filter { Calendar.current.isDate($0.endedAt, inSameDayAs: end) }.count
            let preferred: ModeKind = count % 4 == 0 ? .long : .short
            let next = modes.first { $0.kind == preferred } ?? modes.first { $0.kind == .short } ?? modes.first { $0.kind == .long } ?? modes[0]
            setMode(next.id)
            showToast(next.kind == .focus ? "专注完成，准备下一段时间。" : "专注完成。现在，给自己一点休息。")
        } else {
            let next = modes.first { $0.id == lastFocusID && $0.kind == .focus } ?? modes.first { $0.kind == .focus } ?? modes[0]
            setMode(next.id)
            showToast(next.kind == .focus ? "休息结束，准备开启下一次专注。" : "休息结束，准备开启下一段时间。")
        }
        if sound { onCompletion?() }
        persist()
    }
    @discardableResult func updateName(_ id: String, value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { setSettingsError(id, field: .name, message: "名称不能为空"); return false }
        guard trimmed.count <= 6 else { setSettingsError(id, field: .name, message: "名称最多 6 个字"); return false }
        guard !modes.contains(where: { $0.id != id && $0.name == trimmed }) else { setSettingsError(id, field: .name, message: "模式名称不能重复"); return false }
        guard let index = modes.firstIndex(where: { $0.id == id }) else { return false }
        modes[index].name = trimmed; clearSettingsError(id, field: .name); persist(); return true
    }
    @discardableResult func updateMinutes(_ id: String, value: String) -> Bool {
        guard let minutes = Int(value), (1...120).contains(minutes) else { setSettingsError(id, field: .minutes, message: "时长需为 1–120 整数分钟"); return false }
        guard let index = modes.firstIndex(where: { $0.id == id }) else { return false }
        if modes[index].minutes != minutes {
            modes[index].minutes = minutes
            if selectedID == id { setMode(id) }
        }
        clearSettingsError(id, field: .minutes); persist(); return true
    }
    func updateKind(_ id: String, kind: ModeKind) {
        guard let index = modes.firstIndex(where: { $0.id == id }) else { return }
        if modes[index].kind != kind { modes[index].kind = kind; if selectedID == id { setMode(id) } }
        settingsOK(); persist()
    }
    @discardableResult func addMode() -> String? {
        guard modes.count < 5 else { return nil }
        var name = "新模式", suffix = 2
        while modes.contains(where: { $0.name == name }) { name = "新模式\(suffix)"; suffix += 1 }
        let id = UUID().uuidString
        modes.append(TimerMode(id: id, name: name, minutes: 25, kind: .focus)); settingsOK(); persist(); return id
    }
    func removeMode(_ id: String) {
        guard modes.count > 1 else { return }
        modes.removeAll { $0.id == id }
        settingsErrors[id] = nil
        if !modes.contains(where: { $0.id == selectedID }) { setMode(modes[0].id) }
        settingsOK(); persist()
    }
    // An input's invalid draft remains local to its editor. Other successful edits
    // must not clear its error until that field is corrected or restored on blur.
    private func setSettingsError(_ id: String, field: SettingsField, message: String) {
        settingsErrors[id, default: [:]][field] = message
        settingsOK()
    }
    func clearSettingsError(_ id: String, field: SettingsField) {
        settingsErrors[id]?[field] = nil
        if settingsErrors[id]?.isEmpty == true { settingsErrors[id] = nil }
        settingsOK()
    }
    func settingsOK() {
        let firstError = modes.lazy.compactMap { mode in
            SettingsField.allCases.compactMap { self.settingsErrors[mode.id]?[$0] }.first
        }.first
        settingsMessage = firstError.map { $0 + "，已保留上次有效设置。" } ?? "修改自动保存。最多 5 个模式，每个 1–120 分钟。"
    }
    func saveTask(_ value: String) { task = String(value.prefix(50)); persist() }
    func toggleSound() { sound.toggle(); persist() }
    func toggleTheme() { dark.toggle(); persist() }
    func navigate(_ destination: AppScreen) { screen = destination }
    func showToast(_ message: String) {
        toastGeneration += 1
        let generation = toastGeneration
        toast = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.toastGeneration == generation else { return }; self.toast = nil
        }
    }
    func persist() {
        let state = SavedState(modes: modes, sound: sound, dark: dark, task: task, records: records, session: TimerSession(selectedID: selectedID, running: running, deadline: deadline, remaining: remaining, total: total, roundStarted: roundStarted), lastFocusID: lastFocusID)
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .deferredToDate
            try encoder.encode(state).write(to: fileURL, options: .atomic)
        } catch {
            if !storageFailureShown { storageFailureShown = true; showToast("暂时无法保存设置，请检查本地目录权限。") }
        }
    }
    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .deferredToDate
            let state = try decoder.decode(SavedState.self, from: Data(contentsOf: fileURL))
            var ids = Set<String>(), names = Set<String>()
            let valid = state.modes.filter { mode in
                guard !mode.id.isEmpty, !mode.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, mode.name.count <= 6, (1...120).contains(mode.minutes), !ids.contains(mode.id), !names.contains(mode.name) else { return false }
                ids.insert(mode.id); names.insert(mode.name); return true
            }
            modes = valid.isEmpty ? TimerMode.defaults : Array(valid.prefix(5))
            sound = state.sound; dark = state.dark; task = String(state.task.prefix(50)); records = state.records.filter { $0.minutes > 0 && $0.minutes <= 1440 }
            selectedID = modes[0].id; remaining = modes[0].minutes * 60; total = remaining
            lastFocusID = modes.first { $0.id == state.lastFocusID && $0.kind == .focus }?.id ?? modes.first { $0.kind == .focus }?.id ?? selectedID
            if let session = state.session, modes.contains(where: { $0.id == session.selectedID }), session.total == (modes.first { $0.id == session.selectedID }!.minutes * 60), (0...session.total).contains(session.remaining) {
                selectedID = session.selectedID; remaining = session.remaining; total = session.total; roundStarted = session.roundStarted
                if selected.kind == .focus { lastFocusID = selectedID }
                if session.running, let end = session.deadline { running = true; deadline = end }
            }
        } catch { toast = "本地数据无法读取，已使用默认设置。原文件未改动。" }
    }
}
