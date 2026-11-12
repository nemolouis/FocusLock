import SwiftUI

/// 点菜单栏图标弹出的面板：不用打开主窗口就能完成「专注」页的主要操作
struct MenuBarPanel: View {
    @EnvironmentObject var timer: FocusTimer
    @EnvironmentObject var store: Store
    @EnvironmentObject var blocker: AppBlocker
    @State private var confirmDiscard = false
    private let presets = [15, 25, 45, 60]

    private var accent: Color {
        timer.isResting ? Palette.rest : Color(hex: store.categoryColorHex(timer.categoryId))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if timer.isResting {
                restSection
            } else if timer.isActive {
                activeSection
            } else {
                setupSection
            }

            messageLine

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 300)
        .onChange(of: timer.state) { confirmDiscard = false }
    }

    // MARK: 顶部

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: MenuBarIcon.image(locked: timer.isActive))
            Text("FocusLock").font(.headline)
            Spacer()
            Text(todaySummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var todaySummary: String {
        let today = store.sessions(since: Calendar.current.startOfDay(for: Date()))
        let total = today.reduce(0) { $0 + $1.seconds }
        return tr("今天 ", "Today ") + Fmt.duration(total)
    }

    // MARK: 未开始：模式、时长、分类、锁定、休息

    private var setupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $timer.mode) {
                ForEach(TimerMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if timer.mode == .countdown {
                HStack(spacing: 6) {
                    ForEach(presets, id: \.self) { m in
                        Button("\(m)") { timer.countdownMinutes = m }
                            .buttonStyle(ChipStyle(selected: timer.countdownMinutes == m, color: accent))
                            .help(Fmt.minutes(m))
                    }
                    Spacer(minLength: 4)
                    Stepper(value: $timer.countdownMinutes, in: 1...240) {
                        Text(Fmt.minutes(timer.countdownMinutes))
                            .monospacedDigit()
                            .foregroundStyle(presets.contains(timer.countdownMinutes) ? .secondary : accent)
                    }
                    .fixedSize()
                }
                .font(.callout)
            }

            VStack(alignment: .leading, spacing: 6) {
                sectionLabel(tr("分类", "Category"))
                FlowLayout(spacing: 6, centered: false) {
                    ForEach(store.categories) { c in
                        Button {
                            timer.categoryId = c.id
                        } label: {
                            HStack(spacing: 5) {
                                CategoryDot(hex: c.colorHex, size: 7)
                                Text(c.name)
                            }
                        }
                        .buttonStyle(ChipStyle(selected: timer.categoryId == c.id, color: c.color))
                    }
                }
                .font(.callout)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("专注时锁定应用", "Block apps while focusing"))
                        Text(blockedSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Toggle("", isOn: $store.settings.lockEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                if store.blockedApps.isEmpty {
                    Button(tr("添加要锁定的应用…", "Add apps to block…")) {
                        AppModel.shared.showMainWindow(page: .blocklist)
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }

                HStack {
                    Text(tr("专注后休息", "Break after focus"))
                    Spacer()
                    Stepper(value: $store.settings.restMinutes, in: 1...60) {
                        Text(Fmt.minutes(store.settings.restMinutes))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize()
                    .disabled(!store.settings.restEnabled)
                    Toggle("", isOn: $store.settings.restEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
            .font(.callout)

            Button {
                timer.start()
            } label: {
                Label(tr("开始专注", "Start Focus"), systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(MainButtonStyle(color: accent))
            .keyboardShortcut(.defaultAction)
        }
    }

    private var blockedSummary: String {
        if store.blockedApps.isEmpty { return tr("还没有添加应用", "No apps added yet") }
        let names = store.blockedApps.prefix(3).map(\.name).joined(separator: tr("、", ", "))
        let more = store.blockedApps.count > 3
            ? tr(" 等 \(store.blockedApps.count) 个", " and \(store.blockedApps.count - 3) more")
            : ""
        return names + more
    }

    // MARK: 专注中

    private var activeSection: some View {
        VStack(spacing: 10) {
            bigClock

            if timer.mode == .countdown {
                ProgressView(value: timer.progress)
                    .tint(accent)
            }

            HStack(spacing: 6) {
                CategoryDot(hex: store.categoryColorHex(timer.categoryId), size: 8)
                Text(store.categoryName(timer.categoryId)).fontWeight(.medium)
                Text("· " + (timer.state == .paused ? tr("已暂停", "Paused") : tr("专注中", "Focusing")))
                    .foregroundStyle(.secondary)
                if timer.mode == .countdown {
                    Text("· " + tr("目标 \(Int(timer.targetSeconds / 60)) 分钟", "Goal \(Int(timer.targetSeconds / 60)) min"))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)

            if blocker.isActive {
                Label(tr("正在锁定 \(store.blockedApps.count) 个应用 · 已拦截 \(blocker.blockedCount) 次",
                         "Blocking \(store.blockedApps.count) apps · \(blocker.blockedCount) blocked"),
                      systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if timer.isStrictLocked {
                Label(tr("严格模式：倒计时结束前无法暂停或停止", "Strict mode: can't pause or stop until it ends"),
                      systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if confirmDiscard {
                HStack {
                    Text(tr("放弃本次专注？不会保存。", "Discard this session? It won't be saved."))
                        .font(.caption)
                    Spacer()
                    Button(tr("取消", "Cancel")) { confirmDiscard = false }
                    Button(tr("放弃", "Discard"), role: .destructive) {
                        confirmDiscard = false
                        timer.abandon()
                    }
                }
            } else {
                HStack(spacing: 8) {
                    if timer.state == .running {
                        Button { timer.pause() } label: {
                            Label(tr("暂停", "Pause"), systemImage: "pause.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(MainButtonStyle(color: accent))
                    } else {
                        Button { timer.resume() } label: {
                            Label(tr("继续", "Resume"), systemImage: "play.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(MainButtonStyle(color: accent))
                    }
                    Button { timer.finish() } label: {
                        Label(tr("结束", "Finish"), systemImage: "stop.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .help(tr("结束并保存本次专注", "Finish and save this session"))
                    Button { confirmDiscard = true } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .help(tr("放弃，不保存", "Discard without saving"))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 休息中

    private var restSection: some View {
        VStack(spacing: 10) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.title2)
                .foregroundStyle(accent)
            bigClock
            ProgressView(value: timer.progress)
                .tint(accent)
            Text(tr("休息中 · 不计入记录，结束后会提醒你", "On a break · not recorded, you'll be notified when it ends"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                timer.skipRest()
            } label: {
                Label(tr("跳过休息", "Skip Break"), systemImage: "forward.end.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(MainButtonStyle(color: accent))
        }
        .frame(maxWidth: .infinity)
    }

    private var bigClock: some View {
        Text(timer.displayText)
            .font(.system(size: 46, weight: .light, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText())
    }

    // MARK: 提示和底部

    @ViewBuilder
    private var messageLine: some View {
        if let b = blocker.lastBlocked, blocker.isActive, timer.now.timeIntervalSince(b.date) < 5 {
            Label(tr("已拦截「\(b.name)」", "Blocked \(b.name)"), systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        } else if let m = timer.message, Date().timeIntervalSince(m.date) < 6 {
            Label(m.text, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(accent)
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button {
                AppModel.shared.showMainWindow()
            } label: {
                Label(tr("打开主窗口", "Open Window"), systemImage: "macwindow")
            }
            Button {
                AppModel.shared.showMainWindow(page: .stats)
            } label: {
                Label(tr("统计", "Stats"), systemImage: "chart.pie")
            }
            Spacer()
            Button(tr("退出", "Quit")) { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
