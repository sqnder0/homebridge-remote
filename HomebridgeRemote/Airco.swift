import SwiftUI

// The Fujitsu Airstage plugin publishes one air conditioner as a HeaterCooler
// plus a set of helper services named "<base> Dry Mode Switch", "<base> Fan", …
// `Airco` stitches them back together into one device.

enum AircoMode: Int, CaseIterable, Identifiable {
    case auto, cool, heat, dry, fan
    var id: Int { rawValue }

    var label: String {
        switch self {
        case .auto: "Auto"
        case .cool: "Cool"
        case .heat: "Heat"
        case .dry: "Dry"
        case .fan: "Fan"
        }
    }

    var symbol: String {
        switch self {
        case .auto: "arrow.triangle.2.circlepath"
        case .cool: "snowflake"
        case .heat: "sun.max.fill"
        case .dry: "drop.fill"
        case .fan: "fan.fill"
        }
    }

    var tint: Color {
        switch self {
        case .auto: Color(red: 0.36, green: 0.93, blue: 0.72)
        case .cool: Color(red: 0.25, green: 0.78, blue: 1.00)
        case .heat: Color(red: 1.00, green: 0.55, blue: 0.22)
        case .dry: Color(red: 0.55, green: 0.55, blue: 1.00)
        case .fan: Color(red: 0.72, green: 0.80, blue: 0.95)
        }
    }

    /// Colours for the temperature arc, cold end to warm end.
    var gradient: [Color] {
        switch self {
        case .heat: [Color(red: 1.0, green: 0.78, blue: 0.30), Color(red: 1.0, green: 0.42, blue: 0.20), Color(red: 0.95, green: 0.20, blue: 0.35)]
        case .cool: [Color(red: 0.55, green: 0.95, blue: 1.0), Color(red: 0.25, green: 0.70, blue: 1.0), Color(red: 0.35, green: 0.40, blue: 1.0)]
        default: [tint.opacity(0.7), tint, tint]
        }
    }

    /// Value for TargetHeaterCoolerState (only auto / heat / cool exist there).
    var hapValue: Double? {
        switch self {
        case .auto: 0
        case .heat: 1
        case .cool: 2
        default: nil
        }
    }
}

enum FanSpeed: Int, CaseIterable, Identifiable {
    case auto, quiet, low, medium, high
    var id: Int { rawValue }

    var label: String {
        switch self {
        case .auto: "Auto"
        case .quiet: "Quiet"
        case .low: "Low"
        case .medium: "Mid"
        case .high: "High"
        }
    }

    /// RotationSpeed the plugin maps to this speed.
    var percent: Double { Double(rawValue) * 25 }

    /// Degrees per second for the spinning fan icon.
    var spin: Double {
        let speeds: [Double] = [180, 120, 240, 420, 640]
        return speeds[rawValue]
    }

    static func from(percent p: Double) -> FanSpeed {
        if p <= 0 { return .auto }
        if p <= 25 { return .quiet }
        if p <= 50 { return .low }
        if p <= 75 { return .medium }
        return .high
    }
}

struct Airco {
    enum Part: String, CaseIterable {
        case dry = "Dry Mode Switch"
        case fanMode = "Fan Mode Switch"
        case autoFan = "Auto Fan Speed Switch"
        case powerful = "Powerful Switch"
        case economy = "Economy Switch"
        case energySavingFan = "Energy Saving Fan Switch"
        case minimumHeat = "Minimum Heat Mode Switch"
        case airflow = "Vertical Airflow Direction"
        case fan = "Fan"
        case thermostat = "Thermostat"
        case temperature = "Temperature"
    }

    let main: Accessory
    let parts: [Part: Accessory]

    init(main: Accessory, all: [Accessory]) {
        self.main = main
        let base = Self.baseName(main.name).lowercased()
        var found: [Part: Accessory] = [:]
        for part in Part.allCases {
            let wanted = base + " " + part.rawValue.lowercased()
            if let a = all.first(where: { $0.id != main.id && $0.name.lowercased() == wanted }) {
                found[part] = a
            }
        }
        parts = found
    }

    static func baseName(_ name: String) -> String {
        for suffix in [" Heater Cooler", " HeaterCooler"] where name.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return name
    }

    /// Every Homebridge service that belongs to this airco.
    var memberIDs: Set<String> { Set(parts.values.map(\.id)).union([main.id]) }

    func isOn(_ part: Part) -> Bool { parts[part]?.isOn ?? false }

    var isOn: Bool { main.isOn }

