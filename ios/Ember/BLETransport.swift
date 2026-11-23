import Foundation
import CoreBluetooth
import CryptoKit

/// One-shot async waiter with a timeout. A fresh instance is used per operation,
/// so a late timeout can never complete the wrong request.
@MainActor
final class Waiter<T> {
    private var continuation: CheckedContinuation<T, Error>?

    func wait(timeout: TimeInterval, begin: () -> Void) async throws -> T {
        try await withCheckedThrowingContinuation { c in
            continuation = c
            begin()
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.finish(.failure(CarError.timeout))
            }
        }
    }

    func finish(_ result: Result<T, Error>) {
        guard let c = continuation else { return }
        continuation = nil
        c.resume(with: result)
    }
}

/// Talks to the Ember Bridge (ESP32) over Bluetooth LE.
@MainActor
final class BLETransport: NSObject, CarTransport {
    var onLinkChange: ((LinkState) -> Void)?
    var onStatus: ((CarStatus) -> Void)?
    var onError: ((String) -> Void)?
    var onVehicle: ((VehicleInfo) -> Void)?

    private let secret: () -> SymmetricKey?
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var challengeChar: CBCharacteristic?
    private var commandChar: CBCharacteristic?
    private var statusChar: CBCharacteristic?
    private var vehicleChar: CBCharacteristic?
    private var latestStatus: CarStatus?
    private var wantsConnection = false
    private var commandInFlight = false

    private var readWaiter: Waiter<Data>?
    private var writeWaiter: Waiter<Void>?
    private var statusWaiter: (previousSeq: UInt8, waiter: Waiter<CarStatus>)?

    static let savedPeripheralKey = "ember.bridgePeripheralID"

    private var link: LinkState = .searching {
        didSet { if link != oldValue { onLinkChange?(link) } }
    }

    init(secret: @escaping () -> SymmetricKey?) {
        self.secret = secret
        super.init()
    }

    // MARK: CarTransport

    func start() {
        wantsConnection = true
        if central == nil {
            central = CBCentralManager(delegate: self, queue: nil)   // main queue
        } else {
            connectIfPossible()
        }
    }

    func stop() {
        wantsConnection = false
        central?.stopScan()
        if let p = peripheral { central?.cancelPeripheralConnection(p) }
        failAllWaiters(CarError.notConnected)
    }

    func send(_ command: CarCommand) async throws {
        guard link == .ready, let p = peripheral, let ch = challengeChar, let cmd = commandChar else {
            throw CarError.notConnected
        }
        guard let key = secret() else { throw CarError.noSecret }
        guard !commandInFlight else { throw CarError.bluetooth("Another command is still in progress.") }
        commandInFlight = true
        defer { commandInFlight = false }

        // 1. Fetch a one-time challenge.
        let reader = Waiter<Data>()
        readWaiter = reader
        let nonce = try await reader.wait(timeout: 5) { p.readValue(for: ch) }
        guard nonce.count == EmberProtocol.nonceLength else { throw CarError.badChallenge }

        // 2. Send the signed command.
        let previousSeq = latestStatus?.sequence ?? 0
        let packet = EmberProtocol.commandPacket(command, nonce: nonce, secret: key)
        let writer = Waiter<Void>()
        writeWaiter = writer
        try await writer.wait(timeout: 5) { p.writeValue(packet, for: cmd, type: .withResponse) }

        // 3. Wait for the bridge to report the result (status sequence number changes).
        let result: CarStatus
        if let s = latestStatus, s.sequence != previousSeq {
            result = s
        } else {
            let statusW = Waiter<CarStatus>()
            statusWaiter = (previousSeq, statusW)
            result = try await statusW.wait(timeout: 6) {}
        }
        if result.lastResult != .ok { throw CarError.rejected(result.lastResult) }
    }

    // MARK: Connection management

    private func connectIfPossible() {
        guard wantsConnection, let central, central.state == .poweredOn else { return }
        if let p = peripheral, p.state == .connected || p.state == .connecting { return }

        // Reconnect to the bridge we used before. connect() has no timeout on iOS,
        // so this quietly waits until the car is in range.
        if let idString = UserDefaults.standard.string(forKey: Self.savedPeripheralKey),
           let id = UUID(uuidString: idString),
           let known = central.retrievePeripherals(withIdentifiers: [id]).first {
            attach(known)
            link = .searching
            return
        }
        if let already = central.retrieveConnectedPeripherals(withServices: [EmberProtocol.service]).first {
            attach(already)
            return
        }
        link = .searching
        central.scanForPeripherals(withServices: [EmberProtocol.service])
    }

    private func attach(_ p: CBPeripheral) {
        peripheral = p
        p.delegate = self
        UserDefaults.standard.set(p.identifier.uuidString, forKey: Self.savedPeripheralKey)
        central?.connect(p)
    }

