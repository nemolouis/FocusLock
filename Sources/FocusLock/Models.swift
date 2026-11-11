import AppKit
import SwiftUI

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
    var title: String { self == .countdown ? "倒计时" : "正计时" }
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

    /// 1小时20分 / 25分钟
    static func duration(_ seconds: Double) -> String {
        let mins = Int((seconds / 60).rounded(.down))
        if mins < 1 { return seconds > 0 ? "不足1分钟" : "0分钟" }
        let h = mins / 60, m = mins % 60
        if h == 0 { return "\(m)分钟" }
        return m == 0 ? "\(h)小时" : "\(h)小时\(m)分"
    }

    static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEEE"
        return f
    }()
}
