import Foundation
import CoreLocation

/// Remembers where the car is.
///
/// The bridge has no GPS, so the phone stands in for it: while the app is
/// connected to the bridge over Bluetooth, the phone is within a few meters of
/// the car, so the phone's own location *is* the car's location. Every location
/// update during that time moves the saved spot ("live"). After you walk away,
/// the last saved spot stays put ("last seen").
///
/// Everything stays on this iPhone.
@MainActor
final class CarLocator: NSObject, ObservableObject {
    struct CarSpot: Codable, Equatable {
        var latitude: Double
        var longitude: Double
        var time: Date
        var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    }

    @Published private(set) var me: CLLocation?
    @Published private(set) var carSpot: CarSpot?
    @Published private(set) var address: String?
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined

    /// True while the app is connected to the bridge (so the phone is at the car).
    var nearCar = false {
        didSet { if nearCar, let me { save(me) } }
    }

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var lastGeocoded: CLLocation?
    /// The selected vehicle's storage key (see Vehicle.spotKey).
    private var storeKey = ""

    override init() {
        super.init()
        authorization = manager.authorizationStatus
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5          // meters between updates
    }

    /// Switch to another vehicle's saved spot.
    func useVehicle(spotKey: String) {
        guard spotKey != storeKey else { return }
        storeKey = spotKey
        carSpot = nil
        address = nil
        lastGeocoded = nil
        if let data = UserDefaults.standard.data(forKey: storeKey),
           let spot = try? JSONDecoder().decode(CarSpot.self, from: data) {
            carSpot = spot
            lookUpAddress(for: CLLocation(latitude: spot.latitude, longitude: spot.longitude))
        }
    }

    var isAllowed: Bool { authorization == .authorizedWhenInUse || authorization == .authorizedAlways }
    var isDenied: Bool { authorization == .denied || authorization == .restricted }

    /// Call when the app becomes active.
    func start() {
        if authorization == .notDetermined { manager.requestWhenInUseAuthorization() }
        if isAllowed { manager.startUpdatingLocation() }
    }

    /// Call when the app goes to the background (saves battery).
    func stop() { manager.stopUpdatingLocation() }

    /// "My car is here" button, for when the bridge isn't connected.
    func saveHere() {
        guard let me else { return }
        save(me)
    }

    private func save(_ location: CLLocation) {
        guard !storeKey.isEmpty else { return }
        let spot = CarSpot(latitude: location.coordinate.latitude,
                           longitude: location.coordinate.longitude,
                           time: Date())
        carSpot = spot
        if let data = try? JSONEncoder().encode(spot) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
        // Only look the address up again after moving a bit, not on every update.
        if lastGeocoded.map({ $0.distance(from: location) > 40 }) ?? true {
            lookUpAddress(for: location)
        }
    }

    private func lookUpAddress(for location: CLLocation) {
        lastGeocoded = location
        geocoder.cancelGeocode()
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            let p = placemarks?.first
            let line = [p?.subThoroughfare, p?.thoroughfare].compactMap { $0 }.joined(separator: " ")
            let text = line.isEmpty ? (p?.name ?? p?.locality) : [line, p?.locality].compactMap { $0 }.joined(separator: ", ")
            Task { @MainActor in self?.address = text }
        }
    }
}

extension CarLocator: @preconcurrency CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last,
              latest.horizontalAccuracy >= 0, latest.horizontalAccuracy < 65 else { return }  // ignore rough fixes
        me = latest
        if nearCar { save(latest) }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if isAllowed { manager.startUpdatingLocation() }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Temporary failures (no GPS indoors, etc.) are fine; the next fix updates things.
    }
}
