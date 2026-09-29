import SwiftUI
import UIKit

/// 全屏响铃 + 渐醒 + 解锁。
///
/// 这是整个 App 的核心界面：天空在推进，题目在拦你，代价在涨。
enum WakePhase {
    case ringing
    case snoozed(fireAt: Date)
}

struct RingingView: View {
    @Environment(AlarmStore.self) private var store
    @Environment(AlarmEngine.self) private var engine
    @Binding var session: WakeSession?

    @State private var phase: WakePhase = .ringing
    @State private var question = WakeBrain.makeQuestion(difficulty: .math)
    @State private var wrongPulse = false
    @State private var skyProgress: Double = 0
    @State private var now = Date()

    private let ticker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    private var alarm: DawnusAlarm? {
        guard let id = session?.alarmID else { return nil }
        return store.alarm(for: id)
    }

    var body: some View {
        ZStack {
            // 天空随时间推进
            DawnSky.gradient(at: skyProgress)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 1.2), value: skyProgress)

            // 太阳光晕
            RadialGradient(
                colors: [Color.dawnGold.opacity(DawnSky.haloOpacity(at: skyProgress)), .clear],
                center: .center,
                startRadius: 10,
                endRadius: 320
            )
            .ignoresSafeArea()
            .blendMode(.screen)

