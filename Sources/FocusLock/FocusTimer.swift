import AppKit
import Combine

/// 番茄钟：倒计时 / 正计时，支持开始、暂停、继续、结束、放弃；专注结束后自动休息。
/// 时间基于时间戳计算，不会因为 Timer 抖动而漂移。
@MainActor
final class FocusTimer: ObservableObject {
    enum State { case idle, running, paused, resting }

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
    private var restStart: Date?
    private(set) var restSeconds: Double = 5 * 60
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
                    self.show(tr("电脑进入睡眠，已自动暂停", "Paused because the Mac went to sleep"))
                }
            }
            .store(in: &bag)
    }

    // MARK: - 计算属性

    /// 正在专注（含暂停），不包括休息
    var isActive: Bool { state == .running || state == .paused }
    var isResting: Bool { state == .resting }

    var elapsed: Double {
        let running = segmentStart.map { max(0, now.timeIntervalSince($0)) } ?? 0
        return accumulated + running
    }

    var remaining: Double { max(0, targetSeconds - elapsed) }

    var restRemaining: Double {
        guard let restStart else { return 0 }
        return max(0, restSeconds - now.timeIntervalSince(restStart))
    }

    /// 表盘上显示的秒数
    var displaySeconds: Double {
        switch (state, mode) {
        case (.resting, _): return restRemaining
        case (.idle, .countdown): return Double(countdownMinutes * 60)
        case (.idle, .countup): return 0
        case (_, .countdown): return remaining
        case (_, .countup): return elapsed
        }
    }

    var displayText: String {
        Fmt.clock(displaySeconds, roundUp: isResting || mode == .countdown)
    }

    /// 0...1。倒计时 / 休息为已完成比例；正计时每小时转一圈
    var progress: Double {
        if isResting { return restSeconds > 0 ? min(1, 1 - restRemaining / restSeconds) : 0 }
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
        if isResting { return "☕ \(displayText)" }
        let icon = mode == .countdown ? "🍅" : "⏱"
        return state == .paused ? "\(icon) ⏸ \(displayText)" : "\(icon) \(displayText)"
    }

    // MARK: - 专注

    func start() {
        guard state == .idle || state == .resting else { return }
        if isResting { stopRest(notify: false) }
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

    /// 提前结束并保存（不足 1 分钟不记录），保存了就进入休息
    func finish() {
        guard isActive, !isStrictLocked else { return }
        now = Date()
        let saved = record(completed: false)
        reset()
        if saved {
            show(tr("已保存本次专注", "Session saved"))
            startRest()
        } else {
            show(tr("不足 1 分钟，未记录", "Under 1 minute, not saved"))
        }
    }

    /// 放弃，不保存，也不休息
    func abandon() {
        guard isActive, !isStrictLocked else { return }
        reset()
        show(tr("已放弃本次专注", "Session discarded"))
    }

    /// 退出 App 前调用：无论模式都保存已专注的时间
    func saveOnQuit() {
        guard isActive else { return }
        now = Date()
        record(completed: false)
        reset()
        store.save()
    }

    // MARK: - 休息（不记录、不锁定、结束后停下）

    func startRest() {
        guard store.settings.restEnabled, store.settings.restMinutes > 0 else { return }
        restSeconds = Double(store.settings.restMinutes * 60)
        restStart = Date()
        now = restStart!
        state = .resting
        startTicker()
        updateLock()
    }

    func skipRest() {
        guard isResting else { return }
        stopRest(notify: false)
        show(tr("已跳过休息", "Break skipped"))
    }

    private func stopRest(notify: Bool) {
        ticker?.invalidate()
        ticker = nil
        restStart = nil
        state = .idle
        now = Date()
        updateLock()
        if notify {
            NSSound(named: "Glass")?.play()
            Notifier.post(title: tr("休息结束 ☕", "Break is over ☕"),
                          body: tr("准备好了就开始下一个专注吧", "Start your next focus session when you're ready"))
            show(tr("休息结束", "Break is over"))
            NSApp.requestUserAttention(.informationalRequest)
        }
    }

    // MARK: - 锁定

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
        } else if state == .resting, restRemaining <= 0 {
            stopRest(notify: true)
        }
    }

    private func complete() {
        let mins = Int(targetSeconds / 60)
        let name = store.categoryName(categoryId)
        record(completed: true)
        reset()
        NSSound(named: "Glass")?.play()
        let rest = store.settings.restEnabled && store.settings.restMinutes > 0
        let restText = rest
            ? tr("，休息 \(store.settings.restMinutes) 分钟吧", ". Take a \(store.settings.restMinutes)-minute break")
            : ""
        Notifier.post(title: tr("番茄完成 🍅", "Pomodoro done 🍅"),
                      body: tr("\(name) · 专注了 \(mins) 分钟", "\(name) · \(mins) min focused") + restText)
        show(tr("完成一个番茄！专注了 \(mins) 分钟", "Pomodoro done! \(mins) min focused"))
        NSApp.requestUserAttention(.informationalRequest)
        startRest()
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
