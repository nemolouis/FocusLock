import SwiftUI

/// 在「专注」页点「管理分类」弹出的分类管理面板
struct CategoryManagerSheet: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var timer: FocusTimer
    @Environment(\.dismiss) private var dismiss
    @State private var pendingDelete: FocusCategory?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(tr("管理分类", "Manage Categories")).font(.title2.weight(.semibold))
                Spacer()
                Button {
                    store.addCategory()
                } label: {
                    Label(tr("添加分类", "Add Category"), systemImage: "plus")
                }
                Button(tr("完成", "Done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)

            List {
                ForEach($store.categories) { $cat in
                    CategoryRow(category: $cat,
                                canDelete: store.categories.count > 1 && !(timer.isActive && timer.categoryId == cat.id),
                                onDelete: { pendingDelete = cat })
                }
                .onMove { store.categories.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.inset)

            Text(tr("点颜色块改颜色，点名字直接改名，拖动调整顺序。删除分类不会删除它的专注记录，统计里会显示为「已删除分类」。",
                     "Click the color to change it, click the name to rename, drag to reorder. Deleting a category keeps its sessions; they show as “Deleted category” in stats."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .frame(width: 560, height: 460)
        .confirmationDialog(tr("删除分类「\(pendingDelete?.name ?? "")」？", "Delete “\(pendingDelete?.name ?? "")”?"),
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button(tr("删除", "Delete"), role: .destructive) {
                if let c = pendingDelete {
                    store.deleteCategory(c.id)
                    if timer.categoryId == c.id { timer.categoryId = store.categories.first?.id }
                }
                pendingDelete = nil
            }
            Button(tr("取消", "Cancel"), role: .cancel) { pendingDelete = nil }
        }
    }
}

private struct CategoryRow: View {
    @EnvironmentObject var store: Store
    @Binding var category: FocusCategory
    var canDelete: Bool
    var onDelete: () -> Void

    var body: some View {
        let items = store.sessions.filter { $0.categoryId == category.id }
        let total = items.reduce(0) { $0 + $1.seconds }
        HStack(spacing: 12) {
            ColorPicker("", selection: Binding(
                get: { category.color },
                set: { category.colorHex = $0.hexString }
            ), supportsOpacity: false)
            .labelsHidden()
            .frame(width: 44)

            TextField(tr("分类名称", "Category name"), text: $category.name)
                .textFieldStyle(.plain)
                .font(.title3)

            Spacer()

            Text(tr("\(items.count) 次", "\(items.count) sessions") + " · " + Fmt.duration(total))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(!canDelete)
            .help(canDelete ? tr("删除分类", "Delete category")
                  : tr("至少保留一个分类，且不能删除正在专注的分类", "Keep at least one category; the one in use can't be deleted"))
        }
        .padding(.vertical, 6)
    }
}
