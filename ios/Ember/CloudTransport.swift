import Foundation
import CryptoKit

/// Talks to the car through your relay server, over the internet.
///
/// - Every few seconds: GET /state, check the car's signature, publish status,
///   fuel and GPS location.
/// - Every ~90 s while the app is open: POST /live, so the car reports every
///   few seconds instead of once a minute.
/// - Commands: POST a packet signed with the car's key, then wait for the car
///   to report the result ("ack") at its next check-in.
@MainActor
final class CloudTransport: CarTransport {
    var onLinkChange: ((LinkState) -> Void)?
    var onStatus: ((CarStatus) -> Void)?
    var onError: ((String) -> Void)?
    var onVehicle: ((VehicleInfo) -> Void)?
    var onCellular: ((CellularUpdate) -> Void)?

    /// Set by AutoTransport while Bluetooth is connected (saves data).
    var paused = false

    private let host: String
    private let key: () -> SymmetricKey?
    private var poller: Task<Void, Never>?
    private var acks: [String: UInt8] = [:]
    private var lastReceivedAt: Double = 0
    private var reportedAuthProblem = false

    /// A check-in older than this means the car is probably out of coverage or off.
    private let staleAfter: TimeInterval = 10 * 60

    private(set) var link: LinkState = .cellularWaiting {
        didSet { if link != oldValue { onLinkChange?(link) } }
    }

    init(host: String, key: @escaping () -> SymmetricKey?) {
        self.host = host
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        self.key = key
    }

    // MARK: CarTransport

    func start() {
        onLinkChange?(link)
        guard poller == nil else { return }
        if host.isEmpty {
            onError?("Add your relay server address in Settings to use cellular.")
            return
        }
        poller = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                if let self, !self.paused {
                    if tick % 22 == 0 { await self.askForLiveUpdates() }   // about every 90 s
                    await self.poll()
                }
                tick += 1
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
    }

    func stop() {
        poller?.cancel()
        poller = nil
    }

