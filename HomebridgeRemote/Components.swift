import SwiftUI

/// Dark, softly glowing background shared by every screen.
struct Backdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.05, blue: 0.11), Color(red: 0.09, green: 0.06, blue: 0.19)],
                startPoint: .top, endPoint: .bottom
            )
            Circle().fill(Color.blue.opacity(0.28)).frame(width: 320).blur(radius: 90).offset(x: -140, y: -280)
            Circle().fill(Color.purple.opacity(0.24)).frame(width: 300).blur(radius: 90).offset(x: 150, y: 300)
        }
        .ignoresSafeArea()
    }
}

/// Frosted-glass card tinted with the device's current colour.
struct CardBackground: View {
    var tint: Color

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
        shape
            .fill(.ultraThinMaterial)
            .overlay(
                LinearGradient(colors: [tint.opacity(0.38), tint.opacity(0.04)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .clipShape(shape)
            )
            .overlay(shape.strokeBorder(.white.opacity(0.14), lineWidth: 1))
            .shadow(color: tint.opacity(0.25), radius: 24, y: 10)
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
                .background(Circle().fill(isOn ? tint : Color.white.opacity(0.10)))
                .overlay(Circle().strokeBorder(.white.opacity(isOn ? 0.35 : 0.12), lineWidth: 1))
                .shadow(color: isOn ? tint.opacity(0.85) : .clear, radius: 16)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .medium), trigger: isOn)
        .animation(.smooth, value: isOn)
    }
}

struct RoundStepButton: View {
    var symbol: String
    var enabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 52, height: 52)
                .background(Circle().fill(.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .sensoryFeedback(.selection, trigger: enabled)
    }
}
