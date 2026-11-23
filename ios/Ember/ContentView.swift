import SwiftUI

// MARK: - Palette

enum Palette {
    static let accent = Color(red: 1.00, green: 0.42, blue: 0.21)      // ember orange
    static let accentSoft = Color(red: 1.00, green: 0.62, blue: 0.35)
    static let cool = Color(red: 0.42, green: 0.74, blue: 1.00)         // unlocked / climate blue
    static let good = Color(red: 0.30, green: 0.85, blue: 0.45)
    static let surface = Color.white.opacity(0.06)
    static let stroke = Color.white.opacity(0.10)
}

// MARK: - App shell: two tabs, one banner, one settings sheet

struct ContentView: View {
    @EnvironmentObject private var car: CarController
    @State private var showSettings = false

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $car.selectedTab) {
                RemoteView(showSettings: $showSettings)
                    .tabItem { Label("Remote", systemImage: "car.fill") }
                    .tag(AppTab.remote)
                VehicleView(showSettings: $showSettings)
                    .tabItem { Label("Vehicle", systemImage: "gauge.with.dots.needle.67percent") }
                    .tag(AppTab.vehicle)
                HazardsView(showSettings: $showSettings)
                    .tabItem { Label("Hazards", systemImage: "exclamationmark.triangle.fill") }
                    .tag(AppTab.hazards)
                    .badge(car.status.hazardsOn ? Text("On") : nil)
                AlarmView(showSettings: $showSettings)
                    .tabItem { Label("Alarm", systemImage: "light.beacon.max.fill") }
                    .tag(AppTab.alarm)
                    .badge(car.status.alarmTriggered || car.status.panicOn ? Text("!") : nil)
            }
            .tint(Palette.accent)

            if let banner = car.banner {
                BannerView(banner: banner)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 64)      // sits just above the tab bar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: car.banner)
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(car) }
    }
}

// MARK: - Remote tab

struct RemoteView: View {
    @EnvironmentObject private var car: CarController
    @Binding var showSettings: Bool

    private var ready: Bool { car.link.isUsable && car.pending == nil }

    var body: some View {
        ZStack {
            EmberBackground(running: car.status.engineRunning)

            ScrollView {
                VStack(spacing: 20) {
                    header
                    if !car.demoMode && !car.hasKey { keyMissingCard }
                    ActiveAlertsStrip()
                    StatusCard(link: car.link, status: car.status, demo: car.demoMode)
                    StartButton(status: car.status,
                                busy: car.pending == .start || car.pending == .stop,
                                enabled: ready,
                                onHold: { car.perform(car.status.engineRunning ? .stop : .start) },
                                onShortTap: { car.holdHint() })
                    defrostRow
                    doorsCard
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 110)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: car.status)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            // Long names wrap onto a second line (then shrink a little, then end in "…")
            // instead of pushing the settings button out of place.
            Text(car.carName)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            SettingsButton { showSettings = true }
        }
        .padding(.top, 12)
    }

    private var keyMissingCard: some View {
        Button { showSettings = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "key.fill").foregroundStyle(Palette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("One more step").font(.subheadline.weight(.semibold))
                    Text("Add your bridge key so the app can control the car.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(14)
            .glassCard(18, tint: Palette.accent.opacity(0.3))
        }
        .buttonStyle(.plain)
    }

    // MARK: Defrost

    /// Before starting: a switch to add defrost to the next start.
    /// While running: a button that turns defrost on now.
    @ViewBuilder
    private var defrostRow: some View {
        if car.status.engineRunning {
            Button { Haptics.tap(); car.perform(.aux1) } label: {
                HStack(spacing: 10) {
                    if car.pending == .aux1 { ProgressView().tint(.white) }
                    else { Image(systemName: "windshield.rear.and.heat.waves") }
                    Text("Turn on rear defrost")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.cool)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .glassCard(18, tint: Palette.cool.opacity(0.35), interactive: true)
            }
            .buttonStyle(.plain)
            .disabled(!ready)
        } else {
            Toggle(isOn: $car.defrostOnStart) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Also turn on rear defrost").font(.subheadline.weight(.semibold))
                        Text("Heat and A/C use the settings you left when you parked.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "windshield.rear.and.heat.waves").foregroundStyle(Palette.cool)
                }
            }
            .tint(Palette.cool)
            .padding(14)
            .glassCard(18)
        }
    }

    // MARK: Doors

    private var doorsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Doors").font(.headline)
                Spacer()
                Text(doorText).font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                DoorButton(title: "Lock", symbol: "lock.fill", tint: Palette.accent,
                           current: car.status.lock == .locked,
                           busy: car.pending == .lock, enabled: ready) { car.perform(.lock) }
                DoorButton(title: "Unlock", symbol: "lock.open.fill", tint: Palette.cool,
                           current: car.status.lock == .unlocked,
                           busy: car.pending == .unlock, enabled: ready) { car.perform(.unlock) }
            }
        }
        .padding(16)
        .glassCard(24)
    }

    private var doorText: String {
        switch car.status.lock {
        case .locked: return car.demoMode ? "Locked" : "Last sent: locked"
        case .unlocked: return car.demoMode ? "Unlocked" : "Last sent: unlocked"
        case .unknown: return "Not sent yet"
        }
    }
}

// MARK: - Status card (one plain-English line about the car)