    func send(_ command: CarCommand) async throws {
        guard let key = key() else { throw CarError.noSecret }
        guard !host.isEmpty else { throw CarError.bluetooth("Add your relay server address in Settings.") }
        let ids = EmberCloud.ids(key: key)
        let packet = EmberCloud.commandPacket(command, key: key)

        var request = URLRequest(url: url(ids.carId, "command"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(ids.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["packet": packet.hex])
        let (_, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 202 else {
            throw CarError.bluetooth("The relay server didn't accept the command.")
        }

        // The car picks it up at its next check-in (a few seconds once it's in
        // "live" mode; up to about a minute if it was parked and quiet).
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            await poll()
            if let code = acks[packet.nonceHex] {
                let result = CommandResult(rawValue: code) ?? .badFormat
                if result != .ok { throw CarError.rejected(result) }
                return
            }
        }
        throw CarError.bluetooth("The car hasn't checked in yet. If it does within 5 minutes, it will still run the command.")
    }

    // MARK: Relay calls

    private func url(_ carId: String, _ action: String) -> URL {
        URL(string: "https://\(host)/v1/\(carId)/\(action)")!
    }

    private func askForLiveUpdates() async {
        guard let key = key() else { return }
        let ids = EmberCloud.ids(key: key)
        var request = URLRequest(url: url(ids.carId, "live"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(ids.token)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: request)
    }

    private struct StateResponse: Decodable { let report: String; let sig: String; let receivedAt: Double }

    private func poll() async {
        guard let key = key() else { link = .cellularWaiting; return }
        let ids = EmberCloud.ids(key: key)
        var request = URLRequest(url: url(ids.carId, "state"))
        request.setValue("Bearer \(ids.token)", forHTTPHeaderField: "Authorization")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let result = try? await URLSession.shared.data(for: request),
              let http = result.1 as? HTTPURLResponse else { return }   // offline: keep last state
        let data = result.0

        switch http.statusCode {
        case 200: break
        case 404: link = .cellularWaiting; return                       // car hasn't reported yet
        case 401:
            if !reportedAuthProblem {
                reportedAuthProblem = true
                onError?("The relay server doesn't recognize this key. Check that the app and the bridge use the same key.")
            }
            link = .cellularWaiting
            return
        default: return
        }

        guard let state = try? JSONDecoder().decode(StateResponse.self, from: data),
              EmberCloud.reportIsGenuine(state.report, sigHex: state.sig, key: key),     // ignore anything the car didn't sign
              let report = try? JSONDecoder().decode(CloudReport.self, from: Data(state.report.utf8))
        else { return }

        for ack in report.ack ?? [] { acks[ack.id] = ack.r }

        let checkIn = Date(timeIntervalSince1970: state.receivedAt / 1000)
        link = Date().timeIntervalSince(checkIn) < staleAfter ? .cellular : .cellularWaiting
        guard state.receivedAt != lastReceivedAt else { return }        // nothing new
        lastReceivedAt = state.receivedAt

        if let bytes = Data(hexString: report.st), let status = CarStatus(packet: bytes) {
            onStatus?(status)
        }
        let reportTime = Date(timeIntervalSince1970: TimeInterval(report.t))
        let ageMinutes = max(0, Int(Date().timeIntervalSince(reportTime) / 60))
        if let fuel = report.fuel, fuel >= 0 {
            onVehicle?(VehicleInfo(fuelPercent: fuel, fuelAgeMinutes: ageMinutes, tiresPSI: nil, tiresAgeMinutes: nil))
        }
        onCellular?(CellularUpdate(
            checkIn: checkIn,
            latitude: report.lat,
            longitude: report.lon,
            speedKmh: report.spd,
            fixTime: report.fix.map { Date(timeIntervalSince1970: TimeInterval($0)) }))
    }
}

/// Automatic: Bluetooth when you're near the car, cellular when you're not.
@MainActor
final class AutoTransport: CarTransport {
    var onLinkChange: ((LinkState) -> Void)?
    var onStatus: ((CarStatus) -> Void)?
    var onError: ((String) -> Void)?
    var onVehicle: ((VehicleInfo) -> Void)?
    var onCellular: ((CellularUpdate) -> Void)?

    private let ble: BLETransport
    private let cloud: CloudTransport
    private var bleLink: LinkState = .searching
    private var cloudLink: LinkState = .cellularWaiting
    private var nearby: Bool { bleLink == .ready }

    init(ble: BLETransport, cloud: CloudTransport) {
        self.ble = ble
        self.cloud = cloud

        ble.onLinkChange = { [weak self] link in
            guard let self else { return }
            self.bleLink = link
            self.cloud.paused = (link == .ready)      // no need to use data while next to the car
            self.publishLink()
        }
        cloud.onLinkChange = { [weak self] link in
            self?.cloudLink = link
            self?.publishLink()
        }
        ble.onStatus = { [weak self] s in if self?.nearby == true { self?.onStatus?(s) } }
        cloud.onStatus = { [weak self] s in if self?.nearby == false { self?.onStatus?(s) } }
        ble.onVehicle = { [weak self] v in if self?.nearby == true { self?.onVehicle?(v) } }
        cloud.onVehicle = { [weak self] v in if self?.nearby == false { self?.onVehicle?(v) } }
        ble.onError = { [weak self] e in self?.onError?(e) }
        cloud.onError = { [weak self] e in self?.onError?(e) }
        cloud.onCellular = { [weak self] u in self?.onCellular?(u) }
    }

    private func publishLink() {
        onLinkChange?(nearby ? .ready : cloudLink)
    }

    func start() {
        ble.start()
        cloud.start()
        publishLink()
    }

    func stop() {
        ble.stop()
        cloud.stop()
    }

    func send(_ command: CarCommand) async throws {
        if nearby { try await ble.send(command) } else { try await cloud.send(command) }
    }
}
