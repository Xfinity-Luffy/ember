import SwiftUI
import UIKit
import CryptoKit
import LocalAuthentication

struct Banner: Identifiable, Equatable {
    enum Kind { case success, error, info }
    let id = UUID()
    let text: String
    let kind: Kind
}

enum AppTab: Hashable { case remote, vehicle, hazards, alarm, location }

/// How the app reaches the car.
enum ConnectionMode: String, CaseIterable, Identifiable {
    case bluetooth, cellular, automatic
    var id: String { rawValue }
    var title: String {
        switch self {
        case .bluetooth: return "Bluetooth"
        case .cellular: return "Cellular"
        case .automatic: return "Automatic"
        }
    }
    var explanation: String {
        switch self {
        case .bluetooth: return "Works within about 30 feet of the car. No extra hardware or data plan."
        case .cellular: return "Works from anywhere through your relay server. Needs the bridge's LTE module and a data plan."
        case .automatic: return "Bluetooth when you're near the car, cellular when you're not. Recommended if you have LTE."
        }
    }
}

/// The app's single source of truth: link state, car status, and commands.
@MainActor
final class CarController: ObservableObject {
    @Published private(set) var link: LinkState = .searching
    @Published private(set) var status = CarStatus()
    @Published private(set) var vehicle = VehicleInfo()
    /// Latest cellular check-in from the car (location, time), if using cellular.
    @Published private(set) var cellular: CellularUpdate?
    /// When this phone first saw the "alarm went off" warning.
    @Published private(set) var alarmTriggeredAt: Date?
    @Published private(set) var pending: CarCommand?
    @Published private(set) var hasKey = SecretStore.load() != nil
    @Published var banner: Banner?
    @Published var selectedTab: AppTab = .remote

    @Published var demoMode: Bool {
        didSet {
            UserDefaults.standard.set(demoMode, forKey: Keys.demo)
            rebuildTransport()
        }
    }
    @Published var carName: String {
        didSet { UserDefaults.standard.set(carName, forKey: Keys.name) }
    }
    /// Ask for Face ID (or the passcode) before Unlock and Start.
    @Published var requireFaceID: Bool {
        didSet { UserDefaults.standard.set(requireFaceID, forKey: Keys.faceID) }
    }
    /// Button vibrations.
    @Published var hapticsOn: Bool {
        didSet { UserDefaults.standard.set(hapticsOn, forKey: Haptics.enabledKey) }
    }
    @Published var connectionMode: ConnectionMode {
        didSet {
            UserDefaults.standard.set(connectionMode.rawValue, forKey: Keys.mode)
            rebuildTransport()
        }
    }
    /// Your relay server's address, e.g. ember-relay.yourname.workers.dev
    @Published var relayHost: String {
        didSet { UserDefaults.standard.set(relayHost, forKey: Keys.relay) }
    }
    /// Turn on rear defrost automatically after a remote start.
    @Published var defrostOnStart: Bool {
        didSet { UserDefaults.standard.set(defrostOnStart, forKey: Keys.defrost) }
    }

    private var transport: CarTransport?
    private var bannerTask: Task<Void, Never>?

    private enum Keys {
        static let demo = "ember.demoMode"
        static let name = "ember.carName"
        static let defrost = "ember.defrostOnStart"
        static let faceID = "ember.requireFaceID"
        static let mode = "ember.connectionMode"
        static let relay = "ember.relayHost"
    }

    init() {
        let defaults = UserDefaults.standard
        demoMode = defaults.object(forKey: Keys.demo) as? Bool ?? true
        carName = defaults.string(forKey: Keys.name) ?? "My Car"
        defrostOnStart = defaults.bool(forKey: Keys.defrost)
        requireFaceID = defaults.bool(forKey: Keys.faceID)
        connectionMode = ConnectionMode(rawValue: defaults.string(forKey: Keys.mode) ?? "") ?? .bluetooth
        relayHost = defaults.string(forKey: Keys.relay) ?? ""
        hapticsOn = defaults.object(forKey: Haptics.enabledKey) as? Bool ?? true
        rebuildTransport()
    }

    // MARK: Commands

    func perform(_ command: CarCommand) {
        guard pending == nil else { return }
        pending = command   // block double taps until the command finishes
        Task {
            if requireFaceID, command == .unlock || command == .start {
                guard await authenticate(for: command) else { pending = nil; return }
            }
            let ok = await run(command)
            // Optional follow-up: rear defrost once the engine is actually running.
            guard ok, command == .start, defrostOnStart else { return }
            var waited = 0
            while !status.engineRunning && waited < 40 {   // up to 20 s for the engine to catch
                try? await Task.sleep(nanoseconds: 500_000_000)
                waited += 1
            }
            if status.engineRunning { _ = await run(.aux1) }
        }
    }

