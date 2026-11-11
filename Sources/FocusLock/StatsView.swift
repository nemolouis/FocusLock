import Charts
import SwiftUI

enum StatsRange: String, CaseIterable, Identifiable {
    case today = "今天"
    case week = "近 7 天"
    case month = "近 30 天"
    case all = "全部"

    var id: String { rawValue }
}

struct StatsView: View {
    @EnvironmentObject var store: Store
    @State private var range: StatsRange = .week

    private struct Slice: Identifiable {
        let id: String
        let label: String
        let hex: String
        let seconds: Double
    }

    private struct BarPoint: Identifiable {
        let id = UUID()
        let bucket: Date
        let label: String
        let minutes: Double
    }

    private let cal = Calendar.current

    // MARK: 时间范围

    private var todayStart: Date { cal.startOfDay(for: Date()) }
    private var tomorrowStart: Date { cal.date(byAdding: .day, value: 1, to: todayStart)! }

    private var rangeStart: Date {
        switch range {
        case .today: return todayStart
        case .week: return cal.date(byAdding: .day, value: -6, to: todayStart)!
        case .month: return cal.date(byAdding: .day, value: -29, to: todayStart)!
        case .all: return store.sessions.map(\.startedAt).min().map { cal.startOfDay(for: $0) } ?? todayStart
        }
    }

    private var dayCount: Int {
        max(1, (cal.dateComponents([.day], from: rangeStart, to: tomorrowStart).day ?? 1))
    }

    private var unit: Calendar.Component {
        switch range {
        case .today: return .hour
        case .week, .month: return .day
        case .all: return dayCount > 90 ? .month : .day
        }
    }

    private var filtered: [FocusSession] {
        store.sessions.filter { $0.startedAt >= rangeStart && $0.startedAt < tomorrowStart }
    }

    /// 分类 id -> 唯一显示名（防止重名分类在图例里撞色）
    private var labels: [String: String] {
        var result: [String: String] = [:]
        var used: [String: Int] = [:]
        let keys = Set(filtered.map { key($0.categoryId) })
        for c in store.categories where keys.contains(c.id.uuidString) {
            let n = used[c.name, default: 0]
            used[c.name] = n + 1
            result[c.id.uuidString] = n == 0 ? c.name : "\(c.name) (\(n + 1))"
        }
        for k in keys where result[k] == nil {
            result[k] = k == "none" ? "未分类" : "已删除分类"
        }
        return result
    }

    private func key(_ id: UUID?) -> String {
        guard let id else { return "none" }
        return store.category(id) == nil ? "deleted" : id.uuidString
    }

    private var slices: [Slice] {
        let labels = labels
        let grouped = Dictionary(grouping: filtered) { key($0.categoryId) }
        return grouped.map { k, items in
            Slice(id: k,
                  label: labels[k] ?? k,
                  hex: store.categoryColorHex(items.first?.categoryId),
                  seconds: items.reduce(0) { $0 + $1.seconds })
        }
        .sorted { $0.seconds > $1.seconds }
    }

    private var bars: [BarPoint] {
        let labels = labels
        var acc: [Date: [String: Double]] = [:]
        for s in filtered {
            let b = cal.dateInterval(of: unit, for: s.startedAt)?.start ?? s.startedAt
            acc[b, default: [:]][key(s.categoryId), default: 0] += s.seconds / 60
        }
        // 每根柱子里按图例顺序堆叠，颜色上下位置保持一致
        let rank = Dictionary(uniqueKeysWithValues: slices.enumerated().map { ($1.label, $0) })
        return acc.flatMap { b, dict in
            dict.map { k, m in BarPoint(bucket: b, label: labels[k] ?? k, minutes: m) }
        }
        .sorted { ($0.bucket, rank[$0.label] ?? 99) < ($1.bucket, rank[$1.label] ?? 99) }
    }

    // MARK: 视图

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("统计").font(.largeTitle.weight(.semibold))
                    Spacer()
                    Picker("", selection: $range) {
                        ForEach(StatsRange.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 320)
                }

