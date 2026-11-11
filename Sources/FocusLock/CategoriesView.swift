import SwiftUI

struct CategoriesView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var timer: FocusTimer
    @State private var pendingDelete: FocusCategory?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("分类").font(.largeTitle.weight(.semibold))
                Spacer()
                Button {
                    store.addCategory()
                } label: {
                    Label("添加分类", systemImage: "plus")
                }
            }
            .padding([.horizontal, .top], 24)
            .padding(.bottom, 12)

            List {
                ForEach($store.categories) { $cat in
                    CategoryRow(category: $cat,
                                canDelete: store.categories.count > 1 && !(timer.isActive && timer.categoryId == cat.id),
                                onDelete: { pendingDelete = cat })
                }
                .onMove { store.categories.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.inset)

            Text("拖动可以调整顺序。删除分类不会删除它的专注记录，统计里会显示为「已删除分类」。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(16)
        }
        .confirmationDialog("删除分类「\(pendingDelete?.name ?? "")」？",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("删除", role: .destructive) {
                if let c = pendingDelete {
                    store.deleteCategory(c.id)
                    if timer.categoryId == c.id { timer.categoryId = store.categories.first?.id }
                }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
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

            TextField("分类名称", text: $category.name)
                .textFieldStyle(.plain)
                .font(.title3)

            Spacer()

            Text("\(items.count) 次 · \(Fmt.duration(total))")
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(!canDelete)
            .help(canDelete ? "删除分类" : "至少保留一个分类，且不能删除正在专注的分类")
        }
        .padding(.vertical, 6)
    }
}
