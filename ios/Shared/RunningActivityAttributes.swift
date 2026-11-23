import Foundation
import ActivityKit

/// Live Activity shown on the Lock Screen and in the Dynamic Island while the
/// engine is running after a remote start. Shared by the app and the widget extension.
struct RunningActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// When the remote start will shut the engine off.
        var endsAt: Date
        var hazards: Bool
    }
    var vehicleName: String
    /// "car", "hatchback", "suv" or "truck" (for the icon).
    var vehicleType: String
}

/// Deep links the widgets use to open the app and run an action.
enum EmberLink {
    static let scheme = "ember"
    static func url(_ action: String) -> URL { URL(string: "\(scheme)://\(action)")! }
}
