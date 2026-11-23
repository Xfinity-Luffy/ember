import SwiftUI

// MARK: - Alarm tab

struct AlarmView: View {
    @EnvironmentObject private var car: CarController
    @Binding var showSettings: Bool

    private var ready: Bool { car.link.isUsable && car.pending == nil }

    var body: some View {
        ZStack {
            EmberBackground(running: car.status.engineRunning)

            ScrollView {
                VStack(spacing: 20) {
                    HStack(alignment: .top, spacing: 12) {
                        Text("Alarm")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        SettingsButton { showSettings = true }
                    }
                    .padding(.top, 12)

                    ActiveAlertsStrip(hiding: .alarm)
                    if car.status.alarmTriggered { triggeredCard }
                    securityCard
                    panicCard

                    if car.demoMode && !car.status.alarmTriggered {
                        Button { car.simulateAlarm() } label: {
                            Label("Demo: pretend the alarm went off", systemImage: "sparkles")
                                .font(.footnote)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 110)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: car.status)
    }

    // MARK: Alarm went off

    private var triggeredCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "light.beacon.max.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your alarm went off").font(.headline)
                    if let at = car.alarmTriggeredAt {
                        Text("Seen at \(at.formatted(date: .omitted, time: .shortened))")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            Text("Check on your car. Unlocking it with the app also clears this warning.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button { car.perform(.alarmAck) } label: {
                Text("Got it")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .glassCard(14, tint: Color.red.opacity(0.35), interactive: true)
            }
            .buttonStyle(.plain)
            .disabled(!ready)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(24, tint: Color.red.opacity(0.25))
    }

    // MARK: Armed / disarmed

    private var securityCard: some View {
        let (icon, tint, title, subtitle): (String, Color, String, String) = {
            switch car.status.lock {
            case .locked: return ("lock.shield.fill", Palette.good, "Armed", "The doors are locked, so the alarm is on.")
            case .unlocked: return ("lock.open.fill", .secondary, "Not armed", "The doors are unlocked. Lock them to turn the alarm on.")
            case .unknown: return ("shield.lefthalf.filled", .secondary, "Status unknown", "Lock the car from the Home tab to make sure the alarm is on.")
            }
        }()
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                VehicleSilhouette(type: car.selectedVehicle.type,
                                  color: car.selectedVehicle.color.swatch,
                                  hazards: car.status.hazardsOn,
                                  panic: car.status.panicOn,
                                  alarm: car.status.alarmTriggered)
                    .frame(width: 110, height: 56)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(tint)
                            .frame(width: 30, height: 30)
                            .glass(Circle(), tint: tint.opacity(0.25))
                            .offset(x: 10, y: 4)
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if !car.status.alarmWired && !car.demoMode {
                Text("Alerts when the alarm goes off need the bridge's alarm input wired (see the README).")
                    .font(.footnote).foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(24)
        .accessibilityElement(children: .combine)
    }

    // MARK: Panic

    private var panicCard: some View {
        VStack(spacing: 14) {
            HStack {
                Label("Panic alarm", systemImage: "speaker.wave.3.fill").font(.headline)
                Spacer()
            }
            PanicButton(on: car.status.panicOn,
                        secondsLeft: car.status.panicSecondsRemaining,
                        busy: car.pending == .panicOn || car.pending == .panicOff,
                        enabled: ready,
                        onStart: { car.perform(.panicOn) },
                        onStop: { car.perform(.panicOff) },
                        onShortTap: { car.holdHint(panic: true) })
            Text("Sounds the horn and flashes the lights, to scare someone off or find your car. Stops by itself after 30 seconds.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .glassCard(24)
    }
}

/// Hold for one second to start (no pocket alarms); one tap stops it.
struct PanicButton: View {
    let on: Bool
    let secondsLeft: Int
    let busy: Bool
    let enabled: Bool
    let onStart: () -> Void
    let onStop: () -> Void
    let onShortTap: () -> Void

    @State private var pressing = false
    @State private var fired = false
    private let hold = 1.0

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.clear)
                .glass(Circle(), tint: Color.red.opacity(on ? 0.7 : 0.35), interactive: true)
                .shadow(color: on ? .red.opacity(0.7) : .clear, radius: 30)
            Circle().stroke(Palette.stroke, lineWidth: 8).padding(5)
            Circle()
                .trim(from: 0, to: pressing ? 1 : 0)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(5)
                .animation(pressing ? .linear(duration: hold) : .easeOut(duration: 0.2), value: pressing)
            VStack(spacing: 4) {
                if busy {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: on ? "stop.fill" : "light.beacon.max.fill")
                        .font(.system(size: 30, weight: .bold))
                }
                Text(on ? "Stop" : (pressing ? "Keep holding" : "Panic"))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Text(on ? clock(secondsLeft) : "Press and hold")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .frame(width: 150, height: 150)
        .contentShape(Circle())
        .opacity(enabled || busy ? 1 : 0.45)
        .onTapGesture { if on && enabled { Haptics.tap(); onStop() } }
        .onLongPressGesture(minimumDuration: hold, maximumDistance: 40) {
            guard !on else { return }
            fired = true
            Haptics.tap()
            onStart()
        } onPressingChanged: { isPressing in
            guard !on else { pressing = false; return }
            if isPressing { fired = false; pressing = enabled }
            else {
                pressing = false
                if enabled && !fired { onShortTap() }
            }
        }
        .allowsHitTesting(enabled)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(on ? "Stop panic alarm" : "Start panic alarm")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if enabled { on ? onStop() : onStart() } }
    }
}
