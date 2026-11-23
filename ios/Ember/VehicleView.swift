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
                    FuelCard(percent: car.vehicle.fuelPercent,
                             ageMinutes: car.vehicle.fuelAgeMinutes,
                             connected: car.link.isUsable)
                    TireCard(psi: car.vehicle.tiresPSI,
                             ageMinutes: car.vehicle.tiresAgeMinutes)
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
                CarTopView(lowTires: lowFlags)
                    .frame(width: 92, height: 170)
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

/// Simple top-down car with four tires; low tires glow orange.
struct CarTopView: View {
    let lowTires: [Bool]   // FL, FR, RL, RR

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let tireW = w * 0.16, tireH = h * 0.2
            ZStack {
                // Body
                RoundedRectangle(cornerRadius: w * 0.38, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                    .overlay(RoundedRectangle(cornerRadius: w * 0.38, style: .continuous)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1.5))
                    .frame(width: w * 0.74, height: h)
                // Windshield and rear window
                RoundedRectangle(cornerRadius: 8)
                    .fill(Palette.cool.opacity(0.25))
                    .frame(width: w * 0.5, height: h * 0.14)
                    .offset(y: -h * 0.2)
                RoundedRectangle(cornerRadius: 8)
                    .fill(Palette.cool.opacity(0.18))
                    .frame(width: w * 0.46, height: h * 0.1)
                    .offset(y: h * 0.27)
                // Tires
                ForEach(0..<4) { i in
                    let left = i % 2 == 0, front = i < 2
                    Capsule()
                        .fill(lowTires[i] ? Color.orange : Color.white.opacity(0.55))
                        .shadow(color: lowTires[i] ? .orange.opacity(0.8) : .clear, radius: 8)
                        .frame(width: tireW, height: tireH)
                        .offset(x: (left ? -1 : 1) * (w * 0.37),
                                y: (front ? -1 : 1) * (h * 0.29))
                }
            }
            .frame(width: w, height: h)
        }
        .accessibilityHidden(true)
    }
}
