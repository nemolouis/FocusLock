import AppKit

/// 专注期间监听 App 的启动 / 切换，遇到黑名单里的 App 就把它关掉。
@MainActor
final class AppBlocker: ObservableObject {
    struct BlockEvent: Equatable {
        let name: String
        let date: Date
    }

    /// 这些系统进程永远不拦截
    static let protectedIds: Set<String> = [
        "com.apple.finder", "com.apple.dock", "com.apple.loginwindow",
        "com.apple.systemuiserver", "com.apple.controlcenter",
    ]

    @Published private(set) var isActive = false
    @Published private(set) var lastBlocked: BlockEvent?
    @Published private(set) var blockedCount = 0

    /// 由外部提供：当前黑名单
    var blockedIds: () -> Set<String> = { [] }
    /// 由外部提供：通知里显示的剩余时间等
    var statusText: () -> String = { "" }

    private var observers: [NSObjectProtocol] = []
    private var lastNotified: [String: Date] = [:]

    init() {
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.handle(app, reason: .launched) }
        })
        observers.append(nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.handle(app, reason: .activated) }
        })
    }

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active {
            blockedCount = 0
            sweep()
        }
    }

    /// 关掉当前已经在运行的黑名单 App（比如开始专注时、或专注中新加了黑名单）
    func sweep() {
        guard isActive else { return }
        for app in NSWorkspace.shared.runningApplications {
            handle(app, reason: .sweep)
        }
    }

    private enum Reason { case launched, activated, sweep }

    private func handle(_ app: NSRunningApplication, reason: Reason) {
        guard isActive,
              let id = app.bundleIdentifier,
              id != Bundle.main.bundleIdentifier,
              !Self.protectedIds.contains(id),
              blockedIds().contains(id),
              !app.isTerminated
        else { return }

        let name = app.localizedName ?? id
        app.hide()
        // 先礼貌退出（相当于 ⌘Q，有未保存内容时 App 会自己弹窗）
        app.terminate()

        if reason == .launched {
            // 刚启动的 App 没有用户数据，3 秒还没退就强制结束
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.isActive, !app.isTerminated else { return }
                    app.forceTerminate()
                }
            }
        }

        blockedCount += 1
        lastBlocked = BlockEvent(name: name, date: Date())

        if reason != .sweep {
            // 同一个 App 5 秒内只提醒一次；主窗口开着就拉到前台，只在菜单栏运行时只发通知
            let now = Date()
            if let last = lastNotified[id], now.timeIntervalSince(last) < 5 { return }
            lastNotified[id] = now
            Notifier.post(title: tr("🔒 \(name) 已被锁定", "🔒 \(name) is blocked"), body: statusText())
            if let w = NSApp.windows.first(where: { AppModel.isMainWindow($0) && $0.isVisible }) {
                NSApp.activate(ignoringOtherApps: true)
                w.makeKeyAndOrderFront(nil)
            }
        }
    }
}
