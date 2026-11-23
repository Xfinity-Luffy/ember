import SwiftUI
import MapKit
import CoreLocation

// MARK: - Palette

enum Palette {
    static let accent = Color(red: 1.00, green: 0.42, blue: 0.21)      // ember orange
    static let accentSoft = Color(red: 1.00, green: 0.62, blue: 0.35)
    static let cool = Color(red: 0.42, green: 0.74, blue: 1.00)         // unlocked / climate blue
    static let good = Color(red: 0.30, green: 0.85, blue: 0.45)
    static let surface = Color.white.opacity(0.06)
    static let stroke = Color.white.opacity(0.10)
}

// MARK: - App shell: five tabs, one banner, one settings sheet

struct ContentView: View {
    @EnvironmentObject private var car: CarController
    @EnvironmentObject private var locator: CarLocator
    @State private var showSettings = false

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $car.selectedTab) {
                RemoteView(showSettings: $showSettings)
                    .tabItem { Label("Home", systemImage: "car.side.fill") }
                    .tag(AppTab.remote)
                VehicleView(showSettings: $showSettings)
                    .tabItem { Label("Vehicle", systemImage: "gauge.with.dots.needle.67percent") }
                    .tag(AppTab.vehicle)
                HazardsView(showSettings: $showSettings)
                    .tabItem { Label("Hazards", systemImage: "exclamationmark.triangle") }
                    .tag(AppTab.hazards)
                    .badge(car.status.hazardsOn ? Text("On") : nil)
                AlarmView(showSettings: $showSettings)
                    .tabItem { Label("Alarm", systemImage: "shield") }
                    .tag(AppTab.alarm)
                    .badge(car.status.alarmTriggered || car.status.panicOn ? Text("!") : nil)
                LocationView(showSettings: $showSettings)
                    .tabItem { Label("Location", systemImage: "mappin.and.ellipse") }
                    .tag(AppTab.location)
            }
            .tint(Palette.accent)

            if let banner = car.banner {
                BannerView(banner: banner)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 70)      // sits just above the tab bar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: car.banner)
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(car) }
        .sheet(isPresented: $car.showingVehicles) { VehiclesView().environmentObject(car) }
        .onOpenURL { url in handleLink(url) }
        .onAppear { locator.useVehicle(spotKey: car.selectedVehicle.spotKey) }
        .onChange(of: car.selectedVehicleID) { _, _ in locator.useVehicle(spotKey: car.selectedVehicle.spotKey) }
        // While the app is connected to the bridge, the phone is at the car:
        // let the locator keep the car's spot up to date.
        .onAppear { locator.nearCar = car.link == .ready && !car.demoMode }
        .onChange(of: car.link) { _, link in locator.nearCar = link == .ready && !car.demoMode }
    }

    /// ember://lock, unlock, start, location, home (from widgets and the Live Activity).
    private func handleLink(_ url: URL) {
        guard url.scheme == EmberLink.scheme else { return }
        showSettings = false
        car.showingVehicles = false
        switch url.host ?? "" {
        case "lock": car.selectedTab = .remote; car.perform(.lock, source: .widget)
        case "unlock": car.selectedTab = .remote; car.perform(.unlock, source: .widget)
        case "start":
            car.selectedTab = .remote
            if car.status.engineRunning { car.notify("\(car.carName) is already running", kind: .info) }
            else { car.requestStart(source: .widget) }
        case "location": car.selectedTab = .location
        default: car.selectedTab = .remote
        }
    }
}

// MARK: - Home tab (fits on one screen, above the tab bar)

struct RemoteView: View {
    @EnvironmentObject private var car: CarController
    @EnvironmentObject private var locator: CarLocator
    @Binding var showSettings: Bool

    private var ready: Bool { car.link.isUsable && car.pending == nil }
    private var running: Bool { car.status.engineRunning }

