import SwiftUI

/// 补记 / 编辑一条专注记录：分类、开始结束时间、备注、标签
struct RecordEditorSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    private let original: FocusSession?
    @State private var draft: FocusSession
    @State private var tagInput = ""

    /// session 为 nil 时是补记；defaultDay 指定补记到哪一天（默认就是刚刚过去的 25 分钟）
    init(session: FocusSession?, defaultDay: Date? = nil, defaultCategory: UUID? = nil) {
        original = session
        if let session {
            _draft = State(initialValue: session)
        } else {
            let cal = Calendar.current
            let now = cal.date(bySetting: .second, value: 0, of: Date()) ?? Date()
            let end = defaultDay.flatMap { cal.date(bySettingHour: 9, minute: 25, second: 0, of: $0) } ?? now
            let start = end.addingTimeInterval(-25 * 60)
            _draft = State(initialValue: FocusSession(
                categoryId: defaultCategory, mode: .countup, startedAt: start, endedAt: end,
                seconds: 25 * 60, targetSeconds: nil, completed: false, note: "", tags: [], isManual: true))
        }
    }

    private var isNew: Bool { original == nil }

    private var timesChanged: Bool {
        guard let original else { return true }
        return original.startedAt != draft.startedAt || original.endedAt != draft.endedAt
    }

    /// 改了时间就按开始到结束重新算；没改就保留原来扣除暂停后的时长
    private var seconds: Double {
        timesChanged ? draft.endedAt.timeIntervalSince(draft.startedAt) : (original?.seconds ?? 0)
    }

    private var error: String? {
        let span = draft.endedAt.timeIntervalSince(draft.startedAt)
        if span <= 0 { return tr("结束时间要晚于开始时间", "End time must be after start time") }
        if span > 24 * 3600 { return tr("一条记录不能超过 24 小时", "A session can't be longer than 24 hours") }
        if draft.endedAt > Date().addingTimeInterval(60) { return tr("不能记录未来的时间", "Can't record time in the future") }
        return nil
    }

    private var overlaps: [FocusSession] {
        store.overlapping(start: draft.startedAt, end: draft.endedAt, excluding: draft.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(isNew ? tr("补记一条专注", "Add a Session") : tr("编辑记录", "Edit Session"))
                .font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.horizontal, .top], 20)

            Form {
                Section {
                    Picker(tr("分类", "Category"), selection: $draft.categoryId) {
                        ForEach(store.categories) { c in
                            Text(c.name).tag(Optional(c.id))
                        }
                        if store.category(draft.categoryId) == nil {
                            Text(store.categoryName(draft.categoryId)).tag(draft.categoryId)
                        }
                    }
                    DatePicker(tr("开始", "Start"), selection: $draft.startedAt,
                               displayedComponents: [.date, .hourAndMinute])
                    DatePicker(tr("结束", "End"), selection: $draft.endedAt,
                               displayedComponents: [.date, .hourAndMinute])
                    LabeledContent(tr("专注时长", "Duration")) {
                        Text(error == nil ? Fmt.duration(seconds) : "—").monospacedDigit()
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if let error {
                            Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                        } else if !overlaps.isEmpty {
                            Label(tr("和 \(overlaps.count) 条记录时间重叠", "Overlaps \(overlaps.count) other session(s)"),
                                  systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        }
                        if let original, timesChanged,
                           original.endedAt.timeIntervalSince(original.startedAt) - original.seconds >= 60 {
                            Text(tr("原记录扣除了暂停时间；改时间后会按开始到结束重新计算时长。",
                                    "The original excluded paused time; changing the times recalculates it from start to end."))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                }

                Section(tr("备注", "Note")) {
                    TextField(tr("备注", "Note"), text: $draft.note, prompt: Text(tr("在做什么？", "What did you work on?")))
                        .labelsHidden()
                }

                Section(tr("标签", "Tags")) {
                    if !draft.tags.isEmpty {
                        FlowLayout(spacing: 6, centered: false) {
                            ForEach(draft.tags, id: \.self) { t in
                                TagChip(text: t) { draft.tags.removeAll { $0 == t } }
                            }
                        }
                    }
                    TextField(tr("标签", "Tags"), text: $tagInput,
                              prompt: Text(tr("输入标签后按回车，多个用逗号隔开", "Type a tag and press Return; separate with commas")))
                        .labelsHidden()
                        .onSubmit(addTags)
                    let suggestions = store.allTags.filter { !draft.tags.contains($0) }.prefix(12)
                    if !suggestions.isEmpty {
                        FlowLayout(spacing: 6, centered: false) {
                            ForEach(Array(suggestions), id: \.self) { t in
                                Button("+ " + t) { draft.tags.append(t) }
                                    .buttonStyle(ChipStyle(selected: false, color: .secondary))
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button(tr("取消", "Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? tr("添加", "Add") : tr("保存", "Save")) { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(error != nil)
            }
            .padding(20)
        }
        .frame(width: 500, height: 600)
    }

    private func addTags() {
        let parts = tagInput.split { $0 == "," || $0 == "，" || $0 == "、" }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for p in parts where !draft.tags.contains(p) { draft.tags.append(p) }
        tagInput = ""
    }

    private func save() {
        addTags()
        var s = draft
        s.seconds = seconds
        s.note = s.note.trimmingCharacters(in: .whitespacesAndNewlines)
        store.upsertSession(s)
        dismiss()
    }
}

struct TagChip: View {
    var text: String
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Text("#" + text)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark").font(.caption2.weight(.bold))
                }
                .buttonStyle(.plain)
            }
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.accentColor.opacity(0.12), in: Capsule())
        .foregroundStyle(Color.accentColor)
    }
}
