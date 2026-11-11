import Charts
import SwiftUI

enum StatsPeriod: String, CaseIterable, Identifiable {
    // rawValue 存在 UserDefaults 里，不要改
    case day = "日"
    case week = "周"
    case month = "月"
    case year = "年"
    case all = "总"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: tr("日", "Day")
        case .week: tr("周", "Week")
        case .month: tr("月", "Month")
        case .year: tr("年", "Year")
        case .all: tr("总", "All")
        }
    }

    var component: Calendar.Component? {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        case .all: nil
        }
    }
}

/// 某个分类在当前时间段里的汇总（饼图、图例、记录筛选共用）
struct CategorySlice: Identifiable {
    let id: String      // 分类 key：uuid / "none" / "deleted"
    let label: String
    let hex: String
    let seconds: Double
}

/// 周一为一周的第一天
let statsCalendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.firstWeekday = 2
    c.minimumDaysInFirstWeek = 4
    return c
}()

struct StatsView: View {
    @EnvironmentObject var store: Store
    @AppStorage("statsPeriod") private var period: StatsPeriod = .week
    @State private var offset = 0               // 0 = 当前，-1 = 上一个周期…
    @State private var jumpOffset: Int?         // 从热力图跳到某一天时用
    @State private var recordFilter: String?    // 记录列表按分类筛选

    private struct BarPoint: Identifiable {
        let id = UUID()
        let bucket: Date
        let label: String
        let minutes: Double
    }

    private let cal = statsCalendar

    // MARK: 时间段

    private var todayStart: Date { cal.startOfDay(for: Date()) }
    private var tomorrowStart: Date { cal.date(byAdding: .day, value: 1, to: todayStart)! }

    private var interval: DateInterval {
        guard let comp = period.component else {
            let first = store.sessions.map(\.startedAt).min().map { cal.startOfDay(for: $0) } ?? todayStart
            return DateInterval(start: min(first, todayStart), end: tomorrowStart)
        }
        let anchor = cal.date(byAdding: comp, value: offset, to: Date())!
        return cal.dateInterval(of: comp, for: anchor)!
    }

    /// 时间段里已经过去的天数（算日均用，本周 / 本月只算到今天）
    private var elapsedDays: Int {
        let r = interval
        let end = min(r.end, tomorrowStart)
        return max(1, cal.dateComponents([.day], from: r.start, to: end).day ?? 1)
    }

    private var unit: Calendar.Component {
        switch period {
        case .day: return .hour
        case .week, .month: return .day
        case .year: return .month
        case .all: return elapsedDays > 90 ? .month : .day
        }
    }

    private var periodLabel: String {
        let r = interval
        let last = r.end.addingTimeInterval(-1)
        let thisYear = cal.component(.year, from: Date()) == cal.component(.year, from: r.start)
        let mdZh = thisYear ? "M月d日" : "yyyy年M月d日"
        let mdEn = thisYear ? "MMM d" : "MMM d, yyyy"
        switch period {
        case .day:
            let d = Fmt.date(r.start, zh: mdZh + " EEEE", en: "EEE, " + mdEn)
            if offset == 0 { return tr("今天 · ", "Today · ") + d }
            if offset == -1 { return tr("昨天 · ", "Yesterday · ") + d }
            return d
        case .week:
            let range = Fmt.date(r.start, zh: mdZh, en: mdEn) + " – " + Fmt.date(last, zh: "M月d日", en: "MMM d")
            if offset == 0 { return tr("本周 · ", "This week · ") + range }
            if offset == -1 { return tr("上周 · ", "Last week · ") + range }
            return range
        case .month:
            return (offset == 0 ? tr("本月 · ", "This month · ") : "") + Fmt.date(r.start, zh: "yyyy年M月", en: "MMMM yyyy")
        case .year:
            return (offset == 0 ? tr("今年 · ", "This year · ") : "") + Fmt.date(r.start, zh: "yyyy年", en: "yyyy")
        case .all:
            return tr("全部 · ", "All · ") + Fmt.date(r.start, zh: "yyyy年M月d日 起", en: "'since' MMM d, yyyy")
        }
    }

    // MARK: 数据

    private var filtered: [FocusSession] {
        let r = interval
        return store.sessions.filter { $0.startedAt >= r.start && $0.startedAt < r.end }
    }

    private func key(_ id: UUID?) -> String {
        guard let id else { return "none" }
        return store.category(id) == nil ? "deleted" : id.uuidString
    }

    /// 分类 key -> 唯一显示名（防止重名分类在图例里撞色）
    private func labels(for sessions: [FocusSession]) -> [String: String] {
        var result: [String: String] = [:]
        var used: [String: Int] = [:]
        let keys = Set(sessions.map { key($0.categoryId) })
        for c in store.categories where keys.contains(c.id.uuidString) {
            let n = used[c.name, default: 0]
            used[c.name] = n + 1
            result[c.id.uuidString] = n == 0 ? c.name : "\(c.name) (\(n + 1))"
        }
        for k in keys where result[k] == nil {
            result[k] = k == "none" ? tr("未分类", "Uncategorized") : tr("已删除分类", "Deleted category")
        }
        return result
    }