    private func authenticate(for command: CarCommand) async -> Bool {
        let context = LAContext()
        var problem: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &problem) else {
            show("Set up Face ID or a passcode on this iPhone, or turn off Face ID protection in Settings.", kind: .error)
            return false
        }
        let reason = command == .start ? "Confirm it's you before starting the car." : "Confirm it's you before unlocking the car."
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            show("Cancelled. Nothing was sent to the car.", kind: .info)
            return false
        }
    }

    /// Forgets the remembered bridge so the app searches for one again
    /// (use after replacing the ESP32 board).
    func forgetBridge() {
        UserDefaults.standard.removeObject(forKey: BLETransport.savedPeripheralKey)
        rebuildTransport()
        show("Searching for a bridge nearby.", kind: .info)
    }

    var appVersion: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = info?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    /// Demo mode only: pretend the alarm went off so the Alarm tab can be tried out.
    func simulateAlarm() {
        (transport as? DemoTransport)?.simulateAlarm()
    }

    /// Explains the hold gesture when someone just taps the power button.
    func holdHint(panic: Bool = false) {
        Haptics.tap()
        if panic {
            show("Press and hold for one second to sound the panic alarm. This prevents accidental alarms.", kind: .info)
            return
        }
        show(status.engineRunning
             ? "Press and hold for one second to stop the engine."
             : "Press and hold for one second to start. This prevents accidental starts.",
             kind: .info)
    }

    private func run(_ command: CarCommand) async -> Bool {
        guard let transport else { return false }
        pending = command
        defer { pending = nil }
        do {
            try await transport.send(command)
            Haptics.success()
            show(successText(for: command), kind: .success)
            return true
        } catch {
            Haptics.error()
            show(error.localizedDescription, kind: .error)
            return false
        }
    }

    private func successText(for command: CarCommand) -> String {
        switch command {
        case .lock: return "Doors locked"
        case .unlock: return "Doors unlocked"
        case .start: return status.runStatusWired ? "Start sent to the car" : "Engine started"
        case .stop: return "Engine off"
        case .aux1: return "Rear defrost turned on"
        case .hazardsOn: return "Hazard lights on"
        case .hazardsOff: return "Hazard lights off"
        case .panicOn: return "Panic alarm on"
        case .panicOff: return "Panic alarm stopped"
        case .alarmAck: return "Alarm warning cleared"
        }
    }

    // MARK: Bridge key

    /// Returns false if the text isn't a valid 64-character hex key.
    func saveKey(hex: String) -> Bool {
        guard let data = SecretStore.parseHex(hex), SecretStore.save(data) else { return false }
        hasKey = true
        return true
    }

    func removeKey() {
        SecretStore.delete()
        hasKey = false
    }

    // MARK: Lifecycle

    /// Call after the relay address changes, so cellular uses the new one.
    func relayHostChanged() {
        if connectionMode != .bluetooth && !demoMode { rebuildTransport() }
    }

    func appBecameActive() {
        transport?.start()   // reconnects if the link dropped while in the background
    }

    private func rebuildTransport() {
        transport?.stop()
        let key = { SecretStore.load().map { SymmetricKey(data: $0) } }
        let t: CarTransport
        if demoMode {
            t = DemoTransport()
        } else {
            switch connectionMode {
            case .bluetooth: t = BLETransport(secret: key)
            case .cellular: t = CloudTransport(host: relayHost, key: key)
            case .automatic: t = AutoTransport(ble: BLETransport(secret: key), cloud: CloudTransport(host: relayHost, key: key))
            }
        }
        t.onLinkChange = { [weak self] in self?.link = $0 }
        t.onStatus = { [weak self] new in
            guard let self else { return }
            if new.alarmTriggered && !self.status.alarmTriggered {
                self.alarmTriggeredAt = Date()
                Haptics.error()
                self.show("Your car alarm went off. Open the Alarm tab for details.", kind: .error)
            }
            if !new.alarmTriggered { self.alarmTriggeredAt = nil }
            self.status = new
        }
        t.onError = { [weak self] in self?.show($0, kind: .error) }
        t.onVehicle = { [weak self] in self?.vehicle = $0 }
        t.onCellular = { [weak self] in self?.cellular = $0 }
        transport = t
        status = CarStatus()
        vehicle = VehicleInfo()
        cellular = nil
        link = demoMode ? .demo : (connectionMode == .cellular ? .cellularWaiting : .searching)
        t.start()
    }

    private func show(_ text: String, kind: Banner.Kind) {
        let b = Banner(text: text, kind: kind)
        banner = b
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: kind == .success ? 2_500_000_000 : 5_000_000_000)
            guard !Task.isCancelled, self?.banner == b else { return }
            self?.banner = nil
        }
    }
}

enum Haptics {
    static let enabledKey = "ember.haptics"
    private static var on: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
    @MainActor static func success() { if on { UINotificationFeedbackGenerator().notificationOccurred(.success) } }
    @MainActor static func error() { if on { UINotificationFeedbackGenerator().notificationOccurred(.error) } }
    @MainActor static func tap() { if on { UIImpactFeedbackGenerator(style: .medium).impactOccurred() } }
}
