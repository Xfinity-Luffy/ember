import SwiftUI

// MARK: - Palette

enum Palette {
    static let accent = Color(red: 1.00, green: 0.42, blue: 0.21)      // ember orange
    static let accentSoft = Color(red: 1.00, green: 0.62, blue: 0.35)
    static let cool = Color(red: 0.42, green: 0.74, blue: 1.00)         // unlocked / climate blue
    static let surface = Color.white.opacity(0.06)
    static let stroke = Color.white.opacity(0.10)
    static let background = LinearGradient(
        colors: [Color(red: 0.09, green: 0.09, blue: 0.11), Color(red: 0.03, green: 0.03, blue: 0.04)],
        startPoint: .top, endPoint: .bottom)
}

// MARK: - Main screen

struct ContentView: View {
    @EnvironmentObject private var car: CarController
    @State private var showSettings = false

    private var controlsEnabled: Bool { car.link.isUsable && car.pending == nil }

    var body: some View {
        ZStack(alignment: .bottom) {
            Palette.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    header
                    if !car.demoMode && !car.hasKey { keyMissingCard }
                    StartButton(status: car.status,
                                busy: car.pending == .start || car.pending == .stop,
                                enabled: car.link.isUsable && car.pending == nil) {
                        car.perform(car.status.engineRunning ? .stop : .start)
                    }
                    .padding(.vertical, 8)
                    lockRow
                    climateCard
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }

            if let banner = car.banner {
                BannerView(banner: banner)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: car.banner)
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(car) }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text(car.carName)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                LinkPill(link: car.link)
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .background(Palette.surface, in: Circle())
            }
            .foregroundStyle(.secondary)
            .accessibilityLabel("Settings")
        }
        .padding(.top, 12)
    }

    private var keyMissingCard: some View {
        Button { showSettings = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "key.fill").foregroundStyle(Palette.accent)
                Text("Add your bridge key to control the car.")
                    .font(.subheadline)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var lockRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                ActionTile(title: "Lock", symbol: "lock.fill",
                           tint: Palette.accent,
                           highlighted: car.status.lock == .locked,
                           busy: car.pending == .lock,
                           enabled: controlsEnabled) { car.perform(.lock) }
                ActionTile(title: "Unlock", symbol: "lock.open.fill",
                           tint: Palette.cool,
                           highlighted: car.status.lock == .unlocked,
                           busy: car.pending == .unlock,
                           enabled: controlsEnabled) { car.perform(.unlock) }
            }
            if car.status.lock != .unknown && !car.demoMode {
                Text("Highlight shows the last command sent from this app.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)
            }
        }
    }

    private var climateCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Climate", systemImage: "thermometer.medium")
                .font(.headline)
            Text("Heat or A/C runs at the settings you left when you parked. Set them before you walk away.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button { Haptics.tap(); car.perform(.aux1) } label: {
                HStack {
                    if car.pending == .aux1 { ProgressView().tint(.white) }
                    else { Image(systemName: "windshield.rear.and.heat.waves") }
                    Text("Rear defrost")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(car.status.engineRunning ? Palette.cool.opacity(0.25) : Palette.surface,
                            in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(!controlsEnabled || !car.status.engineRunning)
            .opacity(car.status.engineRunning ? 1 : 0.45)
            if !car.status.engineRunning {
                Text("Available while the engine is running.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Palette.stroke))
    }
}

// MARK: - Hold-to-start button

struct StartButton: View {
    let status: CarStatus
    let busy: Bool
    let enabled: Bool
    let action: () -> Void

    @State private var pressing = false
    private let holdSeconds = 1.0

    private var running: Bool { status.engineRunning }

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: running ? [Palette.accent.opacity(0.55), Palette.accent.opacity(0.10)]
                                    : [Color.white.opacity(0.10), Color.white.opacity(0.03)],
                    center: .center, startRadius: 10, endRadius: 140))
                .shadow(color: running ? Palette.accent.opacity(0.55) : .clear, radius: 40)

            Circle().stroke(Palette.stroke, lineWidth: 10).padding(6)

            Circle()
                .trim(from: 0, to: pressing ? 1 : 0)
                .stroke(running ? Color.white : Palette.accent,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(6)
                .animation(pressing ? .linear(duration: holdSeconds) : .easeOut(duration: 0.2), value: pressing)

            VStack(spacing: 8) {
                if busy {
                    ProgressView().controlSize(.large).tint(.white)
                } else {
                    Image(systemName: "power")
                        .font(.system(size: 46, weight: .semibold))
                }
                Text(primaryText)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(secondaryText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 240, height: 240)
        .contentShape(Circle())
        .opacity(enabled || busy ? 1 : 0.4)
        .onLongPressGesture(minimumDuration: holdSeconds, maximumDistance: 40) {
            Haptics.tap()
            action()
        } onPressingChanged: { isPressing in
            pressing = enabled && isPressing
        }
        .allowsHitTesting(enabled)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(running ? "Stop engine" : "Start engine")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if enabled { action() } }
    }

    private var primaryText: String {
        if busy { return running ? "Stopping…" : "Starting…" }
        guard running else { return "Engine off" }
        if status.secondsRemaining > 0 {
            return String(format: "%d:%02d", status.secondsRemaining / 60, status.secondsRemaining % 60)
        }
        return "Running"
    }

    private var secondaryText: String {
        if busy { return " " }
        return running ? "Hold to stop" : "Hold to start"
    }
}

// MARK: - Small components

struct ActionTile: View {
    let title: String
    let symbol: String
    let tint: Color
    let highlighted: Bool
    let busy: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button { Haptics.tap(); action() } label: {
            VStack(spacing: 10) {
                ZStack {
                    if busy { ProgressView().tint(.white) }
                    else { Image(systemName: symbol).font(.system(size: 26, weight: .semibold)) }
                }
                .frame(height: 30)
                Text(title).font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(highlighted ? tint : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(highlighted ? tint.opacity(0.16) : Palette.surface,
                        in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22)
                .stroke(highlighted ? tint.opacity(0.6) : Palette.stroke))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled || busy ? 1 : 0.45)
    }
}

struct LinkPill: View {
    let link: LinkState

    private var color: Color {
        switch link {
        case .ready: return .green
        case .demo: return Palette.accentSoft
        case .searching, .connecting: return .yellow
        case .bluetoothOff, .unauthorized: return .red
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(link.label).font(.footnote.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Palette.surface, in: Capsule())
        .foregroundStyle(.secondary)
    }
}

struct BannerView: View {
    let banner: Banner

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: banner.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(banner.isError ? .yellow : .green)
            Text(banner.text).font(.subheadline)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.stroke))
    }
}

#Preview {
    ContentView()
        .environmentObject(CarController())
        .preferredColorScheme(.dark)
}
