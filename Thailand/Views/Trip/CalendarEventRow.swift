import SwiftUI
import EventKit

/// A read-only calendar event shown in grey between itinerary items.
struct CalendarEventRow: View {
    let event: EKEvent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
                .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title ?? "Event")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(timeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Circle()
                .fill(Color(cgColor: event.calendar.cgColor))
                .frame(width: 8, height: 8)
        }
        .padding(.vertical, 2)
        .opacity(0.8)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Calendar event. Long-press to add it to the trip.")
    }

    private var timeText: String {
        if event.isAllDay { return "All day · \(event.calendar.title)" }
        let start = event.startDate.formatted(date: .omitted, time: .shortened)
        let end = event.endDate.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end) · \(event.calendar.title)"
    }
}
