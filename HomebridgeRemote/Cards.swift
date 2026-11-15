import SwiftUI

/// Picks the right card for a device and handles rename / remove.
struct DeviceCard: View {
    let saved: SavedDevice
    @Environment(Hub.self) private var hub
    @State private var renaming = false
    @State private var newName = ""

    var body: some View {
        Group {
            if let acc = hub.live[saved.id] {
                if let airco = hub.airco(for: acc.id) {
                    AircoCard(airco: airco, name: saved.name)
                } else if acc.isClimate {
                    ClimateCard(acc: acc, name: saved.name)
                } else {
                    ToggleCard(acc: acc, name: saved.name)
                }
            } else {
                PlaceholderCard(name: saved.name, failed: hub.error != nil)
            }
        }
        .contextMenu {
            Button("Rename", systemImage: "pencil") { newName = saved.name; renaming = true }
            Button("Remove", systemImage: "trash", role: .destructive) { hub.remove(saved.id) }
        }
        .alert("Rename", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Save") { hub.rename(saved.id, to: newName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This is the name Siri listens for.")
        }
    }
}

struct PlaceholderCard: View {
    let name: String
    let failed: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.title3.weight(.semibold))
                Text(failed ? "Can't reach Homebridge" : "Connecting…")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if !failed { ProgressView() }
        }
        .padding(20)
        .background(CardBackground(tint: .gray))
    }
}

// MARK: - Air conditioner / thermostat

struct ClimateCard: View {
    let acc: Accessory
    let name: String
    @Environment(Hub.self) private var hub

    private static let modes: [(value: Int, label: String, symbol: String)] = [
        (0, "Auto", "sparkles"), (1, "Heat", "flame.fill"), (2, "Cool", "snowflake"),
    ]

    private var tint: Color {
        guard acc.isOn else { return .gray }
        switch acc.mode {
        case 1: return .orange
        case 2: return .cyan
        case 0: return .mint
        default: return .blue
        }
    }

    private var step: Double { max(acc.steps[acc.targetKey ?? ""] ?? 1, 0.5) }
    private var range: ClosedRange<Double> { acc.ranges[acc.targetKey ?? ""] ?? 16...30 }

    private var status: String {
        guard acc.isOn else { return "Off" }
        let m = Self.modes.first { $0.value == acc.mode }?.label
        return [m, acc.targetTemp.map { "target \(format($0))" }]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private func format(_ v: Double) -> String { String(format: "%.1f°", v) }

    private func adjust(_ delta: Double) {
        guard let key = acc.targetKey, let t = acc.targetTemp else { return }
        hub.send(acc.id, key, min(max(t + delta, range.lowerBound), range.upperBound))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(name, systemImage: acc.symbol).font(.title3.weight(.semibold))
                    Text(status).font(.subheadline).foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }
                Spacer()
                PowerButton(isOn: acc.isOn, tint: tint) { hub.setPower(acc.id, on: !acc.isOn) }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let current = acc.currentTemp {
                    Text(format(current))
                        .font(.system(size: 64, weight: .thin, design: .rounded))
                        .contentTransition(.numericText())
                    Text("now").font(.subheadline).foregroundStyle(.secondary)
                } else if let target = acc.targetTemp {
                    Text(format(target))
                        .font(.system(size: 64, weight: .thin, design: .rounded))
                        .contentTransition(.numericText())
                }
            }

            HStack(spacing: 14) {
                RoundStepButton(symbol: "minus", enabled: acc.isOn && (acc.targetTemp ?? 0) > range.lowerBound) {
                    adjust(-step)
                }
                VStack(spacing: 2) {
                    Text("Target").font(.caption).foregroundStyle(.secondary)
                    Text(acc.targetTemp.map(format) ?? "–")
                        .font(.title2.weight(.semibold).monospacedDigit())
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity)
                RoundStepButton(symbol: "plus", enabled: acc.isOn && (acc.targetTemp ?? 99) < range.upperBound) {
                    adjust(step)
                }
            }

            if let key = acc.modeKey {
                HStack(spacing: 10) {
                    ForEach(Self.modes, id: \.value) { m in
                        let selected = acc.mode == m.value
                        Button {
                            hub.send(acc.id, key, Double(m.value))
                        } label: {
                            Label(m.label, systemImage: m.symbol)
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Capsule().fill(selected ? tint.opacity(0.85) : .white.opacity(0.10)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .disabled(!acc.isOn)
            }
        }
        .padding(22)
        .background(CardBackground(tint: tint))
        .opacity(acc.isOn ? 1 : 0.92)
        .animation(.smooth, value: acc)
    }
}

// MARK: - Everything else with an on/off state

struct ToggleCard: View {
    let acc: Accessory
    let name: String
    @Environment(Hub.self) private var hub

    private var tint: Color { acc.isOn ? .yellow : .gray }

    var body: some View {
        Button { hub.setPower(acc.id, on: !acc.isOn) } label: {
            HStack(spacing: 16) {
                Image(systemName: acc.symbol)
                    .font(.system(size: 24))
                    .foregroundStyle(acc.isOn ? .white : .white.opacity(0.7))
                    .frame(width: 58, height: 58)
                    .background(Circle().fill(acc.isOn ? tint.opacity(0.85) : .white.opacity(0.10)))
                    .shadow(color: acc.isOn ? tint.opacity(0.8) : .clear, radius: 14)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.headline)
                    Text(acc.isOn ? "On" : "Off").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(18)
            .background(CardBackground(tint: tint))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: acc.isOn)
        .animation(.smooth, value: acc.isOn)
    }
}