    var body: some View {
        ZStack {
            EmberBackground(running: running || car.status.alarmTriggered)

            VStack(spacing: 12) {
                header
                if !car.demoMode && !car.hasKey { keyMissingCard }
                hero
                SlideControl(title: slideTitle,
                             symbol: "power",
                             tint: Palette.accent,
                             active: running,
                             busy: car.pending == .start || car.pending == .stop,
                             enabled: ready,
                             onSlide: { if running { car.perform(.stop) } else { car.requestStart() } },
                             onTap: { car.holdHint() })
                dock
                tiles
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 8)
        }
        .animation(.easeInOut(duration: 0.25), value: car.status)
        .alert("Battery is low", isPresented: Binding(get: { car.lowBatteryStartWarning != nil },
                                                    set: { if !$0 { car.lowBatteryStartWarning = nil } })) {
            Button("Start anyway") {
                car.lowBatteryStartWarning = nil
                car.perform(.start)
            }
            Button("Cancel", role: .cancel) { car.lowBatteryStartWarning = nil }
        } message: {
            Text("The battery reads \(String(format: "%.1f", car.lowBatteryStartWarning ?? 0)) V. The engine may not crank, and trying can drain it further.")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            // Long names wrap onto a second line (then shrink a little) instead of
            // pushing the settings button out of place.
            Button { car.showingVehicles = true } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(car.carName)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
                        Circle()
                            .fill(car.link.isUsable ? Palette.good : Color.orange)
                            .frame(width: 7, height: 7)
                            .shadow(color: car.link.isUsable ? Palette.good : .clear, radius: 4)
                        Text(statusLine)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(car.carName). \(statusLine). Switch vehicle")
            SettingsButton { showSettings = true }
        }
        .padding(.top, 8)
    }

    private var statusLine: String {
        guard car.link.isUsable else { return car.link.label }
        var parts: [String] = []
        switch car.status.lock {
        case .locked: parts.append("Locked")
        case .unlocked: parts.append("Unlocked")
        case .unknown: break
        }
        parts.append(running ? "Running" : "Parked")
        parts.append(car.demoMode ? "Demo" : car.connectionMode.title)
        if car.vehicles.count > 1 { parts.append("\(car.vehicles.count) vehicles") }
        return parts.joined(separator: " · ")
    }

    private var keyMissingCard: some View {
        Button { showSettings = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "key.fill").foregroundStyle(Palette.accent)
                Text("Add your bridge key so the app can control the car.")
                    .font(.footnote.weight(.medium))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
            }
            .padding(12)
            .glassCard(16, tint: Palette.accent.opacity(0.3))
        }
        .buttonStyle(.plain)
    }

    // MARK: Hero: the vehicle with its lights

    private var hero: some View {
        ZStack(alignment: .top) {
            VehicleSilhouette(type: car.selectedVehicle.type,
                              color: car.selectedVehicle.color.swatch,
                              running: running,
                              hazards: car.status.hazardsOn,
                              panic: car.status.panicOn,
                              alarm: car.status.alarmTriggered)
                .padding(.horizontal, 8)
                .padding(.top, 34)
                .frame(maxWidth: .infinity, maxHeight: 190)
                .frame(maxHeight: .infinity)

            HStack {
                if running {
                    chip(running && car.status.secondsRemaining > 0
                         ? "Running \(clock(car.status.secondsRemaining))" : "Running",
                         symbol: "engine.combustion.fill", tint: Palette.accentSoft)
                }
                Spacer()
                if car.vehicle.batteryIsLow, let v = car.vehicle.batteryVolts {
                    chip(String(format: "Battery %.1f V", v), symbol: "minus.plus.batteryblock.exclamationmark", tint: .orange)
                    Spacer()
                }
                switch car.status.lock {
                case .locked: chip("Locked", symbol: "lock.fill", tint: .primary)
                case .unlocked: chip("Unlocked", symbol: "lock.open.fill", tint: Palette.cool)
                case .unknown: EmptyView()
                }
            }
        }
        .frame(minHeight: 90, maxHeight: .infinity)
    }

    private func chip(_ text: String, symbol: String, tint: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .glass(Capsule())
    }

    private var slideTitle: String {
        if car.pending == .start { return "Starting…" }
        if car.pending == .stop { return "Stopping…" }
        return running ? "Slide to stop" : "Slide to start"
    }

    // MARK: Control dock

    private var dock: some View {
        HStack {
            DockButton(title: "Lock", symbol: "lock.fill", tint: Palette.accent,
                       on: car.status.lock == .locked, busy: car.pending == .lock, enabled: ready) {
                car.perform(.lock)
            }
            Spacer()
            DockButton(title: "Unlock", symbol: "lock.open.fill", tint: Palette.cool,
                       on: car.status.lock == .unlocked, busy: car.pending == .unlock, enabled: ready) {
                car.perform(.unlock)
            }
            Spacer()
            DockButton(title: !running && car.defrostOnStart ? "Next start" : "Defrost",
                       symbol: "windshield.rear.and.heat.waves", tint: Palette.cool,
                       on: !running && car.defrostOnStart, busy: car.pending == .aux1,
                       enabled: running ? ready : true) {
                if running {
                    car.perform(.aux1)
                } else {
                    car.defrostOnStart.toggle()
                    car.notify(car.defrostOnStart ? "Rear defrost will turn on with the next start"
                                                  : "Rear defrost won't turn on with the next start",
                               kind: .info)
                }
            }
            Spacer()
            DockButton(title: "Hazards", symbol: "exclamationmark.triangle.fill", tint: .orange,
                       on: car.status.hazardsOn,
                       busy: car.pending == .hazardsOn || car.pending == .hazardsOff, enabled: ready) {
                car.perform(car.status.hazardsOn ? .hazardsOff : .hazardsOn)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: Tiles

    private var tiles: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                TileButton { car.selectedTab = .vehicle } content: { FuelTile(percent: car.vehicle.fuelPercent, age: car.vehicle.fuelAgeMinutes) }
                TileButton { car.selectedTab = .vehicle } content: { TireTile(psi: car.vehicle.tiresPSI) }
            }
            GridRow {
                TileButton { car.selectedTab = .location } content: { MapTile() }
                TileButton { car.selectedTab = .alarm } content: { AlarmTile(status: car.status) }
            }
        }
    }
}

