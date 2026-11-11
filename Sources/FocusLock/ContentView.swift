import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case focus, stats, history, categories, blocklist

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus: "专注"
        case .stats: "统计"
        case .history: "记录"
        case .categories: "分类"
        case .blocklist: "锁定应用"
        }
    }

    var icon: String {
        switch self {
        case .focus: "timer"
        case .stats: "chart.pie"
        case .history: "list.bullet.rectangle"
        case .categories: "tag"
        case .blocklist: "lock.shield"
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
                if timer.isActive {
                    SidebarStatus().padding(10)
                }
            }
        } detail: {
            switch page ?? .focus {
            case .focus: TimerView(goToBlocklist: { lastPage = .blocklist })
            case .stats: StatsView()
            case .history: HistoryView()
            case .categories: CategoriesView()
            case .blocklist: BlocklistView()
            }
        }
    }
}

private struct SidebarStatus: View {
    @EnvironmentObject var timer: FocusTimer
    @EnvironmentObject var blocker: AppBlocker

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(timer.state == .paused ? "已暂停" : "专注中")
                .font(.caption).foregroundStyle(.secondary)
            Text(timer.displayText)
                .font(.title2.weight(.semibold)).monospacedDigit()
            if blocker.isActive {
                Label("锁定中", systemImage: "lock.fill")
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
