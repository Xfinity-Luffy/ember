import SwiftUI
import MapKit
import UIKit

// MARK: - Location tab

struct LocationView: View {
    @EnvironmentObject private var car: CarController
    @EnvironmentObject private var locator: CarLocator
    @Binding var showSettings: Bool

    @State private var position: MapCameraPosition = .automatic

    /// The car's own GPS position over cellular, if it's newer than the phone's saved spot.
    private var cellularFix: (coordinate: CLLocationCoordinate2D, time: Date, speedKmh: Double)? {
        guard !car.demoMode, let c = car.cellular, let lat = c.latitude, let lon = c.longitude else { return nil }
        let time = c.fixTime ?? c.checkIn
        if let saved = locator.carSpot, car.link == .ready || saved.time > time { return nil }
        return (CLLocationCoordinate2D(latitude: lat, longitude: lon), time, c.speedKmh ?? 0)
    }

    /// The car to show: a pretend spot near you in demo mode, the car's cellular
    /// GPS when that's newest, otherwise the spot saved by this phone.
    private var spot: CLLocationCoordinate2D? {
        if car.demoMode {
            let base = locator.me?.coordinate ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
            return CLLocationCoordinate2D(latitude: base.latitude + 0.0011, longitude: base.longitude + 0.0009)
        }
        return cellularFix?.coordinate ?? locator.carSpot?.coordinate
    }

    /// Live = connected over Bluetooth (phone is at the car), or a fresh cellular GPS fix.
    private var live: Bool {
        if car.demoMode || car.link == .ready { return true }
        if let fix = cellularFix { return Date().timeIntervalSince(fix.time) < 120 }
        return false
    }

    private var moving: Bool { (cellularFix?.speedKmh ?? 0) > 5 }

    var body: some View {
        ZStack {
            EmberBackground(running: car.status.engineRunning)

            ScrollView {
                VStack(spacing: 18) {
                    HStack(alignment: .top, spacing: 12) {
                        Text("Location")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        SettingsButton { showSettings = true }
                    }
                    .padding(.top, 12)

                    ActiveAlertsStrip()

                    if locator.isDenied {
                        permissionCard
                    } else {
                        mapCard
                        infoCard
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 110)
            }
        }
    }

    // MARK: Map

    private var mapCard: some View {
        Map(position: $position) {
            if let spot {
                Annotation(car.carName, coordinate: spot, anchor: .bottom) {
                    CarPin(live: live, alert: car.status.alarmTriggered || car.status.panicOn,
                           hazards: car.status.hazardsOn, type: car.selectedVehicle.type)
                }
            }
            UserAnnotation()
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .frame(height: 340)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Palette.stroke))
        .overlay(alignment: .topLeading) {
            HStack(spacing: 6) {
                Circle()
                    .fill(live ? Palette.good : Color.secondary)
                    .frame(width: 8, height: 8)
                Text(live ? (car.demoMode ? "Live · demo" : (cellularFix != nil ? "Live · cellular" : "Live")) : "Last seen")
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glass(Capsule())
            .padding(12)
        }
        .overlay(alignment: .bottomTrailing) {
            if spot != nil {
                Button { showCar() } label: {
                    Image(systemName: "scope")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .glass(Circle(), interactive: true)
                }
                .buttonStyle(.plain)
                .padding(12)
                .accessibilityLabel("Show car")
            }
        }
    }

    // MARK: Details

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: live ? "location.fill" : "mappin.and.ellipse")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(live ? Palette.good : Palette.accent)
                    .frame(width: 44, height: 44)
                    .background((live ? Palette.good : Palette.accent).opacity(0.15), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if let distance = distanceText {
                HStack(spacing: 8) {
                    Image(systemName: "figure.walk")
                    Text(distance)
                }
                .font(.subheadline.weight(.semibold))
            }

            HStack(spacing: 10) {
                actionButton("Directions", "arrow.triangle.turn.up.right.diamond.fill", tint: Palette.accent) { openDirections() }
                    .disabled(spot == nil)
                    .opacity(spot == nil ? 0.45 : 1)
                actionButton("Park here", "mappin.circle.fill") {
                    Haptics.tap()
                    locator.saveHere()
                    car.notify("Saved this spot for \(car.carName)", kind: .success)
                }
                .disabled(locator.me == nil || car.demoMode)
                .opacity(locator.me == nil || car.demoMode ? 0.45 : 1)
                if let spot, let url = shareURL(spot) {
                    ShareLink(item: url, subject: Text(car.carName),
                              message: Text("Here's where \(car.carName) is parked")) {
                        actionLabel("Share", "square.and.arrow.up")
                    }
                    .buttonStyle(.plain)
                } else {
                    actionLabel("Share", "square.and.arrow.up").opacity(0.45)
                }
            }

            Text(footnote)
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(24)
    }

