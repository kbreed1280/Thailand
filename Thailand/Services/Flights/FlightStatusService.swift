import Foundation
import Security

// MARK: - Live status (AeroDataBox via RapidAPI)

/// One side of a flight (departure or arrival) as the data service reports it.
struct FlightEndpoint: Codable, Equatable {
    var airportIATA: String?
    var airportName: String?
    var city: String?
    var timeZone: String?
    var scheduled: Date?
    var revised: Date?
    var runway: Date?
    var terminal: String?
    var gate: String?
    var checkInDesk: String?
    var baggageBelt: String?

    /// Best current estimate: actual (runway) > revised/predicted > scheduled.
    var best: Date? { runway ?? revised ?? scheduled }

    var delayMinutes: Int {
        guard let scheduled, let best else { return 0 }
        return Int((best.timeIntervalSince(scheduled) / 60).rounded())
    }

    var displayAirport: String {
        [airportIATA, city ?? airportName].compactMap { $0 }.joined(separator: " · ")
    }

    var tz: TimeZone { timeZone.flatMap(TimeZone.init(identifier:)) ?? .current }
}

struct FlightStatus: Codable, Equatable {
    var number: String
    var airline: String?
    var status: String
    var aircraft: String?
    var departure: FlightEndpoint
    var arrival: FlightEndpoint
    var fetchedAt: Date

    /// "EnRoute" → "En route", "GateClosed" → "Gate closed".
    var statusText: String {
        let spaced = status.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
        return spaced.prefix(1).uppercased() + spaced.dropFirst().lowercased()
    }

    var isCanceled: Bool { status.lowercased().hasPrefix("cancel") }
    var hasLanded: Bool { ["landed", "arrived"].contains(status.lowercased()) }
}

enum FlightStatusError: LocalizedError {
    case missingKey, badKey, rateLimited, notFound, offline, server(Int), unreadable

    var errorDescription: String? {
        switch self {
        case .missingKey: "Add your free AeroDataBox key in Flight Settings to get live status."
        case .badKey: "The flight-data key was rejected. Check it in Flight Settings."
        case .rateLimited: "You've used this month's free flight checks. Status will update again next month, or upgrade the plan on RapidAPI."
        case .notFound: "No flight with that number on that date. Check the number and date (local departure date)."
        case .offline: "No internet. Showing the last saved status."
        case .server(let code): "The flight service had a problem (\(code)). Try again in a few minutes."
        case .unreadable: "The flight service sent something unexpected. Try again later."
        }
    }
}

/// Talks to AeroDataBox (https://aerodatabox.com) through RapidAPI.
/// The free plan allows a limited number of calls a month, so callers refresh sparingly.
enum FlightStatusService {
    static let host = "aerodatabox.p.rapidapi.com"

    static func fetch(number: String, day: String, session: URLSession = .shared) async throws -> FlightStatus {
        guard let key = FlightKeychain.apiKey, !key.isEmpty else { throw FlightStatusError.missingKey }
        guard NetworkMonitor.shared.isOnline else { throw FlightStatusError.offline }

        let compact = TrackedFlight.normalize(number).replacingOccurrences(of: " ", with: "")
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/flights/number/\(compact)/\(day)"
        components.queryItems = [
            URLQueryItem(name: "withAircraftImage", value: "false"),
            URLQueryItem(name: "withLocation", value: "false"),
            URLQueryItem(name: "dateLocalRole", value: "Departure"),
        ]
        guard let url = components.url else { throw FlightStatusError.notFound }

        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(key, forHTTPHeaderField: "x-rapidapi-key")
        request.setValue(host, forHTTPHeaderField: "x-rapidapi-host")

        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200: break
        case 204, 404: throw FlightStatusError.notFound
        case 401, 403: throw FlightStatusError.badKey
        case 429: throw FlightStatusError.rateLimited
        default: throw FlightStatusError.server(code)
        }
        guard let status = try parse(data, fallbackNumber: compact).first else { throw FlightStatusError.notFound }
        return status
    }

    /// Parses the `/flights/number` response (an array of flight legs).
    static func parse(_ data: Data, fallbackNumber: String, now: Date = .now) throws -> [FlightStatus] {
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw FlightStatusError.unreadable
        }
        return array.map { leg in
            FlightStatus(
                number: leg["number"] as? String ?? fallbackNumber,
                airline: (leg["airline"] as? [String: Any])?["name"] as? String,
                status: leg["status"] as? String ?? "Unknown",
                aircraft: (leg["aircraft"] as? [String: Any])?["model"] as? String,
                departure: endpoint(leg["departure"]),
                arrival: endpoint(leg["arrival"]),
                fetchedAt: now
            )
        }
    }

    private static func endpoint(_ value: Any?) -> FlightEndpoint {
        let dict = value as? [String: Any] ?? [:]
        let airport = dict["airport"] as? [String: Any] ?? [:]
        func time(_ key: String) -> Date? {
            guard let t = dict[key] as? [String: Any], let utc = t["utc"] as? String else { return nil }
            return DateFormatter.parseFlightTime(utc)
        }
        return FlightEndpoint(
            airportIATA: airport["iata"] as? String,
            airportName: airport["shortName"] as? String ?? airport["name"] as? String,
            city: airport["municipalityName"] as? String,
            timeZone: airport["timeZone"] as? String,
            scheduled: time("scheduledTime"),
            revised: time("revisedTime") ?? time("predictedTime"),
            runway: time("runwayTime"),
            terminal: dict["terminal"] as? String,
            gate: dict["gate"] as? String,
            checkInDesk: dict["checkInDesk"] as? String,
            baggageBelt: dict["baggageBelt"] as? String
        )
    }
}

extension DateFormatter {
    static let flightDay: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let flightTimeFormats: [DateFormatter] = ["yyyy-MM-dd HH:mmXXXXX", "yyyy-MM-dd HH:mm:ssXXXXX", "yyyy-MM-dd'T'HH:mm:ssXXXXX"].map {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = $0
        return f
    }

    /// AeroDataBox times look like "2026-11-03 12:35Z".
    static func parseFlightTime(_ string: String) -> Date? {
        for f in flightTimeFormats { if let d = f.date(from: string) { return d } }
        return nil
    }
}

// MARK: - API key (Keychain, this device only)

enum FlightKeychain {
    private static let service = "com.kbreed.thailandtrip.flights"
    private static let account = "aerodatabox-rapidapi-key"

    static var apiKey: String? {
        get {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set {
            let base: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            SecItemDelete(base as CFDictionary)
            guard let newValue, !newValue.isEmpty else { return }
            var add = base
            add[kSecValueData as String] = Data(newValue.utf8)
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
