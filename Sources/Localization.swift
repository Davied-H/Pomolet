import Foundation

/// Persist stable language identifiers, independently of the system locale.
enum AppLanguage: String, Codable, CaseIterable {
    case zhHans = "zh-Hans"
    case english = "en"
    var locale: Locale { Locale(identifier: rawValue) }
    var nativeName: String { self == .zhHans ? "中文" : "English" }
    static func preferred(_ identifiers: [String] = Locale.preferredLanguages) -> AppLanguage {
        let primary = identifiers.first?.lowercased() ?? "en"
        return primary == "zh" || primary.hasPrefix("zh-") || primary.hasPrefix("zh_") ? .zhHans : .english
    }
    func text(_ source: String, _ arguments: CVarArg...) -> String {
        let format = self == .english ? Localizations.english[source] ?? source : source
        return arguments.isEmpty ? format : String(format: format, locale: locale, arguments: arguments)
    }
}

/// A user override is separate from the effective language, so System remains dynamic.
enum LanguagePreference: String, Codable, CaseIterable {
    case system
    case zhHans = "zh-Hans"
    case english = "en"
    func resolve(_ systemLanguages: [String]) -> AppLanguage {
        switch self {
        case .system: return AppLanguage.preferred(systemLanguages)
        case .zhHans: return .zhHans
        case .english: return .english
        }
    }
}

/// Source-language keys follow the same convention as NSLocalizedString.
/// Keep user-authored content outside this catalog.
enum Localizations {
    static let english: [String: String] = [
        "窗口置顶": "Always on Top",
        "取消窗口置顶": "Turn Off Always on Top",
        "展开完整窗口": "Expand Window",
        "拖离边缘恢复完整窗口": "Drag away from the edge to expand",
        "边缘吸附": "Snap to Screen Edges",
        "专注": "Focus",
        "短休息": "Short break",
        "长休息": "Long break",
        "轻调耳机": "Headphones",
        "喝茶 · 闭眼": "Tea · Rest",
        "舒展 · 哈欠": "Stretch · Yawn",
        "暂停片刻，随时继续": "Pause, and return when ready",
        "准备好，进入心流": "Ready when you are",
        "休息，也是专注的一部分": "Rest is part of focus",
        "已重置本轮计时": "Timer reset",
        "专注完成，准备下一段时间。": "Session complete. Ready for the next one.",
        "专注完成。现在，给自己一点休息。": "Focus complete. Take a little break.",
        "休息结束，准备开启下一次专注。": "Break over. Ready to focus again.",
        "休息结束，准备开启下一段时间。": "Break over. Ready for your next session.",
        "名称不能为空": "Enter a mode name",
        "名称最多 24 个字符": "Use 24 characters or fewer",
        "模式名称不能重复": "Mode names must be unique",
        "时长需为 1–120 整数分钟": "Use a whole number from 1 to 120 minutes",
        "，已保留上次有效设置。": ". Your last valid setting has been kept.",
        "修改自动保存。最多 5 个模式，每个 1–120 分钟。": "Changes save automatically. Up to 5 modes, 1–120 minutes each.",
        "新模式": "New mode",
        "新模式%d": "New mode %d",
        "暂时无法保存设置，请检查本地目录权限。": "Unable to save. Check the local folder permissions.",
        "本地数据无法读取，已使用默认设置。原文件未改动。": "Unable to read local data. Defaults are in use; the original file is unchanged.",
        "返回番茄钟": "Back to timer",
        "计时模式": "Timer modes",
        "添加模式": "Add mode",
        "已达 5 个模式上限": "5-mode limit reached",
        "结束提示音": "Completion sound",
        "开启": "On",
        "关闭": "Off",
        "类型与动画": "Type and animation",
        "模式名称": "Mode name",
        "%@的名称": "Name for %@",
        "%@的分钟": "Minutes for %@",
        "分": "min",
        "%@的类型与动画：%@，%@": "Type and animation for %@: %@, %@",
        "删除%@": "Delete %@",
        "语言": "Language",
        "跟随系统": "System",
        "界面语言": "Interface language",
        "剩余 %d 分 %d 秒": "%d minutes, %d seconds remaining",
        "%@ · %d 分钟": "%@ · %d min",
        "数据统计": "Statistics",
        "打开计时设置": "Open timer settings",
        "点击输入本次专注事项（可选）": "What will you focus on? (optional)",
        "当前专注任务": "Current focus task",
        "今日": "Today",
        "关闭结束提示音": "Turn off completion sound",
        "开启结束提示音": "Turn on completion sound",
        "结束时轻声提醒": "A gentle sound when time is up",
        "结束提示音已关闭": "Completion sound is off",
        "切换深浅色": "Toggle light and dark appearance",
        "暂停": "Pause",
        "继续": "Resume",
        "开始%@": "Start %@",
        "重置当前计时": "Reset current timer",
        "今日专注": "Focus today",
        "完成番茄": "Sessions",
        "平均时长": "Average",
        "本周累计": "This week",
        "分钟": "min",
        "次": "sessions",
        "近 7 天 · 专注时长": "Last 7 days · Focus",
        "近 7 天 · 完成次数": "Last 7 days · Sessions",
        "近 7 天 · 单次平均": "Last 7 days · Average",
        "周一至今 · 累计时长": "Week to date · Total",
        "今日记录": "Today’s sessions",
        "%d 条": "%d records",
        "1 条": "1 record",
        "专注当下": "Focused time",
        "%d 分钟": "%d min",
        "今天的第一份专注，从现在开始。": "Your first focus session starts here.",
        "开始一次专注": "Start a focus session",
        "尚未到来": "Not yet",
        "暂无记录": "No data",
        "%@，%@%@。%@：%@": "%@: %@ %@. %@: %@",
        "戴耳机的少年": "Companion wearing headphones",
        "关于Pomolet": "About Pomolet",
        "设置…": "Settings…",
        "隐藏Pomolet": "Hide Pomolet",
        "显示全部": "Show All",
        "退出Pomolet": "Quit Pomolet",
        "开始 / 暂停": "Start / Pause",
        "重置计时": "Reset Timer",
        "关闭窗口": "Close Window",
        "撤销": "Undo",
        "重做": "Redo",
        "剪切": "Cut",
        "复制": "Copy",
        "粘贴": "Paste",
        "全选": "Select All",
        "番茄钟": "Timer",
        "最小化": "Minimize",
        "显示主窗口": "Show Main Window",
        "文件": "File",
        "编辑": "Edit",
        "显示": "View",
        "窗口": "Window",
        "专注于眼前这一件事。\n原生 macOS · SwiftUI / AppKit": "One thing at a time.\nNative macOS · SwiftUI / AppKit",
    ]
}
