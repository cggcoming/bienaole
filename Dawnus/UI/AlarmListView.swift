import SwiftUI

struct AlarmListView: View {
    @Environment(AlarmStore.self) private var store
    @Environment(AlarmEngine.self) private var engine
    @State private var showEditor = false
    @State private var editing: DawnusAlarm? = nil
    @State private var now = Date()

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: 16) {
                    heroSection
                    if engine.authorization != .authorized { authBanner }
                    if let err = engine.lastError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(Color(hex: 0xFF8A8A))
                            .multilineTextAlignment(.center)
                    }
                    alarmList
                    Spacer(minLength: 90)
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
            }

            Button {
                editing = nil
                showEditor = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.85))
                    .frame(width: 58, height: 58)
                    .background { Circle().fill(Color.dawnAmber) }
                    .shadow(color: Color.dawnAmber.opacity(0.45), radius: 14, y: 5)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 22)
            .padding(.bottom, 26)
        }
        .sheet(isPresented: $showEditor) {
            AlarmEditorView(editing: editing)
        }
        .onReceive(ticker) { now = $0 }
    }

    // MARK: 顶部时钟

    private var heroSection: some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(now, format: .dateTime.hour().minute())
                        .font(.dawnTime(46))
                        .foregroundStyle(.white)
                    Text(now, format: .dateTime.second())
                        .font(.dawnTime(18))
                        .foregroundStyle(.white.opacity(0.45))
                    Spacer()
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.35))
                }

                Divider().overlay(Color.white.opacity(0.10))

                if let next = nextAlarm {
                    HStack(spacing: 12) {
                        RingProgress(
                            progress: dawnProgress(for: next),
                            lineWidth: 5,
                            gradient: [Color.dawnAmber.opacity(0.7), Color.dawnGold],
                            size: 44
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text("下一个 · \(next.label)")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                            Text(countdownText(for: next))
                                .font(.system(size: 12.5))
                                .foregroundStyle(.white.opacity(0.6))
                                .monospacedDigit()
                        }
                        Spacer()
                        Text(next.timeText)
                            .font(.dawnTime(24))
                            .foregroundStyle(.white)
                    }
                } else {
                    Text("现在没有开启的闹钟")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
    }

    // MARK: 授权提示

    private var authBanner: some View {
        GlassCard(tint: Color.dawnRose.opacity(0.16), padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "bell.badge")
                        .foregroundStyle(.orange)
                    Text("还没拿到系统闹钟权限")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text("不授权的话，闹钟只能在 App 内响，会被静音开关挡住，也不会出现在锁屏和灵动岛上。")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                Button {
                    Task { await engine.requestAuthorization() }
                } label: {
                    Text("授予闹钟权限")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.85))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background { Capsule().fill(Color.dawnAmber) }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: 列表

    private var alarmList: some View {
        @Bindable var store = store
        return VStack(spacing: 12) {
            ForEach($store.alarms) { $alarm in
                AlarmCard(
                    alarm: $alarm,
                    onEdit: { editing = alarm; showEditor = true },
                    onDelete: {
                        Task { await engine.unschedule(alarm.id) }
                        store.remove(alarm.id)
                    },
                    onToggle: {
                        store.toggle(alarm.id)
                        Task { await engine.sync(store.alarm(for: alarm.id) ?? alarm) }
                    },
                    onPreview: {
                        engine.triggerPreview(alarm: alarm, store: store)
                    }
                )
            }
        }
    }

    // MARK: 计算

    private var nextAlarm: DawnusAlarm? {
        store.alarms
            .filter { $0.isOn }
            .sorted { $0.nextFireDate(from: now) < $1.nextFireDate(from: now) }
            .first
    }

    /// 距离下一次响铃还差多久
    private func countdownText(for alarm: DawnusAlarm) -> String {
        let fire = alarm.nextFireDate(from: now)
        let gap = fire.timeIntervalSince(now)
        guard gap > 0 else { return "即将响起" }
        let h = Int(gap) / 3600
        let m = (Int(gap) % 3600) / 60
        if h >= 24 { let d = h / 24; return "还有 \(d) 天" }
        return h > 0 ? "还有 \(h) 小时 \(m) 分" : "还有 \(m) 分"
    }

    /// 已经进入渐醒窗口的比例：用闹钟的 dawnMinutes 当窗口长度
    private func dawnProgress(for alarm: DawnusAlarm) -> Double {
        let window = Double(alarm.dawnMinutes * 60)
        guard window > 0 else { return 1 }
        let gap = alarm.nextFireDate(from: now).timeIntervalSince(now)
        guard gap <= window else { return 0 }
        return 1 - (gap / window)
    }
}

// MARK: - 单个闹钟卡片

private struct AlarmCard: View {
    @Binding var alarm: DawnusAlarm
    var onEdit: () -> Void
    var onDelete: () -> Void
    var onToggle: () -> Void
    var onPreview: () -> Void

    var body: some View {
        GlassCard(padding: 14) {
            VStack(spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(alarm.timeText)
                                .font(.dawnTime(30))
                                .foregroundStyle(alarm.isOn ? .white : .white.opacity(0.35))
                            Text(alarm.periodText)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        Text(alarm.label)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(alarm.isOn ? .white.opacity(0.85) : .white.opacity(0.35))
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { alarm.isOn },
                        set: { _ in onToggle() }
                    ))
                    .labelsHidden()
                    .tint(.dawnAmber)
                }

                HStack(spacing: 6) {
                    GlassPill(text: alarm.repeatText, systemImage: "repeat")
                    GlassPill(text: alarm.difficulty.name, systemImage: alarm.difficulty.symbol,
                              tint: .dawnAmber.opacity(0.9))
                    if let stake = alarm.stake {
                        GlassPill(text: stake.line, systemImage: "yensign", tint: Color(hex: 0xFF9A8A))
                    }
                    if alarm.dawnMinutes > 0 {
                        GlassPill(text: "渐醒 \(alarm.dawnMinutes)′", systemImage: "sun.horizon",
                                  tint: Color.dawnCyan.opacity(0.9))
                    }
                    Spacer(minLength: 0)
                }

                if alarm.streak > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill").foregroundStyle(.orange)
                        Text("连续打卡 \(alarm.streak) 天")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer()
                    }
                }

                HStack(spacing: 8) {
                    Button { onPreview() } label: {
                        Label("试一下", systemImage: "play.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background { Capsule().fill(Color.white.opacity(0.10)) }
                    }
                    .buttonStyle(.plain)

                    Button { onEdit() } label: {
                        Label("编辑", systemImage: "slider.horizontal.3")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background { Capsule().fill(Color.white.opacity(0.10)) }
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button(role: .destructive) { onDelete() } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: 0xFF8A8A).opacity(0.9))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .opacity(alarm.isOn ? 1 : 0.62)
    }
}
