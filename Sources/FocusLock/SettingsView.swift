import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?

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

                Card(title: tr("菜单栏与启动", "Menu Bar & Launch")) {
                    Toggle(tr("登录时自动启动", "Open at login"), isOn: Binding(
                        get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                        set: { setLoginItem($0) }
                    ))
                    if loginStatus == .requiresApproval {
                        HStack {
                            Text(tr("还需要在「系统设置 › 通用 › 登录项」里允许 FocusLock。",
                                    "Allow FocusLock in System Settings › General › Login Items."))
                            Button(tr("打开系统设置", "Open System Settings")) {
                                SMAppService.openSystemSettingsLoginItems()
                            }
                            .buttonStyle(.link)
                        }
                        .font(.caption)
                    }
                    if let loginError {
                        Text(loginError).font(.caption).foregroundStyle(.red)
                    }
                    Toggle(tr("启动时打开主窗口", "Open the main window at launch"),
                           isOn: $store.settings.showWindowOnLaunch)
                    Text(tr("所有功能都能在菜单栏的番茄锁图标里使用。关掉主窗口后 FocusLock 会继续在菜单栏运行，程序坞里不显示图标。打开「登录时自动启动」并关闭「启动时打开主窗口」，开机后它就只在菜单栏待命。",
                            "Everything is available from the tomato-lock icon in the menu bar. Closing the main window keeps FocusLock running there without a Dock icon. Turn on “Open at login” and off “Open the main window” to keep it quietly in the menu bar."))
                        .font(.caption).foregroundStyle(.secondary)
                }

                Card(title: tr("菜单栏面板", "Menu Bar Panel")) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(tr("选择点开菜单栏图标后显示哪些设置。隐藏的项目仍按当前设置生效，可以在主窗口里修改。",
                                "Choose which settings appear when you click the menu bar icon. Hidden items keep their current values and can still be changed in the main window."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if store.settings.menuBar != MenuBarOptions() {
                            Button(tr("全部显示", "Show All")) { store.settings.menuBar = MenuBarOptions() }
                                .buttonStyle(.link)
                                .font(.caption)
                        }
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                              alignment: .leading, spacing: 8) {
                        Toggle(tr("计时模式（倒计时 / 正计时）", "Timer mode (countdown / stopwatch)"), isOn: $store.settings.menuBar.showMode)
                        Toggle(tr("倒计时时长", "Countdown length"), isOn: $store.settings.menuBar.showDuration)
                        Toggle(tr("分类", "Category"), isOn: $store.settings.menuBar.showCategory)
                        Toggle(tr("专注时锁定应用", "Block apps"), isOn: $store.settings.menuBar.showBlock)
                        Toggle(tr("严格模式", "Strict mode"), isOn: $store.settings.menuBar.showStrict)
                        Toggle(tr("专注后休息", "Break after focus"), isOn: $store.settings.menuBar.showBreak)
                        Toggle(tr("顶部的今日专注时长", "Today's total at the top"), isOn: $store.settings.menuBar.showToday)
                    }
                    .toggleStyle(.checkbox)
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

    private func setLoginItem(_ on: Bool) {
        loginError = nil
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginError = tr("设置失败：", "Couldn't change it: ") + error.localizedDescription
        }
        loginStatus = SMAppService.mainApp.status
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
            Spacer()
            content()
        }
    }
}
