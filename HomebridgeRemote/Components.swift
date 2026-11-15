import SwiftUI

/// Dark background with slowly drifting glows, tinted by what the airco is doing.
struct Backdrop: View {
    var tint: Color = .blue
    @State private var drift = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.03, green: 0.04, blue: 0.10), Color(red: 0.08, green: 0.05, blue: 0.17)],
                startPoint: .top, endPoint: .bottom
            )
            Circle().fill(tint.opacity(0.32)).frame(width: 360).blur(radius: 100)
                .offset(x: drift ? -110 : -170, y: drift ? -250 : -310)
            Circle().fill(Color.purple.opacity(0.22)).frame(width: 320).blur(radius: 100)
                .offset(x: drift ? 170 : 120, y: drift ? 330 : 270)
            Circle().fill(tint.opacity(0.12)).frame(width: 260).blur(radius: 90)
                .offset(x: drift ? 120 : 60, y: drift ? -40 : 30)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 1.2), value: tint)
        .onAppear {
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}

/// Frosted-glass card tinted with the device's current colour.
struct CardBackground: View {
    var tint: Color

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 32, style: .continuous)
        shape
            .fill(.ultraThinMaterial)
            .overlay(
                LinearGradient(colors: [tint.opacity(0.34), tint.opacity(0.03)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .clipShape(shape)
            )
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.05)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
            )
            .shadow(color: tint.opacity(0.25), radius: 26, y: 12)
    }
}

/// Shrinks a little while pressed.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct SectionTitle: View {
    var title: String
    var symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.footnote.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(.white.opacity(0.55))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Round glowing power button.
struct PowerButton: View {
    var isOn: Bool
    var tint: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "power")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(isOn ? .white : .white.opacity(0.7))
                .frame(width: 58, height: 58)
                .background(Circle().fill(isOn ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color.white.opacity(0.10))))
                .overlay(Circle().strokeBorder(.white.opacity(isOn ? 0.35 : 0.12), lineWidth: 1))
                .shadow(color: isOn ? tint.opacity(0.85) : .clear, radius: 16)
                .symbolEffect(.bounce, value: isOn)
        }
        .buttonStyle(PressableStyle())
        .sensoryFeedback(.impact(weight: .medium), trigger: isOn)
        .animation(.smooth, value: isOn)
    }
}

struct RoundStepButton: View {
    var symbol: String
    var enabled: Bool
    var action: () -> Void
    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 52, height: 52)
                .background(Circle().fill(.white.opacity(0.12)))
                .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .sensoryFeedback(.selection, trigger: taps)
    }
}

/// A fan icon that spins while the airco runs, faster at higher fan speeds.
struct SpinningFan: View {
    var degreesPerSecond: Double
    var active: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !active)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Image(systemName: "fan.fill")
                .rotationEffect(.degrees(active ? (t * degreesPerSecond).truncatingRemainder(dividingBy: 360) : 0))
        }
    }
}

/// Soft moving air lines drawn behind the airco card while it runs.
struct AirStream: View {
    var tint: Color
    var active: Bool
    var strength: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !active)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                for i in 0..<4 {
                    let line = CGFloat(i)
                    var path = Path()
                    let baseY: CGFloat = size.height * (0.18 + 0.2 * line)
                    let amplitude: CGFloat = 5 + 3 * line + 6 * CGFloat(strength)
                    let phase: CGFloat = CGFloat(t) * (1.2 + 0.4 * line) * CGFloat(0.6 + strength)
                    path.move(to: CGPoint(x: 0, y: baseY))
                    var x: CGFloat = 0
                    while x <= size.width {
                        let y = baseY + amplitude * sin(x / 55 + phase + line)
                        path.addLine(to: CGPoint(x: x, y: y))
                        x += 6
                    }
                    ctx.stroke(path, with: .color(tint.opacity(0.20 - 0.035 * Double(i))), lineWidth: 2)
                }
            }
        }
        .opacity(active ? 1 : 0)
        .animation(.easeInOut(duration: 0.8), value: active)
        .allowsHitTesting(false)
    }
}
