import SwiftUI

/// 新建 / 编辑闹钟。
/// 这里集中了「起床合约」的所有条款：时间、难度、代价、渐醒窗口、仪式链。
struct AlarmEditorView: View {
    @Environment(AlarmStore.self) private var store
    @Environment(AlarmEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss

    /// 传入已有闹钟 = 编辑；nil = 新建
    var editing: DawnusAlarm?

    @State private var draft: DawnusAlarm
    @State private var stakeEnabled: Bool
    @State private var stakeAmount: Double
    @State private var showRitualPicker = false

    init(editing: DawnusAlarm? = nil) {
        self.editing = editing
        let base = editing ?? DawnusAlarm()
        _draft = State(initialValue: base)
        _stakeEnabled = State(initialValue: base.stake != nil)
        _stakeAmount = State(initialValue: Double(base.stake?.amount ?? 50))
    }

    private let weekdayLabels = [
        (1, "日"), (2, "一"), (3, "二"), (4, "三"), (5, "四"), (6, "五"), (7, "六")
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.midnight.ignoresSafeArea()
                    .overlay { DawnSky.gradient(at: 0.05).opacity(0.5).ignoresSafeArea() }

                ScrollView {
                    VStack(spacing: 18) {
                        dialSection
                        repeatSection
                        difficultySection
                        dawnSection
                        stakeSection
                        ritualSection
                        saveButton
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle(editing == nil ? "新建闹钟" : "编辑闹钟")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    // MARK: 拨盘

    private var dialSection: some View {
        GlassCard(padding: 12) {
            VStack(spacing: 10) {
                DialTimePicker(hour: $draft.hour, minute: $draft.minute, minuteStep: 1)
                    .frame(maxWidth: 300, maxHeight: 300)
                    .padding(.vertical, 4)

                TextField("闹钟名字", text: $draft.label)
                    .font(.system(size: 16, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background { Capsule().fill(Color.white.opacity(0.08)) }
                    .tint(Color.dawnAmber)

                Text("外环调小时 · 内环调分钟，沿弧拖动，抬手自动吸附")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    // MARK: 重复

    private var repeatSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("重复", systemImage: "repeat")
                HStack(spacing: 8) {
                    ForEach(weekdayLabels, id: \.0) { day, text in
                        let on = draft.weekdays.contains(day)
                        Button {
                            if on { draft.weekdays.remove(day) } else { draft.weekdays.insert(day) }
                            haptic()
                        } label: {
                            Text(text)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(on ? .black.opacity(0.85) : .white.opacity(0.8))
                                .frame(width: 38, height: 38)
                                .background {
                                    Circle().fill(on ? Color.dawnAmber : Color.white.opacity(0.10))
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(draft.weekdays.isEmpty ? "只响一次" : draft.repeatText)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    // MARK: 难度

    private var difficultySection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("起床难度", systemImage: "flame")
                ForEach(WakeDifficulty.allCases, id: \.self) { level in
                    let selected = draft.difficulty == level
                    Button {
                        draft.difficulty = level
                        haptic()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: level.symbol)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(selected ? Color.dawnAmber : Color.white.opacity(0.6))
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(level.name).font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text(level.blurb).font(.caption)
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            Spacer()
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected ? Color.dawnAmber : Color.white.opacity(0.25))
                        }
                        .padding(10)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selected ? Color.dawnAmber.opacity(0.14) : Color.clear)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: 渐醒

    private var dawnSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    sectionTitle("晨曦渐醒", systemImage: "sun.horizon")
                    Spacer()
                    Text(draft.dawnMinutes == 0 ? "关闭" : "提前 \(draft.dawnMinutes) 分钟")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.dawnAmber)
                }
                Slider(value: Binding(
                    get: { Double(draft.dawnMinutes) },
                    set: { draft.dawnMinutes = Int($0.rounded()) }
                ), in: 0...40, step: 5)
                .tint(Color.dawnAmber)

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(DawnSky.gradient(at: Double(draft.dawnMinutes) / 40.0))
                    .frame(height: 34)
                    .overlay(alignment: .trailing) {
                        Image(systemName: "sunrise.fill")
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.trailing, 10)
                    }

                Text("闹钟响之前，屏幕会先用 \(max(draft.dawnMinutes, 0)) 分钟从深夜蓝推到晨金色，让皮质醇先一步上涌。")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    // MARK: 代价

    private var stakeSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    sectionTitle("代价模式", systemImage: "yensign.circle")
                    Spacer()
                    Toggle("", isOn: $stakeEnabled)
                        .labelsHidden()
                        .tint(Color.dawnAmber)
                }

                if stakeEnabled {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("承诺金额 ¥\(Int(stakeAmount))")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        Slider(value: $stakeAmount, in: 20...500, step: 10)
                            .tint(Color.dawnRose)
                        HStack(spacing: 6) {
                            ForEach(Stake.presets, id: \.self) { v in
                                Button("¥\(v)") {
                                    stakeAmount = Double(v)
                                    haptic()
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background { Capsule().fill(Color.white.opacity(0.09)) }
                                .buttonStyle(.plain)
                            }
                        }

                        Text("没完成晨间仪式链，这笔钱按下面方式处理：")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.45))

                        ForEach(StakeRecipient.allCases, id: \.self) { r in
                            let selected = draft.stake?.recipient == r
                            Button {
                                draft.stake = Stake(amount: Int(stakeAmount), recipient: r)
                                haptic()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: r.symbol)
                                        .foregroundStyle(selected ? Color.dawnRose : Color.white.opacity(0.55))
                                        .frame(width: 22)
                                    Text(r.name)
                                        .font(.system(size: 14))
                                        .foregroundStyle(.white)
                                    Spacer()
                                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selected ? Color.dawnRose : Color.white.opacity(0.25))
                                }
                                .padding(9)
                                .background {
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .fill(selected ? Color.dawnRose.opacity(0.14) : Color.clear)
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        Text("贪睡一次 ×1.6：¥\(Int(stakeAmount)) → ¥\(Int(round(stakeAmount * 1.6))) → ¥\(Int(round(stakeAmount * 1.6 * 1.6)))")
                            .font(.caption)
                            .foregroundStyle(Color.dawnRose.opacity(0.9))
                    }
                } else {
                    Text("不押任何代价。适合休息日，也适合还不想对自己太狠的时候。")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
    }

    // MARK: 仪式链

    private var ritualSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    sectionTitle("晨间仪式链", systemImage: "figure.walk")
                    Spacer()
                    Button("换一套") {
                        draft.ritual = RitualChain.presets.randomElement() ?? draft.ritual
                        haptic()
                    }
                    .font(.caption)
                    .foregroundStyle(Color.dawnAmber)
                }

                ForEach(Array(draft.ritual.steps.enumerated()), id: \.offset) { i, step in
                    HStack(spacing: 10) {
                        Text("\(i + 1)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.black.opacity(0.8))
                            .frame(width: 20, height: 20)
                            .background { Circle().fill(Color.dawnAmber.opacity(0.9)) }
                        Text(step)
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.9))
                        Spacer()
                    }
                }

                Text("三者全勾才算一次真正的「起床成功」——身体先于意志走完一段物理路径。")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    private var saveButton: some View {
        GlassButton(title: "保存并登记到系统闹钟", systemImage: "alarm", tint: .dawnAmber, role: .primary) {
            draft.stake = stakeEnabled ? Stake(amount: Int(stakeAmount), recipient: draft.stake?.recipient ?? .plant) : nil
            if editing == nil {
                draft.id = UUID()
                draft.createdAt = .now
                store.add(draft)
            } else {
                store.update(draft)
            }
            Task { await engine.sync(draft) }
            haptic(style: .medium)
            dismiss()
        }
    }

    // MARK: 辅助

    private func sectionTitle(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage).font(.system(size: 12, weight: .semibold))
            Text(text).font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(.white.opacity(0.6))
    }

    private func haptic(style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
