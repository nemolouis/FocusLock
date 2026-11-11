import AppKit
import Combine

/// 番茄钟：倒计时 / 正计时，支持开始、暂停、继续、结束、放弃。
/// 时间基于时间戳计算，不会因为 Timer 抖动而漂移。
@MainActor
final class FocusTimer: ObservableObject {
    enum State { case idle, running, paused }

    struct Message: Equatable {
        let text: String
        let date: Date
    }

    @Published private(set) var state: State = .idle
    @Published var mode: TimerMode
    @Published var countdownMinutes: Int
    @Published var categoryId: UUID?
    @Published var note = ""
    @Published private(set) var now = Date()
    @Published private(set) var message: Message?

    private(set) var targetSeconds: Double = 25 * 60
    private var accumulated: Double = 0
    private var segmentStart: Date?
    private var startedAt: Date?
    private var ticker: Timer?
    private var bag: Set<AnyCancellable> = []

    private let store: Store
    private let blocker: AppBlocker

    init(store: Store, blocker: AppBlocker) {
        self.store = store
        self.blocker = blocker
        mode = store.settings.lastMode
        countdownMinutes = store.settings.countdownMinutes
        categoryId = store.category(store.settings.lastCategoryId)?.id ?? store.categories.first?.id

        // 设置变化后重新计算锁定状态
        store.$settings
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.updateLock() } }
            .store(in: &bag)

        // 合盖 / 睡眠时自动暂停，避免把睡眠时间算进专注
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.state == .running else { return }
                    self.pause(force: true)
                    self.show("电脑进入睡眠，已自动暂停")
                }
            }
            .store(in: &bag)
    }

    // MARK: - 计算属性

    var isActive: Bool { state != .idle }

    var elapsed: Double {
        let running = segmentStart.map { max(0, now.timeIntervalSince($0)) } ?? 0
        return accumulated + running
    }

    var remaining: Double { max(0, targetSeconds - elapsed) }

    /// 表盘上显示的秒数
    var displaySeconds: Double {
        switch (state, mode) {
        case (.idle, .countdown): return Double(countdownMinutes * 60)
        case (.idle, .countup): return 0
        case (_, .countdown): return remaining
        case (_, .countup): return elapsed
        }
    }

    var displayText: String { Fmt.clock(displaySeconds, roundUp: mode == .countdown) }

    /// 0...1。倒计时为已完成比例；正计时每小时转一圈
    var progress: Double {
        guard isActive else { return 0 }
        switch mode {
        case .countdown: return targetSeconds > 0 ? min(1, elapsed / targetSeconds) : 0
        case .countup: return elapsed.truncatingRemainder(dividingBy: 3600) / 3600
        }
    }

    /// 严格模式：倒计时结束前不能暂停 / 结束 / 放弃 / 退出
    var isStrictLocked: Bool {
        store.settings.strictMode && mode == .countdown && isActive
    }

    var menuBarText: String {
        let icon = mode == .countdown ? "🍅" : "⏱"
        return state == .paused ? "\(icon) ⏸ \(displayText)" : "\(icon) \(displayText)"
    }

    // MARK: - 操作

    func start() {
        guard state == .idle else { return }
        let t = Date()
        targetSeconds = Double(max(1, countdownMinutes) * 60)
        accumulated = 0
        startedAt = t
        segmentStart = t
        now = t
        state = .running
        message = nil

        store.settings.lastMode = mode
        store.settings.countdownMinutes = countdownMinutes
        store.settings.lastCategoryId = categoryId

        startTicker()
        updateLock()
    }

    func pause(force: Bool = false) {
        guard state == .running, force || !isStrictLocked, let seg = segmentStart else { return }
        let t = Date()
        accumulated += max(0, t.timeIntervalSince(seg))
        segmentStart = nil
        now = t
        state = .paused
        updateLock()
    }

    func resume() {
        guard state == .paused else { return }
        let t = Date()
        segmentStart = t
        now = t
        state = .running
        updateLock()
    }

    /// 提前结束并保存（不足 1 分钟不记录）
    func finish() {
        guard isActive, !isStrictLocked else { return }
        now = Date()
        let saved = record(completed: false)
        reset()
        show(saved ? "已保存本次专注" : "不足 1 分钟，未记录")
    }

    /// 放弃，不保存
    func abandon() {
        guard isActive, !isStrictLocked else { return }
        reset()
        show("已放弃本次专注")
    }

    /// 退出 App 前调用：无论模式都保存已专注的时间
    func saveOnQuit() {
        guard isActive else { return }
        now = Date()
        record(completed: false)
        reset()
        store.save()
    }

    func updateLock() {
        let shouldLock = store.settings.lockEnabled
            && (state == .running || (state == .paused && store.settings.lockWhilePaused))
        blocker.setActive(shouldLock)
    }

    // MARK: - 内部

    private func startTicker() {
        ticker?.invalidate()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func tick() {
        now = Date()
        if state == .running, mode == .countdown, elapsed >= targetSeconds {
            complete()
        }
    }

    private func complete() {
        let mins = Int(targetSeconds / 60)
        let name = store.categoryName(categoryId)
        record(completed: true)
        reset()
        NSSound(named: "Glass")?.play()
        Notifier.post(title: "番茄完成 🍅", body: "\(name) · 专注了 \(mins) 分钟，休息一下吧")
        show("完成一个番茄！专注了 \(mins) 分钟")
        NSApp.requestUserAttention(.informationalRequest)
    }

    @discardableResult
    private func record(completed: Bool) -> Bool {
        guard let startedAt else { return false }
        let secs = mode == .countdown ? min(elapsed, targetSeconds) : elapsed
        guard completed || secs >= 60 else { return false }
        store.sessions.append(FocusSession(
            categoryId: categoryId,
            mode: mode,
            startedAt: startedAt,
            endedAt: Date(),
            seconds: secs,
            targetSeconds: mode == .countdown ? targetSeconds : nil,
            completed: completed,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
        return true
    }

    private func reset() {
        ticker?.invalidate()
        ticker = nil
        state = .idle
        accumulated = 0
        segmentStart = nil
        startedAt = nil
        note = ""
        now = Date()
        updateLock()
    }

    private func show(_ text: String) {
        message = Message(text: text, date: Date())
    }
}
