import ActivityKit
import WidgetKit
import SwiftUI

private let ink = Color(red: 0.11, green: 0.31, blue: 0.85)
private let mango = Color(red: 0.957, green: 0.510, blue: 0.110)

/// Today's plan on the Lock Screen and in the Dynamic Island: next stop, time, and what's after.
struct DayPlanLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DayPlanActivityAttributes.self) { context in
            DayPlanLockScreenView(attributes: context.attributes, state: context.state)
                .padding(16)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: state.next?.symbol ?? "checkmark.circle.fill")
                        .font(.title2).foregroundStyle(mango)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let time = state.next?.time { Text(time, style: .time).font(.headline) }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(state.next?.title ?? "Day done").font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let after = state.after {
                        Text("Then \(after.title)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            } compactLeading: {
                Image(systemName: state.next?.symbol ?? "checkmark").foregroundStyle(mango)
            } compactTrailing: {
                if let time = state.next?.time {
                    Text(time, style: .time).font(.caption.bold()).foregroundStyle(mango)
                } else {
                    Text("\(state.remaining + (state.next == nil ? 0 : 1))").font(.caption.bold()).foregroundStyle(mango)
                }
            } minimal: {
                Image(systemName: state.next?.symbol ?? "checkmark").foregroundStyle(mango)
            }
        }
    }
}

private struct DayPlanLockScreenView: View {
    let attributes: DayPlanActivityAttributes
    let state: DayPlanActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("\(attributes.dayTitle) · \(attributes.tripName)", systemImage: "airplane")
                    .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                Spacer()
                if state.remaining > 0 {
                    Text("+\(state.remaining) more").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
                }
            }
            if let next = state.next {
                HStack(spacing: 12) {
                    Image(systemName: next.symbol)
                        .font(.title3.weight(.semibold)).foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(mango, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("UP NEXT").font(.caption2.weight(.heavy)).foregroundStyle(mango)
                        Text(next.title).font(.headline).foregroundStyle(.white).lineLimit(1)
                        if !next.address.isEmpty {
                            Text(next.address).font(.caption).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                        }
                    }
                    Spacer()
                    if let time = next.time {
                        Text(time, style: .time).font(.title3.bold().monospacedDigit()).foregroundStyle(.white)
                    }
                }
                if let after = state.after {
                    HStack(spacing: 6) {
                        Image(systemName: after.symbol).font(.caption)
                        Text("Then \(after.title)").lineLimit(1)
                        if let time = after.time { Text("· ") + Text(time, style: .time) }
                    }
                    .font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.8))
                }
            } else {
                Label("That's everything for today", systemImage: "checkmark.circle.fill")
                    .font(.headline).foregroundStyle(.white)
            }
        }
    }
}
