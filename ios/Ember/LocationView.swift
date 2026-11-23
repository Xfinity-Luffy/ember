import SwiftUI
import MapKit
import UIKit

// MARK: - Location tab

struct LocationView: View {
    @EnvironmentObject private var car: CarController
    @EnvironmentObject private var locator: CarLocator
    @Binding var showSettings: Bool

    @State private var position: MapCameraPosition = .automatic

    /// The car to show: a pretend spot near you in demo mode, otherwise the saved spot.
    private var spot: CLLocationCoordinate2D? {
        if car.demoMode {
            let base = locator.me?.coordinate ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
            return CLLocationCoordinate2D(latitude: base.latitude + 0.0011, longitude: base.longitude + 0.0009)
        }
        return locator.carSpot?.coordinate
    }

    /// Live = the app is connected to the bridge right now, so the phone is at the car.
    private var live: Bool { car.demoMode || car.link == .ready }

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
                           hazards: car.status.hazardsOn)
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
                Text(live ? (car.demoMode ? "Live · demo" : "Live") : "Last seen")
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glass(Capsule())
            .padding(12)
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

            HStack(spacing: 12) {
                Button { openDirections() } label: {
                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .glassCard(16, tint: Palette.accent.opacity(0.4), interactive: true)
                }
                .buttonStyle(.plain)
                .disabled(spot == nil)
                .opacity(spot == nil ? 0.45 : 1)

                Button { showCar() } label: {
                    Label("Show car", systemImage: "scope")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .glassCard(16, interactive: true)
                }
                .buttonStyle(.plain)
                .disabled(spot == nil)
                .opacity(spot == nil ? 0.45 : 1)
            }

            if !car.demoMode && !live {
                Button {
                    Haptics.tap()
                    locator.saveHere()
                } label: {
                    Label("My car is here", systemImage: "mappin.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .glassCard(16, interactive: true)
                }
                .buttonStyle(.plain)
                .disabled(locator.me == nil)
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
        if live { return car.demoMode ? "Demo car is nearby" : "You're at your car" }
        return "Your car is parked"
    }

    private var subtitle: String {
        if spot == nil { return "Open the app near your car once and its spot is saved automatically." }
        if car.demoMode { return "Pretend spot near you." }
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
        car.demoMode
            ? "Turn off demo mode to save your real car's spot."
            : "Updates live while the app is connected to your car. After you walk away, it keeps the last spot. It stays on this iPhone."
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

    @State private var pulse = false

    private var color: Color { alert ? .red : (hazards ? .orange : Palette.accent) }

    var body: some View {
        ZStack {
            if live || alert || hazards {
                Circle()
                    .stroke(color.opacity(pulse ? 0 : 0.7), lineWidth: 3)
                    .frame(width: pulse ? 70 : 38, height: pulse ? 70 : 38)
            }
            Image(systemName: "car.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
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
