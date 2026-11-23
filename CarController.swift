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

/// The app's single source of truth: link state, car status, and commands.
@MainActor
final class CarController: ObservableObject {
    @Published private(set) var link: LinkState = .searching
    @Published private(set) var status = CarStatus()
    @Published private(set) var pending: CarCommand?
    @Published private(set) var hasKey = SecretStore.load() != nil
    @Published var banner: Banner?

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
    }

    init() {
        let defaults = UserDefaults.standard
        demoMode = defaults.object(forKey: Keys.demo) as? Bool ?? true
        carName = defaults.string(forKey: Keys.name) ?? "My Car"
        defrostOnStart = defaults.bool(forKey: Keys.defrost)
        requireFaceID = defaults.bool(forKey: Keys.faceID)
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

    /// Explains the hold gesture when someone just taps the power button.
    func holdHint() {
        Haptics.tap()
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

    func appBecameActive() {
        transport?.start()   // reconnects if the link dropped while in the background
    }

    private func rebuildTransport() {
        transport?.stop()
        let t: CarTransport = demoMode
            ? DemoTransport()
            : BLETransport(secret: { SecretStore.load().map { SymmetricKey(data: $0) } })
        t.onLinkChange = { [weak self] in self?.link = $0 }
        t.onStatus = { [weak self] in self?.status = $0 }
        t.onError = { [weak self] in self?.show($0, kind: .error) }
        transport = t
        status = CarStatus()
        link = demoMode ? .demo : .searching
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
