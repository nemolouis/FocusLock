import AppKit
import Combine

@MainActor
final class AppModel {
    static let shared = AppModel()

    let store: Store
    let blocker: AppBlocker
    let timer: FocusTimer
    private var appearanceSync: AnyCancellable?

    /// SwiftUI 的 openWindow 只能在视图里拿到，由菜单栏图标视图出现时注册进来
    var openMainWindowAction: (() -> Void)?

    private init() {
        store = Store()
        blocker = AppBlocker()
        timer = FocusTimer(store: store, blocker: blocker)
        blocker.blockedIds = { [unowned store] in Set(store.blockedApps.map(\.bundleId)) }
        blocker.statusText = { [unowned timer] in
            timer.mode == .countdown
                ? tr("专注中，还剩 \(Fmt.clock(timer.remaining, roundUp: true))",
                     "Focusing, \(Fmt.clock(timer.remaining, roundUp: true)) left")
                : tr("专注中，已专注 \(Fmt.clock(timer.elapsed, roundUp: false))",
                     "Focusing, \(Fmt.clock(timer.elapsed, roundUp: false)) so far")
        }
    }

    /// 浅色 / 深色模式作用于整个 App（窗口、菜单栏、弹窗）
    func startAppearanceSync() {
        NSApp.appearance = store.settings.appearance.nsAppearance
        appearanceSync = store.$settings
            .map(\.appearance)
            .removeDuplicates()
            .sink { NSApp.appearance = $0.nsAppearance }
    }

    // MARK: - 主窗口 / 程序坞图标

    static func isMainWindow(_ w: NSWindow) -> Bool {
        w.identifier?.rawValue == "main" || (w.title == "FocusLock" && !(w is NSPanel))
    }

    var mainWindowVisible: Bool {
        NSApp.windows.contains { Self.isMainWindow($0) && $0.isVisible }
    }

    /// 打开主窗口（可指定页面）。打开时显示程序坞图标
    func showMainWindow(page: Page? = nil) {
        if let page { UserDefaults.standard.set(page.rawValue, forKey: "lastPage") }
        NSApp.setActivationPolicy(.regular)
        if let w = NSApp.windows.first(where: Self.isMainWindow) {
            w.makeKeyAndOrderFront(nil)
        } else {
            openMainWindowAction?()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 主窗口都关掉后隐藏程序坞图标，只留在菜单栏
    func updateActivationPolicy() {
        let policy: NSApplication.ActivationPolicy = mainWindowVisible ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }
}
