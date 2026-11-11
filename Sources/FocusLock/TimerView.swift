import SwiftUI

struct TimerView: View {
    @EnvironmentObject var timer: FocusTimer
    @EnvironmentObject var store: Store
    @EnvironmentObject var blocker: AppBlocker
    var goToBlocklist: () -> Void

    @State private var confirmAbandon = false
    private let presets = [15, 25, 45, 60]

    private var accent: Color {
        Color(hex: store.categoryColorHex(timer.categoryId))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Picker("", selection: $timer.mode) {
                    ForEach(TimerMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
                .disabled(timer.isActive)

                dial

                if timer.isActive {
                    activeInfo
                } else {
                    setup
                }

                controls

                banners

                lockRow
                    .frame(maxWidth: 520)

                TodaySummary()
                    .frame(maxWidth: 520)
            }
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .confirmationDialog("放弃本次专注？", isPresented: $confirmAbandon) {
            Button("放弃，不保存", role: .destructive) { timer.abandon() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("已专注的 \(Fmt.duration(timer.elapsed)) 不会被记录。")
        }
    }

    // MARK: 表盘

    private var dial: some View {
        ZStack {
            Circle()
                .stroke(accent.opacity(0.15), lineWidth: 16)
            Circle()
                .trim(from: 0, to: timer.progress)
                .stroke(accent, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: timer.progress)
            VStack(spacing: 6) {
                Text(timer.displayText)
                    .font(.system(size: 64, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 280, height: 280)
        .padding(.vertical, 4)
    }

    private var statusText: String {
        switch timer.state {
        case .idle: return timer.mode == .countdown ? "准备开始一个番茄" : "正计时，随时结束"
        case .running: return timer.mode == .countdown ? "专注中" : "已专注"
        case .paused: return "已暂停"
        }
    }

    // MARK: 未开始时的设置

    private var setup: some View {
        VStack(spacing: 16) {
            if timer.mode == .countdown {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.self) { m in
                        Button("\(m) 分钟") { timer.countdownMinutes = m }
                            .buttonStyle(ChipStyle(selected: timer.countdownMinutes == m, color: accent))
                    }
                    Stepper(value: $timer.countdownMinutes, in: 1...240) {
                        if presets.contains(timer.countdownMinutes) {
                            Text("自定义").foregroundStyle(.secondary)
                        } else {
                            Text("\(timer.countdownMinutes) 分钟").monospacedDigit().foregroundStyle(accent)
                        }
                    }
                    .fixedSize()
                    .padding(.leading, 6)
                }
            }

            CategoryChips(selection: $timer.categoryId)
                .frame(maxWidth: 560)

            TextField("在做什么？（可选）", text: $timer.note)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
                .onSubmit { timer.start() }
        }
    }

    private var activeInfo: some View {
        HStack(spacing: 8) {
            CategoryDot(hex: store.categoryColorHex(timer.categoryId))
            Text(store.categoryName(timer.categoryId)).font(.headline)
            if !timer.note.isEmpty {
                Text("· \(timer.note)").foregroundStyle(.secondary)
            }
            if timer.mode == .countdown {
                Text("· 目标 \(Int(timer.targetSeconds / 60)) 分钟").foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 按钮

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 12) {
            switch timer.state {
            case .idle:
                Button {
                    timer.start()
                } label: {
                    Label("开始专注", systemImage: "play.fill").frame(width: 160)
                }
                .buttonStyle(MainButtonStyle(color: accent))
                .keyboardShortcut(.space, modifiers: [])

            case .running, .paused:
                if timer.isStrictLocked {
                    Label("严格模式：倒计时结束前无法暂停或停止", systemImage: "lock.fill")
                        .foregroundStyle(.secondary)
                } else {
                    if timer.state == .running {
                        Button { timer.pause() } label: {
                            Label("暂停", systemImage: "pause.fill").frame(width: 110)
                        }
                        .buttonStyle(MainButtonStyle(color: accent))
                        .keyboardShortcut(.space, modifiers: [])
                    } else {
                        Button { timer.resume() } label: {
                            Label("继续", systemImage: "play.fill").frame(width: 110)
                        }
                        .buttonStyle(MainButtonStyle(color: accent))
                        .keyboardShortcut(.space, modifiers: [])
                    }
                    Button { timer.finish() } label: {
                        Label("结束", systemImage: "stop.fill").frame(width: 90)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .help("结束并保存本次专注")

                    Button { confirmAbandon = true } label: {
                        Label("放弃", systemImage: "xmark").frame(width: 90)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .help("放弃，不保存")
                }
            }
        }
    }

    // MARK: 提示条

    @ViewBuilder
    private var banners: some View {
        let now = timer.now
        if let b = blocker.lastBlocked, blocker.isActive, now.timeIntervalSince(b.date) < 5 {
            Banner(icon: "lock.fill", text: "已拦截「\(b.name)」，先专注吧", color: .orange)
        } else if let m = timer.message, Date().timeIntervalSince(m.date) < 6 {
            Banner(icon: "checkmark.circle.fill", text: m.text, color: accent)
                .task(id: m.date) {
                    // 空闲时 now 不再刷新，用 task 让提示自动消失
                    try? await Task.sleep(for: .seconds(6))
                    timer.objectWillChange.send()
                }
        }
    }

    // MARK: 锁定

    private var lockRow: some View {
        Card {
            HStack {
                Image(systemName: blocker.isActive ? "lock.fill" : "lock.open")
                    .font(.title3)
                    .foregroundStyle(blocker.isActive ? .orange : .secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Toggle("专注时锁定应用", isOn: $store.settings.lockEnabled)
                        .disabled(blocker.isActive)
                    Group {
                        if store.blockedApps.isEmpty {
                            Text("还没有添加要锁定的应用")
                        } else if blocker.isActive {
                            Text("正在锁定 \(store.blockedApps.count) 个应用 · 本次已拦截 \(blocker.blockedCount) 次")
                        } else {
                            Text(store.blockedApps.prefix(4).map(\.name).joined(separator: "、")
                                 + (store.blockedApps.count > 4 ? " 等 \(store.blockedApps.count) 个" : ""))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button(store.blockedApps.isEmpty ? "添加应用" : "管理") { goToBlocklist() }
            }
        }
    }
}

// MARK: - 今日概览

struct TodaySummary: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let today = store.sessions(since: Calendar.current.startOfDay(for: Date()))
        let total = today.reduce(0) { $0 + $1.seconds }
        let tomatoes = today.filter { $0.mode == .countdown && $0.completed }.count
        Card(title: "今天") {
            HStack {
                stat(Fmt.duration(total), "专注时长")
                Divider().frame(height: 32)
                stat("\(tomatoes)", "完成番茄")
                Divider().frame(height: 32)
                stat("\(today.count)", "专注次数")
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 分类选择

struct CategoryChips: View {
    @EnvironmentObject var store: Store
    @Binding var selection: UUID?

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(store.categories) { c in
                Button {
                    selection = c.id
                } label: {
                    HStack(spacing: 6) {
                        CategoryDot(hex: c.colorHex, size: 8)
                        Text(c.name)
                    }
                }
                .buttonStyle(ChipStyle(selected: selection == c.id, color: c.color))
            }
        }
    }
}

/// 自动换行布局
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let w = rows.map { $0.width }.max() ?? 0
        let h = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: w, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX + (bounds.width - row.width) / 2 // 居中
            for i in row.indices {
                let s = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += s.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for (i, v) in subviews.enumerated() {
            let s = v.sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? s.width : s.width + spacing
            if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let add = rows[rows.count - 1].indices.isEmpty ? s.width : s.width + spacing
            rows[rows.count - 1].indices.append(i)
            rows[rows.count - 1].width += add
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, s.height)
        }
        return rows
    }
}

// MARK: - 样式

struct ChipStyle: ButtonStyle {
    var selected: Bool
    var color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(selected ? color.opacity(0.18) : Color.secondary.opacity(0.08), in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? color : .clear, lineWidth: 1.5))
            .foregroundStyle(selected ? color : .primary)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

struct MainButtonStyle: ButtonStyle {
    var color: Color
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.vertical, 11)
            .padding(.horizontal, 16)
            .background(color.opacity(isEnabled ? 1 : 0.4), in: Capsule())
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .contentShape(Capsule())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.vertical, 11)
            .padding(.horizontal, 12)
            .background(Color.secondary.opacity(configuration.isPressed ? 0.25 : 0.14), in: Capsule())
            .contentShape(Capsule())
    }
}

struct Banner: View {
    var icon: String
    var text: String
    var color: Color

    var body: some View {
        Label(text, systemImage: icon)
            .font(.callout.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
            .transition(.opacity)
    }
}
