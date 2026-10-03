import ActivityKit
import WidgetKit
import SwiftUI

private let lagoon = Color(red: 0.106, green: 0.639, blue: 0.612)
private let mango = Color(red: 0.957, green: 0.510, blue: 0.110)
private let coral = Color(red: 0.910, green: 0.314, blue: 0.357)

/// Next flight on the Lock Screen and in the Dynamic Island: status, times, gate, bags.
struct FlightLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FlightActivityAttributes.self) { context in
            LockScreenFlightView(attributes: context.attributes, state: context.state)
                .padding(16)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.from.isEmpty ? "—" : context.attributes.from).font(.title2.bold())
                        Text(state.departure, style: .time).font(.caption).foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(context.attributes.to.isEmpty ? "—" : context.attributes.to).font(.title2.bold())
                        if let arrival = state.arrival {
                            Text(arrival, style: .time).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.attributes.number).font(.headline)
                        StatusText(state: state).font(.caption.weight(.semibold))
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    FactsRow(state: state)
                }
            } compactLeading: {
                Image(systemName: "airplane").foregroundStyle(lagoon)
            } compactTrailing: {
                if let gate = state.gate, !state.hasLanded {
                    Text(gate).font(.caption.bold()).foregroundStyle(lagoon)
                } else if let belt = state.baggageBelt, state.hasLanded {
                    Text("Belt \(belt)").font(.caption.bold()).foregroundStyle(lagoon)
                } else {
                    Text(state.departure, style: .timer)
                        .font(.caption.monospacedDigit())
                        .frame(maxWidth: 52)
                        .foregroundStyle(state.delayMinutes >= 15 ? mango : lagoon)
                }
            } minimal: {
                Image(systemName: state.isCanceled ? "exclamationmark.triangle.fill" : "airplane")
                    .foregroundStyle(state.isCanceled ? coral : lagoon)
            }
        }
    }
}

private struct LockScreenFlightView: View {
    let attributes: FlightActivityAttributes
    let state: FlightActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(attributes.number, systemImage: "airplane")
                    .font(.headline)
                    .foregroundStyle(.white)
                if !attributes.airline.isEmpty {
                    Text(attributes.airline).font(.caption).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                }
                Spacer()
                StatusText(state: state)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.15), in: Capsule())
            }
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading) {
                    Text(attributes.from.isEmpty ? "—" : attributes.from).font(.title.bold())
                    Text(state.departure, style: .time).font(.subheadline)
                }
                Spacer()
                if !state.hasLanded, !state.isCanceled, state.departure > .now {
                    VStack {
                        Text("departs in").font(.caption2).foregroundStyle(.white.opacity(0.7))
                        Text(state.departure, style: .relative).font(.subheadline.weight(.semibold)).multilineTextAlignment(.center)
                    }
                } else {
                    Image(systemName: "airplane").font(.title3)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(attributes.to.isEmpty ? "—" : attributes.to).font(.title.bold())
                    if let arrival = state.arrival {
                        Text(arrival, style: .time).font(.subheadline)
                    }
                }
            }
            .foregroundStyle(.white)
            FactsRow(state: state)
        }
    }
}

private struct StatusText: View {
    let state: FlightActivityAttributes.ContentState

    var body: some View {
        if state.isCanceled {
            Text("Canceled").foregroundStyle(coral)
        } else if state.hasLanded {
            Text("Landed").foregroundStyle(lagoon)
        } else if state.delayMinutes >= 15 {
            Text("Delayed \(state.delayMinutes) min").foregroundStyle(mango)
        } else {
            Text(state.statusText == "Expected" || state.statusText == "Unknown" ? "On time" : state.statusText).foregroundStyle(lagoon)
        }
    }
}

private struct FactsRow: View {
    let state: FlightActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 8) {
            fact("Terminal", state.terminal ?? "–")
            if state.hasLanded {
                fact("Bags", state.baggageBelt ?? "TBA")
            } else {
                fact("Gate", state.gate ?? "TBA")
            }
            fact("Updated", state.updatedAt.formatted(date: .omitted, time: .shortened))
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(label.uppercased()).font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.6))
            Text(value).font(.subheadline.bold()).foregroundStyle(.white).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}