    var mode: AircoMode {
        if isOn(.dry) { return .dry }
        if isOn(.fanMode) { return .fan }
        switch main.mode {
        case 1: return .heat
        case 2: return .cool
        default: return .auto
        }
    }

    var availableModes: [AircoMode] {
        AircoMode.allCases.filter { m in
            switch m {
            case .dry: parts[.dry] != nil
            case .fan: parts[.fanMode] != nil
            default: main.modeKey != nil
            }
        }
    }

    var hasFanSpeed: Bool { main.writable.contains("RotationSpeed") }

    var fanSpeed: FanSpeed {
        if isOn(.autoFan) { return .auto }
        return FanSpeed.from(percent: main.values["RotationSpeed"] ?? 0)
    }

    var swing: Bool? { main.writable.contains("SwingMode") ? (main.values["SwingMode"] ?? 0) != 0 : nil }

    /// Louver position 1 (high) … 4 (low), from the airflow service.
    var airflowPosition: Int? {
        guard let a = parts[.airflow], let v = a.values["RotationSpeed"] else { return nil }
        return min(max(Int((v / 25).rounded(.up)), 1), 4)
    }

    var currentTemp: Double? { main.currentTemp ?? parts[.temperature]?.currentTemp }
    var targetTemp: Double? { main.targetTemp }
    var range: ClosedRange<Double> { main.ranges[main.targetKey ?? ""] ?? 16...30 }
    var step: Double { max(main.steps[main.targetKey ?? ""] ?? 0.5, 0.5) }

    /// What the unit is doing right now, in words.
    var activity: String {
        guard isOn else { return "Off" }
        switch mode {
        case .dry: return "Drying"
        case .fan: return "Fan only"
        default: break
        }
        switch Int(main.values["CurrentHeaterCoolerState"] ?? -1) {
        case 2: return "Heating"
        case 3: return "Cooling"
        case 1: return "Holding"
        default: return mode.label
        }
    }
}

func formatTemp(_ v: Double) -> String {
    v.rounded() == v ? String(format: "%.0f°", v) : String(format: "%.1f°", v)
}

// MARK: - Controls

extension Hub {
    func airco(for id: String) -> Airco? {
        guard let main = live[id], main.isHeaterCooler else { return nil }
        return Airco(main: main, all: Array(live.values))
    }

    func setMode(_ a: Airco, _ m: AircoMode) {
        var writes: [Write] = []
        if !a.isOn { writes.append(Write(id: a.main.id, key: "Active", value: 1)) }
        let dry = a.parts[.dry], fan = a.parts[.fanMode]
        switch m {
        case .dry:
            if let fan, fan.isOn { assume(fan.id, "On", 0) }
            if let dry { writes.append(Write(id: dry.id, key: "On", value: 1)) }
        case .fan:
            if let dry, dry.isOn { assume(dry.id, "On", 0) }
            if let fan { writes.append(Write(id: fan.id, key: "On", value: 1)) }
        default:
            if let dry, dry.isOn { assume(dry.id, "On", 0) }
            if let fan, fan.isOn { assume(fan.id, "On", 0) }
            if let key = a.main.modeKey, let v = m.hapValue {
                writes.append(Write(id: a.main.id, key: key, value: v))
            }
        }
        sendAll(writes)
    }

    func setTarget(_ a: Airco, _ value: Double) {
        guard let key = a.main.targetKey else { return }
        let v = min(max(value, a.range.lowerBound), a.range.upperBound)
        send(a.main.id, key, v)
    }

    func setFanSpeed(_ a: Airco, _ s: FanSpeed) {
        if s == .auto {
            if let auto = a.parts[.autoFan] {
                assume(a.main.id, "RotationSpeed", 0)
                send(auto.id, "On", 1)
            }
        } else {
            if let auto = a.parts[.autoFan], auto.isOn { assume(auto.id, "On", 0) }
            send(a.main.id, "RotationSpeed", s.percent)
        }
    }

    func setSwing(_ a: Airco, _ on: Bool) { send(a.main.id, "SwingMode", on ? 1 : 0) }

    func setAirflow(_ a: Airco, position: Int) {
        guard let flow = a.parts[.airflow] else { return }
        if a.swing == true { assume(a.main.id, "SwingMode", 0) }
        send(flow.id, "RotationSpeed", Double(position) * 25)
    }

    func toggle(_ a: Airco, _ part: Airco.Part) {
        guard let p = a.parts[part] else { return }
        send(p.id, "On", p.isOn ? 0 : 1)
    }
}
