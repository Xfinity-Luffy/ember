import AppIntents

// Siri, Shortcuts, the Action Button and Shortcut automations (e.g. "every weekday
// at 7:30, start my car") all use these. They act on the vehicle selected in Ember.

struct LockCarIntent: AppIntent {
    static var title: LocalizedStringResource = "Lock car"
    static var description = IntentDescription("Locks the doors of the vehicle selected in Ember.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let r = await CarController.shared.runForShortcut(.lock, source: .siri)
        return .result(dialog: "\(r.message)")
    }
}

struct UnlockCarIntent: AppIntent {
    static var title: LocalizedStringResource = "Unlock car"
    static var description = IntentDescription("Unlocks the doors. Your iPhone asks for Face ID or your passcode first.")
    static var openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let r = await CarController.shared.runForShortcut(.unlock, source: .siri)
        return .result(dialog: "\(r.message)")
    }
}

struct StartCarIntent: AppIntent {
    static var title: LocalizedStringResource = "Start car"
    static var description = IntentDescription("Remote starts the engine. Your iPhone asks for Face ID or your passcode first. Won't start if the battery is low.")
    static var openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let r = await CarController.shared.runForShortcut(.start, source: .siri)
        return .result(dialog: "\(r.message)")
    }
}

struct StopCarIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop car"
    static var description = IntentDescription("Turns off a remote-started engine.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let r = await CarController.shared.runForShortcut(.stop, source: .siri)
        return .result(dialog: "\(r.message)")
    }
}

struct HazardsIntent: AppIntent {
    static var title: LocalizedStringResource = "Turn hazard lights on or off"
    static var description = IntentDescription("Hazard lights turn off by themselves after 10 minutes.")
    static var openAppWhenRun = false

    @Parameter(title: "Turn on", default: true)
    var on: Bool

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let r = await CarController.shared.runForShortcut(on ? .hazardsOn : .hazardsOff, source: .siri)
        return .result(dialog: "\(r.message)")
    }
}

struct CarStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Car status"
    static var description = IntentDescription("Says whether the car is locked or running, plus fuel and battery.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = await CarController.shared.statusForShortcut()
        return .result(dialog: "\(text)")
    }
}

struct EmberShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartCarIntent(),
                    phrases: ["Start my car with \(.applicationName)",
                              "Start the car with \(.applicationName)",
                              "\(.applicationName) start my car"],
                    shortTitle: "Start car", systemImageName: "power")
        AppShortcut(intent: StopCarIntent(),
                    phrases: ["Stop my car with \(.applicationName)",
                              "Turn off my car with \(.applicationName)"],
                    shortTitle: "Stop car", systemImageName: "stop.circle")
        AppShortcut(intent: LockCarIntent(),
                    phrases: ["Lock my car with \(.applicationName)",
                              "Lock the car with \(.applicationName)",
                              "\(.applicationName) lock my car"],
                    shortTitle: "Lock car", systemImageName: "lock.fill")
        AppShortcut(intent: UnlockCarIntent(),
                    phrases: ["Unlock my car with \(.applicationName)",
                              "Unlock the car with \(.applicationName)"],
                    shortTitle: "Unlock car", systemImageName: "lock.open.fill")
        AppShortcut(intent: CarStatusIntent(),
                    phrases: ["Check my car with \(.applicationName)",
                              "Is my car locked in \(.applicationName)",
                              "\(.applicationName) car status"],
                    shortTitle: "Car status", systemImageName: "car.side.fill")
        AppShortcut(intent: HazardsIntent(),
                    phrases: ["Turn on hazards with \(.applicationName)",
                              "Hazard lights with \(.applicationName)"],
                    shortTitle: "Hazards", systemImageName: "exclamationmark.triangle.fill")
    }
}
