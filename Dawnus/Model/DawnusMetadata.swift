import Foundation
import AlarmKit

/// 在 App 与实时活动扩展之间共享的闹钟元数据。
/// AlarmKit 调度时写入，灵动岛 / 锁屏 / Apple Watch 读取渲染。
struct DawnusMetadata: AlarmMetadata, Codable, Hashable, Sendable {
    var alarmID: String
    var title: String
    var stakeLine: String
    var difficultyRaw: String
    var dawnMinutes: Int
    var ritualPreview: String

    init(
        alarmID: String,
        title: String,
        stakeLine: String,
        difficultyRaw: String,
        dawnMinutes: Int,
        ritualPreview: String
    ) {
        self.alarmID = alarmID
        self.title = title
        self.stakeLine = stakeLine
        self.difficultyRaw = difficultyRaw
        self.dawnMinutes = dawnMinutes
        self.ritualPreview = ritualPreview
    }
}
