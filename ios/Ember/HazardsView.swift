import SwiftUI

// MARK: - Hazards tab

struct HazardsView: View {
    @EnvironmentObject private var car: CarController
    @Binding var showSettings: Bool

    private var on: Bool { car.status.hazardsOn }
    private var busy: Bool { car.pending == .hazardsOn || car.pending == .hazardsOff }
    private var ready: Bool { car.link.isUsable && car.pending == nil }

    var body: some View {
        ZStack {
            EmberBackground(running: car.status.engineRunning)

            ScrollView {
                VStack(spacing: 22) {
                    HStack(alignment: .top, spacing: 12) {
                        Text("Hazards")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        SettingsButton { showSettings = true }
                    }
                    .padding(.top, 12)

                    ActiveAlertsStrip(hiding: .hazards)

                    HazardButton(on: on, busy: busy, enabled: ready) {
                        Haptics.tap()
                        car.perform(on ? .hazardsOff : .hazardsOn)
                    }
                    .padding(.vertical, 6)

                    VStack(spacing: 6) {
                        Text(on ? "Hazard lights are on" : "Hazard lights are off")
                            .font(.title3.weight(.semibold))
                        Text(on ? "Turns off by itself in \(clock(car.status.hazardSecondsRemaining))"
                                : "Tap the triangle to turn them on")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    if on {
                        Button { car.perform(.hazardsOn) } label: {
                            Label("Keep on 10 more minutes", systemImage: "timer")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .glassCard(18, tint: Color.orange.opacity(0.3), interactive: true)
                        }
                        .buttonStyle(.plain)
                        .disabled(!ready)
                    }

                    // The car, with its corner lights blinking while the hazards are on.
                    HStack(spacing: 18) {
                        CarTopView(lowTires: [false, false, false, false],
                                   hazards: on, panic: car.status.panicOn, alarmGlow: false)
                            .frame(width: 64, height: 128)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(on ? "Corner lights flashing" : "Corner lights off")
                                .font(.headline)
                                .foregroundStyle(on ? Color.orange : Color.primary)
                            Text(on ? "All four turn signals blink together, front and back."
                                    : "Turning the hazards on blinks all four turn signals.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(18)
                    .glassCard(24, tint: on ? Color.orange.opacity(0.18) : nil)

                    VStack(alignment: .leading, spacing: 10) {
                        Label("When to use them", systemImage: "info.circle").font(.headline)
                        Text("Your car is stopped where it could be hit, or you need to spot it in a busy lot. To save the battery, they turn off by themselves after 10 minutes.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text("The app shows what it last sent. If someone presses the hazard button inside the car, the app won't know.")
                            .font(.footnote).foregroundStyle(.tertiary)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard(24)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 110)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: on)
    }
}

/// "9:41" from seconds.
func clock(_ seconds: Int) -> String {
    String(format: "%d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
}

/// Big glass triangle button; blinks amber while the hazards are on.
struct HazardButton: View {
    let on: Bool
    let busy: Bool
    let enabled: Bool
    let action: () -> Void

    @State private var blink = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.clear)
                    .glass(Circle(), tint: on ? Color.orange.opacity(blink ? 0.75 : 0.25) : nil, interactive: true)
                    .shadow(color: on ? Color.orange.opacity(blink ? 0.8 : 0.2) : .clear, radius: 40)
                if busy {
                    ProgressView().controlSize(.large).tint(.white)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 78, weight: .bold))
                        .foregroundStyle(on ? (blink ? Color.white : Color.orange) : Color.orange)
                }
            }
            .frame(width: 210, height: 210)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled || busy ? 1 : 0.45)
        .onAppear { startBlinking() }
        .onChange(of: on) { _, _ in startBlinking() }
        .accessibilityLabel(on ? "Turn hazard lights off" : "Turn hazard lights on")
    }

    private func startBlinking() {
        blink = false
        guard on else { return }
        withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { blink = true }
    }
}
