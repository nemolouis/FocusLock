import SwiftUI

/// 类似 GitHub 贡献图的专注热力图：一列一周（周一到周日），颜色越深专注越久。
/// 一屏显示 16 周，可以左右滑动（或点 ‹ ›）查看更早的记录，一直到第一条记录那周。
struct HeatmapCard: View {
    @EnvironmentObject var store: Store
    @Environment(\.colorScheme) private var scheme
    var onSelectDay: (Date) -> Void

    @State private var width: CGFloat = 300
    /// 当前最左边那一列的序号（0 = 最早的一周）
    @State private var position: Int?

    private let visibleWeeks = 16
    private let maxWeeks = 260          // 最多往前 5 年
    private let cal = statsCalendar
    private let labelWidth: CGFloat = 22
    private let monthRowHeight: CGFloat = 14

    // GitHub 的绿色色阶
    private var levelColors: [Color] {
        let greens = scheme == .dark
            ? ["#0E4429", "#006D32", "#26A641", "#39D353"]
            : ["#9BE9A8", "#40C463", "#30A14E", "#216E39"]
        return [Color.secondary.opacity(0.13)] + greens.map { Color(hex: $0) }
    }

    /// 不到 1 分钟、<30 分钟、<1 小时、<2 小时、≥2 小时
    private func level(_ seconds: Double) -> Int {
        let m = seconds / 60
        if m < 1 { return 0 }
        if m < 30 { return 1 }
        if m < 60 { return 2 }
        if m < 120 { return 3 }
        return 4
    }

    var body: some View {
        let today = cal.startOfDay(for: Date())
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: today)!.start
        // 网格从第一条记录那周开始，至少 16 周
        let firstWeek = store.sessions.map(\.startedAt).min()
            .flatMap { cal.dateInterval(of: .weekOfYear, for: $0)?.start } ?? thisWeek
        let weeksBack = cal.dateComponents([.weekOfYear], from: firstWeek, to: thisWeek).weekOfYear ?? 0
        let totalWeeks = min(maxWeeks, max(visibleWeeks, weeksBack + 1))
        let gridStart = cal.date(byAdding: .weekOfYear, value: -(totalWeeks - 1), to: thisWeek)!
        let latest = totalWeeks - visibleWeeks
        let first = min(max(0, position ?? latest), latest)
        let daily = dailySeconds(from: gridStart)
        let step = max(8, min(26, ((width - labelWidth) / CGFloat(visibleWeeks)).rounded(.down)))
        let gap = max(2, (step * 0.16).rounded())

        let visStart = cal.date(byAdding: .weekOfYear, value: first, to: gridStart)!
        let visEnd = min(today, cal.date(byAdding: .day, value: visibleWeeks * 7 - 1, to: visStart)!)

