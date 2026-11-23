import Foundation
import CoreBluetooth
import CryptoKit
import Security

/// Wire protocol shared with the Ember Bridge firmware (EmberBridge.ino).
/// If you change anything here, change it there too.
enum EmberProtocol {
    static let service   = CBUUID(string: "e1ff55ff-6a97-433b-bea8-9ec4b34f384e")
    static let challenge = CBUUID(string: "19761279-973c-47a5-8d3d-08d03f22677c")
    static let command   = CBUUID(string: "6a4d6a66-0fe9-48ca-878e-238060417a9d")
    static let status    = CBUUID(string: "7bdb2e96-9fcf-4522-b098-7264afa1c44d")
    static let vehicle   = CBUUID(string: "c8877ecc-75f8-4914-a91b-f18cdebf0910")   // optional (newer bridges)

    static let nonceLength = 16
    static let macLength = 16
    private static let domain = Data("EMBR".utf8)

    /// Command packet: [cmd][first 16 bytes of HMAC-SHA256(secret, "EMBR" || nonce || cmd)]
    static func commandPacket(_ command: CarCommand, nonce: Data, secret: SymmetricKey) -> Data {
        var message = domain
        message.append(nonce)
        message.append(command.rawValue)
        let mac = HMAC<SHA256>.authenticationCode(for: message, using: secret)
        var packet = Data([command.rawValue])
        packet.append(Data(mac).prefix(macLength))
        return packet
    }
}

enum CarCommand: UInt8, CaseIterable {
    case lock = 0x01
    case unlock = 0x02
    case start = 0x03
    case stop = 0x04
    case aux1 = 0x05   // rear defrost by default
    case hazardsOn = 0x06
    case hazardsOff = 0x07
    case panicOn = 0x08
    case panicOff = 0x09
    case alarmAck = 0x0A  // clear the "alarm went off" warning

    var verb: String {
        switch self {
        case .lock: return "Locking"
        case .unlock: return "Unlocking"
        case .start: return "Starting"
        case .stop: return "Stopping"
        case .aux1: return "Defrost"
        case .hazardsOn: return "Hazards on"
        case .hazardsOff: return "Hazards off"
        case .panicOn: return "Panic"
        case .panicOff: return "Stopping panic"
        case .alarmAck: return "Clearing alarm"
        }
    }
}

enum CommandResult: UInt8 {
    case none = 0, ok, badAuth, alreadyRunning, notRunning, lockedOut, badFormat, unsupported

    var errorMessage: String? {
        switch self {
        case .none, .ok: return nil
        case .badAuth: return "The bridge rejected the key. Check the bridge key in Settings."
        case .alreadyRunning: return "The engine is already running or starting."
        case .notRunning: return "The engine isn't running."
        case .lockedOut: return "Too many bad attempts. The bridge is locked for a minute."
        case .badFormat: return "The bridge didn't understand that command."
        case .unsupported: return "That output isn't wired on the bridge."
        }
    }
}

enum LockState: Equatable { case unknown, locked, unlocked }

struct CarStatus: Equatable {
    var engineRunning = false
    var runStatusWired = false
    var lock: LockState = .unknown
    var secondsRemaining = 0
    var lastResult: CommandResult = .none
    var sequence: UInt8 = 0
    var hazardsOn = false
    var hazardSecondsRemaining = 0
    var panicOn = false
    var panicSecondsRemaining = 0
    /// The alarm went off and nobody has acknowledged it yet.
    var alarmTriggered = false
    /// The bridge has the "alarm triggered" input wired.
    var alarmWired = false

    /// Status packet: [ver=1][flags][secs LE16][lastResult][seq][hazard secs LE16][panic secs LE16]
    /// (older bridges send only the first 6 bytes)
    init() {}
    init?(packet d: Data) {
        let b = [UInt8](d)
        guard b.count >= 6, b[0] == 1 else { return nil }
        let flags = b[1]
        engineRunning = flags & 0x01 != 0
        runStatusWired = flags & 0x02 != 0
        if flags & 0x04 != 0 { lock = (flags & 0x08 != 0) ? .locked : .unlocked }
        secondsRemaining = Int(b[2]) | (Int(b[3]) << 8)
        lastResult = CommandResult(rawValue: b[4]) ?? .none
        sequence = b[5]
        hazardsOn = flags & 0x10 != 0
        panicOn = flags & 0x20 != 0
        alarmTriggered = flags & 0x40 != 0
        alarmWired = flags & 0x80 != 0
        if b.count >= 10 {
            hazardSecondsRemaining = Int(b[6]) | (Int(b[7]) << 8)
            panicSecondsRemaining = Int(b[8]) | (Int(b[9]) << 8)
        }
    }
}

/// Fuel and tire readings from the car (Vehicle tab).
struct VehicleInfo: Equatable {
    var fuelPercent: Int?
    var fuelAgeMinutes: Int?
    /// Front-left, front-right, rear-left, rear-right, in psi.
    var tiresPSI: [Double]?
    var tiresAgeMinutes: Int?

    init() {}
    init(fuelPercent: Int?, fuelAgeMinutes: Int?, tiresPSI: [Double]?, tiresAgeMinutes: Int?) {
        self.fuelPercent = fuelPercent
        self.fuelAgeMinutes = fuelAgeMinutes
        self.tiresPSI = tiresPSI
        self.tiresAgeMinutes = tiresAgeMinutes
    }

