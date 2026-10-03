import Foundation
import CoreMotion

struct WalkStats: Equatable {
    var steps: Int
    var meters: Double

    static let zero = WalkStats(steps: 0, meters: 0)

    var kilometersText: String {
        (meters / 1_000).formatted(.number.precision(.fractionLength(1))) + " km"
    }
}

/// Steps and distance walked from the iPhone's motion coprocessor (no GPS, no battery cost).
/// iOS keeps 7 days of history.
final class PedometerService: ObservableObject {
    static let shared = PedometerService()

    @Published private(set) var today: WalkStats = .zero
    @Published private(set) var isDenied = false

    private let pedometer = CMPedometer()
    private var isLive = false

    static var isAvailable: Bool { CMPedometer.isStepCountingAvailable() }

    /// Starts live updates for today (call while a screen showing steps is visible).
    func startToday() {
        guard Self.isAvailable, !isLive else { return }
        updateDenied()
        isLive = true
        let start = Calendar.current.startOfDay(for: .now)
        pedometer.startUpdates(from: start) { [weak self] data, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if error != nil { self.updateDenied() }
                guard let data else { return }
                self.today = WalkStats(steps: data.numberOfSteps.intValue, meters: data.distance?.doubleValue ?? 0)
            }
        }
    }

    func stopToday() {
        guard isLive else { return }
        pedometer.stopUpdates()
        isLive = false
    }

    /// Steps for a past day (within the last 7 days), or nil when unavailable.
    func stats(for day: Date) async -> WalkStats? {
        guard Self.isAvailable else { return nil }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start),
              start <= .now,
              let oldest = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: .now)),
              start >= oldest else { return nil }
        let upTo = min(end, .now)
        return await withCheckedContinuation { continuation in
            pedometer.queryPedometerData(from: start, to: upTo) { data, _ in
                guard let data else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: WalkStats(steps: data.numberOfSteps.intValue, meters: data.distance?.doubleValue ?? 0))
            }
        }
    }

    private func updateDenied() {
        let status = CMPedometer.authorizationStatus()
        isDenied = status == .denied || status == .restricted
    }
}
