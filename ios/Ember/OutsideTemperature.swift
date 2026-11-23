import Foundation
import CoreLocation

/// Current outside temperature near the car, from Open-Meteo (free, no account).
/// Used by "Defrost when it's cold".
enum OutsideTemperature {
    /// Where the car (or phone) was last seen; CarLocator keeps this up to date.
    static let latKey = "ember.lastLatitude"
    static let lonKey = "ember.lastLongitude"

    static func remember(_ c: CLLocationCoordinate2D) {
        UserDefaults.standard.set(c.latitude, forKey: latKey)
        UserDefaults.standard.set(c.longitude, forKey: lonKey)
    }

    /// Degrees Celsius, or nil if unknown (no location yet, offline, etc.).
    static func celsius() async -> Double? {
        let d = UserDefaults.standard
        guard d.object(forKey: latKey) != nil else { return nil }
        let lat = d.double(forKey: latKey), lon = d.double(forKey: lonKey)
        var parts = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        parts?.queryItems = [URLQueryItem(name: "latitude", value: String(format: "%.3f", lat)),
                             URLQueryItem(name: "longitude", value: String(format: "%.3f", lon)),
                             URLQueryItem(name: "current", value: "temperature_2m")]
        guard let url = parts?.url else { return nil }
        struct Response: Decodable {
            struct Current: Decodable { let temperature_2m: Double }
            let current: Current
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        guard let result = try? await URLSession.shared.data(for: request),
              let r = try? JSONDecoder().decode(Response.self, from: result.0) else { return nil }
        return r.current.temperature_2m
    }

    /// "28°F" or "-2°C", following the iPhone's settings.
    static func text(_ celsius: Double) -> String {
        Measurement(value: celsius, unit: UnitTemperature.celsius)
            .formatted(.measurement(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))))
    }
}
