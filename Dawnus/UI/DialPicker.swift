import SwiftUI
import UIKit

/// 双环径向拨盘：外环调小时，内环调分钟。
///
/// 为什么不用系统滚轮：半梦半醒的时候，手指在圆环上「划一道弧」比在矩形滚轮里
/// 精确点选要容易得多——圆形没有边界，抬手就吸附到最近刻度。
struct DialTimePicker: View {
    @Binding var hour: Int
    @Binding var minute: Int

    /// 吸附到的分钟粒度（0 = 不吸附）
    var minuteStep: Int = 1

    private enum Ring { case hour, minute }

    @State private var activeRing: Ring? = nil
    @State private var lastHourAngle: Double = 0
    @State private var lastMinuteAngle: Double = 0
    @State private var dragging = false

    private let outerBand: CGFloat = 46

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let outerR = size / 2 - 16
            let innerR = max(outerR - outerBand - 14, 40)

            ZStack {
                // 外环轨道
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: outerBand)
                    .frame(width: outerR * 2, height: outerR * 2)

                // 内环轨道
                Circle()
                    .stroke(Color.white.opacity(0.06), lineWidth: outerBand * 0.72)
                    .frame(width: innerR * 2, height: innerR * 2)

                // 刻度
                Canvas { ctx, _ in
                    // 小时刻度：每 2 小时一根，每 6 小时一根长线
                    for h in 0..<24 {
                        let a = angle(value: Double(h), total: 24)
                        let long = h % 6 == 0
                        let inner = outerR - outerBand / 2 + 4
                        let outer = outerR + outerBand / 2 - (long ? 6 : 10)
                        ctx.stroke(
                            Path { p in
                                p.move(to: point(center: center, radius: inner, angle: a))
                                p.addLine(to: point(center: center, radius: outer, angle: a))
                            },
                            with: .color(.white.opacity(long ? 0.5 : 0.18)),
                            lineWidth: long ? 2 : 1
                        )
                    }
                    // 分钟刻度：每 5 分钟一根
                    let band = outerBand * 0.72
                    for m in stride(from: 0, to: 60, by: 5) {
                        let a = angle(value: Double(m), total: 60)
                        let long = m % 15 == 0
                        let inner = innerR - band / 2 + 4
                        let outer = innerR + band / 2 - (long ? 5 : 9)
                        ctx.stroke(
                            Path { p in
                                p.move(to: point(center: center, radius: inner, angle: a))
                                p.addLine(to: point(center: center, radius: outer, angle: a))
                            },
                            with: .color(Color.dawnCyan.opacity(long ? 0.55 : 0.2)),
                            lineWidth: long ? 2 : 1
                        )
                    }
                }

                // 小时弧：从 0 点画到当前小时
                Circle()
                    .trim(from: 0, to: Double(hour) / 24 + (dragging && activeRing == .hour ? 0.001 : 0))
                    .stroke(
                        AngularGradient(
                            colors: [Color.dawnAmber.opacity(0.35), Color.dawnAmber],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: outerBand, lineCap: .butt)
                    )
                    .frame(width: outerR * 2, height: outerR * 2)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.18), value: hour)

                // 分钟弧
                Circle()
                    .trim(from: 0, to: Double(minute) / 60)
                    .stroke(
                        AngularGradient(
                            colors: [Color.dawnCyan.opacity(0.3), Color.dawnCyan],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: outerBand * 0.72, lineCap: .butt)
                    )
                    .frame(width: innerR * 2, height: innerR * 2)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.18), value: minute)

                // 两个把手
                handle(center: center, radius: outerR, value: Double(hour), total: 24, color: .dawnAmber)
                handle(center: center, radius: innerR, value: Double(minute), total: 60, color: .dawnCyan, small: true)

                // 中心读数
                VStack(spacing: 2) {
                    Text(String(format: "%d:%02d", hour, minute))
                        .font(.dawnTime(size / 6.2))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text(hour < 12 ? "上午" : "下午")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        let p = value.location
                        let dx = p.x - center.x
                        let dy = p.y - center.y
                        let dist = sqrt(dx * dx + dy * dy)

                        // 第一次移动时决定拨哪个环，之后锁定，避免中途跳环
                        if activeRing == nil {
                            activeRing = abs(dist - outerR) < abs(dist - innerR) ? .hour : .minute
                            dragging = true
                            lastHourAngle = angleFromPoint(dx: dx, dy: dy)
                            lastMinuteAngle = lastHourAngle
                            return
                        }

                        let current = angleFromPoint(dx: dx, dy: dy)
                        guard let ring = activeRing else { return }

                        if ring == .hour {
                            let delta = shortestDelta(from: lastHourAngle, to: current)
                            // 每 15° 一小时；累积够一个刻度就走一格
                            let steps = Int(round((delta * 24 / (2 * .pi))))
                            if steps != 0 {
                                hour = (hour + steps + 24) % 24
                                lastHourAngle = current
                                haptic()
                            }
                        } else {
                            let delta = shortestDelta(from: lastMinuteAngle, to: current)
                            let step = max(1, minuteStep)
                            let rawMinutes = Int(round(delta * 60 / (2 * .pi)))
                            if rawMinutes != 0 {
                                let snapped = rawMinutes / step * step
                                if snapped != 0 {
                                    minute = (minute + snapped + 60) % 60
                                    lastMinuteAngle = current
                                    haptic()
                                }
                            }
                        }
                    }
                    .onEnded { _ in
                        activeRing = nil
                        dragging = false
                    }
            )
            // VoiceOver 上下滑也能调时间：分钟档 1 分，小时档 1 小时
            .focusable()
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: minute = (minute + 1) % 60
                case .decrement: minute = (minute + 59) % 60
                @unknown default: break
                }
                haptic()
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("时间拨盘")
        .accessibilityValue("\(hour) 点 \(minute) 分")
    }

    // MARK: 绘制辅助

    private func handle(center: CGPoint, radius: CGFloat, value: Double, total: Double, color: Color, small: Bool = false) -> some View {
        let a = angle(value: value, total: total)
        let p = point(center: center, radius: radius, angle: a)
        return Circle()
            .fill(.white)
            .frame(width: small ? 16 : 20, height: small ? 16 : 20)
            .shadow(color: color, radius: small ? 8 : 12)
            .overlay {
                Circle()
                    .stroke(color, lineWidth: small ? 3 : 4)
                    .frame(width: small ? 16 : 20, height: small ? 16 : 20)
            }
            .position(p)
            .animation(.easeOut(duration: 0.18), value: value)
    }

    /// 顶部为 0，顺时针增长，返回弧度
    private func angle(value: Double, total: Double) -> Double {
        value / total * 2 * .pi
    }

    private func point(center: CGPoint, radius: CGFloat, angle: Double) -> CGPoint {
        // 顶部为 0，顺时针：x = sin, y = -cos
        CGPoint(
            x: center.x + radius * CGFloat(sin(angle)),
            y: center.y - radius * CGFloat(cos(angle))
        )
    }

    /// 从拖拽点算出角度（顶部 0，顺时针 0…2π）
    private func angleFromPoint(dx: CGFloat, dy: CGFloat) -> Double {
        var a = atan2(Double(dx), Double(-dy))
        if a < 0 { a += 2 * .pi }
        return a
    }

    /// 处理 ±π 跨越的最短角差
    private func shortestDelta(from: Double, to: Double) -> Double {
        var d = to - from
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        return d
    }

    private func haptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
