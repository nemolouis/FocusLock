import SwiftUI

/// 统计页底部的专注记录列表，跟随上方选择的时间段；可补记、编辑、删除
struct RecordsSection: View {
    @EnvironmentObject var store: Store
    let sessions: [FocusSession]
    let options: [CategorySlice]
    @Binding var filterKey: String?
    let keyOf: (UUID?) -> String
    /// 补记时默认的日期（看以往某一天时用那一天）
    var defaultDay: Date?

    @State private var limit = 100
    @State private var editing: EditTarget?

    private struct EditTarget: Identifiable {
        let id = UUID()
        let session: FocusSession?
    }

    private struct DayGroup: Identifiable {
        let day: Date
        let items: [FocusSession]
        var id: Date { day }
        var total: Double { items.reduce(0) { $0 + $1.seconds } }
    }

    private var shown: [FocusSession] {
        sessions
            .filter { filterKey == nil || keyOf($0.categoryId) == filterKey }
            .sorted { $0.startedAt > $1.startedAt }
    }

    private func groups(_ items: [FocusSession]) -> [DayGroup] {
        let cal = Calendar.current
        return Dictionary(grouping: items) { cal.startOfDay(for: $0.startedAt) }
            .map { DayGroup(day: $0.key, items: $0.value.sorted { $0.startedAt > $1.startedAt }) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        let all = shown
        let visible = Array(all.prefix(limit))
        Card {
            HStack {
                Text(tr("专注记录", "Sessions")).font(.headline)
                Text(tr("\(all.count) 条", "\(all.count)")).foregroundStyle(.secondary)
                Spacer()
                if !options.isEmpty {
                    Picker(tr("分类", "Category"), selection: $filterKey) {
                        Text(tr("全部分类", "All categories")).tag(String?.none)
                        ForEach(options) { o in
                            Text(o.label).tag(Optional(o.id))
                        }
                    }
                    .fixedSize()
                }
                Button {
                    editing = EditTarget(session: nil)
                } label: {
                    Label(tr("补记", "Add"), systemImage: "plus")
                }
                .help(tr("手动补记一条专注", "Add a session manually"))
            }

            if all.isEmpty {
                Text(sessions.isEmpty ? tr("这段时间没有记录", "No sessions in this period")
                                      : tr("这个分类在这段时间没有记录", "No sessions for this category in this period"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                VStack(spacing: 0) {
                    ForEach(groups(visible)) { g in
                        HStack {
                            Text(Fmt.day(g.day))
                            Spacer()
                            Text(tr("\(g.items.count) 次", "\(g.items.count) sessions") + " · " + Fmt.duration(g.total))
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, 14)
                        .padding(.bottom, 4)

                        ForEach(g.items) { s in
                            Divider()
                            SessionRow(session: s) { editing = EditTarget(session: s) }
                        }
                    }
                }

                if all.count > visible.count {
                    Button(tr("显示更多（还有 \(all.count - visible.count) 条）", "Show more (\(all.count - visible.count) left)")) {
                        limit += 100
                    }
                    .buttonStyle(.link)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                }
            }
        }
        .onChange(of: filterKey) { limit = 100 }
        .sheet(item: $editing) { target in
            RecordEditorSheet(session: target.session,
                              defaultDay: defaultDay,
                              defaultCategory: store.settings.lastCategoryId ?? store.categories.first?.id)
                .environmentObject(store)
                .environment(\.locale, L10n.locale)
        }
    }
}

private struct SessionRow: View {
    @EnvironmentObject var store: Store
    let session: FocusSession
    var onEdit: () -> Void
    @State private var hovering = false
    @State private var confirmDelete = false

    var body: some View {
        HStack(spacing: 12) {
            CategoryDot(hex: store.categoryColorHex(session.categoryId), size: 12)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(store.categoryName(session.categoryId)).font(.headline)
                    if !session.note.isEmpty {
                        Text(session.note).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                HStack(spacing: 6) {
                    Text("\(Fmt.time.string(from: session.startedAt)) – \(Fmt.time.string(from: session.endedAt))")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    ForEach(session.tags, id: \.self) { TagChip(text: $0) }
                }
            }
            Spacer()
            badge
            Text(Fmt.duration(session.seconds))
                .monospacedDigit()
                .frame(minWidth: 80, alignment: .trailing)
            HStack(spacing: 10) {
                Button(action: onEdit) { Image(systemName: "pencil") }
                    .help(tr("编辑这条记录", "Edit this session"))
                Button { confirmDelete = true } label: { Image(systemName: "trash") }
                    .help(tr("删除这条记录", "Delete this session"))
            }
            .buttonStyle(.borderless)
            .opacity(hovering ? 1 : 0)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: onEdit)
        .contextMenu {
            Button(tr("编辑", "Edit"), action: onEdit)
            Button(tr("删除", "Delete"), role: .destructive) { confirmDelete = true }
        }
        .confirmationDialog(tr("删除这条记录？", "Delete this session?"), isPresented: $confirmDelete) {
            Button(tr("删除", "Delete"), role: .destructive) { store.deleteSession(session.id) }
            Button(tr("取消", "Cancel"), role: .cancel) {}
        }
    }

    @ViewBuilder
    private var badge: some View {
        let (text, color): (String, Color) = {
            if session.isManual { return (tr("补记", "Manual"), .purple) }
            if session.mode == .countup { return (tr("正计时", "Stopwatch"), .blue) }
            return session.completed ? (tr("🍅 完成", "🍅 Done"), .green) : (tr("提前结束", "Ended early"), .secondary)
        }()
        Text(text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }
}
