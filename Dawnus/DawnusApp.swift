import SwiftUI

@main
struct DawnusApp: App {
    @State private var store = AlarmStore()
    @State private var engine = AlarmEngine()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(engine)
                .preferredColorScheme(.dark)
                .task {
                    // 演示模式（-dawnus-demo）下不打扰权限，方便截图与讲方案
                    if DawnusDemoMode.current == nil {
                        await engine.requestAuthorization()
                    }
                    await engine.syncAll(store.alarms)
                    handlePendingIntent()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    // 被系统闹钟的按钮拉回前台时，接管后续流程
                    if newPhase == .active {
                        handlePendingIntent()
                        Task { await engine.syncAll(store.alarms) }
                    }
                }
                .onOpenURL { _ in handlePendingIntent() }
        }
    }

    /// 读 App Intent 留下的「哪个闹钟响了 / 点了什么按钮」，决定是继续响还是直接进仪式链。
    private func handlePendingIntent() {
        guard let pending = WakeIntentBridge.shared.consume(),
              let alarm = store.alarm(for: pending.alarmID)
        else { return }

        switch pending.action {
        case .stop:
            // 在系统闹钟 UI 上点了「起床」：直接把人送进晨间仪式链
            store.session = WakeSession(alarmID: alarm.id, snoozeCount: alarm.snoozeCount)
            NotificationCenter.default.post(name: .dawnusDidUnlock, object: nil)
        case .snooze:
            store.session = WakeSession(alarmID: alarm.id, strike: 2, snoozeCount: alarm.snoozeCount + 1)
        case .open:
            store.session = WakeSession(alarmID: alarm.id, snoozeCount: alarm.snoozeCount)
        }
    }
}
