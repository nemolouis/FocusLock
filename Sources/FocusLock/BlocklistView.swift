import SwiftUI
import UniformTypeIdentifiers

struct BlocklistView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var blocker: AppBlocker
    @EnvironmentObject var timer: FocusTimer

    private var runningCandidates: [NSRunningApplication] {
        let blocked = Set(store.blockedApps.map(\.bundleId))
        return NSWorkspace.shared.runningApplications
            .filter {
                $0.activationPolicy == .regular
                    && $0.bundleURL != nil
                    && $0.bundleIdentifier != nil
                    && $0.bundleIdentifier != Bundle.main.bundleIdentifier
                    && !AppBlocker.protectedIds.contains($0.bundleIdentifier!)
                    && !blocked.contains($0.bundleIdentifier!)
            }
            .sorted { ($0.localizedName ?? "").localizedCompare($1.localizedName ?? "") == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(tr("锁定应用", "Blocked Apps")).font(.largeTitle.weight(.semibold))

                if blocker.isActive {
                    Banner(icon: "lock.fill", text: tr("专注中：可以添加应用，但不能移除或修改锁定设置", "Focusing: you can add apps, but not remove them or change the rules"), color: .orange)
                }

                Card(title: tr("锁定规则", "Rules")) {
                    Toggle(tr("专注时锁定下面的应用", "Block these apps while focusing"), isOn: $store.settings.lockEnabled)
                    Toggle(tr("暂停时也保持锁定", "Keep blocking while paused"), isOn: $store.settings.lockWhilePaused)
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(tr("严格模式", "Strict mode"), isOn: $store.settings.strictMode)
                        Text(tr("开启后，倒计时结束前不能暂停、结束、放弃，也不能退出 FocusLock。", "Once on, you can't pause, finish, discard or quit FocusLock until the countdown ends."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(blocker.isActive || timer.isStrictLocked)

                Card {
                    HStack {
                        Text(tr("要锁定的应用（\(store.blockedApps.count)）", "Apps to block (\(store.blockedApps.count))")).font(.headline)
                        Spacer()
                        Menu {
                            let apps = runningCandidates
                            if apps.isEmpty {
                                Text(tr("没有可添加的应用", "No apps to add"))
                            }
                            ForEach(apps, id: \.processIdentifier) { app in
                                Button(app.localizedName ?? app.bundleIdentifier ?? "") {
                                    if let url = app.bundleURL { add([url]) }
                                }
                            }
                        } label: {
                            Label(tr("从正在运行的应用添加", "Add Running App"), systemImage: "app.badge")
                        }
                        .fixedSize()
                        Button {
                            pickApps()
                        } label: {
                            Label(tr("从应用程序文件夹选择…", "Choose from Applications…"), systemImage: "plus")
                        }
                    }

                    if store.blockedApps.isEmpty {
                        Text(tr("还没有添加应用。比如微信、QQ、浏览器、游戏、视频 App……", "No apps yet. Try chat apps, browsers, games, video apps…"))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 80)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(store.blockedApps) { app in
                                BlockedAppRow(app: app, removable: !blocker.isActive)
                                if app.id != store.blockedApps.last?.id { Divider() }
                            }
                        }
                    }
                }

                Card(title: tr("说明", "How it works")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tr("• 专注开始时，已经打开的锁定应用会被要求退出（和按 ⌘Q 一样，有未保存内容时它会先弹窗问你）。", "• When focus starts, blocked apps that are open are asked to quit (like ⌘Q; they'll ask about unsaved work first)."))
                        Text(tr("• 专注期间打开锁定应用，会被立即关闭，并跳回 FocusLock。", "• Opening a blocked app while focusing closes it right away and brings you back to FocusLock."))
                        Text(tr("• 锁定只在 FocusLock 运行时生效。关掉窗口没关系，FocusLock 会留在菜单栏里继续计时。", "• Blocking only works while FocusLock is running. Closing the window is fine; it keeps timing in the menu bar."))
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
    }

    private func pickApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = tr("锁定", "Block")
        panel.message = tr("选择专注时要锁定的应用", "Choose apps to block while focusing")
        if panel.runModal() == .OK {
            add(panel.urls)
        }
    }

    private func add(_ urls: [URL]) {
        for u in urls { store.addBlockedApp(at: u) }
        blocker.sweep()
    }
}

private struct BlockedAppRow: View {
    @EnvironmentObject var store: Store
    let app: BlockedApp
    let removable: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                .resizable()
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                Text(app.bundleId).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive) {
                store.removeBlockedApp(app.bundleId)
            } label: {
                Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(removable ? .red : .secondary)
            .disabled(!removable)
            .help(removable ? tr("移除", "Remove") : tr("专注中不能移除", "Can't remove while focusing"))
        }
        .padding(.vertical, 8)
    }
}
