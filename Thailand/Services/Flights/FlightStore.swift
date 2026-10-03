import Foundation
import UserNotifications
import BackgroundTasks

struct TrackedFlight: Codable, Identifiable, Equatable {
    var id = UUID()
    /// "TG 103"
    var number: String
    /// Local departure date, "yyyy-MM-dd" (what airlines print on the ticket).
    var day: String
    var note: String = ""
    var status: FlightStatus?
    var lastError: String?

    /// "tg103" / "TG-103" → "TG 103". Airline codes always contain a letter (TG, FD, 3K),
    /// so a bare number like "701" is left as-is and treated as invalid.
    static func normalize(_ raw: String) -> String {
        let cleaned = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        guard let match = cleaned.wholeMatch(of: /([A-Z][A-Z0-9]|[0-9][A-Z])([0-9]{1,4}[A-Z]?)/) else { return raw.uppercased() }
        return "\(match.1) \(match.2)"
    }

    /// True for "TG 103"-style numbers with an airline code.
    static func isValidNumber(_ raw: String) -> Bool {
        normalize(raw).wholeMatch(of: /([A-Z][A-Z0-9]|[0-9][A-Z]) [0-9]{1,4}[A-Z]?/) != nil
    }

    /// Why a number can't be looked up, for the add-flight form.
    static func problem(with raw: String) -> String? {
        let cleaned = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        if cleaned.isEmpty || isValidNumber(raw) { return nil }
        if cleaned.allSatisfy(\.isNumber) {
            return "Add the 2-character airline code in front, e.g. TG \(cleaned) for Thai Airways. It's printed on your ticket next to the flight number."
        }
        if cleaned.prefix(3).allSatisfy(\.isLetter) {
            return "Use the 2-character airline code (e.g. TG, not THA). It's printed on your ticket next to the flight number."
        }
        return "Enter the airline code and number, e.g. TG 103."
    }

    var departureDate: Date? {
        status?.departure.best ?? DateFormatter.flightDay.date(from: day).map { $0.addingTimeInterval(12 * 3600) }
    }

    var arrivalDate: Date? { status?.arrival.best }

    var isFinished: Bool {
        if let status, status.hasLanded || status.isCanceled { return true }
        guard let end = arrivalDate ?? departureDate else { return false }
        return end < Date().addingTimeInterval(-3 * 3600)
    }

    var title: String {
        if let status, let from = status.departure.airportIATA, let to = status.arrival.airportIATA {
            return "\(number) · \(from) → \(to)"
        }
        return number
    }
}

/// Flights you follow, kept on this phone. Live status comes from `FlightStatusService`,
/// refreshed sparingly so the free data plan lasts the whole trip.
@MainActor
final class FlightStore: ObservableObject {
    static let shared = FlightStore()
    nonisolated static let backgroundTaskID = "com.kbreed.thailandtrip.flightRefresh"

    @Published private(set) var flights: [TrackedFlight] = []
    @Published private(set) var refreshing: Set<UUID> = []

    private var fileURL: URL {
        let dir = URL.applicationSupportDirectory.appending(path: "Flights", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "flights.json")
    }

    init() { load() }

    var upcoming: [TrackedFlight] {
        flights.filter { !$0.isFinished }.sorted { ($0.departureDate ?? .distantFuture) < ($1.departureDate ?? .distantFuture) }
    }

    var past: [TrackedFlight] {
        flights.filter(\.isFinished).sorted { ($0.departureDate ?? .distantPast) > ($1.departureDate ?? .distantPast) }
    }

    /// The flight to feature (Lock Screen, Trip header): the next one within 24 hours.
    var nextActive: TrackedFlight? {
        upcoming.first { ($0.departureDate ?? .distantFuture).timeIntervalSinceNow < 24 * 3600 }
    }

    // MARK: Editing

    @discardableResult
    func add(number: String, day: String, note: String = "") -> TrackedFlight {
        let flight = TrackedFlight(number: TrackedFlight.normalize(number), day: day, note: note)
        if let existing = flights.first(where: { $0.number == flight.number && $0.day == day }) { return existing }
        flights.append(flight)
        save()
        Task {
            await requestNotificationPermission()
            await refresh(flight.id, force: true)
        }
        return flight
    }

    func update(_ flight: TrackedFlight) {
        guard let index = flights.firstIndex(where: { $0.id == flight.id }) else { return }
        flights[index] = flight
        save()
    }

    func delete(_ flight: TrackedFlight) {
        flights.removeAll { $0.id == flight.id }
        save()
        FlightActivityController.shared.end(flightID: flight.id)
    }

    // MARK: Refresh

    /// How stale status may get before we spend another API call.
    static func refreshInterval(for flight: TrackedFlight, now: Date = .now) -> TimeInterval? {
        if flight.isFinished { return nil }
        guard let departure = flight.departureDate else { return 6 * 3600 }
        let until = departure.timeIntervalSince(now)
        // The free plan is 400 units/month and each check costs 2, so ~30 checks per flight.
        switch until {
        case ..<(-1 * 3600): return 30 * 60      // in the air: arrival time, baggage belt
        case ..<(6 * 3600): return 20 * 60       // travel day: gate, delays
        case ..<(48 * 3600): return 6 * 3600
        default: return 24 * 3600
        }
    }

