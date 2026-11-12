import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Notifier.available {
            UNUserNotificationCenter.current().delegate = self
        }
        Notifier.requestAuthorization()
        let model = AppModel.shared
        model.startAppearanceSync()

        // 主窗口出现时显示程序坞图标，全部关掉后只留在菜单栏
        let nc = NotificationCenter.default
        // queue: .main 保证回调在主线程，用 assumeIsolated 告诉编译器
        observers.append(nc.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
            let window = note.object as? NSWindow
            MainActor.assumeIsolated {
                guard let window, AppModel.isMainWindow(window) else { return }
                AppModel.shared.updateActivationPolicy()
            }
        })
        observers.append(nc.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            let window = note.object as? NSWindow
            MainActor.assumeIsolated {
                guard let window, AppModel.isMainWindow(window) else { return }
                // 等窗口真正关掉后再判断
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { AppModel.shared.updateActivationPolicy() }
                }
            }
        })

        // 设置了「启动时不打开主窗口」：只在菜单栏运行
        if !model.store.settings.showWindowOnLaunch {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    NSApp.windows.filter(AppModel.isMainWindow).forEach { $0.close() }
                    AppModel.shared.updateActivationPolicy()
                }
            }
        }
    }

    /// 在访达 / 启动台里再次打开 App 时，把主窗口拿出来
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { AppModel.shared.showMainWindow() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let timer = AppModel.shared.timer
        guard timer.isActive else { return .terminateNow }

        NSApp.activate(ignoringOtherApps: true)
        if timer.isStrictLocked {
            let alert = NSAlert()
            alert.messageText = tr("严格模式进行中", "Strict mode is on")
            alert.informativeText = tr("倒计时结束前不能退出 FocusLock。还剩 \(Fmt.clock(timer.remaining, roundUp: true))。",
                                       "You can't quit FocusLock until the countdown ends. \(Fmt.clock(timer.remaining, roundUp: true)) left.")
            alert.addButton(withTitle: tr("继续专注", "Keep Focusing"))
            alert.runModal()
            return .terminateCancel
        }

        let alert = NSAlert()
        alert.messageText = tr("正在专注，确定退出吗？", "Quit while focusing?")
        alert.informativeText = tr("退出后计时停止、App 锁定解除。已专注满 1 分钟的时间会被保存。",
                                   "The timer stops and app locking ends. Focus time of 1 minute or more is saved.")
        alert.addButton(withTitle: tr("继续专注", "Keep Focusing"))
        alert.addButton(withTitle: tr("保存并退出", "Save and Quit"))
        if alert.runModal() == .alertSecondButtonReturn {
            timer.saveOnQuit()
            return .terminateNow
        }
        return .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.store.save()
    }

    // App 在前台时也显示通知横幅
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

@main
struct FocusLockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = AppModel.shared.store
    @StateObject private var timer = AppModel.shared.timer
    @StateObject private var blocker = AppModel.shared.blocker

    var body: some Scene {
        // 切换语言时用 id 让整个界面重建
        let lang = store.settings.language.isEnglish ? "en" : "zh"

        Window("FocusLock", id: "main") {
            ContentView()
                .id(lang)
                .environment(\.locale, L10n.locale)
                .environmentObject(store)
                .environmentObject(timer)
                .environmentObject(blocker)
                .frame(minWidth: 980, minHeight: 640)
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra {
            MenuBarPanel()
                .id(lang)
                .environment(\.locale, L10n.locale)
                .environmentObject(store)
                .environmentObject(timer)
                .environmentObject(blocker)
        } label: {
            MenuBarLabel(timer: timer)
        }
        .menuBarExtraStyle(.window)
    }
}

/// 菜单栏图标：未计时是开着的番茄锁；专注中上锁并显示剩余（或已专注）分钟
struct MenuBarLabel: View {
    @ObservedObject var timer: FocusTimer
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let text = timer.isActive || timer.isResting ? timer.menuBarMinutesText : nil
        Image(nsImage: MenuBarIcon.image(locked: timer.isActive, text: text))
            .onAppear {
                AppModel.shared.openMainWindowAction = { openWindow(id: "main") }
            }
    }
}
