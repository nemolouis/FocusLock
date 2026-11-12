import AppKit
import SwiftUI

// MARK: - 多语言

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system, zh, en
    var id: String { rawValue }

    /// 设置里显示的名字：语言名用它自己的语言写，方便看不懂当前语言的人切回来
    var title: String {
        switch self {
        case .system: tr("跟随系统", "System")
        case .zh: "中文"
        case .en: "English"
        }
    }

    var isEnglish: Bool {
        switch self {
        case .zh: false
        case .en: true
        case .system: !(Locale.preferredLanguages.first ?? "zh").hasPrefix("zh")
        }
    }
}

/// 当前界面语言（由 Store 的设置同步过来）
enum L10n {
    static var isEnglish = false
    static var locale: Locale { Locale(identifier: isEnglish ? "en_US" : "zh_CN") }
}

/// 界面文字：tr("中文", "English")
func tr(_ zh: String, _ en: String) -> String {
    L10n.isEnglish ? en : zh
}

enum AppAppearance: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: tr("跟随系统", "System")
        case .light: tr("浅色", "Light")
        case .dark: tr("深色", "Dark")
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - 数据

struct FocusCategory: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var colorHex: String

    var color: Color { Color(hex: colorHex) }
}

enum TimerMode: String, Codable, CaseIterable, Identifiable {
    case countdown
    case countup

    var id: String { rawValue }
    var title: String { self == .countdown ? tr("倒计时", "Countdown") : tr("正计时", "Stopwatch") }
}

struct FocusSession: Identifiable, Codable, Hashable {
    var id = UUID()
    var categoryId: UUID?
    var mode: TimerMode
    var startedAt: Date
    var endedAt: Date
    /// 实际专注秒数（不含暂停）
    var seconds: Double
    var targetSeconds: Double?
    /// 倒计时是否完整走完
    var completed: Bool
    var note: String
    var tags: [String] = []
    /// 手动补记的记录
    var isManual = false
}

extension FocusSession {
    // 旧数据没有 tags / isManual 字段，缺省时用默认值
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        categoryId = try c.decodeIfPresent(UUID.self, forKey: .categoryId)
        mode = try c.decode(TimerMode.self, forKey: .mode)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        endedAt = try c.decode(Date.self, forKey: .endedAt)
        seconds = try c.decode(Double.self, forKey: .seconds)
        targetSeconds = try c.decodeIfPresent(Double.self, forKey: .targetSeconds)
        completed = try c.decodeIfPresent(Bool.self, forKey: .completed) ?? false
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        isManual = try c.decodeIfPresent(Bool.self, forKey: .isManual) ?? false
    }
}

struct BlockedApp: Identifiable, Codable, Hashable {
    var bundleId: String
    var name: String
    var path: String

    var id: String { bundleId }
}

struct AppSettings: Codable, Equatable {
    var lockEnabled = true
    var lockWhilePaused = true
    var strictMode = false
    var countdownMinutes = 25
    var lastCategoryId: UUID?
    var lastMode: TimerMode = .countdown
    var restEnabled = true
    var restMinutes = 5
    var language: AppLanguage = .system
    var appearance: AppAppearance = .system
    /// 启动时是否打开主窗口；关掉就只在菜单栏运行
    var showWindowOnLaunch = true

    init() {}

    // 缺字段时用默认值，方便以后加设置项
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        lockEnabled = try c.decodeIfPresent(Bool.self, forKey: .lockEnabled) ?? d.lockEnabled
        lockWhilePaused = try c.decodeIfPresent(Bool.self, forKey: .lockWhilePaused) ?? d.lockWhilePaused
        strictMode = try c.decodeIfPresent(Bool.self, forKey: .strictMode) ?? d.strictMode
        countdownMinutes = try c.decodeIfPresent(Int.self, forKey: .countdownMinutes) ?? d.countdownMinutes
        lastCategoryId = try c.decodeIfPresent(UUID.self, forKey: .lastCategoryId)
        lastMode = try c.decodeIfPresent(TimerMode.self, forKey: .lastMode) ?? d.lastMode
        restEnabled = try c.decodeIfPresent(Bool.self, forKey: .restEnabled) ?? d.restEnabled
        restMinutes = try c.decodeIfPresent(Int.self, forKey: .restMinutes) ?? d.restMinutes
        // 之前的版本只有中文：老用户升级后保持中文，新安装才跟随系统
        language = try c.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .zh
        appearance = try c.decodeIfPresent(AppAppearance.self, forKey: .appearance) ?? d.appearance
        showWindowOnLaunch = try c.decodeIfPresent(Bool.self, forKey: .showWindowOnLaunch) ?? d.showWindowOnLaunch
    }
}

struct PersistedData: Codable {
    var categories: [FocusCategory]
    var sessions: [FocusSession]
    var blockedApps: [BlockedApp]
    var settings: AppSettings
}

// MARK: - 颜色

enum Palette {
    static let colors = ["#E5484D", "#3E63DD", "#30A46C", "#F76B15", "#8E4EC6", "#12A594", "#D6409F", "#978365"]
    static let rest = Color(hex: "#30A46C")
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }

    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        return String(format: "#%02X%02X%02X",
                      Int((ns.redComponent * 255).rounded()),
                      Int((ns.greenComponent * 255).rounded()),
                      Int((ns.blueComponent * 255).rounded()))
    }
}

// MARK: - 格式化

enum Fmt {
    /// 25:00 / 1:02:03
    static func clock(_ seconds: Double, roundUp: Bool) -> String {
        let t = max(0, Int(roundUp ? seconds.rounded(.up) : seconds.rounded(.down)))
        let h = t / 3600, m = (t % 3600) / 60, s = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    /// 1小时20分 / 1h 20m
    static func duration(_ seconds: Double) -> String {
        let mins = Int((seconds / 60).rounded(.down))
        if mins < 1 { return seconds > 0 ? tr("不足1分钟", "<1 min") : tr("0分钟", "0 min") }
        let h = mins / 60, m = mins % 60
        if h == 0 { return tr("\(m)分钟", "\(m) min") }
        if m == 0 { return tr("\(h)小时", "\(h)h") }
        return tr("\(h)小时\(m)分", "\(h)h \(m)m")
    }

    /// N 分钟
    static func minutes(_ n: Int) -> String { tr("\(n) 分钟", "\(n) min") }

    static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    /// 按当前语言格式化日期；pattern 分中英文两种
    static func date(_ d: Date, zh: String, en: String) -> String {
        let f = DateFormatter()
        f.locale = L10n.locale
        f.dateFormat = L10n.isEnglish ? en : zh
        return f.string(from: d)
    }

    /// 11月11日 星期三 / Wednesday, Nov 11
    static func day(_ d: Date) -> String { date(d, zh: "M月d日 EEEE", en: "EEEE, MMM d") }
}
