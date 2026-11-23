import Foundation

/// A pretend car, so the app can be used before the bridge is installed
/// (and in the Xcode simulator, which has no Bluetooth).
@MainActor
final class DemoTransport: CarTransport {
    var onLinkChange: ((LinkState) -> Void)?
    var onStatus: ((CarStatus) -> Void)?
    var onError: ((String) -> Void)?
    var onVehicle: ((VehicleInfo) -> Void)?

    private var status = CarStatus()
    private var ticker: Task<Void, Never>?
    private let runSeconds = 15 * 60

    init() {
        status.runStatusWired = true
        status.lock = .locked
    }

    func start() {
        onLinkChange?(.demo)
        onStatus?(status)
        // Sample readings so the Vehicle tab has something to show (one tire a bit low).
        onVehicle?(VehicleInfo(fuelPercent: 62, fuelAgeMinutes: 14,
                               tiresPSI: [36.0, 35.5, 36.0, 29.5], tiresAgeMinutes: 14))
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                self?.tick()
            }
        }
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
    }

    func send(_ command: CarCommand) async throws {
        try await Task.sleep(nanoseconds: 700_000_000)   // feel like a real round trip
        let result: CommandResult
        switch command {
        case .lock:
            status.lock = .locked; result = .ok
        case .unlock:
            status.lock = .unlocked; result = .ok
        case .start:
            if status.engineRunning { result = .alreadyRunning }
            else { status.engineRunning = true; status.secondsRemaining = runSeconds; result = .ok }
        case .stop:
            if !status.engineRunning { result = .notRunning }
            else { status.engineRunning = false; status.secondsRemaining = 0; result = .ok }
        case .aux1:
            result = status.engineRunning ? .ok : .notRunning
        }
        status.lastResult = result
        status.sequence &+= 1
        onStatus?(status)
        if result != .ok { throw CarError.rejected(result) }
    }

    private func tick() {
        guard status.engineRunning else { return }
        status.secondsRemaining -= 1
        if status.secondsRemaining <= 0 {
            status.engineRunning = false
            status.secondsRemaining = 0
        }
        onStatus?(status)
    }
}
