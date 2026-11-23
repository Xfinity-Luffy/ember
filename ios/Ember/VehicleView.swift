import SwiftUI

// MARK: - Vehicle tab: fuel gauge and tire pressures

struct VehicleView: View {
    @EnvironmentObject private var car: CarController
    @Binding var showSettings: Bool

    var body: some View {
        ZStack {
            EmberBackground(running: car.status.engineRunning)

            ScrollView {
                VStack(spacing: 20) {
                    header
                    ActiveAlertsStrip()
                    FuelCard(percent: car.vehicle.fuelPercent,
                             ageMinutes: car.vehicle.fuelAgeMinutes,
                             connected: car.link.isUsable)
                    TireCard(psi: car.vehicle.tiresPSI,
                             ageMinutes: car.vehicle.tiresAgeMinutes,
                             hazards: car.status.hazardsOn,
                             panic: car.status.panicOn,
                             alarm: car.status.alarmTriggered)
                    if car.demoMode {
                        Label("Demo mode shows sample readings.", systemImage: "sparkles")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 110)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: car.vehicle)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("Vehicle")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
            SettingsButton { showSettings = true }
        }
        .padding(.top, 12)
    }
}

/// "Updated 14 min ago" style text.
func updatedText(_ minutes: Int?) -> String? {
    guard let m = minutes else { return nil }
    switch m {
    case 0: return "Updated just now"
    case 1..<60: return "Updated \(m) min ago"
    case 60..<(48 * 60): return "Updated \(m / 60) hr ago"
    default: return "Updated \(m / (24 * 60)) days ago"
    }
}

// MARK: - Fuel

struct FuelCard: View {
    let percent: Int?
    let ageMinutes: Int?
    let connected: Bool

    private var level: Double { Double(percent ?? 0) / 100 }

    private var tint: Color {
        guard let p = percent else { return .secondary }
        if p <= 12 { return .red }
        if p <= 25 { return .orange }
        return Palette.accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Fuel", systemImage: "fuelpump.fill").font(.headline)
                Spacer()
                if let p = percent {
                    Text("\(p)%")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                }
            }

