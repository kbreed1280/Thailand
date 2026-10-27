import WidgetKit
import SwiftUI

/// Lock Screen clock: Nashville time and the time where the phone is, both in 12-hour format.
struct DualClockEntry: TimelineEntry {
    let date: Date
}

struct DualClockProvider: TimelineProvider {
    func placeholder(in context: Context) -> DualClockEntry { DualClockEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (DualClockEntry) -> Void) {
        completion(DualClockEntry(date: .now))
    }

    /// One entry per minute for the next 6 hours, then WidgetKit asks for a new timeline.
    /// WidgetKit also reloads widgets when the phone's time zone changes, so "here" follows you.
    func getTimeline(in context: Context, completion: @escaping (Timeline<DualClockEntry>) -> Void) {
        let cal = Calendar.current
        let thisMinute = cal.dateInterval(of: .minute, for: .now)?.start ?? .now
        let entries = (0..<360).map { DualClockEntry(date: cal.date(byAdding: .minute, value: $0, to: thisMinute)!) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

enum DualClockFormat {
    static let nashville = TimeZone(identifier: "America/Chicago")!

    static func time(_ date: Date, in zone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    /// "Bangkok" from "Asia/Bangkok"; falls back to the zone abbreviation.
    static func placeName(_ zone: TimeZone) -> String {
        if let city = zone.identifier.split(separator: "/").last, zone.identifier.contains("/") {
            return city.replacingOccurrences(of: "_", with: " ")
        }
        return zone.abbreviation() ?? "Here"
    }
}

struct DualClockView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DualClockEntry

    var body: some View {
        let here = TimeZone.autoupdatingCurrent
        let nash = DualClockFormat.time(entry.date, in: DualClockFormat.nashville)
        let local = DualClockFormat.time(entry.date, in: here)
        let sameZone = here.secondsFromGMT(for: entry.date) == DualClockFormat.nashville.secondsFromGMT(for: entry.date)

        switch family {
        case .accessoryInline:
            Text(sameZone ? "Nashville \(nash)" : "NSH \(nash) · \(local)")
        default:
            VStack(alignment: .leading, spacing: 1) {
                row("NASHVILLE", nash)
                if !sameZone {
                    row(DualClockFormat.placeName(here).uppercased(), local)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ label: String, _ time: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 2)
            Text(time)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .monospacedDigit()
                .widgetAccentable()
        }
    }
}

struct DualClockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DualClockWidget", provider: DualClockProvider()) { entry in
            DualClockView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Nashville + Local Time")
        .description("Nashville time and the time where you are, in 12-hour format.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}
