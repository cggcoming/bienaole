import SwiftUI

enum DawnusTab: Hashable {
    case alarms, stats, engine
}

/// 演示 / 截图开关：启动时加 `-dawnus-demo ring` 之类的参数，直接落到某个界面。
/// 例：xcrun simctl launch booted com.dawnus.app -dawnus-demo ring
enum DawnusDemoMode: String {
    case ring, ritual, stats

    static var current: DawnusDemoMode? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-dawnus-demo"), i + 1 < args.count else { return nil }
        return DawnusDemoMode(rawValue: args[i + 1])
    }
}

struct RootView: View {
    @Environment(AlarmStore.self) private var store
    @Environment(AlarmEngine.self) private var engine

    @State private var tab: DawnusTab = .alarms
    @State private var showRitual = false
    @State private var demoHandled = false

    var body: some View {
        @Bindable var store = store

        TabView(selection: $tab) {
            AlarmListView()
                .tabItem { Label("闹钟", systemImage: "alarm") }
                .tag(DawnusTab.alarms)
            StatsView()
                .tabItem { Label("数据", systemImage: "chart.bar.fill") }
                .tag(DawnusTab.stats)
            EngineView()
                .tabItem { Label("引擎", systemImage: "gearshape.2.fill") }
                .tag(DawnusTab.engine)
        }
        .tint(.dawnAmber)
        .background {
            LinearGradient(
                colors: [Color.midnight, Color.midnightTwo],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        // 响铃：系统闹钟把 App 拉起，或用户在列表里点了「试一下」
        .fullScreenCover(isPresented: Binding(
            get: { store.session != nil && !showRitual },
            set: { presented in
                if !presented && !showRitual { store.session = nil }
            }
        )) {
            RingingView(session: $store.session)
        }
        // 仪式链：解锁之后的那三分钟
        .fullScreenCover(isPresented: $showRitual) {
            RitualView(session: $store.session) { showRitual = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dawnusDidUnlock)) { _ in
            showRitual = true
        }
        .task { handleDemoMode() }
    }

    private func handleDemoMode() {
        guard !demoHandled, let mode = DawnusDemoMode.current, let alarm = store.alarms.first else { return }
        demoHandled = true
        switch mode {
        case .stats:
            tab = .stats
        case .ring:
            store.session = WakeSession(alarmID: alarm.id)
        case .ritual:
            store.session = WakeSession(alarmID: alarm.id)
            showRitual = true
        }
    }
}
