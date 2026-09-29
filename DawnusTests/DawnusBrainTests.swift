import XCTest
@testable import Dawnus

/// 覆盖「起床」这件事的核心算法：出题、涨代价、连环递增、统计。
final class DawnusBrainTests: XCTestCase {

    // MARK: 出题

    func testQuestionAnswerIsAmongOptions() {
        for _ in 0..<200 {
            let q = WakeBrain.makeQuestion(difficulty: .math)
            XCTAssertTrue(q.options.contains(q.answer), "正确答案必须出现在选项里：\(q.text)")
            XCTAssertEqual(q.options.count, 4, "应该是 4 个选项")
            XCTAssertEqual(Set(q.options).count, 4, "选项不能重复")
        }
    }

    func testQuestionIsActuallySolvable() {
        let q = WakeBrain.makeQuestion(difficulty: .math)
        // 解析形如 "12 + 7 = ?"
        let parts = q.text.replacingOccurrences(of: " = ?", with: "").split(separator: " ")
        XCTAssertEqual(parts.count, 3, "题目格式应为 a op b")
        let a = Int(parts[0])!, b = Int(parts[2])!
        let expected: Int
        switch parts[1] {
        case "+": expected = a + b
        case "−": expected = a - b
        case "×": expected = a * b
        default: XCTFail("未知运算符 \(parts[1])"); return
        }
        XCTAssertEqual(q.answer, expected, "题目与答案不一致")
    }

    func testCascadeGetsHarderEachStrike() {
        XCTAssertEqual(WakeDifficulty.cascade.requiredSolves(atStrike: 1), 1)
        XCTAssertEqual(WakeDifficulty.cascade.requiredSolves(atStrike: 2), 2)
        XCTAssertEqual(WakeDifficulty.cascade.requiredSolves(atStrike: 3), 3)
        // 第四响封顶在 3，不无限增长
        XCTAssertEqual(WakeDifficulty.cascade.requiredSolves(atStrike: 9), 3)
    }

    func testDifficultyRequirements() {
        XCTAssertEqual(WakeDifficulty.gentle.requiredSolves(atStrike: 1), 0)
        XCTAssertEqual(WakeDifficulty.math.requiredSolves(atStrike: 1), 1)
        XCTAssertEqual(WakeDifficulty.hardcore.requiredSolves(atStrike: 1), 3)
    }

    // MARK: 代价

    func testStakeEscalationMatchesDesign() {
        let stake = Stake(amount: 80, recipient: .plant, escalation: 1.6)
        XCTAssertEqual(stake.amountAfterSnoozes(0), 80)
        XCTAssertEqual(stake.amountAfterSnoozes(1), 128)
        XCTAssertEqual(stake.amountAfterSnoozes(2), 205)
        XCTAssertEqual(stake.amountAfterSnoozes(3), 328)
        XCTAssertEqual(stake.amountAfterSnoozes(4), 524)
    }

    func testPenaltyWithoutStakeIsZero() {
        XCTAssertEqual(WakeBrain.penalty(stake: nil, snoozeCount: 3), 0)
    }

    // MARK: 统计

    func testSuccessRate() {
        let entries = [
            LedgerEntry(alarmLabel: "a", outcome: .kept, amount: 0, snoozeCount: 0, difficultyRaw: "math"),
            LedgerEntry(alarmLabel: "b", outcome: .broke, amount: 50, snoozeCount: 1, difficultyRaw: "math"),
            LedgerEntry(alarmLabel: "c", outcome: .kept, amount: 0, snoozeCount: 0, difficultyRaw: "gentle"),
            LedgerEntry(alarmLabel: "d", outcome: .kept, amount: 0, snoozeCount: 0, difficultyRaw: "gentle")
        ]
        XCTAssertEqual(WakeBrain.successRate(entries), 0.75, accuracy: 0.001)
        XCTAssertEqual(WakeBrain.successRate([]), 0)
    }

    func testStreakBreaksOnMissedDay() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: -offset, to: today)! }

        let entries = [
            LedgerEntry(date: day(0), alarmLabel: "t", outcome: .kept, amount: 0, snoozeCount: 0, difficultyRaw: "math"),
            LedgerEntry(date: day(1), alarmLabel: "y", outcome: .kept, amount: 0, snoozeCount: 0, difficultyRaw: "math"),
            LedgerEntry(date: day(2), alarmLabel: "d2", outcome: .kept, amount: 0, snoozeCount: 0, difficultyRaw: "math"),
            // day(3) 缺席 → 断开
            LedgerEntry(date: day(4), alarmLabel: "d4", outcome: .kept, amount: 0, snoozeCount: 0, difficultyRaw: "math")
        ]
        XCTAssertEqual(WakeBrain.currentStreak(entries), 3)
    }

    func testStreakCountsFromYesterdayWhenTodayNotYetDone() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: -offset, to: today)! }
        let entries = [
            LedgerEntry(date: day(1), alarmLabel: "y", outcome: .kept, amount: 0, snoozeCount: 0, difficultyRaw: "math"),
            LedgerEntry(date: day(2), alarmLabel: "d2", outcome: .kept, amount: 0, snoozeCount: 0, difficultyRaw: "math")
        ]
        XCTAssertEqual(WakeBrain.currentStreak(entries), 2, "今天还没到点，不该把连续记录算断")
    }

    // MARK: 下一次响铃时间

    func testNextFireDateIsInTheFuture() {
        let alarm = DawnusAlarm(hour: 7, minute: 30, weekdays: [2, 3, 4, 5, 6])
        let next = alarm.nextFireDate()
        XCTAssertGreaterThan(next, Date(), "下一次响铃必须在未来")
    }

    func testOneShotAlarmRollsToTomorrowWhenTimePassed() {
        let alarm = DawnusAlarm(hour: 0, minute: 1, weekdays: [])
        let next = alarm.nextFireDate()
        XCTAssertGreaterThan(next, Date())
        let comps = Calendar.current.dateComponents([.hour, .minute], from: next)
        XCTAssertEqual(comps.hour, 0)
        XCTAssertEqual(comps.minute, 1)
    }

    // MARK: 元数据与账本可序列化（要跨进程传给实时活动）

    func testMetadataIsCodable() throws {
        let meta = DawnusMetadata(
            alarmID: UUID().uuidString,
            title: "工作日",
            stakeLine: "本单代价 ¥80",
            difficultyRaw: "math",
            dawnMinutes: 20,
            ritualPreview: "喝水 → 拉窗帘"
        )
        let data = try JSONEncoder().encode(meta)
        let back = try JSONDecoder().decode(DawnusMetadata.self, from: data)
        XCTAssertEqual(back, meta)
    }

    func testAlarmSurvivesRoundTrip() throws {
        let alarm = DawnusAlarm(
            hour: 6, minute: 40, label: "晨跑日", weekdays: [2, 4, 7],
            difficulty: .hardcore, dawnMinutes: 25,
            stake: Stake(amount: 80, recipient: .run),
            ritual: RitualChain.presets[1]
        )
        let data = try JSONEncoder().encode(alarm)
        let back = try JSONDecoder().decode(DawnusAlarm.self, from: data)
        XCTAssertEqual(back, alarm)
        XCTAssertEqual(back.repeatText, "周一 周三 周六")
    }
}
