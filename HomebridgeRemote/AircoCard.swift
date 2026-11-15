import SwiftUI

struct AircoCard: View {
    let airco: Airco
    let name: String
    @Environment(Hub.self) private var hub
    @Namespace private var ns

    private var mode: AircoMode { airco.mode }
    private var tint: Color { airco.isOn ? mode.tint : Color(white: 0.55) }
    private var tempEnabled: Bool { airco.isOn && mode != .fan && airco.main.targetKey != nil }

    var body: some View {
        VStack(spacing: 24) {
            header
            ThermoDial(
                target: airco.targetTemp,
                current: airco.currentTemp,
                range: airco.range,
                step: airco.step,
                tint: tint,
                colors: airco.isOn ? mode.gradient : [Color(white: 0.5), Color(white: 0.6)],
                enabled: tempEnabled,
                commit: { hub.setTarget(airco, $0) }
            )
            modePicker
            if airco.hasFanSpeed { fanSection }
            if airco.swing != nil || airco.airflowPosition != nil { airflowSection }
            extrasSection
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .background {
            ZStack(alignment: .top) {
                CardBackground(tint: tint)
                AirStream(tint: tint, active: airco.isOn,
                          strength: Double(max(airco.fanSpeed.rawValue, 1)) / 4)
                    .frame(height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: airco.isOn)
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: mode)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: airco.fanSpeed)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: airco.airflowPosition)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(name)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                HStack(spacing: 7) {
                    StatusDot(color: tint, pulsing: airco.isOn)
                    Text(airco.activity)
                        .contentTransition(.interpolate)
                    if let room = airco.currentTemp {
                        Text("·")
                        Text("Room \(formatTemp(room))")
                            .contentTransition(.numericText(value: room))
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            PowerButton(isOn: airco.isOn, tint: tint) { hub.setPower(airco.main.id, on: !airco.isOn) }
        }
    }

    // MARK: Mode

    private var modePicker: some View {
        HStack(spacing: 4) {
            ForEach(airco.availableModes) { m in
                let selected = airco.isOn && m == mode
                Button { hub.setMode(airco, m) } label: {
                    VStack(spacing: 6) {
                        Image(systemName: m.symbol)
                            .font(.system(size: 18, weight: .semibold))
                            .symbolEffect(.bounce, value: selected)
                        Text(m.label).font(.caption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .foregroundStyle(selected ? Color.white : Color.white.opacity(0.6))
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(m.tint.gradient)
                                .shadow(color: m.tint.opacity(0.55), radius: 10)
                                .matchedGeometryEffect(id: "mode", in: ns)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white.opacity(0.07)))
        .sensoryFeedback(.selection, trigger: mode)
    }

    // MARK: Fan

    private var fanSection: some View {
        VStack(spacing: 10) {
            HStack {
                SectionTitle(title: "Fan", symbol: "wind")
                SpinningFan(degreesPerSecond: airco.fanSpeed.spin, active: airco.isOn)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
            }
            HStack(spacing: 4) {
                ForEach(FanSpeed.allCases) { s in
                    let selected = airco.fanSpeed == s
                    Button { hub.setFanSpeed(airco, s) } label: {
                        VStack(spacing: 5) {
                            FanBars(level: s.rawValue, highlighted: selected, tint: tint)
                            Text(s.label).font(.caption2.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .foregroundStyle(selected ? Color.white : Color.white.opacity(0.6))
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(.white.opacity(0.16))
                                    .matchedGeometryEffect(id: "fan", in: ns)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(5)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.07)))
            .sensoryFeedback(.selection, trigger: airco.fanSpeed)
        }
        .opacity(airco.isOn ? 1 : 0.5)
    }

    // MARK: Airflow

    private var airflowSection: some View {
        VStack(spacing: 10) {
            SectionTitle(title: "Airflow", symbol: "arrow.down.forward.and.arrow.up.backward")
            HStack(spacing: 8) {
                if let swing = airco.swing {
                    Button { hub.setSwing(airco, !swing) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.and.down")
                                .symbolEffect(.pulse, isActive: swing && airco.isOn)
                            Text("Swing")
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .foregroundStyle(swing ? Color.white : Color.white.opacity(0.65))
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(swing ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color.white.opacity(0.08)))
                        )
                    }
                    .buttonStyle(PressableStyle())
                    .sensoryFeedback(.selection, trigger: swing)
                }
                if let position = airco.airflowPosition {
                    HStack(spacing: 4) {
                        ForEach(1...4, id: \.self) { p in
                            let selected = airco.swing != true && position == p
                            Button { hub.setAirflow(airco, position: p) } label: {
                                Louver(position: p)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 40)
                                    .foregroundStyle(selected ? Color.white : Color.white.opacity(0.45))
                                    .background {
                                        if selected {
                                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                                .fill(.white.opacity(0.16))
                                                .matchedGeometryEffect(id: "louver", in: ns)
                                        }
                                    }
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.07)))
                    .sensoryFeedback(.selection, trigger: position)
                }
            }
        }
        .opacity(airco.isOn ? 1 : 0.5)
    }

    // MARK: Extras

    private struct Extra {
        let part: Airco.Part
        let title: String
        let detail: String
        let symbol: String
        let color: Color
    }

    private static let extras: [Extra] = [
        Extra(part: .powerful, title: "Powerful", detail: "Max output", symbol: "bolt.fill",
              color: Color(red: 1.0, green: 0.75, blue: 0.2)),
        Extra(part: .economy, title: "Economy", detail: "Saves energy", symbol: "leaf.fill",
              color: Color(red: 0.4, green: 0.9, blue: 0.5)),
        Extra(part: .energySavingFan, title: "Fan saver", detail: "Fan rests at target", symbol: "fan.slash",
              color: Color(red: 0.5, green: 0.85, blue: 1.0)),
        Extra(part: .minimumHeat, title: "10° heat", detail: "Frost guard", symbol: "thermometer.snowflake",
              color: Color(red: 1.0, green: 0.5, blue: 0.4)),
    ]

    private var extrasSection: some View {
        let available = Self.extras.filter { airco.parts[$0.part] != nil }
        return Group {
            if !available.isEmpty {
                VStack(spacing: 10) {
                    SectionTitle(title: "Extras", symbol: "sparkles")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(available, id: \.title) { e in
                            ExtraTile(title: e.title, detail: e.detail, symbol: e.symbol, color: e.color,
                                      isOn: airco.isOn(e.part)) {
                                hub.toggle(airco, e.part)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Pieces

struct StatusDot: View {
    var color: Color
    var pulsing: Bool
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .background(
                Circle()
                    .fill(color.opacity(0.5))
                    .scaleEffect(pulse && pulsing ? 2.6 : 1)
                    .opacity(pulse && pulsing ? 0 : 1)
            )
            .onAppear {
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
            }
    }
}

/// Little bar-chart glyph for fan speeds; the auto speed shows an "A".
struct FanBars: View {
    var level: Int
    var highlighted: Bool
    var tint: Color

    var body: some View {
        Group {
            if level == 0 {
                Text("A").font(.system(size: 14, weight: .heavy, design: .rounded))
                    .frame(height: 16)
            } else {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(1...4, id: \.self) { i in
                        Capsule()
                            .fill(i <= level ? (highlighted ? AnyShapeStyle(tint) : AnyShapeStyle(Color.white.opacity(0.75)))
                                             : AnyShapeStyle(Color.white.opacity(0.18)))
                            .frame(width: 4, height: CGFloat(4 + i * 3))
                    }
                }
                .frame(height: 16)
            }
        }
    }
}

/// A slat drawn at the angle of louver position 1 (level) … 4 (pointing down).
struct Louver: View {
    var position: Int

    var body: some View {
        ZStack {
            Capsule().frame(width: 22, height: 4)
                .rotationEffect(.degrees(Double(position - 1) * 20 + 8), anchor: .leading)
                .offset(x: 2, y: -6)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .opacity(0.6)
                .offset(x: CGFloat(position) * 2, y: 9)
        }
    }
}

struct ExtraTile: View {
    var title: String
    var detail: String
    var symbol: String
    var color: Color
    var isOn: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isOn ? Color.black.opacity(0.75) : color)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(isOn ? AnyShapeStyle(color.gradient) : AnyShapeStyle(color.opacity(0.14))))
                    .shadow(color: isOn ? color.opacity(0.7) : .clear, radius: 10)
                    .symbolEffect(.bounce, value: isOn)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(isOn ? "On" : detail)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .contentTransition(.interpolate)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isOn ? color.opacity(0.18) : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isOn ? color.opacity(0.5) : Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle())
        .sensoryFeedback(.impact(weight: .light), trigger: isOn)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isOn)
    }
}

// MARK: - Temperature dial

/// 270° arc. Drag along the ring to pick a temperature, or use − / +.
struct ThermoDial: View {
    var target: Double?
    var current: Double?
    var range: ClosedRange<Double>
    var step: Double
    var tint: Color
    var colors: [Color]
    var enabled: Bool
    var commit: (Double) -> Void

    @State private var dragging: Double?

    private let size: CGFloat = 250
    private let line: CGFloat = 20
    private let sweep: Double = 0.75

    private var shown: Double? { dragging ?? target }

    private func fraction(_ v: Double) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((v - range.lowerBound) / span, 0), 1)
    }

    private func snap(_ v: Double) -> Double {
        let s = max(step, 0.1)
        return min(max((v / s).rounded() * s, range.lowerBound), range.upperBound)
    }

    /// Temperature for a touch point on the ring.
    private func value(at p: CGPoint) -> Double {
        let dx = Double(p.x - size / 2), dy = Double(p.y - size / 2)
        var deg = atan2(dx, -dy) * 180 / .pi            // 0° = top, clockwise positive
        deg = min(max(deg, -135), 135)                   // the gap at the bottom clamps to the ends
        let f = (deg + 135) / 270
        return snap(range.lowerBound + f * (range.upperBound - range.lowerBound))
    }

    var body: some View {
        let f = shown.map(fraction) ?? 0
        let radius = (size - line) / 2

        ZStack {
            // Track
            Circle()
                .trim(from: 0, to: sweep)
                .stroke(.white.opacity(0.08), style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(135))

            // Tick marks
            ForEach(0..<28, id: \.self) { i in
                Capsule()
                    .fill(.white.opacity(Double(i) / 27 <= f ? 0.0 : 0.18))
                    .frame(width: 2, height: 6)
                    .offset(y: -radius + 22)
                    .rotationEffect(.degrees(-135 + 270 * Double(i) / 27))
            }

            // Value arc
            Circle()
                .trim(from: 0, to: sweep * f)
                .stroke(
                    AngularGradient(colors: colors, center: .center,
                                    startAngle: .degrees(0), endAngle: .degrees(270 * max(f, 0.01))),
                    style: StrokeStyle(lineWidth: line, lineCap: .round)
                )
                .rotationEffect(.degrees(135))
                .shadow(color: tint.opacity(enabled ? 0.55 : 0), radius: 14)

            // Knob
            Circle()
                .fill(.white)
                .frame(width: line + 8, height: line + 8)
                .shadow(color: tint.opacity(0.9), radius: dragging == nil ? 6 : 14)
                .scaleEffect(dragging == nil ? 1 : 1.18)
                .offset(y: -radius)
                .rotationEffect(.degrees(-135 + 270 * f))
                .opacity(enabled ? 1 : 0)

            // Centre readout
            VStack(spacing: 2) {
                Text(enabled ? "Set to" : "Target")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.5))
                Text(shown.map(formatTemp) ?? "–")
                    .font(.system(size: 66, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: shown ?? 0))
                    .foregroundStyle(enabled ? Color.white : Color.white.opacity(0.5))
                if let current {
                    Label(formatTemp(current), systemImage: "house.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            // − / + in the gap at the bottom
            HStack {
                RoundStepButton(symbol: "minus", enabled: enabled && (shown ?? 0) > range.lowerBound) {
                    if let t = target { commit(snap(t - step)) }
                }
                Spacer()
                RoundStepButton(symbol: "plus", enabled: enabled && (shown ?? 99) < range.upperBound) {
                    if let t = target { commit(snap(t + step)) }
                }
            }
            .frame(width: size - 20)
            .offset(y: size / 2 - 4)
        }
        .frame(width: size, height: size)
        .padding(.bottom, 26)
        // Only the arc itself reacts to dragging: the centre still scrolls and the
        // − / + buttons in the bottom gap stay tappable.
        .overlay {
            Color.clear
                .frame(width: size, height: size)
                .contentShape(RingHitArea(radius: radius, width: line + 34))
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named("dial"))
                        .onChanged { g in
                            guard enabled else { return }
                            let v = value(at: g.location)
                            if v != dragging { dragging = v }
                        }
                        .onEnded { _ in
                            if let v = dragging, v != target { commit(v) }
                            dragging = nil
                        }
                )
                .padding(.bottom, 26)
        }
        .coordinateSpace(.named("dial"))
        .sensoryFeedback(.selection, trigger: dragging)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: f)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: dragging == nil)
    }
}

/// Touch area for the dial: the ring from 140° to 40° (clockwise over the top),
/// stopping short of the bottom gap where the − / + buttons sit.
struct RingHitArea: Shape {
    var radius: CGFloat
    var width: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: radius,
                 startAngle: .degrees(140), endAngle: .degrees(40), clockwise: false)
        return p.strokedPath(StrokeStyle(lineWidth: width, lineCap: .butt))
    }
}
