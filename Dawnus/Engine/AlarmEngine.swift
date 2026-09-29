// AlarmManager 及其异步序列在 iOS 26 SDK 里还没做好 Sendable 标注，
// 用 @preconcurrency 引入，让编译器把这些 API 当作旧 module 处理，避免误报数据竞争。
@preconcurrency import AlarmKit
import Foundation
import SwiftUI
import UserNotifications

/// AlarmKit 的薄封装。AlarmKit 是 iOS 26 才开放的系统级闹钟框架：
/// 它可以突破静音开关与专注模式，出现在锁屏、灵动岛、StandBy 和配对的 Apple Watch 上。
///
/// 这一层同时提供一套本地通知兜底路径，用于尚未授权或不支持的环境。
@Observable
@MainActor
final class AlarmEngine {

    enum Authorization: String {
        case notDetermined
        case authorized
        case denied
    }

    private(set) var authorization: Authorization = .notDetermined
    private(set) var lastError: String?
    /// AlarmKit 当前登记在系统里的闹钟 id
    private(set) var registeredIDs: Set<UUID> = []

    private let manager = AlarmManager.shared

    init() {
        refreshAuthorization()
        Task { await startObservingUpdates() }
    }

    // MARK: 授权

    func refreshAuthorization() {
        switch manager.authorizationState {
        case .authorized:
            authorization = .authorized
        case .denied:
            authorization = .denied
        case .notDetermined:
            authorization = .notDetermined
        @unknown default:
            authorization = .denied
        }
    }

    func requestAuthorization() async {
        do {
            let state = try await manager.requestAuthorization()
            authorization = (state == .authorized) ? .authorized : .denied
        } catch {
            lastError = "闹钟权限申请失败：\(error.localizedDescription)"
        }
    }

    /// 本地通知是「闹钟权限拿不到」时的兜底通道。
    /// 单独一个方法，是因为不该在用户刚进 App 就一次弹两个系统弹窗——
    /// 权限要等到真正需要它的那条路径上再要。
    func requestNotificationFallback() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    // MARK: 调度

