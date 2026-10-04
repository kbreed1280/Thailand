import CoreLocation
import Foundation

/// One 10-day forecast per trip (cached for an hour) so each day in the itinerary can show
/// its weather and heat, and the planner can keep outdoor stops out of the hottest days.
@MainActor
final class TripForecast: ObservableObject {
    static let shared = TripForecast()

    @Published private(set) var snapshots: [String: WeatherSnapshot] = [:]
    private var fetchedAt: [String: Date] = [:]
    private var inFlight: Set<String> = []
    private let provider: WeatherProvider = AutomaticWeatherProvider()

    /// Where the trip is: its destination if it names a known city, else the middle of your
    /// planned and saved places, else Bangkok.
    static func location(for trip: Trip) -> CLLocation {
        let destination = (trip.destination ?? "").lowercased()
        if !destination.isEmpty, let city = WeatherPlace.cities.first(where: {
            destination.contains($0.name.lowercased().components(separatedBy: " /").first ?? $0.name.lowercased())
        }) {
            return city.location
        }
        let points = trip.sortedDays.flatMap(\.sortedItems).compactMap(\.coordinate) + trip.confirmedSpots.compactMap(\.coordinate)
        guard !points.isEmpty else { return WeatherPlace.cities[0].location }
        let n = Double(points.count)
        return CLLocation(latitude: points.map(\.latitude).reduce(0, +) / n, longitude: points.map(\.longitude).reduce(0, +) / n)
    }

    private func key(_ trip: Trip) -> String { trip.objectID.uriRepresentation().absoluteString }

    func forecast(for trip: Trip) -> WeatherSnapshot? { snapshots[key(trip)] }

    func day(_ date: Date, in trip: Trip) -> WeatherSnapshot.Day? {
        let calendar = Calendar.current
        return forecast(for: trip)?.days.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    func refresh(_ trip: Trip) async {
        let k = key(trip)
        if let at = fetchedAt[k], Date().timeIntervalSince(at) < 3600 { return }
        guard !inFlight.contains(k) else { return }
        // Forecasts only reach ~10 days out; skip trips that haven't started getting close.
        if let start = trip.startDate, start.timeIntervalSinceNow > 11 * 86_400 { return }
        if let end = trip.endDate, end.timeIntervalSinceNow < -86_400 { return }
        inFlight.insert(k)
        defer { inFlight.remove(k) }
        let location = Self.location(for: trip)
        let zone = await LocalTimeZone.at(location)
        if let snapshot = try? await provider.snapshot(for: location, timeZone: zone) {
            snapshots[k] = snapshot
            fetchedAt[k] = .now
        }
    }

    /// Days with a dangerous heat index ("danger" or worse, ≥ 39 °C), for the planner.
    func hotDays(in trip: Trip) -> Set<Date> {
        Set(forecast(for: trip)?.days.filter { $0.heatLevel >= .danger }.map(\.date) ?? [])
    }
}
