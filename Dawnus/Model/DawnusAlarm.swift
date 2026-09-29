import Foundation

// MARK: - 解锁难度

/// 闹钟的「起床难度」。决定了关掉闹钟需要付出的认知代价。
enum WakeDifficulty: String, Codable, CaseIterable, Identifiable, Sendable {
    case gentle      // 温柔：滑一下就停
    case math        // 算术：一道两位数运算
    case hardcore    // 硬核：连续三题，错一次从头再来
    case cascade     // 连环：每贪睡一次，题数 +1，且需要连答

    var id: String { rawValue }

    var name: String {
        switch self {
        case .gentle:   return "温柔"
        case .math:     return "算术"
        case .hardcore: return "硬核三连"
        case .cascade:  return "连环递增"
        }
    }

    var symbol: String {
        switch self {
        case .gentle:   return "moon.stars"
        case .math:     return "plusminus"
        case .hardcore: return "flame"
        case .cascade:  return "arrow.trianglehead.2.clockwise"
        }
    }

    var blurb: String {
        switch self {
        case .gentle:
            return "起床后按「我已起床」即可，适合休息日。"
        case .math:
            return "需要答对一道随机运算，把大脑唤醒。"
        case .hardcore:
            return "连答三题，中途答错回到第一题。"
        case .cascade:
            return "第 1 响 1 题，第 2 响 2 题，第 3 响 3 题，没有回头路。"
        }
    }

    /// 本次响铃需要答对的题数（nturn = 第几次响，从 1 开始）
    func requiredSolves(atStrike strike: Int) -> Int {
        switch self {
        case .gentle:   return 0
        case .math:     return 1
        case .hardcore: return 3
        case .cascade:  return min(strike, 3)
        }
    }
}

// MARK: - 代价 / 惩罚去向

enum StakeRecipient: String, Codable, CaseIterable, Identifiable, Sendable {
    case panda   // 捐给公益
    case run     // 罚公里数
    case circle  // 发朋友圈
    case plant   // 转给「心愿账户」（自罚储蓄）

    var id: String { rawValue }

    var name: String {
        switch self {
        case .panda:  return "捐给熊猫基金"
        case .run:    return "罚跑 3 公里"
        case .circle: return "发公开朋友圈"
        case .plant:  return "存入心愿账户"
        }
    }

    var symbol: String {
        switch self {
        case .panda:  return "pawprint"
        case .run:    return "figure.run"
        case .circle: return "person.3"
        case .plant:  return "banknote"
        }
    }

    var verb: String {
        switch self {
        case .panda:  return "捐出"
        case .run:    return "折算跑步"
        case .circle: return "公开"
        case .plant:  return "冻结"
        }
    }
}

/// 起床合约里的「代价」部分。
struct Stake: Codable, Hashable, Sendable {
    var amount: Int
    var recipient: StakeRecipient
    /// 每次贪睡的涨价倍率
    var escalation: Double = 1.6

    static let presets: [Int] = [20, 50, 80, 120, 200, 500]

    /// 贪睡 n 次后的金额
    func amountAfterSnoozes(_ n: Int) -> Int {
        guard n > 0 else { return amount }
        let raw = Double(amount) * pow(escalation, Double(n))
        // 取整到 1 元，避免出现 ¥128.4 这种数字
        return Int(round(raw))
    }

    var line: String { "¥\(amount) · \(recipient.name)" }
}

// MARK: - 晨间仪式链

struct RitualChain: Codable, Hashable, Sendable {
    var steps: [String]

    static let presets: [RitualChain] = [
        RitualChain(steps: ["喝一杯水", "拉开窗帘", "写下今天唯一必做的一件事"]),
        RitualChain(steps: ["站到窗边深呼吸 3 次", "铺好床", "换下睡衣"]),
        RitualChain(steps: ["洗一把冷水脸", "把手机放到另一个房间充电", "写下今天的第一件任务"]),
        RitualChain(steps: ["喝半杯温水", "出门走 5 分钟", "对着镜子说一句今天要做的事"])
    ]

    static let empty = RitualChain(steps: [])

    var preview: String {
        steps.prefix(2).joined(separator: " → ")
    }
}

// MARK: - 闹钟

struct DawnusAlarm: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var hour: Int
    var minute: Int
    var label: String
    /// 空集合 = 只响一次；非空 = 每周重复（Calendar weekday：1 周日 … 7 周六）
    var weekdays: Set<Int>
    var isOn: Bool
    var difficulty: WakeDifficulty
    /// 晨光渐醒提前量（分钟）。会作为 AlarmKit 的 preAlert 倒计时。
    var dawnMinutes: Int
    var stake: Stake?
    var ritual: RitualChain
    /// 已被贪睡的次数（每次独立完成流程后清零）
    var snoozeCount: Int
    /// 连续打卡天数
    var streak: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        hour: Int = 7,
        minute: Int = 0,
        label: String = "起床",
        weekdays: Set<Int> = [2, 3, 4, 5, 6],
        isOn: Bool = true,
        difficulty: WakeDifficulty = .math,
        dawnMinutes: Int = 20,
        stake: Stake? = nil,
        ritual: RitualChain = RitualChain.presets[0],
        snoozeCount: Int = 0,
        streak: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.hour = hour
        self.minute = minute
        self.label = label
        self.weekdays = weekdays
        self.isOn = isOn
        self.difficulty = difficulty
        self.dawnMinutes = dawnMinutes
        self.stake = stake
        self.ritual = ritual
        self.snoozeCount = snoozeCount
        self.streak = streak
        self.createdAt = createdAt
    }

    var timeText: String {
        String(format: "%d:%02d", hour, minute)
    }

    var periodText: String { hour < 12 ? "上午" : "下午" }

    var repeatText: String {
        guard !weekdays.isEmpty else { return "单次" }
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        if weekdays.count == 7 { return "每天" }
        let every = Set([2, 3, 4, 5, 6])
        if weekdays == every { return "工作日" }
        if weekdays == Set([1, 7]) { return "周末" }
        // 每个都带「周」，避免出现「周一 三 六」这种读起来别扭的文案
        return weekdays.sorted().map { "周" + names[$0 - 1] }.joined(separator: " ")
    }

    /// 下一次触发的绝对时间（用于列表展示与兜底通知）
    func nextFireDate(from now: Date = .now, calendar: Calendar = .current) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day], from: now)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        guard let candidate = calendar.date(from: comps) else { return now }

        if weekdays.isEmpty {
            return candidate > now ? candidate : calendar.date(byAdding: .day, value: 1, to: candidate)!
        }
        // 找到下一个命中工作日的最近日期（含今天）
        for offset in 0...7 {
            guard let d = calendar.date(byAdding: .day, value: offset, to: candidate) else { continue }
            let weekday = calendar.component(.weekday, from: d)
            if weekdays.contains(weekday), d > now { return d }
        }
        return candidate
    }
}

// MARK: - 账本

enum WakeOutcome: String, Codable, Sendable {
    case kept    // 守约
    case broke   // 破约
}

struct LedgerEntry: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var date: Date
    var alarmLabel: String
    var outcome: WakeOutcome
    var amount: Int
    var snoozeCount: Int
    var difficultyRaw: String

    init(
        id: UUID = UUID(),
        date: Date = .now,
        alarmLabel: String,
        outcome: WakeOutcome,
        amount: Int,
        snoozeCount: Int,
        difficultyRaw: String
    ) {
        self.id = id
        self.date = date
        self.alarmLabel = alarmLabel
        self.outcome = outcome
        self.amount = amount
        self.snoozeCount = snoozeCount
        self.difficultyRaw = difficultyRaw
    }
}