                if filtered.isEmpty {
                    ContentUnavailableView("这段时间还没有专注记录",
                                           systemImage: "chart.pie",
                                           description: Text("完成一次专注后，这里会显示分类占比和每日趋势。"))
                        .frame(maxWidth: .infinity, minHeight: 360)
                } else {
                    tiles
                    HStack(alignment: .top, spacing: 16) {
                        pieCard.frame(minWidth: 380, maxHeight: .infinity, alignment: .top)
                        barCard.frame(maxHeight: .infinity, alignment: .top)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(24)
        }
    }

    private var tiles: some View {
        let total = filtered.reduce(0) { $0 + $1.seconds }
        let tomatoes = filtered.filter { $0.mode == .countdown && $0.completed }.count
        return HStack(spacing: 12) {
            tile("总专注", Fmt.duration(total), "clock")
            tile("专注次数", "\(filtered.count) 次", "number")
            tile("完成番茄", "\(tomatoes) 个", "checkmark.seal")
            tile(range == .today ? "平均每次" : "日均专注",
                 Fmt.duration(range == .today ? total / Double(max(1, filtered.count)) : total / Double(dayCount)),
                 "chart.line.uptrend.xyaxis")
        }
    }

    private func tile(_ title: String, _ value: String, _ icon: String) -> some View {
        Card {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    // 饼图（环形）
    private var pieCard: some View {
        let total = slices.reduce(0) { $0 + $1.seconds }
        return Card(title: "分类占比") {
            HStack(alignment: .center, spacing: 20) {
                ZStack {
                    Chart(slices) { s in
                        SectorMark(angle: .value("时长", s.seconds),
                                   innerRadius: .ratio(0.62),
                                   angularInset: 1.5)
                            .cornerRadius(4)
                            .foregroundStyle(Color(hex: s.hex))
                    }
                    .chartLegend(.hidden)
                    VStack(spacing: 2) {
                        Text(Fmt.duration(total)).font(.headline).monospacedDigit()
                        Text("合计").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 180, height: 180)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(slices) { s in
                        HStack(spacing: 8) {
                            CategoryDot(hex: s.hex)
                            Text(s.label).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(Fmt.duration(s.seconds)).foregroundStyle(.secondary).monospacedDigit()
                            Text(String(format: "%.0f%%", total > 0 ? s.seconds / total * 100 : 0))
                                .monospacedDigit()
                                .frame(width: 40, alignment: .trailing)
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }

    // 柱状图（按分类堆叠）
    private var barCard: some View {
        let s = slices
        let title: String = switch unit {
        case .hour: "每小时专注（分钟）"
        case .month: "每月专注（分钟）"
        default: "每日专注（分钟）"
        }
        return Card(title: title) {
            Chart(bars) { p in
                BarMark(x: .value("时间", p.bucket, unit: unit),
                        y: .value("分钟", p.minutes))
                    .foregroundStyle(by: .value("分类", p.label))
                    .cornerRadius(3)
            }
            .chartForegroundStyleScale(domain: s.map(\.label), range: s.map { Color(hex: $0.hex) })
            .chartLegend(position: .bottom, alignment: .leading)
            .modifier(XDomain(enabled: unit != .month, start: rangeStart, end: tomorrowStart))
            .chartXAxis {
                switch unit {
                case .hour:
                    AxisMarks(values: .stride(by: .hour, count: 3)) {
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)))
                    }
                case .month:
                    AxisMarks(values: .stride(by: .month)) {
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.year(.twoDigits).month(.defaultDigits))
                    }
                default:
                    AxisMarks(values: .stride(by: .day, count: dayCount > 14 ? 5 : 1)) {
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                    }
                }
            }
            .frame(minHeight: 240)
        }
    }
}

/// 让日 / 小时柱状图铺满整个时间范围，空的日子也留位置
private struct XDomain: ViewModifier {
    var enabled: Bool
    var start: Date
    var end: Date

    func body(content: Content) -> some View {
        if enabled {
            content.chartXScale(domain: start...end)
        } else {
            content
        }
    }
}
