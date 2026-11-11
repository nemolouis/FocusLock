import SwiftUI

/// 类似 GitHub 贡献图的专注热力图：近 16 周，一列一周（周一到周日），颜色越深专注越久
struct HeatmapCard: View {
    @EnvironmentObject var store: Store
    @Environment(\.colorScheme) private var scheme
    var onSelectDay: (Date) -> Void

    @State private var width: CGFloat = 300
    private let weeks = 16
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
        let gridStart = cal.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeek)!
        let daily = dailySeconds(from: gridStart)
        // 格子大小随卡片宽度变化，最大 26pt
        let step = max(8, min(26, ((width - labelWidth) / CGFloat(weeks)).rounded(.down)))
        let gap = max(2, (step * 0.16).rounded())

        Card(title: tr("近 16 周", "Last 16 weeks")) {
            Text(summary(daily, from: gridStart, to: today))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 3) {
                monthLabels(gridStart: gridStart, step: step)
                HStack(alignment: .top, spacing: 0) {
                    weekdayLabels(step: step)
                    ForEach(0..<weeks, id: \.self) { w in
                        VStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { r in
                                let day = cal.date(byAdding: .day, value: w * 7 + r, to: gridStart)!
                                cell(day: day, today: today, seconds: daily[day] ?? 0, step: step, gap: gap)
                            }
                        }
                    }
                }
                legend
            }
            .frame(width: labelWidth + CGFloat(weeks) * step)
            .frame(maxWidth: .infinity)   // 卡片比格子宽时居中
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        }
    }

    // MARK: 格子

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

    /// 每个月第一次出现的那一列上方标月份
    private func monthLabels(gridStart: Date, step: CGFloat) -> some View {
        var marks: [(col: Int, text: String)] = []
        var lastMonth = -1
        for w in 0..<weeks {
            let d = cal.date(byAdding: .day, value: w * 7, to: gridStart)!
            let m = cal.component(.month, from: d)
            if m != lastMonth {
                marks.append((w, Fmt.date(d, zh: "M月", en: "MMM")))
                lastMonth = m
            }
        }
        // 第一列的月份和下一个月太近就不标，避免文字重叠
        if marks.count > 1, marks[1].col - marks[0].col < 3 { marks.removeFirst() }
        return ZStack(alignment: .topLeading) {
            ForEach(marks, id: \.col) { mark in
                Text(mark.text)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .offset(x: labelWidth + CGFloat(mark.col) * step)
            }
        }
        .frame(maxWidth: .infinity, minHeight: monthRowHeight, maxHeight: monthRowHeight, alignment: .topLeading)
    }

    private func weekdayLabels(step: CGFloat) -> some View {
        let names = L10n.isEnglish ? ["M", "", "W", "", "F", "", ""] : ["一", "", "三", "", "五", "", ""]
        return VStack(alignment: .leading, spacing: 0) {
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

    private func dailySeconds(from start: Date) -> [Date: Double] {
        var result: [Date: Double] = [:]
        for s in store.sessions where s.startedAt >= start {
            result[cal.startOfDay(for: s.startedAt), default: 0] += s.seconds
        }
        return result
    }

    private func summary(_ daily: [Date: Double], from start: Date, to today: Date) -> String {
        var activeDays = 0, longest = 0, run = 0
        var total = 0.0
        var d = start
        while d <= today {
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
