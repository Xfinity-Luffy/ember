import WidgetKit
import SwiftUI
import ActivityKit

// Home Screen and Lock Screen buttons, plus the "engine running" Live Activity.
// The buttons open Ember and run the action there (Face ID rules from Settings still apply).

private let ember = Color(red: 1.00, green: 0.42, blue: 0.21)

@main
struct EmberWidgetBundle: WidgetBundle {
    var body: some Widget {
        StartWidget()
        LockWidget()
        QuickActionsWidget()
        RunningLiveActivity()
    }
}

// MARK: - Timeline (the buttons never change, so one entry is enough)

struct StaticEntry: TimelineEntry { let date: Date }

struct StaticProvider: TimelineProvider {
    func placeholder(in context: Context) -> StaticEntry { StaticEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (StaticEntry) -> Void) { completion(StaticEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<StaticEntry>) -> Void) {
        completion(Timeline(entries: [StaticEntry(date: .now)], policy: .never))
    }
}

// MARK: - Start (Lock Screen circle or small Home Screen square)

struct StartWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EmberStart", provider: StaticProvider()) { _ in
            ActionWidgetView(title: "Start", symbol: "power", tint: ember, action: "start")
        }
        .configurationDisplayName("Start car")
        .description("Opens Ember and starts your car.")
        .supportedFamilies([.accessoryCircular, .systemSmall])
    }
}

struct LockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EmberLock", provider: StaticProvider()) { _ in
            ActionWidgetView(title: "Lock", symbol: "lock.fill", tint: .blue, action: "lock")
        }
        .configurationDisplayName("Lock car")
        .description("Opens Ember and locks your car.")
        .supportedFamilies([.accessoryCircular, .systemSmall])
    }
}

struct ActionWidgetView: View {
    let title: String
    let symbol: String
    let tint: Color
    let action: String
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if family == .accessoryCircular {
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 1) {
                        Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
                        Text(title).font(.system(size: 10, weight: .semibold))
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "car.side.fill").foregroundStyle(.secondary)
                        Spacer()
                        Text("Ember").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: symbol)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(tint.gradient, in: Circle())
                    Text("\(title) car").font(.headline)
                }
            }
        }
        .widgetURL(EmberLink.url(action))
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color(red: 0.10, green: 0.08, blue: 0.20), Color(red: 0.22, green: 0.09, blue: 0.10)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

// MARK: - Four buttons (medium Home Screen widget)

struct QuickActionsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EmberQuickActions", provider: StaticProvider()) { _ in
            QuickActionsView()
        }
        .configurationDisplayName("Car controls")
        .description("Lock, unlock, start and find your car.")
        .supportedFamilies([.systemMedium])
    }
}

struct QuickActionsView: View {
    private struct Item: Identifiable {
        let title: String, symbol: String, action: String, tint: Color
        var id: String { action }
    }
    private let items: [Item] = [
        Item(title: "Lock", symbol: "lock.fill", action: "lock", tint: .blue),
        Item(title: "Unlock", symbol: "lock.open.fill", action: "unlock", tint: .teal),
        Item(title: "Start", symbol: "power", action: "start", tint: ember),
        Item(title: "Find", symbol: "mappin.and.ellipse", action: "location", tint: .green),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "car.side.fill")
                Text("Ember").font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.secondary)
            HStack(spacing: 0) {
                ForEach(items) { item in
                    Link(destination: EmberLink.url(item.action)) {
                        VStack(spacing: 6) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 52, height: 52)
                                .background(item.tint.gradient, in: Circle())
                            Text(item.title).font(.caption.weight(.medium))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color(red: 0.10, green: 0.08, blue: 0.20), Color(red: 0.22, green: 0.09, blue: 0.10)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

// MARK: - Live Activity: engine running

struct RunningLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunningActivityAttributes.self) { context in
            HStack(spacing: 14) {
                Image(systemName: "engine.combustion.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(ember)
                    .frame(width: 48, height: 48)
                    .background(ember.opacity(0.18), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.vehicleName).font(.headline)
                    Text(context.state.hazards ? "Engine running · hazards on" : "Engine running")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    countdown(context.state.endsAt)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("left").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .activityBackgroundTint(Color(red: 0.08, green: 0.07, blue: 0.14))
            .activitySystemActionForegroundColor(.white)
            .widgetURL(EmberLink.url("home"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "engine.combustion.fill")
                        .font(.title2)
                        .foregroundStyle(ember)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context.state.endsAt)
                        .font(.title2.weight(.bold))
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.vehicleName).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Engine running. It turns off by itself when the timer ends.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "engine.combustion.fill").foregroundStyle(ember)
            } compactTrailing: {
                countdown(context.state.endsAt)
                    .frame(maxWidth: 46)
            } minimal: {
                Image(systemName: "engine.combustion.fill").foregroundStyle(ember)
            }
            .widgetURL(EmberLink.url("home"))
        }
    }

    /// A countdown the system updates by itself; never builds an invalid range.
    private func countdown(_ end: Date) -> some View {
        let now = Date()
        return Text(timerInterval: now...max(now, end), countsDown: true)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
    }
}
