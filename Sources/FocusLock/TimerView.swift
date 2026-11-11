import SwiftUI

struct TimerView: View {
    @EnvironmentObject var timer: FocusTimer
    @EnvironmentObject var store: Store
    @EnvironmentObject var blocker: AppBlocker
    var goToBlocklist: () -> Void

    @State private var confirmAbandon = false
    private let presets = [15, 25, 45, 60]

    private var accent: Color {
        timer.isResting ? Palette.rest : Color(hex: store.categoryColorHex(timer.categoryId))
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
                .disabled(timer.isActive || timer.isResting)

                dial

                if timer.isActive {
                    activeInfo
                } else if timer.isResting {
                    restInfo
                } else {
                    setup
                }

                controls

                banners

                lockRow
                    .frame(maxWidth: 520)
            }
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .confirmationDialog(tr("放弃本次专注？", "Discard this session?"), isPresented: $confirmAbandon) {
            Button(tr("放弃，不保存", "Discard"), role: .destructive) { timer.abandon() }
            Button(tr("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(tr("已专注的 \(Fmt.duration(timer.elapsed)) 不会被记录。",
                    "\(Fmt.duration(timer.elapsed)) of focus won't be saved."))
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
                if timer.isResting {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.title2)
                        .foregroundStyle(accent)
                }
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
        case .idle:
            return timer.mode == .countdown ? tr("准备开始一个番茄", "Ready for a pomodoro")
                                            : tr("正计时，随时结束", "Stopwatch, stop any time")
        case .running: return timer.mode == .countdown ? tr("专注中", "Focusing") : tr("已专注", "Focused")
        case .paused: return tr("已暂停", "Paused")
        case .resting: return tr("休息中", "On a break")
        }
    }

    // MARK: 未开始时的设置

    private var setup: some View {
        VStack(spacing: 16) {
            if timer.mode == .countdown {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.self) { m in
                        Button(Fmt.minutes(m)) { timer.countdownMinutes = m }
                            .buttonStyle(ChipStyle(selected: timer.countdownMinutes == m, color: accent))
                    }
                    Stepper(value: $timer.countdownMinutes, in: 1...240) {
                        if presets.contains(timer.countdownMinutes) {
                            Text(tr("自定义", "Custom")).foregroundStyle(.secondary)
                        } else {
                            Text(Fmt.minutes(timer.countdownMinutes)).monospacedDigit().foregroundStyle(accent)
                        }
                    }
                    .fixedSize()
                    .padding(.leading, 6)
                }
            }

            restSetting

            CategoryChips(selection: $timer.categoryId)
                .frame(maxWidth: 560)

            TextField(tr("在做什么？（可选）", "What are you working on? (optional)"), text: $timer.note)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
                .onSubmit { timer.start() }
        }
    }

    /// 专注后自动休息：开关 + 时长
    private var restSetting: some View {
        HStack(spacing: 10) {
            Image(systemName: "cup.and.saucer.fill")
                .foregroundStyle(store.settings.restEnabled ? Palette.rest : .secondary)
            Toggle(tr("专注后休息", "Break after focus"), isOn: $store.settings.restEnabled)
            Stepper(value: $store.settings.restMinutes, in: 1...60) {
                Text(Fmt.minutes(store.settings.restMinutes)).monospacedDigit()
            }
            .fixedSize()
            .disabled(!store.settings.restEnabled)
        }
        .font(.callout)
    }

    private var activeInfo: some View {
        HStack(spacing: 8) {
            CategoryDot(hex: store.categoryColorHex(timer.categoryId))
            Text(store.categoryName(timer.categoryId)).font(.headline)
            if !timer.note.isEmpty {
                Text("· " + timer.note).foregroundStyle(.secondary)
            }
            if timer.mode == .countdown {
                Text("· " + tr("目标 \(Int(timer.targetSeconds / 60)) 分钟", "Goal \(Int(timer.targetSeconds / 60)) min"))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var restInfo: some View {
        Text(tr("起来走走，喝口水。休息不计入记录，结束后会提醒你。",
                "Stand up, stretch, drink some water. Breaks aren't recorded; you'll be notified when it ends."))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 420)
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
                    Label(tr("开始专注", "Start Focus"), systemImage: "play.fill").frame(width: 160)
                }
                .buttonStyle(MainButtonStyle(color: accent))
                .keyboardShortcut(.space, modifiers: [])

            case .resting:
                Button {
                    timer.skipRest()
                } label: {
                    Label(tr("跳过休息", "Skip Break"), systemImage: "forward.end.fill").frame(width: 160)
                }
                .buttonStyle(MainButtonStyle(color: accent))
                .keyboardShortcut(.space, modifiers: [])

            case .running, .paused:
                if timer.isStrictLocked {
                    Label(tr("严格模式：倒计时结束前无法暂停或停止", "Strict mode: can't pause or stop until the countdown ends"),
                          systemImage: "lock.fill")
                        .foregroundStyle(.secondary)
                } else {
                    if timer.state == .running {
                        Button { timer.pause() } label: {
                            Label(tr("暂停", "Pause"), systemImage: "pause.fill").frame(width: 110)
                        }
                        .buttonStyle(MainButtonStyle(color: accent))
                        .keyboardShortcut(.space, modifiers: [])
                    } else {
                        Button { timer.resume() } label: {
                            Label(tr("继续", "Resume"), systemImage: "play.fill").frame(width: 110)
                        }
                        .buttonStyle(MainButtonStyle(color: accent))
                        .keyboardShortcut(.space, modifiers: [])
                    }
                    Button { timer.finish() } label: {
                        Label(tr("结束", "Finish"), systemImage: "stop.fill").frame(width: 90)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .help(tr("结束并保存本次专注", "Finish and save this session"))

                    Button { confirmAbandon = true } label: {
                        Label(tr("放弃", "Discard"), systemImage: "xmark").frame(width: 90)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .help(tr("放弃，不保存", "Discard without saving"))
                }
            }
        }
    }

    // MARK: 提示条

    @ViewBuilder
    private var banners: some View {
        let now = timer.now
        if let b = blocker.lastBlocked, blocker.isActive, now.timeIntervalSince(b.date) < 5 {
            Banner(icon: "lock.fill",
                   text: tr("已拦截「\(b.name)」，先专注吧", "Blocked \(b.name). Stay focused!"),
                   color: .orange)
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
                VStack(alignment: .leading, spacing: 2) {
                    Toggle(tr("专注时锁定应用", "Block apps while focusing"), isOn: $store.settings.lockEnabled)
                        .disabled(blocker.isActive)
                    Group {
                        if store.blockedApps.isEmpty {
                            Text(tr("还没有添加要锁定的应用", "No apps added yet"))
                        } else if blocker.isActive {
                            Text(tr("正在锁定 \(store.blockedApps.count) 个应用 · 本次已拦截 \(blocker.blockedCount) 次",
                                    "Locking \(store.blockedApps.count) apps · blocked \(blocker.blockedCount) times"))
                        } else {
                            Text(store.blockedApps.prefix(4).map(\.name).joined(separator: tr("、", ", "))
                                 + (store.blockedApps.count > 4
                                    ? tr(" 等 \(store.blockedApps.count) 个", " and \(store.blockedApps.count - 4) more")
                                    : ""))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 20)
                }
                Spacer()
                Button(store.blockedApps.isEmpty ? tr("添加应用", "Add Apps") : tr("管理", "Manage")) { goToBlocklist() }
            }
        }
    }
}

// MARK: - 分类选择 + 管理入口

struct CategoryChips: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var timer: FocusTimer
    @Binding var selection: UUID?
    @State private var managing = false

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
            Button {
                managing = true
            } label: {
                Label(tr("管理分类", "Manage"), systemImage: "slider.horizontal.3")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(ChipStyle(selected: false, color: .secondary))
            .help(tr("添加、重命名、改颜色、排序或删除分类", "Add, rename, recolor, reorder or delete categories"))
        }
        .sheet(isPresented: $managing) {
            CategoryManagerSheet()
                .environmentObject(store)
                .environmentObject(timer)
                .environment(\.locale, L10n.locale)
        }
    }
}

/// 自动换行布局
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    /// true 每行居中，false 左对齐
    var centered = true

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
            var x = bounds.minX + (centered ? (bounds.width - row.width) / 2 : 0)
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
