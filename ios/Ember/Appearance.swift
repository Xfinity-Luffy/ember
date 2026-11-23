import SwiftUI
import Combine

/// Light / dark choice in Settings.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark, automatic
    static let storageKey = "ember.appearance"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        case .automatic: return "Auto"
        }
    }

    var explanation: String {
        switch self {
        case .system: return "Matches your iPhone's Light or Dark setting."
        case .light: return "Always light."
        case .dark: return "Always dark."
        case .automatic: return "Light during the day, dark from 7 PM to 7 AM."
        }
    }

    /// nil = follow the iPhone.
    func scheme(at date: Date = Date()) -> ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        case .automatic:
            let hour = Calendar.current.component(.hour, from: date)
            return (hour >= 19 || hour < 7) ? .dark : .light
        }
    }
}

/// Applies the chosen appearance to the whole app and re-checks Auto every minute.
struct AppearanceRoot<Content: View>: View {
    @AppStorage(AppearanceMode.storageKey) private var appearance = AppearanceMode.system.rawValue
    @State private var now = Date()
    @ViewBuilder let content: () -> Content

    private let tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        content()
            .preferredColorScheme((AppearanceMode(rawValue: appearance) ?? .system).scheme(at: now))
            .onReceive(tick) { now = $0 }
    }
}
