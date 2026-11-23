import Foundation
import ActivityKit

/// Starts, updates and ends the "engine running" Live Activity from the car's status.
@MainActor
enum RunningActivity {
    private static var current: Activity<RunningActivityAttributes>?
    private static var lastEnd: Date?

    static func update(name: String, type: VehicleType, status: CarStatus) {
        let running = status.engineRunning && status.secondsRemaining > 0
        guard running else { end(); return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let endsAt = Date().addingTimeInterval(TimeInterval(status.secondsRemaining))
        let state = RunningActivityAttributes.ContentState(endsAt: endsAt, hazards: status.hazardsOn)
        let content = ActivityContent(state: state, staleDate: endsAt.addingTimeInterval(60))
        if let current {
            // Only update when the end time moved noticeably (the timer counts down by itself).
            if let lastEnd, abs(lastEnd.timeIntervalSince(endsAt)) < 5,
               current.content.state.hazards == status.hazardsOn { return }
            lastEnd = endsAt
            Task { await current.update(content) }
        } else {
            let attributes = RunningActivityAttributes(vehicleName: name, vehicleType: type.rawValue)
            current = try? Activity.request(attributes: attributes, content: content, pushType: nil)
            lastEnd = endsAt
        }
    }

    static func end() {
        guard let activity = current else { return }
        current = nil
        lastEnd = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