            VStack(spacing: 0) {
                header
                Spacer(minLength: 8)

                phaseContent

                Spacer(minLength: 8)
                footArea
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 26)
        }
        .onAppear(perform: setup)
        .onDisappear { WakeSound.shared.stop() }
        .onReceive(ticker) { tick($0) }
    }

    // MARK: 头部

    private var header: some View {
        VStack(spacing: 6) {
            Text(now, format: .dateTime.hour().minute())
                .font(.dawnTime(52))
                .foregroundStyle(.white)
                .monospacedDigit()
            if let alarm {
                Text(alarm.label)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                Text(WakeBrain.stakeLine(stake: alarm.stake, snoozeCount: session?.snoozeCount ?? 0))
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: 0xFFC9A0))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background { Capsule().fill(Color.black.opacity(0.22)) }
            }
        }
        .padding(.top, 30)
    }

    // MARK: 任务区（答题 / 直接起床）

    /// 单独抽出来，因为 switch 不能直接写在 result builder 里
    @ViewBuilder
    private var phaseContent: some View {
        switch phase {
        case .ringing:
            taskArea
        case .snoozed(let fireAt):
            snoozeArea(fireAt: fireAt)
        }
    }

    @ViewBuilder
    private var taskArea: some View {
        if let alarm, let session {
            let need = alarm.difficulty.requiredSolves(atStrike: session.strike)
            VStack(spacing: 18) {
            if need == 0 {
                // 温柔模式：不做题
                VStack(spacing: 10) {
                    Image(systemName: "sunrise.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("天亮了")
                        .font(.dawnTitle(24))
                        .foregroundStyle(.white)
                }
                .padding(.vertical, 20)
            } else {
                VStack(spacing: 10) {
                    // 进度点
                    HStack(spacing: 7) {
                        ForEach(0..<need, id: \.self) { i in
                            Circle()
                                .fill(i < session.solved ? Color.dawnGold : Color.white.opacity(0.25))
                                .frame(width: 8, height: 8)
                        }
                    }
                    Text("第 \(min(session.solved + 1, need)) / \(need) 题")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))

                    Text(question.text)
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .modifier(ShakeEffect(shakes: wrongPulse ? 3 : 0))
                        .animation(.default, value: wrongPulse)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(question.options, id: \.self) { option in
                            Button {
                                answer(option)
                            } label: {
                                Text("\(option)")
                                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, minHeight: 66)
                                    .background {
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .fill(Color.white.opacity(0.14))
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: 340)

                    if session.mistakes > 0 {
                        Text("答错 \(session.mistakes) 次" + (alarm.difficulty == .hardcore ? " · 硬核模式回到第一题" : ""))
                            .font(.caption)
                            .foregroundStyle(Color(hex: 0xFFB3A0))
                    }
                }
                .padding(18)
                .glassEffect(.regular.tint(Color.white.opacity(0.06)), in: .rect(cornerRadius: 26))
            }
        }
        }
    }

    // MARK: 贪睡区

    private func snoozeArea(fireAt: Date) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "zzz")
                .font(.system(size: 34))
                .foregroundStyle(.white.opacity(0.7))
            Text("再睡一会儿")
                .font(.dawnTitle(20))
                .foregroundStyle(.white)
            let remain = max(0, fireAt.timeIntervalSince(now))
            Text("\(Int(ceil(remain))) 秒后重新响")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.7))
                .monospacedDigit()
            Text(WakeBrain.stakeLine(stake: alarm?.stake, snoozeCount: session?.snoozeCount ?? 0))
                .font(.caption)
                .foregroundStyle(Color(hex: 0xFFC9A0))
            Button("我现在就响") {
                fireAgain()
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background { Capsule().fill(Color.white.opacity(0.14)) }
            .buttonStyle(.plain)
        }
        .padding(22)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    // MARK: 底部

    private var footArea: some View {
        VStack(spacing: 10) {
            if let alarm, let session {
                let need = alarm.difficulty.requiredSolves(atStrike: session.strike)
                if need == 0 {
                    GlassButton(title: "我已起床", systemImage: "checkmark", tint: .dawnGold, role: .primary) {
                        finish()
                    }
                }
            }

            if let alarm {
                let nextAmount = WakeBrain.penalty(stake: alarm.stake, snoozeCount: (session?.snoozeCount ?? 0) + 1)
                Button {
                    snooze()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "moon.zzz.fill")
                        Text(alarm.stake == nil ? "贪睡 9 分钟" : "贪睡 9 分钟 · 代价涨到 ¥\(nextAmount)")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                }
                .buttonStyle(.plain)

                Text("连环模式：第 \((session?.strike ?? 1) + 1) 响会多一道题")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.bottom, 12)
    }

    // MARK: 逻辑

    private func setup() {
        guard let alarm else { return }
        session?.solved = 0
        question = WakeBrain.makeQuestion(
            difficulty: alarm.difficulty,
            round: session?.strike ?? 1
        )
        WakeSound.shared.start()
        // 渐醒：进入界面后 20 秒内把天空从深夜推到晨曦（演示节奏；真实由 preAlert 决定）
        skyProgress = 0
        withAnimation(.easeInOut(duration: 20)) {
            skyProgress = 1
        }
    }

    private func tick(_ date: Date) {
        now = date
        if case .snoozed(let fireAt) = phase, date >= fireAt {
            fireAgain()
        }
    }

    private func answer(_ value: Int) {
        guard var s = session, let alarm = alarm else { return }
        if value == question.answer {
            s.solved += 1
            session = s
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            let need = alarm.difficulty.requiredSolves(atStrike: s.strike)
            if s.solved >= need {
                finish()
            } else {
                question = WakeBrain.makeQuestion(difficulty: alarm.difficulty, round: s.solved + 1)
            }
        } else {
            s.mistakes += 1
            if alarm.difficulty == .hardcore { s.solved = 0 }
            session = s
            wrongPulse.toggle()
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func snooze() {
        guard var s = session else { return }
        s.snoozeCount += 1
        s.strike += 1                 // 连环递增：下一响更难
        s.solved = 0
        session = s
        WakeSound.shared.stop()
        // 真实环境 9 分钟；这里用 20 秒，方便直接体验完整链路
        phase = .snoozed(fireAt: Date().addingTimeInterval(20))
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func fireAgain() {
        phase = .ringing
        skyProgress = 0
        withAnimation(.easeInOut(duration: 12)) { skyProgress = 1 }
        WakeSound.shared.start()
        guard let alarm else { return }
        question = WakeBrain.makeQuestion(
            difficulty: alarm.difficulty,
            round: session?.strike ?? 1
        )
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    private func finish() {
        WakeSound.shared.stop()
        guard let s = session else { return }
        // 进入晨间仪式链；由 RootView 负责展示
        store.session = s
        NotificationCenter.default.post(name: .dawnusDidUnlock, object: nil)
    }
}

// MARK: 答错抖动

struct ShakeEffect: GeometryEffect {
    var shakes: Int
    var amount: CGFloat = 8
    var animatableData: CGFloat {
        get { CGFloat(shakes) }
        set { shakes = Int(newValue) }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        guard shakes > 0 else { return ProjectionTransform() }
        let offset = amount * sin(CGFloat(shakes) * .pi * 0.7)
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}
