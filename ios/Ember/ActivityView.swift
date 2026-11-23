import SwiftUI

/// History of commands sent to your cars (Settings › Activity).
struct ActivityView: View {
    @ObservedObject private var log = ActivityLog.shared
    @State private var confirmClear = false

    var body: some View {
        ZStack {
            EmberBackground(running: false)
            if log.entries.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 40)).foregroundStyle(.secondary)
                    Text("Nothing yet").font(.headline)
                    Text("Every lock, unlock and start shows up here, with the time and whether it worked.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(32)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(groups, id: \.0) { day, entries in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(day).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                                    .padding(.leading, 4)
                                VStack(spacing: 0) {
                                    ForEach(entries) { e in
                                        row(e)
                                        if e.id != entries.last?.id { Divider().overlay(Palette.stroke).padding(.leading, 52) }
                                    }
                                }
                                .padding(.vertical, 4)
                                .glassCard(20)
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !log.entries.isEmpty {
                ToolbarItem(placement: .primaryAction) { Button("Clear") { confirmClear = true } }
            }
        }
        .confirmationDialog("Clear the activity history on this iPhone?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear history", role: .destructive) { log.clear() }
        }
    }

    private var groups: [(String, [ActivityEntry])] {
        var result: [(String, [ActivityEntry])] = []
        for e in log.entries {
            let day = e.date.formatted(Date.FormatStyle().weekday(.wide).month(.abbreviated).day())
            let label = Calendar.current.isDateInToday(e.date) ? "Today"
                : (Calendar.current.isDateInYesterday(e.date) ? "Yesterday" : day)
            if result.last?.0 == label { result[result.count - 1].1.append(e) } else { result.append((label, [e])) }
        }
        return result
    }

    private func row(_ e: ActivityEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon(for: e.action))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(e.succeeded ? Palette.accent : .red)
                .frame(width: 32, height: 32)
                .background((e.succeeded ? Palette.accent : Color.red).opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("\(e.action) · \(e.vehicle)").font(.subheadline.weight(.medium)).lineLimit(1)
                Text([e.succeeded ? nil : "Didn't go through", e.detail, e.source.label]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            Text(e.date.formatted(date: .omitted, time: .shortened))
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func icon(for action: String) -> String {
        switch action {
        case "Lock": return "lock.fill"
        case "Unlock": return "lock.open.fill"
        case "Start": return "power"
        case "Stop": return "stop.fill"
        case "Rear defrost": return "windshield.rear.and.heat.waves"
        case "Hazards on", "Hazards off": return "exclamationmark.triangle.fill"
        case "Panic alarm", "Panic off": return "light.beacon.max.fill"
        default: return "gearshape.fill"
        }
    }
}

/// How to use Siri, Shortcuts, widgets and scheduled starts.
struct ShortcutsHelpView: View {
    var body: some View {
        ZStack {
            EmberBackground(running: false)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    tip("Siri", "mic.fill",
                        "Say \"Start my car with Ember\", \"Lock my car with Ember\" or \"Check my car with Ember\". Unlock and Start ask for Face ID first.")
                    tip("Schedule a start", "alarm.fill",
                        "Shortcuts app › Automation › New Automation › Time of Day. Pick the time and days, choose Run Immediately, then add Ember's \"Start car\" action.")
                    tip("Widgets", "square.grid.2x2.fill",
                        "Touch and hold the Home Screen or Lock Screen, tap Edit › Add Widget, and choose Ember. The buttons open Ember and run the action.")
                    tip("Control Center and Action Button", "switch.2",
                        "Add a Shortcuts control in Control Center, or set the Action Button to Shortcut, then pick an Ember action.")
                    tip("Live Activity", "timer",
                        "After a remote start, the time left shows on your Lock Screen and in the Dynamic Island.")
                    Text("Siri and Shortcuts use the vehicle selected in Ember. They need your iPhone near the car over Bluetooth, or cellular set up.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(20)
            }
        }
        .navigationTitle("Siri and Shortcuts")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tip(_ title: String, _ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            RowIcon(symbol, Palette.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(20)
    }
}
