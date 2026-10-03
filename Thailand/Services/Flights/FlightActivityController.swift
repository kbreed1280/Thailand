import Foundation
import ActivityKit

/// Starts, updates and ends the Lock Screen / Dynamic Island Live Activity for the
/// next flight (within 24 hours). Updated whenever the app refreshes flight status.
@MainActor
final class FlightActivityController {
    static let shared = FlightActivityController()

    private var current: Activity<FlightActivityAttributes>? {
        Activity<FlightActivityAttributes>.activities.first
    }

    static func state(for flight: TrackedFlight) -> FlightActivityAttributes.ContentState {
        let status = flight.status
        return FlightActivityAttributes.ContentState(
            statusText: status?.statusText ?? "Scheduled",
            departure: flight.departureDate ?? .now,
            arrival: flight.arrivalDate,
            delayMinutes: status?.departure.delayMinutes ?? 0,
            terminal: status?.departure.terminal,
            gate: status?.departure.gate,
            baggageBelt: status?.arrival.baggageBelt,
            isCanceled: status?.isCanceled ?? false,
            hasLanded: status?.hasLanded ?? false,
            updatedAt: status?.fetchedAt ?? .now
        )
    }

    func sync(with store: FlightStore) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard let flight = store.nextActive else {
            if let current, let finished = store.flights.first(where: { $0.id.uuidString == current.attributes.flightID }), finished.isFinished {
                end(flightID: finished.id)
            }
            return
        }
        let state = Self.state(for: flight)
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(45 * 60))

        if let current, current.attributes.flightID == flight.id.uuidString {
            Task { await current.update(content) }
            if flight.isFinished { end(flightID: flight.id) }
            return
        }
        // A different (or no) flight is showing: replace it.
        if let current { Task { await current.end(nil, dismissalPolicy: .immediate) } }
        let attributes = FlightActivityAttributes(
            flightID: flight.id.uuidString,
            number: flight.number,
            from: flight.status?.departure.airportIATA ?? "",
            to: flight.status?.arrival.airportIATA ?? "",
            airline: flight.status?.airline ?? ""
        )
        _ = try? Activity.request(attributes: attributes, content: content, pushType: nil)
    }

    func end(flightID: UUID) {
        for activity in Activity<FlightActivityAttributes>.activities where activity.attributes.flightID == flightID.uuidString {
            Task { await activity.end(nil, dismissalPolicy: .after(Date().addingTimeInterval(30 * 60))) }
        }
    }
}
