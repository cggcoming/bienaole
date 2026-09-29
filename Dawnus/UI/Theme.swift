import SwiftUI

// MARK: - 色板

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// 深夜：还没到点时的底色
    static let midnight    = Color(hex: 0x070A12)
    static let midnightTwo = Color(hex: 0x0E1420)
    /// 晨曦：渐醒推进到的底色
    static let dawnRose    = Color(hex: 0xFF7A5C)
    static let dawnAmber   = Color(hex: 0xFFB347)
    static let dawnGold    = Color(hex: 0xFFD98A)
    static let dawnCyan    = Color(hex: 0x5ED0E0)
}

// MARK: - 晨曦色彩引擎

/// 把「渐醒进度」映射成一片天空。
/// 这是整个 App 的核心视觉：闹钟响之前，屏幕会先慢慢亮起来。
enum DawnSky {
    struct Stop {
        var at: Double      // 0…1 进度
        var color: Color
    }

    /// 一段真实的日出色阶：深夜蓝 → 靛紫 → 玫红 → 琥珀 → 晨金
    static let stops: [Stop] = [
        Stop(at: 0.00, color: Color(hex: 0x05070F)),
        Stop(at: 0.18, color: Color(hex: 0x101B33)),
        Stop(at: 0.36, color: Color(hex: 0x2E2A55)),
        Stop(at: 0.54, color: Color(hex: 0x6B3A5B)),
        Stop(at: 0.70, color: Color(hex: 0xB9555A)),
        Stop(at: 0.84, color: Color(hex: 0xF08A4B)),
        Stop(at: 0.94, color: Color(hex: 0xFFC46B)),
        Stop(at: 1.00, color: Color(hex: 0xFFE9B8))
    ]

    /// 给定进度返回对应的天空色（分段线性插值）
    static func color(at progress: Double) -> Color {
        let p = min(max(progress, 0), 1)
        guard let first = stops.first, let last = stops.last else { return .black }
        if p <= first.at { return first.color }
        if p >= last.at { return last.color }
        for i in 0..<(stops.count - 1) {
            let a = stops[i], b = stops[i + 1]
            if p >= a.at && p <= b.at {
                let t = (p - a.at) / max(0.0001, b.at - a.at)
                return a.color.mix(with: b.color, by: t)
            }
        }
        return last.color
    }

    static func gradient(at progress: Double) -> LinearGradient {
        LinearGradient(
            colors: [
                color(at: max(0, progress - 0.12)),
                color(at: progress),
                color(at: min(1, progress + 0.08))
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// 太阳光晕的不透明度：进度越高越亮
    static func haloOpacity(at progress: Double) -> Double {
        0.10 + 0.55 * min(max(progress, 0), 1)
    }
}

// MARK: - 排版

extension Font {
    /// 大号时间显示（等宽数字，避免数字跳动）
    static func dawnTime(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
            .monospacedDigit()
    }

    static func dawnTitle(_ size: CGFloat = 22) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
}
