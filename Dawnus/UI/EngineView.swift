import SwiftUI

/// 引擎页：权限状态、系统登记情况，以及一键触发四种响铃模式的演示入口。
struct EngineView: View {
    @Environment(AlarmStore.self) private var store
    @Environment(AlarmEngine.self) private var engine

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if store.recoveredBackup != nil { recoveryBanner }
                statusSection
                demoSection
                noteSection
                Spacer(minLength: 30)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
        }
    }

    // MARK: 状态

    private var recoveryBanner: some View {
        GlassCard(tint: Color.dawnRose.opacity(0.16), padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.dawnRose)
                    Text("上次的存档读不出来")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text("已把损坏的原文件另存为 \(store.recoveredBackup?.lastPathComponent ?? "备份")，没有直接覆盖它。闹钟已按默认值重建。")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
    }

    private var statusSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape.2")
                        .font(.system(size: 12, weight: .semibold))
                    Text("引擎状态")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.6))

                StatusRow(
                    title: "系统闹钟权限",
                    value: authorizationText,
                    tint: engine.authorization == .authorized ? Color.dawnGold : .orange
                )
                StatusRow(
                    title: "已登记到系统",
                    value: "\(engine.registeredIDs.count) 个",
                    tint: .white
                )

                Button {
                    Task {
                        await engine.requestAuthorization()
                        // 拿不到系统闹钟权限时，至少把本地通知这条兜底路径打通
                        if engine.authorization != .authorized {
                            await engine.requestNotificationFallback()
                        }
                        await engine.syncAll(store.alarms)
                    }
                } label: {
                    Text(engine.authorization == .authorized ? "重新同步全部闹钟" : "申请权限并同步")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.85))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background { Capsule().fill(Color.dawnAmber) }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var authorizationText: String {
        switch engine.authorization {
        case .authorized:    return "已授权"
        case .notDetermined: return "未询问"
        case .denied:        return "已拒绝"
        }
    }

    // MARK: 演示

    private var demoSection: some View {
        GlassCard(tint: Color.dawnAmber.opacity(0.10)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "play.rectangle")
                        .font(.system(size: 12, weight: .semibold))
                    Text("立刻体验完整链路")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.6))

                Text("点一下就会全屏响铃：天空推进 → 解锁 → 晨间仪式链 → 写回账本。贪睡会让代价涨价、连环模式会加题。")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))

                ForEach(WakeDifficulty.allCases) { level in
                    Button {
                        startDemo(level)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: level.symbol)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.dawnAmber)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(level.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text(level.blurb)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            Spacer()
                            Image(systemName: "play.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .padding(11)
                        .background {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(Color.white.opacity(0.07))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func startDemo(_ level: WakeDifficulty) {
        // 找一个同难度的现成闹钟，没有就造一个临时的
        let alarm = store.alarms.first { $0.difficulty == level } ?? {
            let demo = DawnusAlarm(
                hour: Calendar.current.component(.hour, from: .now),
                minute: Calendar.current.component(.minute, from: .now),
                label: "演示 · \(level.name)",
                weekdays: [],
                difficulty: level,
                dawnMinutes: 20,
                stake: level == .gentle ? nil : Stake(amount: 80, recipient: .plant),
                ritual: RitualChain.presets.randomElement() ?? .presets[0]
            )
            store.add(demo)
            return demo
        }()
        engine.triggerPreview(alarm: alarm, store: store)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    // MARK: 说明

    private var noteSection: some View {
        GlassCard(tint: Color.dawnCyan.opacity(0.10)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 12, weight: .semibold))
                    Text("为什么这么做")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.6))

                VStack(alignment: .leading, spacing: 6) {
                    NoteLine(text: "真正的失败从来不是没听见，是听见了没起来。所以闹钟只负责「响」，拂晓负责「起」。")
                    NoteLine(text: "代价模式用的是前景效应：人对确定损失的反应强度约为等量收益的 2 倍。")
                    NoteLine(text: "晨曦渐醒用的是 AlarmKit 的 preAlert 倒计时：响之前先让皮质醇上涌。")
                    NoteLine(text: "仪式链把「起床」从一个瞬间改写成一段三分钟的物理路径。")
                }
            }
        }
    }
}

private struct StatusRow: View {
    var title: String
    var value: String
    var tint: Color

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13.5))
                .foregroundStyle(.white.opacity(0.75))
            Spacer()
            Text(value)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(tint)
        }
    }
}

private struct NoteLine: View {
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Circle().fill(Color.dawnCyan.opacity(0.8)).frame(width: 5, height: 5)
                .padding(.top, 6)
            Text(text)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}
