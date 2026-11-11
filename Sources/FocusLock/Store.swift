import Combine
import Foundation

/// 所有数据存在 ~/Library/Application Support/FocusLock/data.json
@MainActor
final class Store: ObservableObject {
    @Published var categories: [FocusCategory] = []
    @Published var sessions: [FocusSession] = []
    @Published var blockedApps: [BlockedApp] = []
    @Published var settings = AppSettings()

    let fileURL: URL
    private var autosave: AnyCancellable?
    private var languageSync: AnyCancellable?

    init() {
        // FOCUSLOCK_DATA_DIR 可覆盖数据目录（测试用）
        let dir = ProcessInfo.processInfo.environment["FOCUSLOCK_DATA_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("FocusLock", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("data.json")
        load()
        L10n.isEnglish = settings.language.isEnglish
        // 语言设置变化时立即同步（sink 收到的是新值，界面重绘前就已更新）
        languageSync = $settings.sink { L10n.isEnglish = $0.language.isEnglish }
        autosave = objectWillChange
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.save() }
            }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            categories = Self.defaultCategories()
            return
        }
        do {
            let d = try JSONDecoder().decode(PersistedData.self, from: data)
            categories = d.categories.isEmpty ? Self.defaultCategories() : d.categories
            sessions = d.sessions
            blockedApps = d.blockedApps
            settings = d.settings
        } catch {
            // 文件损坏时先备份，绝不直接覆盖用户数据
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = fileURL.deletingLastPathComponent().appendingPathComponent("data.corrupt-\(stamp).json")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            categories = Self.defaultCategories()
        }
    }

    func save() {
        let d = PersistedData(categories: categories, sessions: sessions, blockedApps: blockedApps, settings: settings)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(d) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// 首次启动时的默认分类，按系统语言起名
    static func defaultCategories() -> [FocusCategory] {
        let en = AppLanguage.system.isEnglish
        return [
            FocusCategory(name: en ? "Study" : "学习", colorHex: "#3E63DD"),
            FocusCategory(name: en ? "Work" : "工作", colorHex: "#F76B15"),
            FocusCategory(name: en ? "Reading" : "阅读", colorHex: "#30A46C"),
            FocusCategory(name: en ? "Exercise" : "运动", colorHex: "#E5484D"),
        ]
    }

    // MARK: - 查询

    func category(_ id: UUID?) -> FocusCategory? {
        guard let id else { return nil }
        return categories.first { $0.id == id }
    }

    func categoryName(_ id: UUID?) -> String {
        if id == nil { return tr("未分类", "Uncategorized") }
        return category(id)?.name ?? tr("已删除分类", "Deleted category")
    }

    func categoryColorHex(_ id: UUID?) -> String {
        category(id)?.colorHex ?? "#8B8D98"
    }

    func sessions(since start: Date) -> [FocusSession] {
        sessions.filter { $0.startedAt >= start }
    }

    /// 用过的所有标签，按使用次数排序
    var allTags: [String] {
        var count: [String: Int] = [:]
        for s in sessions { for t in s.tags { count[t, default: 0] += 1 } }
        return count.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
    }

    /// 和给定时间段重叠的其他记录
    func overlapping(start: Date, end: Date, excluding id: UUID?) -> [FocusSession] {
        sessions.filter { $0.id != id && $0.startedAt < end && start < $0.endedAt }
    }

    // MARK: - 修改

    func addCategory() {
        let used = Set(categories.map(\.colorHex))
        let color = Palette.colors.first { !used.contains($0) } ?? Palette.colors[categories.count % Palette.colors.count]
        categories.append(FocusCategory(name: tr("新分类", "New category"), colorHex: color))
    }

    func deleteCategory(_ id: UUID) {
        guard categories.count > 1 else { return }
        categories.removeAll { $0.id == id }
        if settings.lastCategoryId == id { settings.lastCategoryId = categories.first?.id }
    }

    func deleteSession(_ id: UUID) {
        sessions.removeAll { $0.id == id }
    }

    /// 新增或更新一条记录（补记 / 编辑）
    func upsertSession(_ s: FocusSession) {
        if let i = sessions.firstIndex(where: { $0.id == s.id }) {
            sessions[i] = s
        } else {
            sessions.append(s)
        }
    }

    @discardableResult
    func addBlockedApp(at url: URL) -> Bool {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return false }
        guard id != Bundle.main.bundleIdentifier, !AppBlocker.protectedIds.contains(id) else { return false }
        guard !blockedApps.contains(where: { $0.bundleId == id }) else { return true }
        var name = FileManager.default.displayName(atPath: url.path)
        if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
        blockedApps.append(BlockedApp(bundleId: id, name: name, path: url.path))
        blockedApps.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        return true
    }

    func removeBlockedApp(_ id: String) {
        blockedApps.removeAll { $0.bundleId == id }
    }
}
