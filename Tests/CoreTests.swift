import Foundation

@MainActor @main struct CoreTests {
    static var assertions = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) { assertions += 1; if !condition() { fatalError("FAIL: \(message)") } }
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("focus-native-tests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        var date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 12))!
        let file = folder.appendingPathComponent("state.json")
        let store = PomodoroStore(fileURL: file, startTicker: false, now: { date })
        check(store.modes.count == 3 && store.remaining == 1500, "default modes")
        store.toggle(); date = date.addingTimeInterval(3.2); store.tick(); check(store.remaining == 1497, "wall-clock tick")
        let deadline = store.deadline
        check(store.updateName("focus", value: "深度专注"), "rename")
        check(store.running && store.deadline == deadline && store.mediaResetID == 0, "rename preserves live timer and media")
        store.toggleSound(); check(store.running && store.deadline == deadline, "sound preserves live timer")
        check(!store.updateMinutes("focus", value: ""), "empty minutes rejected")
        check(!store.updateMinutes("focus", value: "0"), "zero minutes rejected")
        check(!store.updateMinutes("focus", value: "1.5"), "non-integer rejected")
        check(!store.updateName("focus", value: "短休息"), "duplicate name rejected")
        check(store.running && store.selected.minutes == 25, "invalid edits keep live timer")
        store.toggle(); check(!store.running && store.roundStarted && store.remaining == 1497, "pause keeps reset available")
        store.updateMinutes("focus", value: "1"); check(store.remaining == 60 && !store.roundStarted && store.mediaResetID > 0, "current duration change resets timer and media")
        store.saveTask("写作"); store.toggle(); date = date.addingTimeInterval(60); store.tick()
        check(store.records.count == 1 && store.records[0].minutes == 1 && store.records[0].task == "写作", "completion writes actual focus record")
        check(store.selected.kind == .short && !store.running, "focus routes to short rest")
        for _ in 0..<3 { store.setMode("focus"); store.toggle(); date = date.addingTimeInterval(60); store.tick() }
        check(store.todayRecords.count == 4 && store.selected.kind == .long, "fourth focus routes to long rest")
        let custom = store.addMode()!; check(store.updateName(custom, value: "阅读"), "custom name")
        store.updateMinutes(custom, value: "2"); store.setMode(custom); store.toggle(); date = date.addingTimeInterval(120); store.tick()
        check(store.selected.kind == .short, "custom focus routes to rest")
        store.toggle(); date = date.addingTimeInterval(Double(store.total)); store.tick(); check(store.selectedID == custom, "rest returns to last custom focus")
        _ = store.addMode(); check(store.modes.count == 5 && store.addMode() == nil, "five-mode cap")
        let names = Set(store.modes.map(\.name)); check(names.count == 5, "new mode names unique")
        store.toggleTheme(); store.persist()
        let reloaded = PomodoroStore(fileURL: file, startTicker: false, now: { date })
        check(reloaded.modes == store.modes && reloaded.dark == store.dark && reloaded.records == store.records, "JSON round-trip")
        reloaded.setMode(custom); reloaded.toggle()
        let resumed = PomodoroStore(fileURL: file, startTicker: false, now: { date.addingTimeInterval(10) })
        check(resumed.running && resumed.remaining == 110, "running session restores from deadline")
        let expired = PomodoroStore(fileURL: file, startTicker: false, now: { date.addingTimeInterval(180) })
        check(!expired.running && expired.records.count == reloaded.records.count + 1, "expired session completes once on relaunch")
        let once = PomodoroStore(fileURL: file, startTicker: false, now: { date.addingTimeInterval(200) })
        check(once.records.count == expired.records.count, "completion not duplicated")
        store.removeMode(custom); check(store.selectedID != custom && store.modes.count == 4, "deleting selected mode falls back")
        while store.modes.count > 1 { store.removeMode(store.modes.last!.id) }
        store.removeMode(store.modes[0].id); check(store.modes.count == 1, "last mode protected")
        store.setMode(store.modes[0].id); store.toggle(); date = date.addingTimeInterval(Double(store.total)); store.tick(); check(!store.running && store.modes.count == 1, "single-mode completion safe")
        let validationFile = folder.appendingPathComponent("validation.json")
        let validation = PomodoroStore(fileURL: validationFile, startTicker: false, now: { date })
        check(!validation.updateName("focus", value: ""), "blank name creates field error")
        validation.updateMinutes("short", value: "6")
        check(validation.settingsMessage.contains("名称不能为空"), "valid duration edit keeps another row name error")
        validation.updateKind("long", kind: .short)
        check(validation.settingsMessage.contains("名称不能为空"), "animation edit keeps outstanding error")
        _ = validation.updateMinutes("short", value: "0")
        validation.clearSettingsError("focus", field: .name)
        check(validation.settingsMessage.contains("时长需为"), "blur restores only own field and reveals next error")
        _ = validation.updateName("long", value: "散步")
        check(validation.settingsMessage.contains("时长需为"), "valid name keeps outstanding duration error")
        validation.updateMinutes("short", value: "7")
        check(validation.settingsMessage.hasPrefix("修改自动保存"), "correcting final invalid field restores neutral note")
        _ = validation.updateMinutes("short", value: "")
        validation.clearSettingsError("short", field: .minutes)
        check(validation.settingsMessage.hasPrefix("修改自动保存") && validation.modes[1].minutes == 7, "duration blur clears its draft error while retaining last valid setting")
        _ = validation.updateName("short", value: "")
        validation.removeMode("short")
        check(validation.settingsMessage.hasPrefix("修改自动保存"), "removing invalid row removes its error")

        let routingFile = folder.appendingPathComponent("routing.json")
        let routing = PomodoroStore(fileURL: routingFile, startTicker: false, now: { date })
        let reading = routing.addMode()!
        routing.updateName(reading, value: "阅读")
        routing.updateMinutes(reading, value: "1")
        routing.setMode(reading); routing.toggle(); date = date.addingTimeInterval(60); routing.tick()
        let restReload = PomodoroStore(fileURL: routingFile, startTicker: false, now: { date })
        check(restReload.selected.kind == .short, "rest selection restores on relaunch")
        restReload.toggle(); date = date.addingTimeInterval(Double(restReload.total)); restReload.tick()
        check(restReload.selectedID == reading, "rest after relaunch returns to last custom focus")
        var payload = try JSONSerialization.jsonObject(with: Data(contentsOf: routingFile)) as! [String: Any]
        payload.removeValue(forKey: "lastFocusID")
        try JSONSerialization.data(withJSONObject: payload).write(to: routingFile)
        let legacy = PomodoroStore(fileURL: routingFile, startTicker: false, now: { date })
        check(legacy.modes.count == 4 && legacy.selectedID == reading && legacy.toast == nil, "legacy JSON without last focus remains readable")
        legacy.setMode("short")
        payload = try JSONSerialization.jsonObject(with: Data(contentsOf: routingFile)) as! [String: Any]
        payload["lastFocusID"] = "short"
        try JSONSerialization.data(withJSONObject: payload).write(to: routingFile)
        let invalidLast = PomodoroStore(fileURL: routingFile, startTicker: false, now: { date })
        invalidLast.toggle(); date = date.addingTimeInterval(Double(invalidLast.total)); invalidLast.tick()
        check(invalidLast.selectedID == "focus", "stored rest id cannot become last focus")
        invalidLast.setMode("short")
        payload = try JSONSerialization.jsonObject(with: Data(contentsOf: routingFile)) as! [String: Any]
        payload["lastFocusID"] = "deleted-custom"
        try JSONSerialization.data(withJSONObject: payload).write(to: routingFile)
        let missingLast = PomodoroStore(fileURL: routingFile, startTicker: false, now: { date })
        missingLast.toggle(); date = date.addingTimeInterval(Double(missingLast.total)); missingLast.tick()
        check(missingLast.selectedID == "focus", "deleted stored last focus falls back safely")
        let tuesday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 12))!
        func record(_ day: Int, _ minutes: Int) -> FocusRecord { FocusRecord(endedAt: calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 11))!, task: "", minutes: minutes, modeName: "专注") }
        let stats = StatisticsData.build(records: [record(18, 50), record(19, 30), record(20, 25), record(20, 15)], now: tuesday, calendar: calendar)
        check(stats.today.minutes == 40 && stats.today.count == 2 && stats.today.average == 20, "daily statistics")
        check(stats.weekMinutes == 70 && stats.week == [30, 70, nil, nil, nil, nil, nil], "calendar week excludes Sunday and future days")
        let empty = StatisticsData.build(records: [], now: tuesday, calendar: calendar)
        check(empty.today.average == 0 && empty.weekMinutes == 0, "empty statistics")
        let corrupt = folder.appendingPathComponent("corrupt.json"); let bad = Data("broken".utf8); try bad.write(to: corrupt)
        let fallback = PomodoroStore(fileURL: corrupt, startTicker: false, now: { date })
        check(fallback.modes == TimerMode.defaults && fallback.toast != nil, "corrupt storage fallback")
        let unchanged = try Data(contentsOf: corrupt)
        check(unchanged == bad, "corrupt file remains untouched during load")
        print("PASS: \(assertions) native assertions: timer, pause/reset, automatic settings, five modes, completion/rest routing, JSON storage, relaunch/wake deadlines, statistics and damaged data.")
    }
}