    /// 把一个 DawnusAlarm 同步到系统：已开启就登记，已关闭或未开启就撤销。
    func sync(_ alarm: DawnusAlarm) async {
        guard alarm.isOn else {
            await unschedule(alarm.id)
            return
        }
        guard authorization == .authorized else { return }

        let id = alarm.id
        let metadata = DawnusMetadata(
            alarmID: id.uuidString,
            title: alarm.label,
            stakeLine: WakeBrain.stakeLine(stake: alarm.stake, snoozeCount: alarm.snoozeCount),
            difficultyRaw: alarm.difficulty.rawValue,
            dawnMinutes: alarm.dawnMinutes,
            ritualPreview: alarm.ritual.preview
        )

        // 「贪睡 ¥xxx」按钮直接把用户拉进 App，进入全屏渐醒 + 解锁流程
        let secondary = AlarmButton(
            text: alarm.stake == nil ? "再睡 9 分钟" : "贪睡 ¥\(WakeBrain.penalty(stake: alarm.stake, snoozeCount: alarm.snoozeCount + 1))",
            textColor: .white,
            systemImageName: "arrow.counterclockwise"
        )

        let stopButton = AlarmButton(
            text: "起床",
            textColor: .white,
            systemImageName: "sunrise"
        )

        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: alarm.label),
            stopButton: stopButton,
            secondaryButton: secondary,
            secondaryButtonBehavior: .custom
        )

        // preAlert = 晨曦渐醒窗口；postAlert = 响铃后留给你的宽限时间（超时系统判定破约）
        let countdown: Alarm.CountdownDuration? = alarm.dawnMinutes > 0
            ? Alarm.CountdownDuration(
                preAlert: TimeInterval(alarm.dawnMinutes * 60),
                postAlert: TimeInterval(max(60, alarm.dawnMinutes * 12))
              )
            : nil

        let presentation: AlarmPresentation
        if countdown == nil {
            presentation = AlarmPresentation(alert: alert)
        } else {
            // 带渐醒窗口时必须提供 countdown / paused 两种呈现，
            // 否则系统会直接解除闹钟。（AlarmKit 的硬性要求）
            presentation = AlarmPresentation(
                alert: alert,
                countdown: AlarmPresentation.Countdown(
                    title: LocalizedStringResource(stringLiteral: "晨曦渐醒中"),
                    pauseButton: AlarmButton(
                        text: "暂停渐醒",
                        textColor: .white,
                        systemImageName: "pause.circle"
                    )
                ),
                paused: AlarmPresentation.Paused(
                    title: LocalizedStringResource(stringLiteral: "渐醒已暂停"),
                    resumeButton: AlarmButton(
                        text: "继续",
                        textColor: .white,
                        systemImageName: "play.circle"
                    )
                )
            )
        }

        let attributes = AlarmAttributes<DawnusMetadata>(
            presentation: presentation,
            metadata: metadata,
            tintColor: .orange
        )

        let configuration = AlarmManager.AlarmConfiguration(
            countdownDuration: countdown,
            schedule: makeSchedule(for: alarm),
            attributes: attributes,
            stopIntent: StopWakeIntent(alarmID: id.uuidString),
            secondaryIntent: OpenDawnusIntent(alarmID: id.uuidString, isSnooze: true),
            sound: .named("dawn")
        )

        do {
            try await manager.schedule(id: id, configuration: configuration)
            registeredIDs.insert(id)
            lastError = nil
        } catch {
            lastError = "登记失败：\(error.localizedDescription)"
            await scheduleFallbackNotification(alarm)
        }
    }

    func unschedule(_ id: UUID) async {
        do {
            try await manager.cancel(id: id)
        } catch {
            // 已取消或不存在，忽略
        }
        registeredIDs.remove(id)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }

    func syncAll(_ alarms: [DawnusAlarm]) async {
        for alarm in alarms {
            await sync(alarm)
        }
    }

    // MARK: 系统闹钟状态流

    private func startObservingUpdates() async {
        for await remote in manager.alarmUpdates {
            let ids = Set(remote.map { $0.id })
            registeredIDs = ids
        }
    }

    // MARK: 兜底本地通知

    private func makeSchedule(for alarm: DawnusAlarm) -> Alarm.Schedule {
        let time = Alarm.Schedule.Relative.Time(hour: alarm.hour, minute: alarm.minute)
        guard !alarm.weekdays.isEmpty else {
            let date = alarm.nextFireDate()
            return .fixed(date)
        }
        let weekdayMapping: [Int: Locale.Weekday] = [
            1: .sunday, 2: .monday, 3: .tuesday, 4: .wednesday,
            5: .thursday, 6: .friday, 7: .saturday
        ]
        let days = alarm.weekdays.sorted().compactMap { weekdayMapping[$0] }
        let relative = Alarm.Schedule.Relative(time: time, repeats: .weekly(days))
        return .relative(relative)
    }

    private func scheduleFallbackNotification(_ alarm: DawnusAlarm) async {
        let content = UNMutableNotificationContent()
        content.title = alarm.label
        content.body = WakeBrain.stakeLine(stake: alarm.stake, snoozeCount: alarm.snoozeCount)
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let comps = DateComponents(hour: alarm.hour, minute: alarm.minute)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: !alarm.weekdays.isEmpty)
        let request = UNNotificationRequest(identifier: alarm.id.uuidString, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: 演示用：立刻在 App 内触发一次响铃（不惊动系统闹钟）

    /// 为了方便体验，提供一条 App 内的即时响铃路径。
    /// 真实场景应由 AlarmKit 在系统层触发。
    func triggerPreview(alarm: DawnusAlarm, store: AlarmStore) {
        store.session = WakeSession(alarmID: alarm.id, strike: 1, snoozeCount: alarm.snoozeCount)
    }
}
