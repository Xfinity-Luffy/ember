import SwiftUI

/// One of your cars (up to 4). Each has its own bridge key (in the Keychain),
/// its own remembered bridge, its own saved parking spot and connection type.
struct Vehicle: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var vin = ""
    var year = ""
    var make = ""
    var model = ""
    var trim = ""
    var body = ""
    var plate = ""
    var color: VehicleColor = .silver
    var connection: ConnectionMode = .bluetooth
    var type: VehicleType = .car

    static let maxCount = 4

    /// "2021 Mazda Mazda3" (empty if unknown).
    var description: String {
        [year, make.capitalized(with: nil), model].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Storage keys that belong to this vehicle.
    var keychainAccount: String { id.uuidString }
    var peripheralKey: String { "ember.bridgePeripheralID.\(id.uuidString)" }
    var spotKey: String { "ember.carSpot.\(id.uuidString)" }

    enum CodingKeys: String, CodingKey {
        case id, name, vin, year, make, model, trim, body, plate, color, connection, type
    }
}

extension Vehicle {
    /// Reads saved vehicles, including ones saved before a field existed.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "My Car"
        vin = try c.decodeIfPresent(String.self, forKey: .vin) ?? ""
        year = try c.decodeIfPresent(String.self, forKey: .year) ?? ""
        make = try c.decodeIfPresent(String.self, forKey: .make) ?? ""
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        trim = try c.decodeIfPresent(String.self, forKey: .trim) ?? ""
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        plate = try c.decodeIfPresent(String.self, forKey: .plate) ?? ""
        color = (try? c.decodeIfPresent(VehicleColor.self, forKey: .color)) ?? .silver
        connection = (try? c.decodeIfPresent(ConnectionMode.self, forKey: .connection)) ?? .bluetooth
        type = (try? c.decodeIfPresent(VehicleType.self, forKey: .type))
            ?? VehicleType.guess(body: body, model: model)
    }
}

/// The shape used for the vehicle's silhouette.
enum VehicleType: String, Codable, CaseIterable, Identifiable {
    case car, hatchback, suv, truck
    var id: String { rawValue }

    var title: String {
        switch self {
        case .car: return "Car"
        case .hatchback: return "Hatchback"
        case .suv: return "SUV"
        case .truck: return "Truck"
        }
    }
    /// Short label for the segmented picker.
    var shortTitle: String { self == .hatchback ? "Hatch" : title }

    /// Best guess from NHTSA's body class (e.g. "Hatchback/Liftback/Notchback",
    /// "Sport Utility Vehicle (SUV)/Multi-Purpose Vehicle (MPV)", "Pickup").
    static func guess(body: String, model: String = "") -> VehicleType {
        let b = (body + " " + model).lowercased()
        if b.contains("pickup") || b.contains("truck") { return .truck }
        if b.contains("sport utility") || b.contains("suv") || b.contains("crossover")
            || b.contains("multi-purpose") || b.contains("van") || b.contains("wagon") { return .suv }
        if b.contains("hatchback") || b.contains("liftback") { return .hatchback }
        return .car
    }
}

enum VehicleColor: String, Codable, CaseIterable, Identifiable {
    case white, silver, gray, black, red, blue, green, orange
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var swatch: Color {
        switch self {
        case .white: return Color(white: 0.95)
        case .silver: return Color(red: 0.75, green: 0.77, blue: 0.80)
        case .gray: return Color(red: 0.42, green: 0.44, blue: 0.47)
        case .black: return Color(white: 0.12)
        case .red: return Color(red: 0.78, green: 0.10, blue: 0.14)
        case .blue: return Color(red: 0.16, green: 0.36, blue: 0.75)
        case .green: return Color(red: 0.16, green: 0.48, blue: 0.32)
        case .orange: return Color(red: 0.95, green: 0.45, blue: 0.14)
        }
    }
}

// MARK: - VIN tools

enum VIN {
    /// Uppercases and drops spaces/dashes. VINs never use I, O or Q.
    static func clean(_ text: String) -> String {
        text.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    static func isWellFormed(_ vin: String) -> Bool {
        vin.count == 17 && !vin.contains(where: { "IOQ".contains($0) }) && vin.allSatisfy { $0.isASCII }
    }

    /// The 9th character is a check digit on North American VINs. Returns nil
    /// when it can't be checked (wrong length / characters).
    static func checkDigitMatches(_ vin: String) -> Bool? {
        guard isWellFormed(vin) else { return nil }
        let values: [Character: Int] = [
            "A": 1, "B": 2, "C": 3, "D": 4, "E": 5, "F": 6, "G": 7, "H": 8,
            "J": 1, "K": 2, "L": 3, "M": 4, "N": 5, "P": 7, "R": 9,
            "S": 2, "T": 3, "U": 4, "V": 5, "W": 6, "X": 7, "Y": 8, "Z": 9,
        ]
        let weights = [8, 7, 6, 5, 4, 3, 2, 10, 0, 9, 8, 7, 6, 5, 4, 3, 2]
        var sum = 0
        for (i, ch) in vin.enumerated() {
            let v = ch.wholeNumberValue ?? values[ch] ?? 0
            sum += v * weights[i]
        }
        let remainder = sum % 11
        let expected: Character = remainder == 10 ? "X" : Character(String(remainder))
        return vin[vin.index(vin.startIndex, offsetBy: 8)] == expected
    }

    /// Shows only the last 6 characters: ••••••••••••123456
    static func masked(_ vin: String) -> String {
        guard vin.count > 6 else { return vin }
        return String(repeating: "•", count: vin.count - 6) + vin.suffix(6)
    }

    struct Decoded { var year = "", make = "", model = "", trim = "", body = "" }

    enum LookupError: LocalizedError {
        case badVIN, notFound, offline
        var errorDescription: String? {
            switch self {
            case .badVIN: return "A VIN is 17 letters and numbers (never I, O or Q)."
            case .notFound: return "No match found for that VIN. Check it and try again, or fill in the details yourself."
            case .offline: return "Couldn't reach the lookup service. Check your connection, or fill in the details yourself."
            }
        }
    }

    /// Looks the VIN up in NHTSA's free public vehicle database (vPIC).
    static func lookUp(_ vin: String) async throws -> Decoded {
        let vin = clean(vin)
        guard isWellFormed(vin) else { throw LookupError.badVIN }
        guard let url = URL(string: "https://vpic.nhtsa.dot.gov/api/vehicles/DecodeVinValues/\(vin)?format=json") else {
            throw LookupError.badVIN
        }
        struct Response: Decodable { let Results: [[String: String?]] }
        let data: Data
        do { (data, _) = try await URLSession.shared.data(from: url) } catch { throw LookupError.offline }
        guard let row = (try? JSONDecoder().decode(Response.self, from: data))?.Results.first else {
            throw LookupError.notFound
        }
        func field(_ name: String) -> String { ((row[name] ?? nil) ?? "").trimmingCharacters(in: .whitespaces) }
        let decoded = Decoded(year: field("ModelYear"), make: field("Make"), model: field("Model"),
                              trim: field("Trim"), body: field("BodyClass"))
        if decoded.make.isEmpty && decoded.model.isEmpty { throw LookupError.notFound }
        return decoded
    }
}
