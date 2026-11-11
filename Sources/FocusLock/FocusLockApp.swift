import Combine
import SwiftUI
import UserNotifications

@MainActor
final class AppModel {
    static let shared = AppModel()

    let store: Store
    let blocker: AppBlocker
    let timer: FocusTimer
    private var appearanceSync: AnyCancellable?

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
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if Notifier.available {
            UNUserNotificationCenter.current().delegate = self
        }
        Notifier.requestAuthorization()
        AppModel.shared.startAppearanceSync()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let timer = AppModel.shared.timer
        guard timer.isActive else { return .terminateNow }

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
            MenuBarContent()
                .id(lang)
                .environmentObject(store)
                .environmentObject(timer)
                .environmentObject(blocker)
        } label: {
            if timer.isActive || timer.isResting {
                Text(timer.menuBarText).monospacedDigit()
            } else {
                Image(systemName: "timer")
            }
        }
    }
}

struct MenuBarContent: View {
    @EnvironmentObject var timer: FocusTimer
    @EnvironmentObject var store: Store
    @EnvironmentObject var blocker: AppBlocker
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if timer.isResting {
            Text(tr("休息中 \(timer.displayText)", "On a break \(timer.displayText)"))
            Button(tr("跳过休息", "Skip Break")) { timer.skipRest() }
        } else if timer.isActive {
            Text("\(store.categoryName(timer.categoryId)) · \(timer.mode.title) \(timer.displayText)")
            if blocker.isActive {
                Text(tr("🔒 正在锁定 \(store.blockedApps.count) 个应用", "🔒 Locking \(store.blockedApps.count) apps"))
            }
            Divider()
            if timer.isStrictLocked {
                Text(tr("严格模式：结束前无法停止", "Strict mode: can't stop until it ends"))
            } else {
                if timer.state == .running {
                    Button(tr("暂停", "Pause")) { timer.pause() }
                } else {
                    Button(tr("继续", "Resume")) { timer.resume() }
                }
                Button(tr("结束并保存", "Finish and Save")) { timer.finish() }
            }
        } else {
            Button(timer.mode == .countdown
                   ? tr("开始专注（\(timer.countdownMinutes) 分钟倒计时）", "Start Focus (\(timer.countdownMinutes)-min countdown)")
                   : tr("开始专注（正计时）", "Start Focus (stopwatch)")) {
                timer.start()
            }
        }
        Divider()
        Button(tr("打开 FocusLock", "Open FocusLock")) {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button(tr("退出", "Quit")) { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