            // Gauge: E ---------- F
            HStack(spacing: 10) {
                Text("E").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.10))
                        // quarter marks
                        HStack(spacing: 0) {
                            ForEach(1..<4) { _ in
                                Spacer()
                                Rectangle().fill(Color.white.opacity(0.18)).frame(width: 1.5, height: 10)
                            }
                            Spacer()
                        }
                        if percent != nil {
                            Capsule()
                                .fill(LinearGradient(colors: [tint.opacity(0.75), tint],
                                                     startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(14, geo.size.width * level))
                        }
                    }
                }
                .frame(height: 16)
                Text("F").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            }

            if percent == nil {
                Text("No reading yet. Fuel level updates while the car is on, so start it or drive it once with the bridge connected.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                HStack {
                    if let p = percent, p <= 12 {
                        Label("Fuel is low", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.red)
                    }
                    Spacer()
                    if let t = updatedText(ageMinutes) {
                        Text(t).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(percent.map { "Fuel \($0) percent" } ?? "Fuel level unknown")
    }
}

// MARK: - Tires

struct TireCard: View {
    /// Front-left, front-right, rear-left, rear-right.
    let psi: [Double]?
    let ageMinutes: Int?
    var hazards = false
    var panic = false
    var alarm = false

    /// Below this, a tire is flagged. Your exact pressure is on the driver's door-frame sticker.
    private let lowPSI = 30.0

    private var anyLow: Bool { psi?.contains { $0 < lowPSI } ?? false }

    private var lowFlags: [Bool] {
        guard let values = psi else { return [false, false, false, false] }
        return values.map { value in value < lowPSI }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Tire pressure", systemImage: "tirepressure").font(.headline)
                Spacer()
                if psi != nil {
                    Text(anyLow ? "Check tires" : "All good")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(anyLow ? .orange : Palette.good)
                }
            }

            HStack(alignment: .center, spacing: 14) {
                VStack(spacing: 46) {
                    TireReading(label: "Front left", value: psi?[0], low: lowPSI)
                    TireReading(label: "Rear left", value: psi?[2], low: lowPSI)
                }
                CarTopView(lowTires: lowFlags, hazards: hazards, panic: panic, alarmGlow: alarm)
                    .frame(width: 92, height: 184)
                VStack(spacing: 46) {
                    TireReading(label: "Front right", value: psi?[1], low: lowPSI)
                    TireReading(label: "Rear right", value: psi?[3], low: lowPSI)
                }
            }
            .frame(maxWidth: .infinity)

            if psi == nil {
                Text("Not set up yet. Your Mazda3 measures each tire, but shares the readings in a Mazda-only format the bridge can't read yet.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top) {
                    Text("Recommended pressure is on the sticker inside the driver's door frame.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if let t = updatedText(ageMinutes) {
                        Text(t).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(24)
    }
}

struct TireReading: View {
    let label: String
    let value: Double?
    let low: Double

    private var isLow: Bool { (value ?? low) < low }

    var body: some View {
        VStack(spacing: 2) {
            Text(value.map { String(format: "%.0f", $0) } ?? "--")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isLow ? .orange : .primary)
            Text(value == nil ? label : "psi · \(label.lowercased())")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(width: 80)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(value.map { "\(label), \(Int($0)) psi\(isLow ? ", low" : "")" } ?? "\(label), no reading")
    }
}

/// Modern top-down car: curved body, panoramic glass roof, light bars,
/// mirrors and four wheels. Low tires glow orange.
/// While active, it also shows: hazards (all four corner lights blink amber),
/// panic (head/tail lights flash and sound waves come from the horn), and
/// alarm (a red glow pulses around the car).
/// Drawn on a 100 x 200 grid that scales to whatever frame it's given.
struct CarTopView: View {
    let lowTires: [Bool]   // FL, FR, RL, RR
    var hazards = false
    var panic = false
    var alarmGlow = false

    private static let blinkInterval = 0.45

    var body: some View {
        if hazards || panic || alarmGlow {
            TimelineView(.periodic(from: .now, by: Self.blinkInterval)) { context in
                let tick = Int(context.date.timeIntervalSinceReferenceDate / Self.blinkInterval)
                drawing(lit: tick % 2 == 0)
            }
        } else {
            drawing(lit: false)
        }
    }

    private func drawing(lit: Bool) -> some View {
        let cornersOn = (hazards || panic) && lit
        return ZStack {
            // Alarm: red glow pulsing around the whole car
            if alarmGlow {
                CarBodyShape()
                    .stroke(Color.red, lineWidth: 3)
                    .shadow(color: .red, radius: lit ? 18 : 6)
                    .shadow(color: .red.opacity(0.6), radius: lit ? 30 : 10)
                    .opacity(lit ? 1 : 0.45)
            }
            // Wheels first, so the body covers their inner half.
            ForEach(0..<4) { i in
                WheelShape(index: i)
                    .fill(lowTires[i] ? Color.orange : Color(white: 0.14))
                    .shadow(color: lowTires[i] ? .orange.opacity(0.9) : .clear, radius: 10)
                WheelRimShape(index: i)
                    .fill(lowTires[i] ? Color.white.opacity(0.7) : Color.white.opacity(0.35))
            }
            // Mirrors
            MirrorsShape().fill(Color.white.opacity(0.22))
            // Body: soft metallic sheen
            CarBodyShape()
                .fill(LinearGradient(colors: [Color.white.opacity(0.30), Color.white.opacity(0.10), Color.white.opacity(0.16)],
                                     startPoint: .top, endPoint: .bottom))
            CarBodyShape().stroke(Color.white.opacity(0.35), lineWidth: 1.2)
            // Hood crease
            HoodLinesShape().stroke(Color.white.opacity(0.18), lineWidth: 1)
            // Panoramic glass roof
            CanopyShape()
                .fill(LinearGradient(colors: [Palette.cool.opacity(0.55), Color(red: 0.16, green: 0.12, blue: 0.36).opacity(0.85)],
                                     startPoint: .top, endPoint: .bottom))
            CanopyShape().stroke(Color.white.opacity(0.25), lineWidth: 1)
            RoofSeamsShape().stroke(Color.white.opacity(0.16), lineWidth: 1)
            // Light bars (flash during panic)
            HeadlightShape()
                .stroke(Color.white, style: StrokeStyle(lineWidth: panic && lit ? 3.5 : 2.2, lineCap: .round))
                .shadow(color: .white.opacity(0.9), radius: panic && lit ? 10 : 4)
                .opacity(panic && !lit ? 0.3 : 1)
            TaillightShape()
                .stroke(Color(red: 1.0, green: 0.22, blue: 0.22), style: StrokeStyle(lineWidth: panic && lit ? 3.5 : 2.2, lineCap: .round))
                .shadow(color: .red.opacity(0.9), radius: panic && lit ? 10 : 4)
                .opacity(panic && !lit ? 0.3 : 1)
            // Corner turn signals (hazards, and panic)
            CornerLightsShape()
                .fill(Color.orange.opacity(cornersOn ? 1 : 0.12))
                .shadow(color: .orange, radius: cornersOn ? 10 : 0)
                .shadow(color: .orange.opacity(0.7), radius: cornersOn ? 18 : 0)
            // Horn sound waves (panic)
            if panic {
                HornWavesShape()
                    .stroke(Color.white.opacity(lit ? 0.9 : 0.25), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            }
        }
        .aspectRatio(0.5, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Four small amber lamps at the front and rear corners.
private struct CornerLightsShape: Shape {
    func path(in rect: CGRect) -> Path {
        let g = Grid(rect: rect)
        var path = Path()
        for r in [g.r(13, 20, 9, 7), g.r(78, 20, 9, 7), g.r(13, 175, 9, 7), g.r(78, 175, 9, 7)] {
            path.addRoundedRect(in: r, cornerSize: CGSize(width: r.width * 0.4, height: r.width * 0.4))
        }
        return path
    }
}

/// Two arcs radiating ahead of the nose.
private struct HornWavesShape: Shape {
    func path(in rect: CGRect) -> Path {
        let g = Grid(rect: rect)
        var path = Path()
        for radius in [CGFloat(10), 18] {
            let r = radius / 100 * rect.width
            path.addArc(center: g.p(50, 4), radius: r,
                        startAngle: .degrees(215), endAngle: .degrees(325), clockwise: false)
            path.move(to: g.p(50, 4))   // don't join the arcs
        }
        return path
    }
}

/// Maps the 100 x 200 design grid onto a real rectangle.
private struct Grid {
    let rect: CGRect
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX + x / 100 * rect.width, y: rect.minY + y / 200 * rect.height)
    }
    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(origin: p(x, y), size: CGSize(width: w / 100 * rect.width, height: h / 200 * rect.height))
    }
}

private struct CarBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        let g = Grid(rect: rect)
        var path = Path()
        path.move(to: g.p(50, 3))
        path.addCurve(to: g.p(86, 28), control1: g.p(70, 3), control2: g.p(84, 9))
        path.addLine(to: g.p(88, 70))
        path.addCurve(to: g.p(87, 162), control1: g.p(89.5, 100), control2: g.p(89.5, 132))
        path.addCurve(to: g.p(50, 197), control1: g.p(86, 188), control2: g.p(72, 197))
        path.addCurve(to: g.p(13, 162), control1: g.p(28, 197), control2: g.p(14, 188))
        path.addCurve(to: g.p(12, 70), control1: g.p(10.5, 132), control2: g.p(10.5, 100))
        path.addLine(to: g.p(14, 28))
        path.addCurve(to: g.p(50, 3), control1: g.p(16, 9), control2: g.p(30, 3))
        path.closeSubpath()
        return path
    }
}

private struct CanopyShape: Shape {
    func path(in rect: CGRect) -> Path {
        let g = Grid(rect: rect)
        var path = Path()
        path.move(to: g.p(50, 54))
        path.addCurve(to: g.p(77, 66), control1: g.p(65, 54), control2: g.p(75, 58))
        path.addLine(to: g.p(75, 142))
        path.addCurve(to: g.p(50, 158), control1: g.p(74, 152), control2: g.p(65, 158))
        path.addCurve(to: g.p(25, 142), control1: g.p(35, 158), control2: g.p(26, 152))
        path.addLine(to: g.p(23, 66))
        path.addCurve(to: g.p(50, 54), control1: g.p(25, 58), control2: g.p(35, 54))
        path.closeSubpath()
        return path
    }
}

/// Where the windshield meets the roof, and the roof meets the rear glass.
private struct RoofSeamsShape: Shape {
    func path(in rect: CGRect) -> Path {
        let g = Grid(rect: rect)
        var path = Path()
        path.move(to: g.p(24, 82)); path.addQuadCurve(to: g.p(76, 82), control: g.p(50, 76))
        path.move(to: g.p(25, 132)); path.addQuadCurve(to: g.p(75, 132), control: g.p(50, 138))
        return path
    }
}

private struct HoodLinesShape: Shape {
    func path(in rect: CGRect) -> Path {
        let g = Grid(rect: rect)
        var path = Path()
        path.move(to: g.p(36, 14)); path.addQuadCurve(to: g.p(32, 50), control: g.p(31, 30))
        path.move(to: g.p(64, 14)); path.addQuadCurve(to: g.p(68, 50), control: g.p(69, 30))
        return path
    }
}

private struct HeadlightShape: Shape {
    func path(in rect: CGRect) -> Path {
        let g = Grid(rect: rect)
        var path = Path()
        path.move(to: g.p(20, 16))
        path.addQuadCurve(to: g.p(80, 16), control: g.p(50, 5))
        return path
    }
}

private struct TaillightShape: Shape {
    func path(in rect: CGRect) -> Path {
        let g = Grid(rect: rect)
        var path = Path()
        path.move(to: g.p(18, 186))
        path.addQuadCurve(to: g.p(82, 186), control: g.p(50, 196))
        return path
    }
}

private struct MirrorsShape: Shape {
    func path(in rect: CGRect) -> Path {
        let g = Grid(rect: rect)
        var path = Path()
        path.addRoundedRect(in: g.r(3, 58, 11, 7), cornerSize: CGSize(width: 3, height: 3))
        path.addRoundedRect(in: g.r(86, 58, 11, 7), cornerSize: CGSize(width: 3, height: 3))
        return path
    }
}

/// index: 0 FL, 1 FR, 2 RL, 3 RR
private func wheelRect(_ index: Int) -> (x: CGFloat, y: CGFloat) {
    let left = index % 2 == 0, front = index < 2
    return (left ? 4 : 82, front ? 32 : 126)
}

private struct WheelShape: Shape {
    let index: Int
    func path(in rect: CGRect) -> Path {
        let g = Grid(rect: rect)
        let w = wheelRect(index)
        return Path(roundedRect: g.r(w.x, w.y, 14, 34), cornerRadius: 0.05 * rect.width, style: .continuous)
    }
}

private struct WheelRimShape: Shape {
    let index: Int
    func path(in rect: CGRect) -> Path {
        let g = Grid(rect: rect)
        let w = wheelRect(index)
        let outerX = index % 2 == 0 ? w.x + 2 : w.x + 9   // rim stripe on the outside edge
        return Path(roundedRect: g.r(outerX, w.y + 6, 3, 22), cornerRadius: 0.015 * rect.width, style: .continuous)
    }
}