    private func resetCharacteristics() {
        challengeChar = nil
        commandChar = nil
        statusChar = nil
        vehicleChar = nil
        latestStatus = nil
    }

    private func failAllWaiters(_ error: Error) {
        readWaiter?.finish(.failure(error)); readWaiter = nil
        writeWaiter?.finish(.failure(error)); writeWaiter = nil
        statusWaiter?.waiter.finish(.failure(error)); statusWaiter = nil
    }

    private func friendly(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == CBATTErrorDomain,
           ns.code == CBATTError.insufficientAuthentication.rawValue || ns.code == CBATTError.insufficientEncryption.rawValue {
            return "Pairing didn't finish. Try again and enter the 6-digit passkey."
        }
        if ns.domain == CBErrorDomain, ns.code == CBError.peerRemovedPairingInformation.rawValue {
            return "The bridge forgot this phone. In iPhone Settings > Bluetooth, tap ⓘ next to Ember Bridge, choose Forget This Device, then reopen the app."
        }
        return error.localizedDescription
    }
}

// MARK: - CBCentralManagerDelegate

extension BLETransport: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            connectIfPossible()
        case .poweredOff:
            link = .bluetoothOff
            failAllWaiters(CarError.notConnected)
        case .unauthorized:
            link = .unauthorized
        default:
            link = .searching
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        central.stopScan()
        link = .connecting
        attach(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        link = .connecting
        peripheral.discoverServices([EmberProtocol.service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if let error { onError?(friendly(error)) }
        resetCharacteristics()
        link = .searching
        if wantsConnection { central.connect(peripheral) }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        resetCharacteristics()
        failAllWaiters(CarError.notConnected)
        if let error, (error as NSError).domain == CBErrorDomain,
           (error as NSError).code == CBError.peerRemovedPairingInformation.rawValue {
            onError?(friendly(error))
        }
        link = .searching
        if wantsConnection { central.connect(peripheral) }   // waits until back in range
    }
}

// MARK: - CBPeripheralDelegate

extension BLETransport: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil,
              let service = peripheral.services?.first(where: { $0.uuid == EmberProtocol.service }) else {
            onError?("This device isn't an Ember Bridge.")
            return
        }
        peripheral.discoverCharacteristics(
            [EmberProtocol.challenge, EmberProtocol.command, EmberProtocol.status, EmberProtocol.vehicle], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] {
            switch c.uuid {
            case EmberProtocol.challenge: challengeChar = c
            case EmberProtocol.command: commandChar = c
            case EmberProtocol.status: statusChar = c
            case EmberProtocol.vehicle: vehicleChar = c
            default: break
            }
        }
        guard let statusChar, challengeChar != nil, commandChar != nil else {
            onError?("The bridge firmware doesn't match this app version.")
            return
        }
        // Reading the encrypted status characteristic makes iOS pair (passkey prompt)
        // the first time. The link only counts as ready once that read succeeds.
        peripheral.setNotifyValue(true, for: statusChar)
        peripheral.readValue(for: statusChar)
        if let vehicleChar {   // older bridge firmware doesn't have this; that's fine
            peripheral.setNotifyValue(true, for: vehicleChar)
            peripheral.readValue(for: vehicleChar)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == EmberProtocol.challenge {
            if let error {
                readWaiter?.finish(.failure(CarError.bluetooth(friendly(error))))
            } else {
                readWaiter?.finish(.success(characteristic.value ?? Data()))
            }
            readWaiter = nil
            return
        }

        if characteristic.uuid == EmberProtocol.vehicle {
            if error == nil, let data = characteristic.value, let info = VehicleInfo(packet: data) {
                onVehicle?(info)
            }
            return
        }

        guard characteristic.uuid == EmberProtocol.status else { return }
        if let error {
            onError?(friendly(error))
            return
        }
        guard let data = characteristic.value, let status = CarStatus(packet: data) else { return }
        latestStatus = status
        onStatus?(status)
        if link != .ready { link = .ready }
        if let pending = statusWaiter, status.sequence != pending.previousSeq {
            statusWaiter = nil
            pending.waiter.finish(.success(status))
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == EmberProtocol.command else { return }
        if let error {
            writeWaiter?.finish(.failure(CarError.bluetooth(friendly(error))))
        } else {
            writeWaiter?.finish(.success(()))
        }
        writeWaiter = nil
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        // Subscribing may fail before pairing completes; retry once the link is encrypted.
        if error != nil, characteristic.uuid == EmberProtocol.status {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard let self, let p = self.peripheral, p.state == .connected, let s = self.statusChar else { return }
                p.setNotifyValue(true, for: s)
            }
        }
    }
}
