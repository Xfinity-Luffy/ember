import SwiftUI
import UIKit
import CryptoKit

struct Banner: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isError: Bool
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

    private var transport: CarTransport?
    private var bannerTask: Task<Void, Never>?

    private enum Keys {
        static let demo = "ember.demoMode"
        static let name = "ember.carName"
    }

    init() {
        let defaults = UserDefaults.standard
        demoMode = defaults.object(forKey: Keys.demo) as? Bool ?? true
        carName = defaults.string(forKey: Keys.name) ?? "My Car"
        rebuildTransport()
    }

    // MARK: Commands

    func perform(_ command: CarCommand) {
        guard pending == nil, let transport else { return }
        pending = command
        Task {
            do {
                try await transport.send(command)
                Haptics.success()
                show(successText(for: command), isError: false)
            } catch {
                Haptics.error()
                show(error.localizedDescription, isError: true)
            }
            pending = nil
        }
    }

    private func successText(for command: CarCommand) -> String {
        switch command {
        case .lock: return "Locked"
        case .unlock: return "Unlocked"
        case .start: return status.runStatusWired ? "Start sent" : "Engine started"
        case .stop: return "Engine off"
        case .aux1: return "Rear defrost toggled"
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
        t.onError = { [weak self] in self?.show($0, isError: true) }
        transport = t
        status = CarStatus()
        link = demoMode ? .demo : .searching
        t.start()
    }

    private func show(_ text: String, isError: Bool) {
        let b = Banner(text: text, isError: isError)
        banner = b
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: isError ? 5_000_000_000 : 2_500_000_000)
            guard !Task.isCancelled, self?.banner == b else { return }
            self?.banner = nil
        }
    }
}

enum Haptics {
    @MainActor static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    @MainActor static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    @MainActor static func tap() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
}
