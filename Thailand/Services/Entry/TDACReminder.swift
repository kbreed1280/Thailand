import Foundation
import UIKit
import UserNotifications

/// Thailand Digital Arrival Card (TDAC): every foreign visitor must submit it online
/// within the 3 days (72 hours) before arriving. Works out the window from your trip and
/// flights, reminds you when it opens, and links to the official THIM app and website.
enum TDACReminder {
    /// Official Thai Immigration Bureau app (Royal Thai Police).
    static let thimAppStoreURL = URL(string: "https://apps.apple.com/app/id6759272559")!
    static let officialWebsite = URL(string: "https://tdac.immigration.go.th")!

    /// Thai international airports, to recognize the flight that lands in Thailand.
    static let thaiAirports: Set<String> = ["BKK", "DMK", "HKT", "CNX", "USM", "KBV", "CEI", "HDY", "UTP", "UTH", "URT", "NST", "TST"]
    static let thailand = TimeZone(identifier: "Asia/Bangkok")!

    struct Window: Equatable {
        let arrival: Date
        let opens: Date
        /// Where the arrival date came from, for the UI ("your flight TG 701" / "trip start date").
        let source: String

        func status(now: Date = .now) -> Status {
            if now >= arrival { return .passed }
            if now >= opens { return .open }
            return .notYet
        }
    }

    enum Status { case notYet, open, passed }

    /// Arrival from a tracked flight landing in Thailand (best), else the trip's start date
    /// (assumed mid-day Thailand time).
    static func window(tripStart: Date?, flights: [TrackedFlight]) -> Window? {
        let landing = flights.compactMap { flight -> (Date, String)? in
            guard let arrival = flight.status?.arrival,
                  let code = arrival.airportIATA?.uppercased(), thaiAirports.contains(code),
                  let date = arrival.best ?? arrival.scheduled else { return nil }
            return (date, "your flight \(flight.number)")
        }
        .filter { $0.0 > Date().addingTimeInterval(-86_400 * 30) }
        .min { $0.0 < $1.0 }

        if let (arrival, source) = landing {
            return Window(arrival: arrival, opens: arrival.addingTimeInterval(-72 * 3600), source: source)
        }
        guard let start = tripStart else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = thailand
        let day = cal.dateComponents([.year, .month, .day], from: start)
        guard let arrival = cal.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)) else { return nil }
        return Window(arrival: arrival, opens: arrival.addingTimeInterval(-72 * 3600), source: "your trip start date")
    }

    // MARK: Notifications

    private static let openID = "tdac-window-open"
    private static let lastCallID = "tdac-last-call"

    /// Schedules "TDAC is open" at 9 AM local on the day the window opens (or right when it opens,
    /// if that's later), plus a last-call reminder the day before arrival.
    static func schedule(for window: Window) async {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        cancel()

        let cal = Calendar.current
        var openFire = cal.date(bySettingHour: 9, minute: 0, second: 0, of: window.opens) ?? window.opens
        if openFire < window.opens { openFire = window.opens }
        let lastCall = window.arrival.addingTimeInterval(-24 * 3600)

        func add(_ id: String, at date: Date, title: String, body: String) async {
            guard date > .now else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.userInfo = ["deepLink": "tdac"]
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: date), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }

        await add(openID, at: openFire,
                  title: "Thailand arrival card (TDAC) is open",
                  body: "Submit it now in the THIM app or at tdac.immigration.go.th. It's free, and takes about 5 minutes per person.")
        await add(lastCallID, at: lastCall,
                  title: "Last call: Thailand arrival card",
                  body: "You land tomorrow. If you haven't submitted your TDAC yet, do it today and save the QR code in WanderHub.")
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [openID, lastCallID])
    }

    /// Opens THIM (the App Store page shows "Open" when it's installed).
    @MainActor
    static func openTHIM() {
        UIApplication.shared.open(thimAppStoreURL)
    }
}
