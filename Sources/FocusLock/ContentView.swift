import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case focus, stats, blocklist, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus: tr("专注", "Focus")
        case .stats: tr("统计", "Stats")
        case .blocklist: tr("锁定应用", "Blocked Apps")
        case .settings: tr("设置", "Settings")
        }
    }

    var icon: String {
        switch self {
        case .focus: "timer"
        case .stats: "chart.pie"
        case .blocklist: "lock.shield"
        case .settings: "gearshape"
        }
    }
}

struct ContentView: View {
    // 这里不观察计时器：计时每秒更新，只让左下角的小状态框跟着刷新，避免整个窗口重算
    /// 记住上次打开的页面
    @AppStorage("lastPage") private var lastPage: Page = .focus
    /// 主窗口是否在屏幕上。SwiftUI 即使不显示主窗口也会在后台建好它，
    /// 所以窗口不可见（没打开 / 已关闭）时不渲染内容，释放整套界面占用的内存
    @State private var windowVisible = false

    private var page: Page? { lastPage }

    var body: some View {
        Group {
            if windowVisible {
                mainContent
            } else {
                Color.clear
            }
        }
        .background(WindowVisibilityReader(isVisible: $windowVisible))
    }

    private var mainContent: some View {
        NavigationSplitView {
            List(selection: Binding(get: { lastPage }, set: { if let p = $0 { lastPage = p } })) {
                ForEach(Page.allCases) { p in
                    Label(p.title, systemImage: p.icon).tag(p)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
            .safeAreaInset(edge: .bottom) {
                SidebarStatus()
            }
        } detail: {
            switch page ?? .focus {
            case .focus: TimerView(goToBlocklist: { lastPage = .blocklist })
            case .stats: StatsView()
            case .blocklist: BlocklistView()
            case .settings: SettingsView()
            }
        }
    }
}

/// 监听所在窗口是否显示在屏幕上。
/// 变成「显示」要求窗口真的出现在屏幕上（启动时在后台建好但没显示的窗口不算）；
/// 变成「不显示」要求窗口被关闭、隐藏或最小化（只是被别的窗口挡住不算，免得反复重建界面）
private struct WindowVisibilityReader: NSViewRepresentable {
    @Binding var isVisible: Bool

    func makeNSView(context: Context) -> VisibilityView {
        let v = VisibilityView()
        v.onChange = { visible in if isVisible != visible { isVisible = visible } }
        return v
    }

    func updateNSView(_ v: VisibilityView, context: Context) {
        v.onChange = { visible in if isVisible != visible { isVisible = visible } }
    }

    final class VisibilityView: NSView {
        var onChange: ((Bool) -> Void)?
        private var tokens: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            tokens.forEach { NotificationCenter.default.removeObserver($0) }
            tokens = []
            guard let w = window else { report(false); return }
            let names: [Notification.Name] = [
                NSWindow.didChangeOcclusionStateNotification, NSWindow.didBecomeKeyNotification,
                NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
                NSWindow.willCloseNotification,
            ]
            for name in names {
                tokens.append(NotificationCenter.default.addObserver(forName: name, object: w, queue: .main) { [weak self] note in
                    let closing = note.name == NSWindow.willCloseNotification
                    MainActor.assumeIsolated {
                        self?.evaluate(closing: closing)
                        if !closing { self?.scheduleRechecks() }
                    }
                })
            }
            evaluate(closing: false)
            scheduleRechecks()
        }

        private var lastReported: Bool?
        private var rechecks: [DispatchWorkItem] = []

        private func evaluate(closing: Bool) {
            guard let w = window, !closing, w.isVisible, !w.isMiniaturized else {
                if lastReported != false { lastReported = false; report(false) }
                return
            }
            // 真的显示在屏幕上（或成了当前窗口）才开始渲染；已经在渲染时被挡住就保持不变
            if (w.occlusionState.contains(.visible) || w.isKeyWindow || Self.isOnScreen(w)), lastReported != true {
                lastReported = true
                report(true)
            }
        }

        /// 直接问窗口服务器这个窗口是否在屏幕上（启动时在后台建好的隐藏窗口这里是 false）
        private static func isOnScreen(_ w: NSWindow) -> Bool {
            guard w.windowNumber > 0,
                  let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(w.windowNumber)) as? [[String: Any]],
                  let first = info.first
            else { return false }
            return (first[kCGWindowIsOnscreen as String] as? Bool) ?? false
        }

        /// 窗口刚出现时系统不一定发「可见性变化」通知（比如不抢焦点地显示），之后 3 秒内再查几次
        private func scheduleRechecks() {
            rechecks.forEach { $0.cancel() }
            rechecks = [0.15, 0.4, 0.8, 1.5, 3.0].map { delay in
                let item = DispatchWorkItem { [weak self] in
                    MainActor.assumeIsolated { self?.evaluate(closing: false) }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
                return item
            }
        }

        /// 异步回报，避免在 SwiftUI 更新视图的过程中改状态
        private func report(_ visible: Bool) {
            DispatchQueue.main.async { [weak self] in self?.onChange?(visible) }
        }

        deinit {
            rechecks.forEach { $0.cancel() }
            tokens.forEach { NotificationCenter.default.removeObserver($0) }
        }
    }
}

private struct SidebarStatus: View {
    @EnvironmentObject var timer: FocusTimer
    @EnvironmentObject var blocker: AppBlocker

    var body: some View {
        if timer.isActive || timer.isResting {
            VStack(alignment: .leading, spacing: 4) {
                Text(timer.isResting ? tr("休息中", "On a break")
                     : timer.state == .paused ? tr("已暂停", "Paused") : tr("专注中", "Focusing"))
                    .font(.caption).foregroundStyle(.secondary)
                Text(timer.displayText)
                    .font(.title2.weight(.semibold)).monospacedDigit()
                if blocker.isActive {
                    Label(tr("锁定中", "Locking"), systemImage: "lock.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
            .padding(10)
        }
    }
}

/// 卡片容器
struct Card<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title).font(.headline)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator.opacity(0.5)))
    }
}

struct CategoryDot: View {
    var hex: String
    var size: CGFloat = 10
    var body: some View {
        Circle().fill(Color(hex: hex)).frame(width: size, height: size)
    }
}
