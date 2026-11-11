import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var store: Store
    @State private var filterId: UUID?

    private struct DayGroup: Identifiable {
        let day: Date
        let items: [FocusSession]
        var id: Date { day }
        var total: Double { items.reduce(0) { $0 + $1.seconds } }
    }

    private var groups: [DayGroup] {
        let cal = Calendar.current
        let items = store.sessions
            .filter { filterId == nil || $0.categoryId == filterId }
            .sorted { $0.startedAt > $1.startedAt }
        let grouped = Dictionary(grouping: items) { cal.startOfDay(for: $0.startedAt) }
        return grouped.map { DayGroup(day: $0.key, items: $0.value) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("专注记录").font(.largeTitle.weight(.semibold))
                Spacer()
                Picker("分类", selection: $filterId) {
                    Text("全部分类").tag(UUID?.none)
                    ForEach(store.categories) { c in
                        Text(c.name).tag(Optional(c.id))
                    }
                }
                .frame(width: 180)
            }
            .padding([.horizontal, .top], 24)
            .padding(.bottom, 12)

            if groups.isEmpty {
                ContentUnavailableView("还没有记录", systemImage: "list.bullet.rectangle",
                                       description: Text("专注满 1 分钟后结束，或完成一个番茄，就会出现在这里。"))
                    .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(groups) { g in
                        Section {
                            ForEach(g.items) { s in
                                SessionRow(session: s)
                            }
                        } header: {
                            HStack {
                                Text(Fmt.day.string(from: g.day))
                                Spacer()
                                Text("\(g.items.count) 次 · \(Fmt.duration(g.total))")
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

private struct SessionRow: View {
    @EnvironmentObject var store: Store
    let session: FocusSession
    @State private var hovering = false
    @State private var confirmDelete = false

    var body: some View {
        HStack(spacing: 12) {
            CategoryDot(hex: store.categoryColorHex(session.categoryId), size: 12)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(store.categoryName(session.categoryId)).font(.headline)
                    if !session.note.isEmpty {
                        Text(session.note).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Text("\(Fmt.time.string(from: session.startedAt)) – \(Fmt.time.string(from: session.endedAt))")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            badge
            Text(Fmt.duration(session.seconds))
                .monospacedDigit()
                .frame(minWidth: 80, alignment: .trailing)
            Button {
                confirmDelete = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .opacity(hovering ? 1 : 0)
            .help("删除这条记录")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button("删除", role: .destructive) { confirmDelete = true }
        }
        .confirmationDialog("删除这条记录？", isPresented: $confirmDelete) {
            Button("删除", role: .destructive) { store.deleteSession(session.id) }
            Button("取消", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var badge: some View {
        let (text, color): (String, Color) = {
            if session.mode == .countup { return ("正计时", .blue) }
            return session.completed ? ("🍅 完成", .green) : ("提前结束", .secondary)
        }()
        Text(text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }
}
