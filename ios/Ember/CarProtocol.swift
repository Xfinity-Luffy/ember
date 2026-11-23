import Foundation
import CoreBluetooth
import CryptoKit

/// Wire protocol shared with the Ember Bridge firmware (EmberBridge.ino).
/// If you change anything here, change it there too.
enum EmberProtocol {
    static let service   = CBUUID(string: "e1ff55ff-6a97-433b-bea8-9ec4b34f384e")
    static let challenge = CBUUID(string: "19761279-973c-47a5-8d3d-08d03f22677c")
    static let command   = CBUUID(string: "6a4d6a66-0fe9-48ca-878e-238060417a9d")
    static let status    = CBUUID(string: "7bdb2e96-9fcf-4522-b098-7264afa1c44d")

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

    var verb: String {
        switch self {
        case .lock: return "Locking"
        case .unlock: return "Unlocking"
        case .start: return "Starting"
        case .stop: return "Stopping"
        case .aux1: return "Defrost"
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

    /// Status packet: [ver=1][flags][secs LE16][lastResult][seq]
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
    }
}

enum LinkState: Equatable {
    case bluetoothOff
    case unauthorized
    case searching
    case connecting
    case ready
    case demo

    var label: String {
        switch self {
        case .bluetoothOff: return "Bluetooth off"
        case .unauthorized: return "Bluetooth not allowed"
        case .searching: return "Looking for car"
        case .connecting: return "Connecting"
        case .ready: return "Connected"
        case .demo: return "Demo mode"
        }
    }
    var isUsable: Bool { self == .ready || self == .demo }
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
    func start()
    func stop()
    /// Sends a command and returns once the bridge reports a result.
    func send(_ command: CarCommand) async throws
}
