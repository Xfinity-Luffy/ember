import SwiftUI

/// A row of glowing chips at the top of each tab for anything that's active
/// right now (hazards, panic, alarm, engine). Tap a chip to jump to its tab.
struct ActiveAlertsStrip: View {
    @EnvironmentObject private var car: CarController
    /// Leave out chips that point to the tab you're already on.
    var hiding: AppTab? = nil

    private struct Chip: Identifiable {
        let id: String
        let icon: String
        let text: String
        let color: Color
        let tab: AppTab
        let urgent: Bool
    }

    private var chips: [Chip] {
        let s = car.status
        var list: [Chip] = []
        if s.alarmTriggered {
            list.append(Chip(id: "alarm", icon: "light.beacon.max.fill", text: "Alarm went off",
                             color: .red, tab: .alarm, urgent: true))
        }
        if s.panicOn {
            list.append(Chip(id: "panic", icon: "speaker.wave.3.fill",
                             text: "Panic · \(clock(s.panicSecondsRemaining))",
                             color: .red, tab: .alarm, urgent: true))
        }
        if s.hazardsOn {
            list.append(Chip(id: "hazards", icon: "exclamationmark.triangle.fill",
                             text: "Hazards on · \(clock(s.hazardSecondsRemaining))",
                             color: .orange, tab: .hazards, urgent: false))
        }
        if s.engineRunning {
            list.append(Chip(id: "engine", icon: "engine.combustion.fill",
                             text: s.secondsRemaining > 0 ? "Running · \(clock(s.secondsRemaining))" : "Engine running",
                             color: Palette.accent, tab: .remote, urgent: false))
        }
        return list.filter { $0.tab != hiding }
    }

    var body: some View {
        let items = chips
        if !items.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items) { chip in
                        Button {
                            Haptics.tap()
                            car.selectedTab = chip.tab
                        } label: {
                            ChipLabel(icon: chip.icon, text: chip.text, color: chip.color, urgent: chip.urgent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens the \(String(describing: chip.tab)) tab")
                    }
                }
                .padding(.vertical, 4)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

private struct ChipLabel: View {
    let icon: String
    let text: String
    let color: Color
    let urgent: Bool

    @State private var glow = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color, radius: glow ? 6 : 1)
                .opacity(glow ? 1 : 0.55)
            Image(systemName: icon).font(.caption.weight(.bold))
            Text(text).font(.footnote.weight(.semibold)).monospacedDigit()
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glass(Capsule(), tint: color.opacity(urgent ? 0.35 : 0.22), interactive: true)
        .onAppear {
            withAnimation(.easeInOut(duration: urgent ? 0.45 : 0.8).repeatForever(autoreverses: true)) { glow = true }
        }
    }
}
