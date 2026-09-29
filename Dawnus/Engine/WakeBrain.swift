import Foundation

/// 负责「起床」这件事的所有计算：出题、涨价、判题、结算。
/// 纯函数为主，方便将来写单元测试。
enum WakeBrain {

    // MARK: 算术题

    struct MathQuestion: Hashable {
        var text: String
        var answer: Int
        /// 4 个选项，含 1 个正确 + 3 个精心设计的干扰项
        var options: [Int]
    }

    /// 按难度生成一道题。越难，进位越多、数字越大。
    static func makeQuestion(difficulty: WakeDifficulty, round: Int = 1) -> MathQuestion {
        // round 越大（连环模式的后几响），题目越难
        let scale = difficulty == .cascade ? round : (difficulty == .hardcore ? 2 : 1)
        let answer: Int
        let text: String

        switch Int.random(in: 0...2) {
        case 0:
            let a = Int.random(in: (11 * scale)...(19 * scale + 9))
            let b = Int.random(in: (7 * scale)...(19 * scale + 11))
            answer = a + b
            text = "\(a) + \(b) = ?"
        case 1:
            let a = Int.random(in: (30 * scale + 5)...(79 * scale + 9))
            let b = Int.random(in: 6...(a - 4))
            answer = a - b
            text = "\(a) − \(b) = ?"
        default:
            let a = Int.random(in: 3...(9 + scale * 3))
            let b = Int.random(in: 3...(9 + scale * 2))
            answer = a * b
            text = "\(a) × \(b) = ?"
        }

        return MathQuestion(text: text, answer: answer, options: makeOptions(answer: answer))
    }

    /// 干扰项设计：围绕正确答案做「±1 / ±10 / 进位错误」扰动，
    /// 而不是随机数字——这样使用者不能靠「大小感觉」蒙对。
    private static func makeOptions(answer: Int) -> [Int] {
        var set = Set<Int>([answer])
        let deltas = [1, -1, 10, -10, 2, -2, 9, -9, 11, -11]
        var shuffled = deltas.shuffled()
        while set.count < 4, !shuffled.isEmpty {
            let d = shuffled.removeFirst()
            let candidate = answer + d
            if candidate > 0 { set.insert(candidate) }
        }
        var filler = answer + 20
        while set.count < 4 {
            set.insert(filler)
            filler += 7
        }
        return set.shuffled()
    }

    // MARK: 代价

    /// 贪睡 n 次后的应罚金额
    static func penalty(stake: Stake?, snoozeCount: Int) -> Int {
        guard let stake else { return 0 }
        return stake.amountAfterSnoozes(snoozeCount)
    }

    /// 给 UI 展示的代价描述
    static func stakeLine(stake: Stake?, snoozeCount: Int) -> String {
        guard let stake else { return "无代价模式" }
        let amount = penalty(stake: stake, snoozeCount: snoozeCount)
        let base = "本单代价 ¥\(amount)"
        guard snoozeCount > 0 else { return base }
        let origin = stake.amount
        return base + " · 已因贪睡 \(snoozeCount) 次从 ¥\(origin) 涨到 ¥\(amount)"
    }

    // MARK: 统计

    /// 起床率
    static func successRate(_ entries: [LedgerEntry]) -> Double {
        guard !entries.isEmpty else { return 0 }
        let kept = entries.filter { $0.outcome == .kept }.count
        return Double(kept) / Double(entries.count)
    }

    /// 连续早起天数：从今天往前，只要有一天破约就断
    static func currentStreak(_ entries: [LedgerEntry], calendar: Calendar = .current) -> Int {
        let keptDays = Set(entries.filter { $0.outcome == .kept }.compactMap {
            calendar.startOfDay(for: $0.date)
        })
        var streak = 0
        var cursor = calendar.startOfDay(for: .now)
        // 今天还没起床不算断（今天可能还没到点）
        if !keptDays.contains(cursor) {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        while keptDays.contains(cursor) {
            streak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        return streak
    }

    /// 近 7 天每天一条，用于柱状图
    struct DayBucket: Identifiable {
        var id: Date { date }
        var date: Date
        var label: String
        var kept: Bool
        var hadPlan: Bool
    }

    static func lastSevenDays(_ entries: [LedgerEntry], calendar: Calendar = .current) -> [DayBucket] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "EEE"
        let today = calendar.startOfDay(for: .now)
        return (0..<7).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            let todays = entries.filter { calendar.isDate($0.date, inSameDayAs: day) }
            return DayBucket(
                date: day,
                label: f.string(from: day),
                kept: todays.contains { $0.outcome == .kept },
                hadPlan: !todays.isEmpty
            )
        }
    }
}