// MARK: - Slide to start / stop

struct SlideControl: View {
    let title: String
    let symbol: String
    let tint: Color
    let active: Bool
    let busy: Bool
    let enabled: Bool
    let onSlide: () -> Void
    let onTap: () -> Void

    @State private var offset: CGFloat = 0
    private let knob: CGFloat = 50

    var body: some View {
        GeometryReader { geo in
            let maxX = max(1, geo.size.width - knob - 8)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.clear)
                    .glass(Capsule(), tint: active ? tint.opacity(0.35) : nil)
                Text(title)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.leading, 44)
                    .opacity(1 - Double(offset / maxX))
                Circle()
                    .fill(active ? Color.white : tint)
                    .frame(width: knob, height: knob)
                    .overlay {
                        if busy {
                            ProgressView().tint(active ? tint : .white)
                        } else {
                            Image(systemName: symbol)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(active ? tint : .white)
                        }
                    }
                    .shadow(color: (active ? Color.white : tint).opacity(0.55), radius: 12)
                    .offset(x: 4 + offset)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard enabled else { return }
                                offset = min(max(0, value.translation.width), maxX)
                            }
                            .onEnded { _ in
                                let moved = offset
                                withAnimation(.spring(duration: 0.3)) { offset = 0 }
                                guard enabled else { return }
                                if moved > maxX * 0.85 {
                                    Haptics.tap()
                                    onSlide()
                                } else if moved < 8 {
                                    onTap()
                                }
                            }
                    )
            }
        }
        .frame(height: 58)
        .opacity(enabled || busy ? 1 : 0.45)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if enabled { onSlide() } }
    }
}

// MARK: - Round dock button

struct DockButton: View {
    let title: String
    let symbol: String
    let tint: Color
    let on: Bool
    let busy: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button { Haptics.tap(); action() } label: {
            VStack(spacing: 6) {
                ZStack {
                    if busy {
                        ProgressView()
                    } else {
                        Image(systemName: symbol).font(.system(size: 20, weight: .semibold))
                    }
                }
                .frame(width: 56, height: 56)
                .glass(Circle(), tint: on ? tint.opacity(0.45) : nil, interactive: true)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled || busy ? 1 : 0.45)
        .accessibilityLabel(title)
        .accessibilityValue(on ? "On" : "")
    }
}

// MARK: - Home tiles