struct StatusCard: View {
    let link: LinkState
    let status: CarStatus
    let demo: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 46, height: 46)
                .background(tint.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(24)
        .accessibilityElement(children: .combine)
    }

    private var connected: Bool { link.isUsable }

    private var icon: String {
        switch link {
        case .bluetoothOff, .unauthorized: return "exclamationmark.triangle.fill"
        case .searching, .connecting: return "antenna.radiowaves.left.and.right"
        case .ready, .demo: return status.engineRunning ? "engine.combustion.fill" : "car.fill"
        }
    }

    private var tint: Color {
        switch link {
        case .bluetoothOff, .unauthorized: return .yellow
        case .searching, .connecting: return .secondary
        case .ready, .demo: return status.engineRunning ? Palette.accent : Palette.good
        }
    }

    private var title: String {
        switch link {
        case .bluetoothOff: return "Bluetooth is off"
        case .unauthorized: return "Bluetooth isn't allowed"
        case .searching: return "Looking for your car…"
        case .connecting: return "Connecting…"
        case .ready, .demo:
            guard status.engineRunning else { return "Engine is off" }
            if status.secondsRemaining > 0 {
                return "Running · \(status.secondsRemaining / 60) min left"
            }
            return "Engine is running"
        }
    }

    private var subtitle: String {
        switch link {
        case .bluetoothOff: return "Turn it on in Control Center."
        case .unauthorized: return "Allow Bluetooth for Ember in iPhone Settings."
        case .searching: return "Stay within about 30 feet of the car."
        case .connecting: return "This takes a few seconds."
        case .ready, .demo:
            let mode = demo ? "Demo car, not connected to a real one." : "Connected to your car."
            return mode
        }
    }
}

// MARK: - Hold-to-start button

struct StartButton: View {
    let status: CarStatus
    let busy: Bool
    let enabled: Bool
    let onHold: () -> Void
    let onShortTap: () -> Void

    @State private var pressing = false
    @State private var fired = false
    private let holdSeconds = 1.0

    private var running: Bool { status.engineRunning }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.clear)
                .glass(Circle(), tint: running ? Palette.accent.opacity(0.6) : nil, interactive: true)
                .shadow(color: running ? Palette.accent.opacity(0.5) : .clear, radius: 36)

            Circle().stroke(Palette.stroke, lineWidth: 10).padding(6)

            Circle()
                .trim(from: 0, to: pressing ? 1 : 0)
                .stroke(running ? Color.white : Palette.accent,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(6)
                .animation(pressing ? .linear(duration: holdSeconds) : .easeOut(duration: 0.2), value: pressing)

            VStack(spacing: 6) {
                if busy {
                    ProgressView().controlSize(.large).tint(.white)
                } else {
                    Image(systemName: "power").font(.system(size: 42, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(hint).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(width: 220, height: 220)
        .contentShape(Circle())
        .opacity(enabled || busy ? 1 : 0.4)
        .onLongPressGesture(minimumDuration: holdSeconds, maximumDistance: 40) {
            fired = true
            Haptics.tap()
            onHold()
        } onPressingChanged: { isPressing in
            if isPressing {
                fired = false
                pressing = enabled
            } else {
                pressing = false
                if enabled && !fired { onShortTap() }   // let go too early: explain the gesture
            }
        }
        .allowsHitTesting(enabled)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(running ? "Stop engine" : "Start engine")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if enabled { onHold() } }
    }

    private var title: String {
        if busy { return running ? "Stopping…" : "Starting…" }
        if pressing { return "Keep holding" }
        guard running else { return "Start" }
        if status.secondsRemaining > 0 {
            return String(format: "%d:%02d", status.secondsRemaining / 60, status.secondsRemaining % 60)
        }
        return "Running"
    }

    private var hint: String {
        if busy { return " " }
        if pressing { return running ? "to stop" : "to start" }
        return running ? "Hold to stop" : "Press and hold"
    }
}

// MARK: - Small components

struct DoorButton: View {
    let title: String
    let symbol: String
    let tint: Color
    let current: Bool
    let busy: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button { Haptics.tap(); action() } label: {
            HStack(spacing: 8) {
                if busy { ProgressView().tint(.white) }
                else { Image(systemName: symbol).font(.system(size: 18, weight: .semibold)) }
                Text(title).font(.subheadline.weight(.semibold))
                if current && !busy {
                    Image(systemName: "checkmark.circle.fill").font(.footnote)
                }
            }
            .foregroundStyle(current ? tint : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .glassCard(18, tint: current ? tint.opacity(0.4) : nil, interactive: true)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled || busy ? 1 : 0.45)
        .accessibilityValue(current ? "Current" : "")
    }
}

struct BannerView: View {
    let banner: Banner

    private var icon: (String, Color) {
        switch banner.kind {
        case .success: return ("checkmark.circle.fill", .green)
        case .error: return ("exclamationmark.triangle.fill", .yellow)
        case .info: return ("hand.tap.fill", Palette.accentSoft)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon.0).foregroundStyle(icon.1)
            Text(banner.text).font(.subheadline)
            Spacer(minLength: 0)
        }
        .padding(14)
        .glassCard(18)
    }
}

#Preview {
    ContentView()
        .environmentObject(CarController())
        .preferredColorScheme(.dark)
}

// MARK: - Shared header button

struct SettingsButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape.fill")
                .font(.title3)
                .frame(width: 44, height: 44)
                .glass(Circle(), interactive: true)
        }
        .foregroundStyle(.secondary)
        .fixedSize()            // never squeezed, always top-right
        .layoutPriority(1)
        .accessibilityLabel("Settings")
    }
}
