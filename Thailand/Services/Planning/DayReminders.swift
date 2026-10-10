import Foundation
import UserNotifications

/// "Tomorrow: 5 stops, starting 8:00 AM at Roots Coffee. High 34°, heat index danger." at
/// 8 PM the night before each planned day. Rescheduled whenever the app comes to the front.
enum DayReminders {
    static let enabledKey = "dayRemindersEnabled"
    private static let prefix = "day-reminder-"

    static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    struct Reminder: Equatable {
        let id: String
        let fireDate: Date
        let title: String
        let body: String
    }

    /// Pure: what to schedule for these days (unit-tested).
    static func reminders(for days: [(date: Date, stops: [(title: String, time: Date?)])],
                          weather: (Date) -> String? = { _ in nil },
                          now: Date = .now, calendar: Calendar = .current) -> [Reminder] {
        days.compactMap { day in
            guard !day.stops.isEmpty,
                  let eve = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: day.date)),
                  let fire = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: eve),
                  fire > now else { return nil }
            let first = day.stops.first { $0.time != nil } ?? day.stops[0]
            var body = "\(day.stops.count) stop\(day.stops.count == 1 ? "" : "s")"
            if let time = first.time {
                body += ", starting \(time.formatted(date: .omitted, time: .shortened)) at \(first.title)"
            } else {
                body += ", starting with \(first.title)"
            }
            body += "."
            if let w = weather(day.date) { body += " \(w)" }
            let stamp = ISO8601DateFormatter().string(from: calendar.startOfDay(for: day.date))
            return Reminder(id: prefix + stamp, fireDate: fire, title: "Tomorrow's plan", body: body)
        }
    }

    @MainActor
    static func reschedule(for trip: Trip) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard isEnabled else { return }

        let days = trip.sortedDays.compactMap { day -> (date: Date, stops: [(title: String, time: Date?)])? in
            guard let date = day.date else { return nil }
            return (date, day.sortedItems.map { ($0.displayTitle, $0.time) })
        }
        let forecast = TripForecast.shared
        let list = reminders(for: days, weather: { date in
            guard let d = forecast.day(date, in: trip) else { return nil }
            return "High \(Temperature.both(d.highC)), \(d.conditionText.lowercased()). Heat: \(d.heatLevel.title.lowercased())."
        })
        guard !list.isEmpty else { return }
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        } else if settings.authorizationStatus == .denied {
            return
        }
        for r in list.prefix(30) {
            let content = UNMutableNotificationContent()
            content.title = r.title
            content.body = r.body
            content.sound = .default
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: r.fireDate)
            try? await center.add(UNNotificationRequest(identifier: r.id, content: content,
                                                        trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
        }
    }
}
