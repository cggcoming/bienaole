import AppIntents
import AlarmKit
import Foundation

/// 点击系统闹钟 UI 上的「起床 / 停止」时触发。
/// AlarmKit 会自己处理停止逻辑，我们通过这个 Intent 记录一次成功。
struct StopWakeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "结束闹钟" }
    static var description: IntentDescription { IntentDescription("停止正在响的拂晓闹钟。") }

    @Parameter(title: "闹钟 ID")
    var alarmID: String

    init() { self.alarmID = "" }
    init(alarmID: String) { self.alarmID = alarmID }

    func perform() async throws -> some IntentResult {
        WakeIntentBridge.shared.record(alarmID: alarmID, action: .stop)
        return .result()
    }
}

/// 点击「贪睡」/「打开」时触发：把 App 拉到前台，进入全屏解锁流程。
struct OpenDawnusIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "打开拂晓" }
    static var description: IntentDescription { IntentDescription("打开拂晓 App 完成解锁。") }

    /// 点这个按钮要直接把 App 拉起来（这是全屏渐醒 + 算术解锁能生效的前提）
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "闹钟 ID")
    var alarmID: String

    @Parameter(title: "是否贪睡", default: false)
    var isSnooze: Bool

    init() {
        self.alarmID = ""
        self.isSnooze = false
    }

    init(alarmID: String, isSnooze: Bool = false) {
        self.alarmID = alarmID
        self.isSnooze = isSnooze
    }

    func perform() async throws -> some IntentResult {
        WakeIntentBridge.shared.record(alarmID: alarmID, action: isSnooze ? .snooze : .open)
        return .result()
    }
}

/// Intent 与 App 主进程之间的桥：写进 App Group，App 冷启动时读取。
enum IntentAction: String {
    case stop
    case snooze
    case open
}

final class WakeIntentBridge: @unchecked Sendable {
    static let shared = WakeIntentBridge()
    private init() {}

    func record(alarmID: String, action: IntentAction) {
        SharedStore.set(alarmID, forKey: "pendingAlarmID")
        SharedStore.set(action.rawValue, forKey: "pendingAction")
        SharedStore.set(Date().timeIntervalSince1970, forKey: "pendingAt")
    }

    struct Pending {
        var alarmID: UUID
        var action: IntentAction
    }

    func consume() -> Pending? {
        guard let rawID = SharedStore.string(forKey: "pendingAlarmID"),
              let id = UUID(uuidString: rawID),
              let rawAction = SharedStore.string(forKey: "pendingAction"),
              let action = IntentAction(rawValue: rawAction)
        else { return nil }
        SharedStore.remove(forKey: "pendingAlarmID")
        SharedStore.remove(forKey: "pendingAction")
        return Pending(alarmID: id, action: action)
    }
}
