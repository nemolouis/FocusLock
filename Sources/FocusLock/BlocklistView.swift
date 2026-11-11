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
                Text("锁定应用").font(.largeTitle.weight(.semibold))

                if blocker.isActive {
                    Banner(icon: "lock.fill", text: "专注中：可以添加应用，但不能移除或修改锁定设置", color: .orange)
                }

                Card(title: "锁定规则") {
                    Toggle("专注时锁定下面的应用", isOn: $store.settings.lockEnabled)
                    Toggle("暂停时也保持锁定", isOn: $store.settings.lockWhilePaused)
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("严格模式", isOn: $store.settings.strictMode)
                        Text("开启后，倒计时结束前不能暂停、结束、放弃，也不能退出 FocusLock。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(blocker.isActive || timer.isStrictLocked)

                Card {
                    HStack {
                        Text("要锁定的应用（\(store.blockedApps.count)）").font(.headline)
                        Spacer()
                        Menu {
                            let apps = runningCandidates
                            if apps.isEmpty {
                                Text("没有可添加的应用")
                            }
                            ForEach(apps, id: \.processIdentifier) { app in
                                Button(app.localizedName ?? app.bundleIdentifier ?? "") {
                                    if let url = app.bundleURL { add([url]) }
                                }
                            }
                        } label: {
                            Label("从正在运行的应用添加", systemImage: "app.badge")
                        }
                        .fixedSize()
                        Button {
                            pickApps()
                        } label: {
                            Label("从应用程序文件夹选择…", systemImage: "plus")
                        }
                    }

                    if store.blockedApps.isEmpty {
                        Text("还没有添加应用。比如微信、QQ、浏览器、游戏、视频 App……")
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

                Card(title: "说明") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("• 专注开始时，已经打开的锁定应用会被要求退出（和按 ⌘Q 一样，有未保存内容时它会先弹窗问你）。")
                        Text("• 专注期间打开锁定应用，会被立即关闭，并跳回 FocusLock。")
                        Text("• 锁定只在 FocusLock 运行时生效。关掉窗口没关系，FocusLock 会留在菜单栏里继续计时。")
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
        panel.prompt = "锁定"
        panel.message = "选择专注时要锁定的应用"
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
            .help(removable ? "移除" : "专注中不能移除")
        }
        .padding(.vertical, 8)
    }
}