    private var title: String {
        if spot == nil { return "No location yet" }
        if car.demoMode { return "Demo car is nearby" }
        if car.link == .ready { return "You're at your car" }
        if moving { return "Your car is moving" }
        if cellularFix != nil { return live ? "Your car, live over cellular" : "Your car's last GPS position" }
        return "Your car is parked"
    }

    private var subtitle: String {
        if spot == nil { return "Open the app near your car once and its spot is saved automatically." }
        if car.demoMode { return "Pretend spot near you." }
        if let fix = cellularFix {
            let speed = Measurement(value: fix.speedKmh, unit: UnitSpeed.kilometersPerHour)
                .formatted(.measurement(width: .abbreviated, usage: .general, numberFormatStyle: .number.precision(.fractionLength(0))))
            let when = fix.time.formatted(.relative(presentation: .named))
            return moving ? "\(speed) · updated \(when)" : "From the car's GPS · \(when)"
        }
        let place = locator.address ?? "Location saved"
        if live { return "\(place) · updating live" }
        if let time = locator.carSpot?.time {
            return "\(place) · \(time.formatted(.relative(presentation: .named)))"
        }
        return place
    }

    private var distanceText: String? {
        guard let spot, let me = locator.me else { return nil }
        let meters = me.distance(from: CLLocation(latitude: spot.latitude, longitude: spot.longitude))
        if meters < 15 { return "Right next to you" }
        let distance = Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
        let minutes = max(1, Int((meters / 80).rounded()))    // about 80 m per minute walking
        return "\(distance) away · about \(minutes) min walk"
    }

    private var footnote: String {
        if car.demoMode { return "Turn off demo mode to save your real car's spot." }
        if car.connectionMode != .bluetooth {
            return "Over cellular, the car sends its GPS position about once a minute when parked, every 20 seconds when driving, and every few seconds while this screen is open."
        }
        return "Updates live while the app is connected to your car. After you walk away, it keeps the last spot. It stays on this iPhone."
    }

    private func actionLabel(_ title: String, _ symbol: String, tint: Color? = nil) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
            Text(title).font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .glassCard(16, tint: tint?.opacity(0.4), interactive: true)
    }

    private func actionButton(_ title: String, _ symbol: String, tint: Color? = nil,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) { actionLabel(title, symbol, tint: tint) }
            .buttonStyle(.plain)
    }

    private func shareURL(_ spot: CLLocationCoordinate2D) -> URL? {
        var parts = URLComponents(string: "https://maps.apple.com/")
        parts?.queryItems = [URLQueryItem(name: "ll", value: String(format: "%.6f,%.6f", spot.latitude, spot.longitude)),
                             URLQueryItem(name: "q", value: car.carName)]
        return parts?.url
    }

    private func showCar() {
        guard let spot else { return }
        withAnimation {
            position = .region(MKCoordinateRegion(center: spot, latitudinalMeters: 400, longitudinalMeters: 400))
        }
    }

    private func openDirections() {
        guard let spot else { return }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: spot))
        item.name = car.carName
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }

    // MARK: Permission

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Location is off for Ember", systemImage: "location.slash.fill")
                .font(.headline)
            Text("Ember uses your iPhone's location to remember where your car is. Turn it on in Settings › Ember › Location › While Using the App.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            } label: {
                Text("Open Settings")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .glassCard(16, tint: Palette.accent.opacity(0.4), interactive: true)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(24)
    }
}

// MARK: - Car pin on the map

struct CarPin: View {
    let live: Bool
    let alert: Bool
    let hazards: Bool
    var type: VehicleType = .car

    @State private var pulse = false

    private var color: Color { alert ? .red : (hazards ? .orange : Palette.accent) }

    var body: some View {
        ZStack {
            if live || alert || hazards {
                Circle()
                    .stroke(color.opacity(pulse ? 0 : 0.7), lineWidth: 3)
                    .frame(width: pulse ? 70 : 38, height: pulse ? 70 : 38)
            }
            VehicleSilhouette(type: type, color: .white)
                .padding(.horizontal, 5)
                .frame(width: 40, height: 40)
                .background(color.gradient, in: Circle())
                .overlay(Circle().stroke(.white, lineWidth: 2.5))
                .shadow(color: color.opacity(0.6), radius: 8)
        }
        .frame(width: 72, height: 72)
        .onAppear {
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
        }
        .accessibilityLabel("Your car")
    }
}
