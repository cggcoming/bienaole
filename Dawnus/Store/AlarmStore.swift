import Foundation
import Observation

/// 单一数据源。用 JSON 文件持久化，避免为演示项目引入额外的持久化栈。
@Observable
final class AlarmStore {

    // MARK: 持久化数据

    var alarms: [DawnusAlarm] = []
    var ledger: [LedgerEntry] = []

    // MARK: 运行时状态

    /// 当前正在响的会话（nil 表示没在响）
    var session: WakeSession?

    /// 存档损坏时保留的备份路径（非 nil 表示这次启动是从损坏状态恢复的）
    private(set) var recoveredBackup: URL?

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        load()
        if alarms.isEmpty {
            alarms = Self.seedAlarms()
            save()
        }
    }

    // MARK: 路径

    private static func defaultFileURL() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("dawnus-store.json")
    }

    // MARK: 读写

    private struct Snapshot: Codable {
        var alarms: [DawnusAlarm]
        var ledger: [LedgerEntry]
    }

    private static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        // 显式声明日期格式，避免默认的「自 2001 年起算的秒数」这种不可读、易错的形式
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    func save() {
        let snap = Snapshot(alarms: alarms, ledger: ledger)
        guard let data = try? Self.makeEncoder().encode(snap) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let snap = try Self.makeDecoder().decode(Snapshot.self, from: data)
            alarms = snap.alarms
            ledger = snap.ledger
        } catch {
            // 存档读不出来时，绝不静默覆盖——先留一份现场，再重建。
            // 「用户数据无声消失」是产品里最不可原谅的一类 bug。
            let stamp = ISO8601DateFormatter().string(from: .now)
                .replacingOccurrences(of: ":", with: "-")
            let backup = fileURL.deletingPathExtension()
                .appendingPathExtension("damaged-\(stamp).json")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            recoveredBackup = backup
        }
    }

    // MARK: 增删改

    func add(_ alarm: DawnusAlarm) {
        alarms.append(alarm)
        save()
    }

    func update(_ alarm: DawnusAlarm) {
        guard let i = alarms.firstIndex(where: { $0.id == alarm.id }) else { return }
        alarms[i] = alarm
        save()
    }

    func remove(_ id: UUID) {
        alarms.removeAll { $0.id == id }
        save()
    }

    func toggle(_ id: UUID) {
        guard let i = alarms.firstIndex(where: { $0.id == id }) else { return }
        alarms[i].isOn.toggle()
        save()
    }

    func alarm(for id: UUID) -> DawnusAlarm? {
        alarms.first { $0.id == id }
    }

    // MARK: 结算

    enum Result: String {
        case kept
        case broke
    }

    /// 走完或放弃一次闹钟流程后的记账
    func settle(alarmID: UUID, snoozeCount: Int, kind: Result) {
        guard let alarm = alarm(for: alarmID) else { return }
        let amount = kind == .kept ? 0 : WakeBrain.penalty(stake: alarm.stake, snoozeCount: snoozeCount)
        let entry = LedgerEntry(
            alarmLabel: alarm.label,
            outcome: kind == .kept ? .kept : .broke,
            amount: amount,
            snoozeCount: snoozeCount,
            difficultyRaw: alarm.difficulty.rawValue
        )
        ledger.insert(entry, at: 0)

        guard let i = alarms.firstIndex(where: { $0.id == alarmID }) else { save(); return }
        if kind == .kept {
            alarms[i].streak += 1
        } else {
            alarms[i].streak = 0
        }
        alarms[i].snoozeCount = 0
        save()
    }

    // MARK: 与 App Intent 的跨进程通信

    /// AppIntent 执行时把「哪个闹钟响了」写进共享区，App 冷启动后取用。
    /// 共享层的可用性由 `SharedStore` 负责降级，这里不关心签名环境。
    func publishFired(alarmID: UUID) {
        SharedStore.set(alarmID.uuidString, forKey: "pendingAlarmID")
        SharedStore.set(Date().timeIntervalSince1970, forKey: "pendingAlarmAt")
    }

    func consumePendingFired() -> UUID? {
        guard let raw = SharedStore.string(forKey: "pendingAlarmID"),
              let id = UUID(uuidString: raw) else { return nil }
        SharedStore.remove(forKey: "pendingAlarmID")
        return id
    }

    // MARK: 种子数据

    private static func seedAlarms() -> [DawnusAlarm] {
        [
            DawnusAlarm(
                hour: 6, minute: 40, label: "晨跑日",
                weekdays: [2, 4, 7], difficulty: .hardcore, dawnMinutes: 25,
                stake: Stake(amount: 80, recipient: .run),
                ritual: RitualChain.presets[1]
            ),
            DawnusAlarm(
                hour: 7, minute: 0, label: "工作日",
                weekdays: [2, 3, 4, 5, 6], difficulty: .math, dawnMinutes: 20,
                stake: Stake(amount: 50, recipient: .plant),
                ritual: RitualChain.presets[0]
            ),
            DawnusAlarm(
                hour: 9, minute: 30, label: "周末自然醒",
                weekdays: [1, 7], difficulty: .gentle, dawnMinutes: 30,
                stake: nil,
                ritual: RitualChain.presets[2]
            )
        ]
    }
}

// MARK: - 一次响铃会话

struct WakeSession: Hashable {
    var alarmID: UUID
    var startedAt: Date
    /// 这是第几次响（连环模式下会累加）
    var strike: Int
    /// 已答对的题数
    var solved: Int
    /// 本次共答错几次
    var mistakes: Int
    var snoozeCount: Int

    init(alarmID: UUID, strike: Int = 1, snoozeCount: Int = 0) {
        self.alarmID = alarmID
        self.startedAt = .now
        self.strike = strike
        self.solved = 0
        self.mistakes = 0
        self.snoozeCount = snoozeCount
    }
}
