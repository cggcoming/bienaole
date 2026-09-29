import SwiftUI
import UIKit

/// 晨间仪式链：关掉闹钟之后的那 3 分钟。
///
/// 传统闹钟在这里就结束了——屏幕一黑，人又躺下去。
/// 拂晓在这里才开始：让身体先于意志走完一段物理路径。
struct RitualView: View {
    @Environment(AlarmStore.self) private var store
    @Binding var session: WakeSession?
    var onFinish: () -> Void

    @State private var checked: Set<Int> = []
    @State private var celebrate = false

    private var alarm: DawnusAlarm? {
        guard let id = session?.alarmID else { return nil }
        return store.alarm(for: id)
    }

    var body: some View {
        ZStack {
            DawnSky.gradient(at: 1.0).ignoresSafeArea()
            RadialGradient(
                colors: [Color.dawnGold.opacity(celebrate ? 0.45 : 0.2), .clear],
                center: .top,
                startRadius: 20,
                endRadius: 420
            )
            .ignoresSafeArea()
            .animation(.easeOut(duration: 0.8), value: celebrate)

            VStack(spacing: 22) {
                VStack(spacing: 6) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(Color.dawnGold)
                        .symbolEffect(.bounce, value: celebrate)
                    Text("起床成功")
                        .font(.dawnTitle(28))
                        .foregroundStyle(.white)
                    if let alarm {
                        Text(alarm.label)
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
                .padding(.top, 46)

                VStack(spacing: 10) {
                    if let alarm, !alarm.ritual.steps.isEmpty {
                        ForEach(Array(alarm.ritual.steps.enumerated()), id: \.offset) { i, step in
                            let on = checked.contains(i)
                            Button {
                                if on { checked.remove(i) } else { checked.insert(i) }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                if checked.count == alarm.ritual.steps.count { celebrate = true }
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 22))
                                        .foregroundStyle(on ? Color.dawnGold : .white.opacity(0.35))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(step)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundStyle(.white)
                                        Text("第 \(i + 1) 步")
                                            .font(.caption)
                                            .foregroundStyle(.white.opacity(0.45))
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 15)
                                .background {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(on ? Color.dawnGold.opacity(0.16) : Color.white.opacity(0.07))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        Text("这条闹钟没有设置仪式链")
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                if let alarm, let session {
                    Text("本次贪睡 \(session.snoozeCount) 次 · 答错 \(session.mistakes) 次 · 难度 \(alarm.difficulty.name)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                }

                Spacer()

                GlassButton(
                    title: buttonTitle,
                    systemImage: "checkmark.seal.fill",
                    tint: .dawnGold,
                    role: .primary
                ) {
                    complete()
                }
                .disabled(!allChecked)
                .opacity(allChecked ? 1 : 0.45)
                .padding(.bottom, 34)
            }
            .padding(.horizontal, 22)
        }
    }

    private var stepsCount: Int { alarm?.ritual.steps.count ?? 0 }
    private var allChecked: Bool { stepsCount == 0 || checked.count == stepsCount }

    private var buttonTitle: String {
        allChecked ? "完成，今天已打卡" : "完成 \(checked.count)/\(stepsCount) 步才能打卡"
    }

    private func complete() {
        guard let session else { return }
        store.settle(alarmID: session.alarmID, snoozeCount: session.snoozeCount, kind: .kept)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        self.session = nil
        onFinish()
    }
}