    /// Vehicle packet: [ver=1][flags][fuel %][fuel age min LE16][FL FR RL RR psi*10 LE16][tire age min LE16]
    /// flags: bit0 fuel known, bit1 tires known. 0xFFFF = unknown.
    init?(packet d: Data) {
        let b = [UInt8](d)
        guard b.count >= 15, b[0] == 1 else { return nil }
        func u16(_ i: Int) -> Int { Int(b[i]) | (Int(b[i + 1]) << 8) }
        if b[1] & 0x01 != 0 {
            fuelPercent = min(100, Int(b[2]))
            fuelAgeMinutes = u16(3) == 0xFFFF ? nil : u16(3)
        }
        if b[1] & 0x02 != 0 {
            let raw = [u16(5), u16(7), u16(9), u16(11)]
            if !raw.contains(0xFFFF) { tiresPSI = raw.map { Double($0) / 10 } }
            tiresAgeMinutes = u16(13) == 0xFFFF ? nil : u16(13)
        }
    }
}

enum LinkState: Equatable {
    case bluetoothOff
    case unauthorized
    case searching
    case connecting
    case ready
    case demo
    /// Talking to the car through the relay server over cellular.
    case cellular
    /// Cellular is set up but the car hasn't checked in recently.
    case cellularWaiting

    var label: String {
        switch self {
        case .bluetoothOff: return "Bluetooth off"
        case .unauthorized: return "Bluetooth not allowed"
        case .searching: return "Looking for car"
        case .connecting: return "Connecting"
        case .ready: return "Connected"
        case .demo: return "Demo mode"
        case .cellular: return "Connected via cellular"
        case .cellularWaiting: return "Waiting for the car"
        }
    }
    var isUsable: Bool { self == .ready || self == .demo || self == .cellular }
}

enum CarError: LocalizedError {
    case notConnected, noSecret, timeout, badChallenge, rejected(CommandResult), bluetooth(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to the car."
        case .noSecret: return "Add your bridge key in Settings first."
        case .timeout: return "The car didn't answer in time."
        case .badChallenge: return "Unexpected reply from the bridge."
        case .rejected(let r): return r.errorMessage ?? "Command rejected."
        case .bluetooth(let m): return m
        }
    }
}

/// Anything that can carry commands to the car: the real Bluetooth bridge or the demo.
@MainActor
protocol CarTransport: AnyObject {
    var onLinkChange: ((LinkState) -> Void)? { get set }
    var onStatus: ((CarStatus) -> Void)? { get set }
    var onError: ((String) -> Void)? { get set }
    var onVehicle: ((VehicleInfo) -> Void)? { get set }
    var onCellular: ((CellularUpdate) -> Void)? { get set }
    func start()
    func stop()
    /// Sends a command and returns once the bridge reports a result.
    func send(_ command: CarCommand) async throws
}

// MARK: - Cellular (LTE) protocol, shared with EmberLTE.h and server/src/index.js

/// What the car last reported over cellular.
struct CellularUpdate: Equatable {
    /// When the relay received the report.
    var checkIn: Date
    var latitude: Double?
    var longitude: Double?
    var speedKmh: Double?
    /// When the GPS fix was taken.
    var fixTime: Date?
}

enum EmberCloud {
    private static func mac(_ label: String, _ parts: [Data], key: SymmetricKey) -> Data {
        var message = Data(label.utf8)
        for p in parts { message.append(p) }
        return Data(HMAC<SHA256>.authenticationCode(for: message, using: key))
    }

    /// carId = first 8 bytes of HMAC(key,"EMBR-ID"); token = first 16 of HMAC(key,"EMBR-API").
    static func ids(key: SymmetricKey) -> (carId: String, token: String) {
        (mac("EMBR-ID", [], key: key).prefix(8).hex, mac("EMBR-API", [], key: key).prefix(16).hex)
    }

    /// [cmd][unix time BE 4][nonce 8][HMAC(key,"EMBR-LTE"||first 13 bytes)[0..16]]
    static func commandPacket(_ command: CarCommand, key: SymmetricKey, now: Date = Date()) -> (hex: String, nonceHex: String) {
        let t = UInt32(now.timeIntervalSince1970)
        var head = Data([command.rawValue, UInt8(t >> 24), UInt8((t >> 16) & 0xFF), UInt8((t >> 8) & 0xFF), UInt8(t & 0xFF)])
        var nonce = Data(count: 8)
        _ = nonce.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 8, $0.baseAddress!) }
        head.append(nonce)
        let packet = head + mac("EMBR-LTE", [head], key: key).prefix(16)
        return (packet.hex, nonce.hex)
    }

    /// The car signs every report: X-Ember-Sig = HMAC(key,"EMBR-RPT"||body)[0..16].
    static func reportIsGenuine(_ body: String, sigHex: String, key: SymmetricKey) -> Bool {
        mac("EMBR-RPT", [Data(body.utf8)], key: key).prefix(16).hex == sigHex.lowercased()
    }
}

/// The car's report, as JSON (see buildReport in EmberLTE.h).
struct CloudReport: Decodable {
    struct Ack: Decodable { let id: String; let r: UInt8 }
    let v: Int
    let t: UInt32
    let st: String
    let fuel: Int?
    let lat: Double?
    let lon: Double?
    let spd: Double?
    let fix: UInt32?
    let ack: [Ack]?
}

extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
    init?(hexString: String) {
        let chars = Array(hexString.utf8)
        guard chars.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(chars.count / 2)
        var i = 0
        while i < chars.count {
            guard let b = UInt8(String(decoding: chars[i..<i + 2], as: UTF8.self), radix: 16) else { return nil }
            bytes.append(b)
            i += 2
        }
        self.init(bytes)
    }
}