    private func slices(for sessions: [FocusSession]) -> [CategorySlice] {
        let labels = labels(for: sessions)
        return Dictionary(grouping: sessions) { key($0.categoryId) }
            .map { k, items in
                CategorySlice(id: k,
                              label: labels[k] ?? k,
                              hex: store.categoryColorHex(items.first?.categoryId),
                              seconds: items.reduce(0) { $0 + $1.seconds })
            }
            .sorted { $0.seconds > $1.seconds }
    }

    private func bars(for sessions: [FocusSession], slices: [CategorySlice]) -> [BarPoint] {
        let labels = Dictionary(uniqueKeysWithValues: slices.map { ($0.id, $0.label) })
        let rank = Dictionary(uniqueKeysWithValues: slices.enumerated().map { ($1.label, $0) })
        var acc: [Date: [String: Double]] = [:]
        for s in sessions {
            let b = cal.dateInterval(of: unit, for: s.startedAt)?.start ?? s.startedAt
            acc[b, default: [:]][key(s.categoryId), default: 0] += s.seconds / 60
        }
        // 每根柱子里按图例顺序堆叠，颜色上下位置保持一致
        return acc.flatMap { b, dict in
            dict.map { k, m in BarPoint(bucket: b, label: labels[k] ?? k, minutes: m) }
        }
        .sorted { ($0.bucket, rank[$0.label] ?? 99) < ($1.bucket, rank[$1.label] ?? 99) }
    }

    /// 从热力图点某一天：切到「日」并定位到那天
    private func jump(to day: Date) {
        let target = -(cal.dateComponents([.day], from: cal.startOfDay(for: day), to: todayStart).day ?? 0)
        if period == .day {
            offset = target
        } else {
            jumpOffset = target
            period = .day
        }
    }

    // MARK: 视图

