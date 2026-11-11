import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(tr("设置", "Settings")).font(.largeTitle.weight(.semibold))

                Card(title: tr("通用", "General")) {
                    row(tr("语言", "Language")) {
                        Picker("", selection: $store.settings.language) {
                            ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 280)
                    }
                    row(tr("外观", "Appearance")) {
                        Picker("", selection: $store.settings.appearance) {
                            ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 280)
                    }
                }

                Card(title: tr("休息", "Breaks")) {
                    Toggle(tr("每次专注结束后自动休息", "Start a break after each focus session"),
                           isOn: $store.settings.restEnabled)
                    row(tr("休息时长", "Break length")) {
                        Stepper(value: $store.settings.restMinutes, in: 1...60) {
                            Text(Fmt.minutes(store.settings.restMinutes)).monospacedDigit()
                        }
                        .disabled(!store.settings.restEnabled)
                    }
                    Text(tr("休息不会被记录，也不会锁定应用。休息结束会发通知，然后停下来，不会自动开始下一个专注。",
                            "Breaks aren't recorded and don't lock apps. You'll get a notification when a break ends; the next focus session won't start on its own."))
                        .font(.caption).foregroundStyle(.secondary)
                }

                Card(title: tr("数据", "Data")) {
                    HStack {
                        Text(store.fileURL.path)
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(tr("在访达中显示", "Show in Finder")) {
                            store.save()
                            NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
            Spacer()
            content()
        }
    }
}
