import SwiftUI

/// Heat index ("feels like" from heat + humidity) using the US National Weather Service formula,
/// with the NWS risk bands. Thailand's humidity makes this a far better guide than temperature alone.
enum HeatIndex {
    /// Heat index in °C from air temperature (°C) and relative humidity (0–1).
    static func celsius(temperatureC: Double, humidity: Double) -> Double {
        let f = fahrenheit(temperatureF: temperatureC * 9 / 5 + 32, humidityPercent: humidity * 100)
        return (f - 32) * 5 / 9
    }

    /// NWS Rothfusz regression with its low/high humidity adjustments.
    static func fahrenheit(temperatureF t: Double, humidityPercent rh: Double) -> Double {
        let simple = 0.5 * (t + 61 + (t - 68) * 1.2 + rh * 0.094)
        if (simple + t) / 2 < 80 { return simple }

        var hi = -42.379 + 2.04901523 * t + 10.14333127 * rh
            - 0.22475541 * t * rh - 0.00683783 * t * t - 0.05481717 * rh * rh
            + 0.00122874 * t * t * rh + 0.00085282 * t * rh * rh - 0.00000199 * t * t * rh * rh
        if rh < 13, (80...112).contains(t) {
            hi -= ((13 - rh) / 4) * ((17 - abs(t - 95)) / 17).squareRoot()
        } else if rh > 85, (80...87).contains(t) {
            hi += ((rh - 85) / 10) * ((87 - t) / 5)
        }
        return hi
    }

    enum Level: Int, Comparable, CaseIterable {
        case comfortable, caution, extremeCaution, danger, extremeDanger

        /// NWS bands, in °F: 80 / 90 / 103 / 125.
        init(heatIndexC: Double) {
            let f = heatIndexC * 9 / 5 + 32
            switch f {
            case ..<80: self = .comfortable
            case ..<90: self = .caution
            case ..<103: self = .extremeCaution
            case ..<125: self = .danger
            default: self = .extremeDanger
            }
        }

        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }

        var title: String {
            switch self {
            case .comfortable: "Comfortable"
            case .caution: "Caution"
            case .extremeCaution: "Extreme caution"
            case .danger: "Danger"
            case .extremeDanger: "Extreme danger"
            }
        }

        var color: Color {
            switch self {
            case .comfortable: Theme.lagoon
            case .caution: Color(hex: "#E8B400")
            case .extremeCaution: Theme.mango
            case .danger: Theme.coral
            case .extremeDanger: Color(hex: "#9B1B30")
            }
        }

        var symbol: String {
            switch self {
            case .comfortable: "thermometer.low"
            case .caution: "thermometer.medium"
            case .extremeCaution, .danger: "thermometer.high"
            case .extremeDanger: "thermometer.sun.fill"
            }
        }

        /// What to actually do, tuned for a day walking around Thailand.
        var advice: String {
            switch self {
            case .comfortable:
                "Good walking weather. Still carry water."
            case .caution:
                "Tiring if you're walking a lot. Drink water regularly and take shade breaks."
            case .extremeCaution:
                "Heat exhaustion is possible with long walks. Drink before you're thirsty, add electrolytes, and duck into a 7-Eleven, mall or café for AC every hour."
            case .danger:
                "Heat exhaustion is likely and heat stroke is possible. Do outdoor sights early or late, take Grab/BTS for longer hops, and rest in AC midday."
            case .extremeDanger:
                "Heat stroke is likely with exposure. Stay in AC during the hottest hours and keep outdoor time short."
            }
        }
    }

    /// Daylight stretches when walking is most comfortable: heat index below
    /// "extreme caution" (32 °C / 90 °F) and rain under 60%. Falls back to the
    /// coolest stretches below "danger" when the whole day is hot.
    static func bestWalkingWindows(
        hours: [WeatherSnapshot.Hour],
        sunrise: Date?,
        sunset: Date?,
        calendar: Calendar
    ) -> [DateInterval] {
        guard let first = hours.first else { return [] }
        let day = calendar.startOfDay(for: first.date)
        let dawn = sunrise ?? calendar.date(bySettingHour: 6, minute: 0, second: 0, of: day)!
        let dusk = (sunset ?? calendar.date(bySettingHour: 18, minute: 30, second: 0, of: day)!).addingTimeInterval(2 * 3600)
        let daylight = hours.filter { $0.date >= dawn.addingTimeInterval(-1800) && $0.date < dusk }

        func windows(maxLevel: Level) -> [DateInterval] {
            var result: [DateInterval] = []
            var start: Date?
            var end: Date?
            for hour in daylight {
                let ok = Level(heatIndexC: hour.heatIndexC) <= maxLevel && hour.precipitationChance < 0.6
                if ok {
                    if start == nil { start = hour.date }
                    end = hour.date.addingTimeInterval(3600)
                } else if let s = start, let e = end {
                    result.append(DateInterval(start: s, end: e))
                    start = nil
                }
            }
            if let s = start, let e = end { result.append(DateInterval(start: s, end: e)) }
            return result.filter { $0.duration >= 3600 }
        }

        let comfortable = windows(maxLevel: .caution)
        return comfortable.isEmpty ? windows(maxLevel: .extremeCaution) : comfortable
    }

    /// The hottest stretch of the day, e.g. 1 PM–4 PM.
    /// The continuous run of hours around the peak that share the peak's risk level.
    static func hottestWindow(hours: [WeatherSnapshot.Hour]) -> DateInterval? {
        guard let peakIndex = hours.indices.max(by: { hours[$0].heatIndexC < hours[$1].heatIndexC }) else { return nil }
        let level = hours[peakIndex].heatLevel
        guard level >= .extremeCaution else { return nil }
        var first = peakIndex, last = peakIndex
        while first > 0, hours[first - 1].heatLevel >= level { first -= 1 }
        while last < hours.count - 1, hours[last + 1].heatLevel >= level { last += 1 }
        return DateInterval(start: hours[first].date, end: hours[last].date.addingTimeInterval(3600))
    }
}

enum WindowText {
    /// "6 AM–9 AM, 6 PM–8 PM" in the forecast's time zone.
    static func format(_ windows: [DateInterval], timeZone: TimeZone) -> String {
        var style = Date.FormatStyle.dateTime.hour()
        style.timeZone = timeZone
        return windows.map { "\($0.start.formatted(style))–\($0.end.formatted(style))" }.joined(separator: ", ")
    }
}