struct TileButton<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        Button { Haptics.tap(); action() } label: {
            content()
                .frame(maxWidth: .infinity, minHeight: 84, maxHeight: 84, alignment: .topLeading)
                .glassCard(22, interactive: true)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct TileLabel: View {
    let text: String
    let symbol: String
    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

struct FuelTile: View {
    let percent: Int?
    let age: Int?

    private var tint: Color {
        guard let p = percent else { return .secondary }
        return p <= 12 ? .red : (p <= 25 ? .orange : Palette.accent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TileLabel(text: "Fuel", symbol: "fuelpump")
            HStack(spacing: 10) {
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.12), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: Double(percent ?? 0) / 100)
                        .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text(percent.map { "\($0)%" } ?? "--")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(percent == nil ? "No reading yet" : (updatedText(age)?.replacingOccurrences(of: "Updated ", with: "") ?? "Fuel left"))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(percent.map { "Fuel \($0) percent left" } ?? "Fuel level unknown")
    }
}

struct TireTile: View {
    let psi: [Double]?
    private let low = 30.0
    private let names = ["Front left", "Front right", "Rear left", "Rear right"]

    var body: some View {
        let lowIndexes = (psi ?? []).enumerated().filter { $0.element < low }.map { $0.offset }
        VStack(alignment: .leading, spacing: 6) {
            TileLabel(text: "Tires", symbol: "circle.circle")
            if let psi {
                Text(lowIndexes.isEmpty ? "All good" : "\(lowIndexes.count) low")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(lowIndexes.isEmpty ? Palette.good : .orange)
                Text(lowIndexes.first.map { "\(names[$0]) · \(Int(psi[$0].rounded())) psi" }
                     ?? "\(Int((psi.min() ?? 0).rounded()))–\(Int((psi.max() ?? 0).rounded())) psi")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text("Not set up").font(.system(size: 20, weight: .bold, design: .rounded))
                Text("See the Vehicle tab").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .accessibilityElement(children: .combine)
    }
}

struct AlarmTile: View {
    let status: CarStatus

    var body: some View {
        let (title, tint, sub): (String, Color, String) = {
            if status.alarmTriggered { return ("Went off", .red, "Tap for details") }
            if status.panicOn { return ("Panic on", .red, "Horn and lights") }
            switch status.lock {
            case .locked: return ("Armed", Palette.good, "Doors locked")
            case .unlocked: return ("Not armed", .secondary, "Doors unlocked")
            case .unknown: return ("Unknown", .secondary, "Lock to arm")
            }
        }()
        VStack(alignment: .leading, spacing: 6) {
            TileLabel(text: "Alarm", symbol: "shield")
            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
            Text(sub).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12)
        .accessibilityElement(children: .combine)
    }
}

/// Small static map of where the car is; tap to open the Location tab.
struct MapTile: View {
    @EnvironmentObject private var car: CarController
    @EnvironmentObject private var locator: CarLocator

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let spot = car.mapSpot(locator: locator) {
                Map(initialPosition: .region(MKCoordinateRegion(center: spot, latitudinalMeters: 450, longitudinalMeters: 450)),
                    interactionModes: []) {
                    Annotation("", coordinate: spot) {
                        Circle().fill(Palette.accent).frame(width: 14, height: 14)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                    UserAnnotation()
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .id(car.selectedVehicleID)
                .allowsHitTesting(false)
            } else {
                LinearGradient(colors: [Color.primary.opacity(0.08), Color.primary.opacity(0.02)],
                               startPoint: .top, endPoint: .bottom)
                Image(systemName: "map")
                    .font(.system(size: 30))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text(caption)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .glass(Capsule())
                .padding(8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Location. \(caption)")
    }

    private var caption: String {
        guard let spot = car.mapSpot(locator: locator) else { return "Find my car" }
        guard let me = locator.me else { return "Car location" }
        let meters = me.distance(from: CLLocation(latitude: spot.latitude, longitude: spot.longitude))
        if meters < 15 { return "Right here" }
        return Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road)) + " away"
    }
}

// MARK: - Status card (one plain-English line about the car)

struct StatusCard: View {
    let link: LinkState
    let status: CarStatus
    let demo: Bool
    var checkIn: Date? = nil

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
        case .searching, .connecting, .cellularWaiting: return "antenna.radiowaves.left.and.right"
        case .ready, .demo, .cellular: return status.engineRunning ? "engine.combustion.fill" : "car.fill"
        }
    }

    private var tint: Color {
        switch link {
        case .bluetoothOff, .unauthorized: return .yellow
        case .searching, .connecting, .cellularWaiting: return .secondary
        case .ready, .demo, .cellular: return status.engineRunning ? Palette.accent : Palette.good
        }
    }

    private var title: String {
        switch link {
        case .bluetoothOff: return "Bluetooth is off"
        case .unauthorized: return "Bluetooth isn't allowed"
        case .searching: return "Looking for your car…"
        case .connecting: return "Connecting…"
        case .cellularWaiting: return "Waiting for your car…"
        case .ready, .demo, .cellular:
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
        case .cellularWaiting: return "It checks in over cellular about once a minute. Make sure it has signal."
        case .cellular:
            guard let checkIn else { return "Connected via cellular." }
            return "Connected via cellular · checked in \(checkIn.formatted(.relative(presentation: .named)))."
        case .ready, .demo:
            let mode = demo ? "Demo car, not connected to a real one." : "Connected to your car."
            return mode
        }
    }
}

// MARK: - Banner

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
