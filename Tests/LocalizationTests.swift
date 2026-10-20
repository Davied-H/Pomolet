import Foundation

@MainActor @main struct LocalizationTests {
    static var checks=0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) { checks += 1; if !condition() { fatalError("FAIL: " + message) } }
    static func main() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("pomolet-i18n-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:directory)}
        let file=directory.appendingPathComponent("state.json")
        var date=Date(timeIntervalSince1970:1_792_454_400)
        let store=PomodoroStore(fileURL:file,startTicker:false,now:{date})
        check(AppLanguage.preferred(["zh-TW"]) == .zhHans,"Chinese system fallback")
        check(AppLanguage.preferred(["en-GB"]) == .english,"English system fallback")
        check(AppLanguage.preferred(["fr-FR","zh-Hans"]) == .zhHans,"first supported preferred locale")
        check(AppLanguage.preferred(["de"]) == .english,"unsupported system locale fallback")
        store.setLanguage(.zhHans)
        check(store.displayName(store.selected) == "专注","Chinese built-in label")
        store.saveTask("Research my project");store.toggle()
        let deadline=store.deadline,resetID=store.mediaResetID,total=store.total
        store.setLanguage(.english)
        check(store.running && store.deadline == deadline && store.mediaResetID == resetID && store.total == total,"language switch preserves running session")
        check(store.displayName(store.selected) == "Focus","default label follows language")
        check(store.modes[0].name == "专注" && store.task == "Research my project","language switch does not rewrite user data")
        check(store.controlTitle == "Pause","running control localized")
        check(store.updateName("focus",value:"Focus") && store.modes[0].builtInName == .focus,"unchanged translated edit preserves default identity")
        check(!store.updateName("focus",value:"Short break"),"duplicate translated label rejected")
        check(store.updateName("focus",value:"Deep work and reading"),"English names longer than six characters accepted")
        check(store.modes[0].builtInName == nil,"renamed mode becomes user-authored")
        store.setLanguage(.zhHans)
        check(store.displayName(store.selected) == "Deep work and reading","custom name unchanged in Chinese")
        check(store.running && store.deadline == deadline,"custom rename preserves timer")
        store.setLanguage(.english)
        let restored=PomodoroStore(fileURL:file,startTicker:false,now:{date})
        check(restored.language == .english && restored.running && restored.deadline == deadline,"language and running session survive relaunch")
        check(restored.displayName(restored.selected) == "Deep work and reading","long custom name survives relaunch")
        restored.toggle()
        let first=restored.addMode()!,second=restored.addMode()!
        check(restored.displayName(restored.modes.first{$0.id == first}!) == "New mode","new name in active language")
        check(restored.displayName(restored.modes.first{$0.id == second}!) == "New mode 2","unique new English name")
        check(!restored.updateName("short",value:""),"invalid draft rejected")
        check(restored.settingsMessage.hasPrefix("Enter a mode name"),"English error")
        restored.setLanguage(.zhHans)
        check(restored.settingsMessage.hasPrefix("名称不能为空"),"existing error changes language")
        restored.clearSettingsError("short",field:.name)
        check(restored.settingsMessage.hasPrefix("修改自动保存"),"localized neutral note restored")
        restored.showToast("已重置本轮计时");restored.setLanguage(.english)
        check(restored.toast == "Timer reset","visible toast changes language")
        check(restored.text("剩余 %d 分 %d 秒",2,9) == "2 minutes, 9 seconds remaining","formatted accessibility label")
        date=date.addingTimeInterval(1500);store.tick()
        check(store.records.count == 1 && store.records[0].task == "Research my project" && store.records[0].modeName == "Deep work and reading","completion keeps historical content")
        // Legacy JSON has neither language nor built-in-name metadata.
        var legacy=try JSONSerialization.jsonObject(with:Data(contentsOf:file)) as! [String:Any]
        legacy["schemaVersion"]=1;legacy.removeValue(forKey:"language")
        legacy["modes"]=[["id":"focus","name":"专注","minutes":25,"kind":"focus"],["id":"short","name":"短休息","minutes":5,"kind":"short"],["id":"custom","name":"我的任务","minutes":20,"kind":"focus"]]
        legacy.removeValue(forKey:"session")
        try JSONSerialization.data(withJSONObject:legacy).write(to:file)
        let migrated=PomodoroStore(fileURL:file,startTicker:false)
        check(migrated.language == .zhHans,"legacy users keep Chinese")
        migrated.setLanguage(.english)
        check(migrated.displayName(migrated.modes[0]) == "Focus" && migrated.displayName(migrated.modes[2]) == "我的任务","legacy defaults migrate but custom names stay untouched")
        migrated.persist()
        var future=try JSONSerialization.jsonObject(with:Data(contentsOf:file)) as! [String:Any];future["language"]="future-language"
        try JSONSerialization.data(withJSONObject:future).write(to:file)
        let fallback=PomodoroStore(fileURL:file,startTicker:false)
        check(fallback.modes.count == 3 && fallback.modes[2].name == "我的任务","unknown language does not discard data")
        // Every catalog entry must have an English translation with matching format placeholders.
        let format=try NSRegularExpression(pattern:"%(?:[0-9.]+)?[@df]")
        func placeholders(_ s:String)->[String] { format.matches(in:s,range:NSRange(s.startIndex...,in:s)).map{(s as NSString).substring(with:$0.range)} }
        let han=try NSRegularExpression(pattern:"[\\p{Han}]")
        for (source,en) in Localizations.english {
            check(!en.isEmpty && han.firstMatch(in:en,range:NSRange(en.startIndex...,in:en)) == nil,"English coverage: "+source)
            check(placeholders(source) == placeholders(en),"format placeholder parity: "+source)
        }
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
        let literal=try NSRegularExpression(pattern:#"(?:store|language)\.text\("((?:[^"\\]|\\.)*)""#)
        for url in try FileManager.default.contentsOfDirectory(at:root.appendingPathComponent("Sources"),includingPropertiesForKeys:nil) where url.pathExtension == "swift" {
            let source=try String(contentsOf:url,encoding:.utf8)
            for match in literal.matches(in:source,range:NSRange(source.startIndex...,in:source)) {
                let key=(source as NSString).substring(with:match.range(at:1)).replacingOccurrences(of:"\\n",with:"\n")
                check(Localizations.english[key] != nil,"UI key translated: "+key)
            }
        }
        let report:[String:Any]=["checks":checks,"languages":AppLanguage.allCases.map(\.rawValue),"catalogEntries":Localizations.english.count,"coverage":"UI catalog, format placeholders, legacy migration, user data preservation, active timer, restart and live feedback"]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
        print("PASS: \(checks) localization checks across \(Localizations.english.count) catalog entries")
    }
}
