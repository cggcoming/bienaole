import Charts
import SwiftUI

/// 数据页：把「起床」这件事量化。
/// 起床率、连续天数、被扣金额、近 7 天柱状图、流水。
struct StatsView: View {
    @Environment(AlarmStore.self) private var store

    private var rate: Double { WakeBrain.successRate(store.ledger) }
    private var streak: Int { WakeBrain.currentStreak(store.ledger) }
    private var lostTotal: Int { store.ledger.reduce(0) { $0 + $1.amount } }
    private var keptCount: Int { store.ledger.filter { $0.outcome == .kept }.count }
    private var buckets: [WakeBrain.DayBucket] { WakeBrain.lastSevenDays(store.ledger) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                summarySection
                weekSection
                ledgerSection
                Spacer(minLength: 30)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
        }
    }

    // MARK: 概览

    private var summarySection: some View {
        GlassCard {
            HStack(spacing: 18) {
                RingProgress(
                    progress: rate,
                    lineWidth: 11,
                    gradient: [Color(hex: 0xFF7A5C), Color.dawnGold],
                    label: "\(Int(rate * 100))%",
                    caption: "起床率",
                    size: 116
                )
                VStack(alignment: .leading, spacing: 12) {
                    StatLine(title: "连续打卡", value: "\(streak) 天", systemImage: "flame.fill", tint: .orange)
                    StatLine(title: "守住承诺", value: "\(keptCount) 次", systemImage: "checkmark.seal", tint: Color.dawnGold)
                    StatLine(title: "累计被扣", value: "¥\(lostTotal)", systemImage: "yensign", tint: Color(hex: 0xFF9A8A))
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: 近 7 天

    private var weekSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 12, weight: .semibold))
                    Text("近 7 天")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.6))

                Chart(buckets) { bucket in
                    BarMark(
                        x: .value("星期", bucket.label),
                        y: .value("起床", bucket.kept ? 1 : 0)
                    )
                    .foregroundStyle(
                        bucket.kept
                            ? AnyShapeStyle(LinearGradient(colors: [Color.dawnAmber, Color.dawnGold], startPoint: .bottom, endPoint: .top))
                            : AnyShapeStyle(Color.white.opacity(0.12))
                    )
                    .cornerRadius(5)
                }
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                }
                .frame(height: 130)

                Text("白色柱 = 当天没完成仪式链（或没设闹钟）")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    // MARK: 流水

    private var ledgerSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 12, weight: .semibold))
                    Text("账本")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.6))

                if store.ledger.isEmpty {
                    Text("还没有记录。走完一次闹钟流程就会出现在这里。")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.vertical, 8)
                } else {
                    ForEach(store.ledger.prefix(20)) { entry in
                        LedgerRow(entry: entry)
                        if entry.id != store.ledger.prefix(20).last?.id {
                            Divider().overlay(Color.white.opacity(0.08))
                        }
                    }
                }
            }
        }
    }
}

private struct StatLine: View {
    var title: String
    var value: String
    var systemImage: String
    var tint: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
    }
}

private struct LedgerRow: View {
    var entry: LedgerEntry

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.outcome == .kept ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(entry.outcome == .kept ? Color.dawnGold : Color(hex: 0xFF9A8A))
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.alarmLabel)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                Text(entry.date.formatted(date: .abbreviated, time: .shortened) + " · 贪睡 \(entry.snoozeCount) 次")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer()
            Text(entry.outcome == .kept ? "守约" : "−¥\(entry.amount)")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(entry.outcome == .kept ? Color.dawnGold : Color(hex: 0xFF9A8A))
        }
        .padding(.vertical, 2)
    }
}
