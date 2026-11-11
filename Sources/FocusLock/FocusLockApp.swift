import SwiftUI
import UserNotifications

@MainActor
final class AppModel {
    static let shared = AppModel()

    let store: Store
    let blocker: AppBlocker
    let timer: FocusTimer

    private init() {
        store = Store()
        blocker = AppBlocker()
        timer = FocusTimer(store: store, blocker: blocker)
        blocker.blockedIds = { [unowned store] in Set(store.blockedApps.map(\.bundleId)) }
        blocker.statusText = { [unowned timer] in
            timer.mode == .countdown
                ? "专注中，还剩 \(Fmt.clock(timer.remaining, roundUp: true))"
                : "专注中，已专注 \(Fmt.clock(timer.elapsed, roundUp: false))"
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if Notifier.available {
            UNUserNotificationCenter.current().delegate = self
        }
        Notifier.requestAuthorization()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let timer = AppModel.shared.timer
        guard timer.isActive else { return .terminateNow }

        if timer.isStrictLocked {
            let alert = NSAlert()
            alert.messageText = "严格模式进行中"
            alert.informativeText = "倒计时结束前不能退出 FocusLock。还剩 \(Fmt.clock(timer.remaining, roundUp: true))。"
            alert.addButton(withTitle: "继续专注")
            alert.runModal()
            return .terminateCancel
        }

        let alert = NSAlert()
        alert.messageText = "正在专注，确定退出吗？"
        alert.informativeText = "退出后计时停止、App 锁定解除。已专注满 1 分钟的时间会被保存。"
        alert.addButton(withTitle: "继续专注")
        alert.addButton(withTitle: "保存并退出")
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
        Window("FocusLock", id: "main") {
            ContentView()
                .environmentObject(store)
                .environmentObject(timer)
                .environmentObject(blocker)
                .frame(minWidth: 860, minHeight: 620)
        }
        .defaultSize(width: 1000, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(store)
                .environmentObject(timer)
                .environmentObject(blocker)
        } label: {
            if timer.isActive {
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
        if timer.isActive {
            Text("\(store.categoryName(timer.categoryId)) · \(timer.mode.title) \(timer.displayText)")
            if blocker.isActive { Text("🔒 正在锁定 \(store.blockedApps.count) 个应用") }
            Divider()
            if timer.isStrictLocked {
                Text("严格模式：结束前无法停止")
            } else {
                if timer.state == .running {
                    Button("暂停") { timer.pause() }
                } else {
                    Button("继续") { timer.resume() }
                }
                Button("结束并保存") { timer.finish() }
            }
        } else {
            Button("开始专注（\(timer.mode == .countdown ? "\(timer.countdownMinutes) 分钟倒计时" : "正计时")）") {
                timer.start()
            }
        }
        Divider()
        Button("打开 FocusLock") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("退出") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
