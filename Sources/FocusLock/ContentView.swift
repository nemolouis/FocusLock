import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case focus, stats, blocklist, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus: tr("专注", "Focus")
        case .stats: tr("统计", "Stats")
        case .blocklist: tr("锁定应用", "Blocked Apps")
        case .settings: tr("设置", "Settings")
        }
    }

    var icon: String {
        switch self {
        case .focus: "timer"
        case .stats: "chart.pie"
        case .blocklist: "lock.shield"
        case .settings: "gearshape"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var timer: FocusTimer
    @EnvironmentObject var blocker: AppBlocker
    /// 记住上次打开的页面
    @AppStorage("lastPage") private var lastPage: Page = .focus

    private var page: Page? { lastPage }

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { lastPage }, set: { if let p = $0 { lastPage = p } })) {
                ForEach(Page.allCases) { p in
                    Label(p.title, systemImage: p.icon).tag(p)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
            .safeAreaInset(edge: .bottom) {
                if timer.isActive || timer.isResting {
                    SidebarStatus().padding(10)
                }
            }
        } detail: {
            switch page ?? .focus {
            case .focus: TimerView(goToBlocklist: { lastPage = .blocklist })
            case .stats: StatsView()
            case .blocklist: BlocklistView()
            case .settings: SettingsView()
            }
        }
    }
}

private struct SidebarStatus: View {
    @EnvironmentObject var timer: FocusTimer
    @EnvironmentObject var blocker: AppBlocker

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(timer.isResting ? tr("休息中", "On a break")
                 : timer.state == .paused ? tr("已暂停", "Paused") : tr("专注中", "Focusing"))
                .font(.caption).foregroundStyle(.secondary)
            Text(timer.displayText)
                .font(.title2.weight(.semibold)).monospacedDigit()
            if blocker.isActive {
                Label(tr("锁定中", "Locking"), systemImage: "lock.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// 卡片容器
struct Card<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title).font(.headline)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator.opacity(0.5)))
    }
}

struct CategoryDot: View {
    var hex: String
    var size: CGFloat = 10
    var body: some View {
        Circle().fill(Color(hex: hex)).frame(width: size, height: size)
    }
}