    var body: some View {
        let sessions = filtered
        let sl = slices(for: sessions)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if sessions.isEmpty {
                    ContentUnavailableView(tr("这段时间还没有专注记录", "No focus sessions in this period"),
                                           systemImage: "chart.pie",
                                           description: Text(tr("完成一次专注，或在下方「补记」一条记录。",
                                                                "Finish a focus session, or add one below.")))
                        .frame(maxWidth: .infinity, minHeight: 200)
                    HeatmapCard(onSelectDay: jump)
                        .frame(maxWidth: 440, alignment: .leading)
                } else {
                    tiles(sessions)
                    // 饼图、柱状图、热力图并排一行，等宽等高
                    HStack(alignment: .top, spacing: 16) {
                        pieCard(sl)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        barCard(bars(for: sessions, slices: sl), slices: sl)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        HeatmapCard(onSelectDay: jump)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }

                RecordsSection(sessions: sessions, options: sl, filterKey: $recordFilter, keyOf: key,
                               defaultDay: period == .day && offset != 0 ? interval.start : nil)
            }
            .padding(24)
        }
        .onChange(of: period) {
            offset = jumpOffset ?? 0
            jumpOffset = nil
            recordFilter = nil
        }
        .onChange(of: offset) { recordFilter = nil }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(tr("统计", "Stats")).font(.largeTitle.weight(.semibold))
                Spacer()
                Picker("", selection: $period) {
                    ForEach(StatsPeriod.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 300)
            }
            HStack(spacing: 10) {
                if period != .all {
                    Button { offset -= 1 } label: { Image(systemName: "chevron.left") }
                        .help(tr("上一个", "Previous"))
                }
                Text(periodLabel)
                    .font(.headline)
                    .monospacedDigit()
                if period != .all {
                    Button { offset += 1 } label: { Image(systemName: "chevron.right") }
                        .disabled(offset >= 0)
                        .help(tr("下一个", "Next"))
                    if offset != 0 {
                        Button(tr("回到现在", "Back to now")) { offset = 0 }
                            .buttonStyle(.link)
                    }
                }
            }
        }
    }

    private func tiles(_ sessions: [FocusSession]) -> some View {
        let total = sessions.reduce(0) { $0 + $1.seconds }
        let tomatoes = sessions.filter { $0.mode == .countdown && $0.completed }.count
        return HStack(spacing: 12) {
            tile(tr("总专注", "Total focus"), Fmt.duration(total), "clock")
            tile(tr("专注次数", "Sessions"), tr("\(sessions.count) 次", "\(sessions.count)"), "number")
            tile(tr("完成番茄", "Pomodoros"), tr("\(tomatoes) 个", "\(tomatoes)"), "checkmark.seal")
            if period == .day {
                tile(tr("平均每次", "Avg. session"), Fmt.duration(total / Double(max(1, sessions.count))), "chart.line.uptrend.xyaxis")
            } else {
                tile(tr("日均专注", "Daily average"), Fmt.duration(total / Double(elapsedDays)), "chart.line.uptrend.xyaxis")
            }
        }
    }

    private func tile(_ title: String, _ value: String, _ icon: String) -> some View {
        Card {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    // 环形饼图；点图例可以筛选下面的记录
    private func pieCard(_ slices: [CategorySlice]) -> some View {
        let total = slices.reduce(0) { $0 + $1.seconds }
        return Card(title: tr("分类占比", "By category")) {
            VStack(spacing: 14) {
                ZStack {
                    Chart(slices) { s in
                        SectorMark(angle: .value("time", s.seconds),
                                   innerRadius: .ratio(0.62),
                                   angularInset: 1.5)
                            .cornerRadius(4)
                            .foregroundStyle(Color(hex: s.hex))
                            .opacity(recordFilter == nil || recordFilter == s.id ? 1 : 0.3)
                    }
                    .chartLegend(.hidden)
                    VStack(spacing: 2) {
                        Text(Fmt.duration(total)).font(.headline).monospacedDigit()
                        Text(tr("合计", "Total")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 150, height: 150)
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 2) {
                    ForEach(slices) { s in
                        Button {
                            recordFilter = recordFilter == s.id ? nil : s.id
                        } label: {
                            HStack(spacing: 6) {
                                CategoryDot(hex: s.hex, size: 8)
                                Text(s.label).lineLimit(1)
                                Spacer(minLength: 6)
                                Text(Fmt.duration(s.seconds)).foregroundStyle(.secondary).monospacedDigit()
                                    .lineLimit(1)
                                Text(String(format: "%.0f%%", total > 0 ? s.seconds / total * 100 : 0))
                                    .monospacedDigit()
                                    .frame(width: 34, alignment: .trailing)
                            }
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(recordFilter == s.id ? Color(hex: s.hex).opacity(0.14) : .clear,
                                        in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(tr("只看这个分类的记录", "Show only this category's sessions"))
                    }
                }
            }
        }
    }

    // 按分类堆叠的柱状图
    private func barCard(_ points: [BarPoint], slices: [CategorySlice]) -> some View {
        // X 轴范围对齐到整小时 / 整天 / 整月，首尾的柱子不会超出图表
        let r = interval
        let domainStart = cal.dateInterval(of: unit, for: r.start)?.start ?? r.start
        let domainEnd = cal.dateInterval(of: unit, for: r.end.addingTimeInterval(-1))?.end ?? r.end
        let title: String = switch unit {
        case .hour: tr("每小时专注（分钟）", "Minutes per hour")
        case .month: tr("每月专注（分钟）", "Minutes per month")
        default: tr("每日专注（分钟）", "Minutes per day")
        }
        return Card(title: title) {
            Chart(points) { p in
                BarMark(x: .value("time", p.bucket, unit: unit),
                        y: .value("minutes", p.minutes))
                    .foregroundStyle(by: .value("category", p.label))
                    .cornerRadius(3)
            }
            .chartForegroundStyleScale(domain: slices.map(\.label), range: slices.map { Color(hex: $0.hex) })
            .chartLegend(position: .bottom, alignment: .leading)
            .chartXScale(domain: domainStart...domainEnd)
            .chartXAxis { xAxis }
            .frame(minHeight: 220)
        }
    }

    private var xAxis: some AxisContent {
        switch (period, unit) {
        case (.day, _):
            return AnyAxisContent(AxisMarks(values: .stride(by: .hour, count: 3)) {
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)).locale(L10n.locale))
            })
        case (.week, _):
            return AnyAxisContent(AxisMarks(values: .stride(by: .day)) {
                AxisGridLine()
                AxisValueLabel(format: .dateTime.weekday(.abbreviated).locale(L10n.locale), centered: true)
            })
        case (.month, _):
            return AnyAxisContent(AxisMarks(values: .stride(by: .day, count: 5)) {
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day().locale(L10n.locale), centered: true)
            })
        case (.year, _):
            return AnyAxisContent(AxisMarks(values: .stride(by: .month)) {
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).locale(L10n.locale), centered: true)
            })
        case (_, .month):
            let months = max(1, elapsedDays / 30)
            return AnyAxisContent(AxisMarks(values: .stride(by: .month, count: months > 12 ? 3 : 1)) {
                AxisGridLine()
                AxisValueLabel(format: .dateTime.year(.twoDigits).month(.defaultDigits).locale(L10n.locale), centered: true)
            })
        default:
            return AnyAxisContent(AxisMarks(values: .stride(by: .day, count: max(1, elapsedDays / 7))) {
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.defaultDigits).day().locale(L10n.locale))
            })
        }
    }
}
