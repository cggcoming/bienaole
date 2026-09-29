import SwiftUI

/// iOS 26 的 Liquid Glass 封装。
/// 全站统一玻璃质感：深色底 + 极低透明度 tint + 圆角，让内容「浮」在渐变的天空上。
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 22
    var tint: Color = Color.white.opacity(0.07)
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .glassEffect(.regular.tint(tint), in: .rect(cornerRadius: cornerRadius))
    }
}

/// 一枚会发光的玻璃按钮
struct GlassButton: View {
    var title: String
    var systemImage: String? = nil
    var tint: Color = .white
    var role: Role = .plain
    var action: () -> Void

    enum Role { case plain, primary, danger }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .fontWeight(.semibold)
            }
            .font(.system(size: 16))
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background {
                if role == .primary {
                    Capsule().fill(tint)
                } else {
                    Capsule().fill(Color.white.opacity(0.10))
                }
            }
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var foregroundColor: Color {
        switch role {
        case .plain:   return .white
        case .primary: return .black.opacity(0.85)
        case .danger:  return Color(hex: 0xFF6B6B)
        }
    }
}

/// 玻璃药丸标签
struct GlassPill: View {
    var text: String
    var systemImage: String? = nil
    var tint: Color = .white.opacity(0.72)

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            Capsule().fill(Color.white.opacity(0.09))
        }
    }
}

/// 一个 -90° 起笔的环形进度，用来当「渐醒进度环」和「起床率环」
struct RingProgress: View {
    var progress: Double
    var lineWidth: CGFloat = 8
    var gradient: [Color] = [Color.dawnAmber, Color.dawnGold]
    var label: String? = nil
    var caption: String? = nil
    var size: CGFloat = 108

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(
                    AngularGradient(colors: gradient, center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.5), value: progress)

            if let label {
                VStack(spacing: 2) {
                    Text(label)
                        .font(.system(size: size / 4.4, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    if let caption {
                        Text(caption)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
    }
}
