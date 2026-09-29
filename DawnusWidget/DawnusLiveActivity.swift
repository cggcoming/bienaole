import AlarmKit
import SwiftUI
import WidgetKit

@main
struct DawnusWidgetBundle: WidgetBundle {
    var body: some Widget {
        DawnusAlarmLiveActivity()
    }
}

// MARK: - 实时活动 / 灵动岛

/// AlarmKit 要求 App 提供 Live Activity 来渲染 Countdown（渐醒倒计时）与 Paused 状态。
/// 这里同时接管锁屏、灵动岛、StandBy 三种呈现。
struct DawnusAlarmLiveActivity: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<DawnusMetadata>.self) { context in
            lockScreen(context: context)
        } dynamicIsland: { context in
            dynamicIsland(context: context)
        }
    }

    // MARK: 锁屏 / StandBy

    @ViewBuilder
    private func lockScreen(context: ActivityViewContext<AlarmAttributes<DawnusMetadata>>) -> some View {
        let meta = resolvedMetadata(context.attributes)
        let state = context.state

        HStack(spacing: 14) {
            DawnGlyph(progress: progress(of: state), tint: context.attributes.tintColor ?? .orange)
                .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text(meta.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(secondaryLine(state: state, meta: meta))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !meta.stakeLine.contains("无代价") {
                    Text(meta.stakeLine)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "sunrise.fill")
                .foregroundStyle(.orange)
        }
        .padding(16)
        .activityBackgroundTint(Color(red: 0.07, green: 0.08, blue: 0.12))
        .activitySystemActionForegroundColor(.white)
    }

    // MARK: 灵动岛

    private func dynamicIsland(context: ActivityViewContext<AlarmAttributes<DawnusMetadata>>)
        -> DynamicIsland
    {
        let meta = resolvedMetadata(context.attributes)
        let state = context.state
        let tint = context.attributes.tintColor ?? .orange

        return DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(meta.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(secondaryLine(state: state, meta: meta))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.leading, 4)
            }
            DynamicIslandExpandedRegion(.trailing) {
                DawnGlyph(progress: progress(of: state), tint: tint)
                    .frame(width: 44, height: 44)
                    .padding(.trailing, 4)
            }
            DynamicIslandExpandedRegion(.bottom) {
                HStack(spacing: 6) {
                    Image(systemName: "sunrise.fill")
                    Text(meta.stakeLine)
                        .font(.caption2)
                    Spacer()
                    ForEach(meta.ritualPreview.components(separatedBy: " → "), id: \.self) { step in
                        Text(step).font(.caption2).foregroundStyle(.white.opacity(0.65))
                    }
                }
                .foregroundStyle(.orange)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            }
        } compactLeading: {
            Image(systemName: "sunrise.fill")
                .foregroundStyle(tint)
                .padding(.leading, 4)
        } compactTrailing: {
            DawnGlyph(progress: progress(of: state), tint: tint, lineWidth: 3)
                .frame(width: 16, height: 16)
                .padding(.trailing, 4)
        } minimal: {
            Image(systemName: "sunrise.fill")
                .foregroundStyle(tint)
        }
        .widgetURL(URL(string: "dawnus://ring"))
        .keylineTint(tint)
    }

    // MARK: 辅助

    /// AlarmAttributes 的 metadata 是可选的，缺失时给一个安全的占位，避免整个实时活动崩掉。
    private func resolvedMetadata(_ attributes: AlarmAttributes<DawnusMetadata>) -> DawnusMetadata {
        attributes.metadata ?? DawnusMetadata(
            alarmID: "",
            title: "拂晓",
            stakeLine: "无代价模式",
            difficultyRaw: "gentle",
            dawnMinutes: 20,
            ritualPreview: ""
        )
    }

    private func progress(of state: AlarmPresentationState) -> Double {
        guard case .countdown(let cd) = state.mode else { return 1 }
        let total = cd.totalCountdownDuration
        guard total > 0 else { return 1 }
        let elapsed = cd.previouslyElapsedDuration + Date.now.timeIntervalSince(cd.startDate ?? .now)
        return min(max(elapsed / total, 0), 1)
    }

    private func secondaryLine(state: AlarmPresentationState, meta: DawnusMetadata) -> String {
        switch state.mode {
        case .alert:
            return "该起了 · \(meta.difficultyRaw)"
        case .countdown(let cd):
            let remain = max(0, cd.totalCountdownDuration - cd.previouslyElapsedDuration)
            let minutes = Int(ceil(remain / 60))
            return minutes > 0 ? "渐醒中 · 还有 \(minutes) 分钟" : "就要响了"
        case .paused:
            return "渐醒已暂停"
        @unknown default:
            return meta.title
        }
    }
}

/// 一个随着渐醒进度「从暗到亮」的圆，视觉上就是日出。
struct DawnGlyph: View {
    var progress: Double
    var tint: Color
    var lineWidth: Double = 4

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [.orange, .yellow, .orange.opacity(0.6)],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Circle()
                .fill(tint.opacity(0.25 + 0.5 * progress))
                .frame(width: 8 + 10 * progress, height: 8 + 10 * progress)
        }
        .animation(.easeInOut, value: progress)
    }
}