    func needsRefresh(_ flight: TrackedFlight, now: Date = .now) -> Bool {
        guard let interval = Self.refreshInterval(for: flight, now: now) else { return false }
        guard let fetched = flight.status?.fetchedAt else { return true }
        return now.timeIntervalSince(fetched) >= interval
    }

    func refreshAllIfNeeded() async {
        for flight in flights where needsRefresh(flight) {
            await refresh(flight.id, force: false)
        }
        FlightActivityController.shared.sync(with: self)
        scheduleBackgroundRefresh()
    }

    func refresh(_ id: UUID, force: Bool) async {
        guard let flight = flights.first(where: { $0.id == id }), !refreshing.contains(id) else { return }
        if !force, !needsRefresh(flight) { return }
        // Even a manual refresh waits 2 minutes, to protect the monthly allowance.
        if force, let fetched = flight.status?.fetchedAt, Date().timeIntervalSince(fetched) < 120 { return }

        // Numbers without an airline code (e.g. "701") can never be found; say why instead of calling the API.
        if let problem = TrackedFlight.problem(with: flight.number) {
            var current = flight
            current.lastError = problem + " Delete this flight and add it again."
            update(current)
            return
        }

        refreshing.insert(id)
        defer { refreshing.remove(id) }
        do {
            let status = try await FlightStatusService.fetch(number: flight.number, day: flight.day)
            guard var current = flights.first(where: { $0.id == id }) else { return }
            if let old = current.status { notifyChanges(flight: current, from: old, to: status) }
            current.status = status
            current.lastError = nil
            update(current)
        } catch {
            guard var current = flights.first(where: { $0.id == id }) else { return }
            current.lastError = (error as? LocalizedError)?.errorDescription ?? "Couldn't update this flight."
            update(current)
        }
        FlightActivityController.shared.sync(with: self)
    }

    // MARK: Alerts

    private func requestNotificationPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    /// Compares two snapshots and returns what a traveler would want to be told.
    nonisolated static func changes(from old: FlightStatus, to new: FlightStatus) -> [String] {
        var lines: [String] = []
        if new.isCanceled, !old.isCanceled { lines.append("Flight canceled. Contact the airline.") }
        if let gate = new.departure.gate, gate != old.departure.gate {
            lines.append(old.departure.gate == nil ? "Gate \(gate)" : "Gate changed to \(gate) (was \(old.departure.gate!))")
        }
        if let terminal = new.departure.terminal, terminal != old.departure.terminal, old.departure.terminal != nil {
            lines.append("Terminal changed to \(terminal)")
        }
        let oldDelay = old.departure.delayMinutes, newDelay = new.departure.delayMinutes
        if abs(newDelay - oldDelay) >= 15 {
            lines.append(newDelay > 0 ? "Delayed \(newDelay) min" : "Back on time")
        }
        if let belt = new.arrival.baggageBelt, belt != old.arrival.baggageBelt {
            lines.append("Bags on belt \(belt)")
        }
        if new.hasLanded, !old.hasLanded { lines.append("Landed") }
        return lines
    }

    private func notifyChanges(flight: TrackedFlight, from old: FlightStatus, to new: FlightStatus) {
        let lines = Self.changes(from: old, to: new)
        guard !lines.isEmpty else { return }
        let content = UNMutableNotificationContent()
        content.title = "✈️ \(flight.number)"
        content.body = lines.joined(separator: " · ")
        content.sound = .default
        let request = UNNotificationRequest(identifier: "flight-\(flight.id)-\(Date().timeIntervalSince1970)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: Background refresh

    nonisolated static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskID, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            let work = Task { @MainActor in
                await FlightStore.shared.refreshAllIfNeeded()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    func scheduleBackgroundRefresh() {
        guard let next = upcoming.compactMap({ Self.refreshInterval(for: $0) }).min() else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskID)
        request.earliestBeginDate = Date().addingTimeInterval(next)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: Detect flights in bookings

    /// Finds flight numbers ("TG 103", "FD3205") in booking text, with a date nearby if any.
    nonisolated static func detectFlights(in text: String) -> [String] {
        let known = Set(["TG", "FD", "SL", "DD", "PG", "WE", "VZ", "XJ", "AK", "SQ", "CX", "EK", "QR", "JL", "NH", "KE", "OZ", "BR", "CI", "UA", "AA", "DL", "LH", "BA", "AF", "KL", "TR", "MH", "VN", "VJ", "EY", "TK", "QF", "NZ", "CA", "MU", "CZ", "HX", "UO", "3K", "8M", "AI", "6E", "OD", "Z2", "5J", "PR", "GA", "JQ", "MM", "7C", "ZE", "LJ", "BX", "IT"])
        var found: [String] = []
        let upper = text.uppercased()
        for match in upper.matches(of: /\b([A-Z0-9]{2})[ -]?(\d{2,4})\b/) {
            let code = String(match.1)
            guard known.contains(code), code.contains(where: \.isLetter) else { continue }
            let number = "\(code) \(match.2)"
            if !found.contains(number) { found.append(number) }
        }
        return found
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        flights = (try? decoder.decode([TrackedFlight].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(flights) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
