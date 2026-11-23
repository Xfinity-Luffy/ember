import Foundation

/// What the app sent to the car and how it went, newest first. Kept on this iPhone.
struct ActivityEntry: Codable, Identifiable, Equatable {
    enum Source: String, Codable {
        case app, siri, widget, automatic
        var label: String {
            switch self {
            case .app: return "App"
            case .siri: return "Siri or Shortcuts"
            case .widget: return "Widget"
            case .automatic: return "Automatic"
            }
        }
    }
    var id = UUID()
    var date: Date
    var vehicle: String
    var action: String
    var succeeded: Bool
    var detail: String?
    var source: Source
}

@MainActor
final class ActivityLog: ObservableObject {
    static let shared = ActivityLog()
    @Published private(set) var entries: [ActivityEntry] = []
    private let key = "ember.activityLog"
    private let maxEntries = 300

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([ActivityEntry].self, from: data) {
            entries = saved
        }
    }

    func add(_ entry: ActivityEntry) {
        entries.insert(entry, at: 0)
        if entries.count > maxEntries { entries.removeLast(entries.count - maxEntries) }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(data, forKey: key) }
    }
}