        Card {
            HStack(spacing: 6) {
                Text(rangeTitle(visStart, visEnd, isLatest: first >= latest))
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                if first < latest {
                    Button(tr("最近", "Latest")) { withAnimation { position = latest } }
                        .buttonStyle(.link)
                        .font(.caption)
                }
                Button { withAnimation { position = max(0, first - visibleWeeks) } } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(first <= 0)
                .help(tr("更早", "Earlier"))
                Button { withAnimation { position = min(latest, first + visibleWeeks) } } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(first >= latest)
                .help(tr("更近", "Later"))
            }
            .buttonStyle(.borderless)

            Text(summary(daily, from: visStart, to: visEnd))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top, spacing: 0) {
                    weekdayLabels(step: step)
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 0) {
                            ForEach(0..<totalWeeks, id: \.self) { w in
                                column(week: w, gridStart: gridStart, today: today, daily: daily, step: step, gap: gap)
                                    .id(w)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollIndicators(.never)
                    .scrollTargetBehavior(.viewAligned)
                    .scrollPosition(id: $position, anchor: .leading)
                    .defaultScrollAnchor(.trailing)
                    .frame(width: CGFloat(visibleWeeks) * step,
                           height: monthRowHeight + 3 + 7 * step)
                }
                legend
            }
            .frame(width: labelWidth + CGFloat(visibleWeeks) * step)
            .frame(maxWidth: .infinity)   // 卡片比格子宽时居中
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        }
        .onAppear { if position == nil { position = latest } }
    }

    // MARK: 一列 = 一周

    private func column(week w: Int, gridStart: Date, today: Date, daily: [Date: Double],
                        step: CGFloat, gap: CGFloat) -> some View {
        let weekStart = cal.date(byAdding: .day, value: w * 7, to: gridStart)!
        let prevWeek = cal.date(byAdding: .day, value: -7, to: weekStart)!
        let newMonth = w == 0 || cal.component(.month, from: weekStart) != cal.component(.month, from: prevWeek)
        return VStack(alignment: .leading, spacing: 0) {
            // 每个月第一次出现的那一列上方标月份；1 月顺带标年份
            Group {
                if newMonth {
                    Text(cal.component(.month, from: weekStart) == 1
                         ? Fmt.date(weekStart, zh: "yyyy年", en: "yyyy")
                         : Fmt.date(weekStart, zh: "M月", en: "MMM"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                } else {
                    Color.clear
                }
            }
            .frame(width: step, height: monthRowHeight, alignment: .topLeading)
            .padding(.bottom, 3)

            ForEach(0..<7, id: \.self) { r in
                let day = cal.date(byAdding: .day, value: r, to: weekStart)!
                cell(day: day, today: today, seconds: daily[day] ?? 0, step: step, gap: gap)
            }
        }
    }

    @ViewBuilder
    private func cell(day: Date, today: Date, seconds: Double, step: CGFloat, gap: CGFloat) -> some View {
        if day > today {
            Color.clear.frame(width: step, height: step)
        } else {
            RoundedRectangle(cornerRadius: max(2, step * 0.2))
                .fill(levelColors[level(seconds)])
                .overlay {
                    if day == today {
                        RoundedRectangle(cornerRadius: max(2, step * 0.2))
                            .strokeBorder(Color.primary.opacity(0.55), lineWidth: 1.2)
                    }
                }
                .padding(gap / 2)
                .frame(width: step, height: step)
                .contentShape(Rectangle())
                .help(Fmt.date(day, zh: "yyyy年M月d日 EEEE", en: "EEE, MMM d, yyyy") + " · "
                      + (seconds >= 60 ? Fmt.duration(seconds) : tr("没有专注", "No focus"))
                      + tr("（点击查看）", " (click to open)"))
                .onTapGesture { onSelectDay(day) }
        }
    }

    private func weekdayLabels(step: CGFloat) -> some View {
        let names = L10n.isEnglish ? ["M", "", "W", "", "F", "", ""] : ["一", "", "三", "", "五", "", ""]
        return VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: monthRowHeight + 3)
            ForEach(0..<7, id: \.self) { i in
                Text(names[i])
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: labelWidth, height: step, alignment: .leading)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 3) {
            Text(tr("可左右滑动", "Swipe to scroll"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Text(tr("少", "Less")).font(.caption2).foregroundStyle(.secondary)
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(levelColors[i])
                    .frame(width: 9, height: 9)
            }
            Text(tr("多", "More")).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    // MARK: 数据

    private func rangeTitle(_ start: Date, _ end: Date, isLatest: Bool) -> String {
        if isLatest { return tr("近 16 周", "Last 16 weeks") }
        let sameYear = cal.component(.year, from: start) == cal.component(.year, from: end)
        let s = Fmt.date(start, zh: "yyyy年M月d日", en: sameYear ? "MMM d" : "MMM d, yyyy")
        let e = Fmt.date(end, zh: sameYear ? "M月d日" : "yyyy年M月d日", en: "MMM d, yyyy")
        return s + " – " + e
    }

    private func dailySeconds(from start: Date) -> [Date: Double] {
        var result: [Date: Double] = [:]
        for s in store.sessions where s.startedAt >= start {
            result[cal.startOfDay(for: s.startedAt), default: 0] += s.seconds
        }
        return result
    }

    private func summary(_ daily: [Date: Double], from start: Date, to end: Date) -> String {
        var activeDays = 0, longest = 0, run = 0
        var total = 0.0
        var d = start
        while d <= end {
            let sec = daily[d] ?? 0
            total += sec
            if sec >= 60 {
                activeDays += 1
                run += 1
                longest = max(longest, run)
            } else {
                run = 0
            }
            d = cal.date(byAdding: .day, value: 1, to: d)!
        }
        return tr("\(activeDays) 天有专注 · 最长连续 \(longest) 天 · 共 \(Fmt.duration(total))",
                  "\(activeDays) active days · \(longest)-day best streak · \(Fmt.duration(total))")
    }
}
