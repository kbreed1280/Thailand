import SwiftUI
import CoreLocation

/// The travel "leg" between two consecutive stops: time and distance by the next stop's
/// travel mode, and a warning when the gap is too tight.
struct LegRow: View {
    @ObservedObject var from: Item
    @ObservedObject var to: Item
    var onWalk: ((WalkTarget) -> Void)? = nil

    @State private var leg: TravelLeg?
    @State private var isLoading = true

    private var minutesLate: Int {
        guard let leg, let end = from.endTime, let start = to.time else { return 0 }
        return ScheduleMath.minutesLate(previousEnd: end, travelSeconds: leg.seconds, nextStart: start)
    }

    private var taskKey: String {
        "\(from.latitude),\(from.longitude)>\(to.latitude),\(to.longitude)|\(to.travelModeRaw ?? "")|\(to.time?.timeIntervalSince1970 ?? 0)|\(from.durationMinutes)"
    }

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(minutesLate > 0 ? Color.orange : Theme.lagoon.opacity(0.5))
                .frame(width: 3, height: 28)
                .padding(.leading, 18)
            Image(systemName: to.travelMode.systemImage)
            if isLoading {
                ProgressView().controlSize(.mini)
            } else if let leg {
                Text("\(ScheduleMath.durationText(seconds: leg.seconds)) · \(DistanceText.distance(leg.meters))")
                    .monospacedDigit()
            } else {
                Text("—")
            }
            Spacer()
            if minutesLate > 0 {
                Label("Running ~\(minutesLate) min late", systemImage: "exclamationmark.triangle.fill")
                    .fontWeight(.semibold)
            } else if let onWalk, to.travelMode == .walking, let coordinate = to.coordinate {
                Button {
                    onWalk(WalkTarget(name: to.displayTitle, coordinate: coordinate))
                } label: {
                    Label("Walk", systemImage: "figure.walk.circle")
                }
                .buttonStyle(.borderless)
            }
        }
        .font(.caption)
        .foregroundStyle(minutesLate > 0 ? Color.orange : Color.secondary)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 16))
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .task(id: taskKey) {
            guard let start = from.coordinate, let end = to.coordinate else {
                isLoading = false
                return
            }
            if let cached = TravelTimeService.shared.cachedLeg(from: start, to: end, mode: to.travelMode, at: to.time) {
                leg = cached
                isLoading = false
                return
            }
            isLoading = true
            leg = await TravelTimeService.shared.leg(from: start, to: end, mode: to.travelMode, at: to.time)
            isLoading = false
        }
    }

    private var accessibilityText: String {
        guard let leg else { return "\(to.travelMode.title) to \(to.displayTitle), time unknown" }
        var text = "\(to.travelMode.title) \(ScheduleMath.durationText(seconds: leg.seconds)) to \(to.displayTitle)"
        if minutesLate > 0 { text += ". Running about \(minutesLate) minutes late" }
        return text
    }
}
