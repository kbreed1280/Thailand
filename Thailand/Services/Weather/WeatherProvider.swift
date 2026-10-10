import Foundation
import CoreLocation
import WeatherKit

/// What the weather screens need to show and to warn about.
struct WeatherSnapshot: Equatable {
    struct Hour: Equatable, Identifiable {
        var date: Date
        var temperatureC: Double
        var humidity: Double            // 0–1
        var precipitationChance: Double // 0–1
        var uvIndex: Int
        var symbolName: String
        var id: Date { date }

        var heatIndexC: Double { HeatIndex.celsius(temperatureC: temperatureC, humidity: humidity) }
        var heatLevel: HeatIndex.Level { HeatIndex.Level(heatIndexC: heatIndexC) }
    }

    struct Day: Equatable, Identifiable {
        var date: Date
        var highC: Double
        var lowC: Double
        /// Peak heat index from that day's hourly forecast (or estimated from the high).
        var maxHeatIndexC: Double
        var precipitationChance: Double
        var uvIndexMax: Int
        var symbolName: String
        var conditionText: String
        var sunrise: Date?
        var sunset: Date?
        var id: Date { date }

        var heatLevel: HeatIndex.Level { HeatIndex.Level(heatIndexC: maxHeatIndexC) }
    }

    enum Source: Equatable { case apple, openMeteo }

    var temperatureC: Double
    var feelsLikeC: Double
    var conditionText: String
    var symbolName: String
    var uvIndex: Int
    var humidity: Double
    var highC: Double
    var lowC: Double
    /// Upcoming hours (up to ~10 days).
    var hours: [Hour]
    /// Today first, up to 10 days.
    var days: [Day]
    var timeZone: TimeZone
    var source: Source
    var attributionLogoLight: URL?
    var attributionLogoDark: URL?
    var attributionLink: URL?

    var heatIndexC: Double { HeatIndex.celsius(temperatureC: temperatureC, humidity: humidity) }
    var heatLevel: HeatIndex.Level { HeatIndex.Level(heatIndexC: heatIndexC) }

    var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal
    }

    /// Hours for the rest of today and the next morning, for walking advice.
    var next24Hours: [Hour] { Array(hours.prefix(24)) }

    /// Today's daylight stretches best for walking (see HeatIndex.bestWalkingWindows).
    var bestWalkingWindows: [DateInterval] {
        let today = days.first
        let todayHours = hours.filter { calendar.isDate($0.date, inSameDayAs: today?.date ?? .now) }
        return HeatIndex.bestWalkingWindows(hours: todayHours, sunrise: today?.sunrise, sunset: today?.sunset, calendar: calendar)
    }

    var hottestWindowToday: DateInterval? {
        HeatIndex.hottestWindow(hours: hours.filter { calendar.isDate($0.date, inSameDayAs: days.first?.date ?? .now) })
    }

    /// Heads-ups for a day on foot.
    var alerts: [String] {
        var messages: [String] = []
        let peak = max(heatIndexC, days.first?.maxHeatIndexC ?? heatIndexC)
        let level = HeatIndex.Level(heatIndexC: peak)
        if level >= .danger {
            messages.append("Heat index up to \(Temperature.both(peak)) today (\(level.title.lowercased())). Walk early or late and rest in AC midday.")
        } else if level == .extremeCaution {
            messages.append("Heat index up to \(Temperature.both(peak)) today. Carry water and plan shade or café breaks.")
        }
        if uvIndex >= 8 || (days.first?.uvIndexMax ?? 0) >= 8 {
            messages.append("Very high UV (\(max(uvIndex, days.first?.uvIndexMax ?? 0))). Sunscreen, hat and sunglasses.")
        }
        if let rainy = hours.prefix(8).first(where: { $0.precipitationChance >= 0.6 }) {
            var style = Date.FormatStyle.dateTime.hour().minute()
            style.timeZone = timeZone
            messages.append("Rain likely around \(rainy.date.formatted(style)). Bring an umbrella or poncho.")
        }
        return messages
    }
}

/// Weather source behind a protocol so the app still works if WeatherKit isn't set up.
protocol WeatherProvider {
    func snapshot(for location: CLLocation, timeZone: TimeZone) async throws -> WeatherSnapshot
}

extension WeatherProvider {
    /// Uses the location's own time zone, so "hottest 1–4 PM" is local time there.
    func snapshot(for location: CLLocation) async throws -> WeatherSnapshot {
        try await snapshot(for: location, timeZone: await LocalTimeZone.at(location))
    }
}

enum LocalTimeZone {
    /// Time zone at a coordinate (reverse geocoded); falls back to the phone's.
    static func at(_ location: CLLocation) async -> TimeZone {
        if let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first, let tz = placemark.timeZone {
            return tz
        }
        // Thailand's bounding box, for when geocoding is unavailable.
        let c = location.coordinate
        if (5...21).contains(c.latitude) && (97...106).contains(c.longitude) { return WeatherPlace.thailandTimeZone }
        return .current
    }
}

/// Apple Weather first; if WeatherKit isn't enabled for this app or fails, Open-Meteo (free, no key).
struct AutomaticWeatherProvider: WeatherProvider {
    func snapshot(for location: CLLocation, timeZone: TimeZone) async throws -> WeatherSnapshot {
        do {
            return try await WeatherKitProvider().snapshot(for: location, timeZone: timeZone)
        } catch {
            return try await OpenMeteoProvider().snapshot(for: location, timeZone: timeZone)
        }
    }
}

struct WeatherKitProvider: WeatherProvider {
    func snapshot(for location: CLLocation, timeZone: TimeZone) async throws -> WeatherSnapshot {
        let service = WeatherService.shared
        let now = Date()
        let (current, hourly, daily) = try await service.weather(
            for: location,
            including: .current,
            .hourly(startDate: now.addingTimeInterval(-1_800), endDate: now.addingTimeInterval(10 * 86_400)),
            .daily(startDate: now.addingTimeInterval(-86_400), endDate: now.addingTimeInterval(10 * 86_400))
        )
        let attribution = try? await service.attribution

        let hours = hourly.forecast.map {
            WeatherSnapshot.Hour(
                date: $0.date,
                temperatureC: $0.temperature.converted(to: .celsius).value,
                humidity: $0.humidity,
                precipitationChance: $0.precipitationChance,
                uvIndex: $0.uvIndex.value,
                symbolName: $0.symbolName
            )
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let todayStart = cal.startOfDay(for: now)
        let days = daily.forecast
            .filter { $0.date >= todayStart.addingTimeInterval(-3600) }
            .prefix(10)
            .map { day in
                let high = day.highTemperature.converted(to: .celsius).value
                return WeatherSnapshot.Day(
                    date: day.date,
                    highC: high,
                    lowC: day.lowTemperature.converted(to: .celsius).value,
                    maxHeatIndexC: Self.peakHeatIndex(hours: hours, on: day.date, calendar: cal, fallbackHighC: high),
                    precipitationChance: day.precipitationChance,
                    uvIndexMax: day.uvIndex.value,
                    symbolName: day.symbolName,
                    conditionText: day.condition.description,
                    sunrise: day.sun.sunrise,
                    sunset: day.sun.sunset
                )
            }

        return WeatherSnapshot(
            temperatureC: current.temperature.converted(to: .celsius).value,
            feelsLikeC: current.apparentTemperature.converted(to: .celsius).value,
            conditionText: current.condition.description,
            symbolName: current.symbolName,
            uvIndex: current.uvIndex.value,
            humidity: current.humidity,
            highC: days.first?.highC ?? current.temperature.converted(to: .celsius).value,
            lowC: days.first?.lowC ?? current.temperature.converted(to: .celsius).value,
            hours: hours.filter { $0.date >= now.addingTimeInterval(-1_800) },
            days: Array(days),
            timeZone: timeZone,
            source: .apple,
            attributionLogoLight: attribution?.combinedMarkLightURL,
            attributionLogoDark: attribution?.combinedMarkDarkURL,
            attributionLink: attribution?.legalPageURL
        )
    }

    /// Highest hourly heat index on a day; if hours don't reach that far, assume a typical
    /// Thai afternoon humidity of 55% at the daily high.
    static func peakHeatIndex(hours: [WeatherSnapshot.Hour], on day: Date, calendar: Calendar, fallbackHighC: Double) -> Double {
        let sameDay = hours.filter { calendar.isDate($0.date, inSameDayAs: day) }
        if sameDay.count >= 12, let peak = sameDay.map(\.heatIndexC).max() { return peak }
        return HeatIndex.celsius(temperatureC: fallbackHighC, humidity: 0.55)
    }
}

/// Open-Meteo (open-meteo.com): free, no key, 10-day hourly forecast with humidity.
struct OpenMeteoProvider: WeatherProvider {
    private struct Response: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let relative_humidity_2m: Double
            let apparent_temperature: Double
            let uv_index: Double?
            let weather_code: Int
            let is_day: Int
        }
        struct Hourly: Decodable {
            let time: [TimeInterval]
            let temperature_2m: [Double?]
            let relative_humidity_2m: [Double?]
            let precipitation_probability: [Double?]
            let uv_index: [Double?]
            let weather_code: [Int?]
            let is_day: [Int?]
        }
        struct Daily: Decodable {
            let time: [TimeInterval]
            let temperature_2m_max: [Double?]
            let temperature_2m_min: [Double?]
            let precipitation_probability_max: [Double?]
            let uv_index_max: [Double?]
            let weather_code: [Int?]
            let sunrise: [TimeInterval?]
            let sunset: [TimeInterval?]
        }
        let current: Current
        let hourly: Hourly
        let daily: Daily
    }

    func snapshot(for location: CLLocation, timeZone: TimeZone) async throws -> WeatherSnapshot {
        var url = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        url.queryItems = [
            .init(name: "latitude", value: String(location.coordinate.latitude)),
            .init(name: "longitude", value: String(location.coordinate.longitude)),
            .init(name: "current", value: "temperature_2m,relative_humidity_2m,apparent_temperature,uv_index,weather_code,is_day"),
            .init(name: "hourly", value: "temperature_2m,relative_humidity_2m,precipitation_probability,uv_index,weather_code,is_day"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max,uv_index_max,weather_code,sunrise,sunset"),
            .init(name: "forecast_days", value: "10"),
            .init(name: "timezone", value: timeZone.identifier),
            .init(name: "timeformat", value: "unixtime"),
        ]
        let (data, response) = try await URLSession.shared.data(from: url.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let r = try JSONDecoder().decode(Response.self, from: data)
        let now = Date()

        var hours: [WeatherSnapshot.Hour] = []
        for i in r.hourly.time.indices {
            guard let t = r.hourly.temperature_2m[i], let rh = r.hourly.relative_humidity_2m[i] else { continue }
            let code = r.hourly.weather_code[i] ?? 0
            hours.append(.init(
                date: Date(timeIntervalSince1970: r.hourly.time[i]),
                temperatureC: t,
                humidity: rh / 100,
                precipitationChance: (r.hourly.precipitation_probability[i] ?? 0) / 100,
                uvIndex: Int((r.hourly.uv_index[i] ?? 0).rounded()),
                symbolName: WMOCode.symbol(code, isDay: (r.hourly.is_day[i] ?? 1) == 1)
            ))
        }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        var days: [WeatherSnapshot.Day] = []
        for i in r.daily.time.indices {
            guard let high = r.daily.temperature_2m_max[i], let low = r.daily.temperature_2m_min[i] else { continue }
            let date = Date(timeIntervalSince1970: r.daily.time[i])
            let code = r.daily.weather_code[i] ?? 0
            days.append(.init(
                date: date,
                highC: high,
                lowC: low,
                maxHeatIndexC: WeatherKitProvider.peakHeatIndex(hours: hours, on: date, calendar: cal, fallbackHighC: high),
                precipitationChance: (r.daily.precipitation_probability_max[i] ?? 0) / 100,
                uvIndexMax: Int((r.daily.uv_index_max[i] ?? 0).rounded()),
                symbolName: WMOCode.symbol(code, isDay: true),
                conditionText: WMOCode.text(code),
                sunrise: r.daily.sunrise[i].map { Date(timeIntervalSince1970: $0) },
                sunset: r.daily.sunset[i].map { Date(timeIntervalSince1970: $0) }
            ))
        }

        let c = r.current
        return WeatherSnapshot(
            temperatureC: c.temperature_2m,
            feelsLikeC: c.apparent_temperature,
            conditionText: WMOCode.text(c.weather_code),
            symbolName: WMOCode.symbol(c.weather_code, isDay: c.is_day == 1),
            uvIndex: Int((c.uv_index ?? 0).rounded()),
            humidity: c.relative_humidity_2m / 100,
            highC: days.first?.highC ?? c.temperature_2m,
            lowC: days.first?.lowC ?? c.temperature_2m,
            hours: hours.filter { $0.date >= now.addingTimeInterval(-1_800) },
            days: days,
            timeZone: timeZone,
            source: .openMeteo,
            attributionLogoLight: nil,
            attributionLogoDark: nil,
            attributionLink: URL(string: "https://open-meteo.com")
        )
    }
}

/// WMO weather codes (used by Open-Meteo) to text and SF Symbols.
enum WMOCode {
    static func text(_ code: Int) -> String {
        switch code {
        case 0: "Clear"
        case 1: "Mostly clear"
        case 2: "Partly cloudy"
        case 3: "Cloudy"
        case 45, 48: "Fog"
        case 51, 53, 55: "Drizzle"
        case 56, 57, 66, 67: "Freezing rain"
        case 61: "Light rain"
        case 63: "Rain"
        case 65: "Heavy rain"
        case 71, 73, 75, 77, 85, 86: "Snow"
        case 80: "Rain showers"
        case 81: "Heavy showers"
        case 82: "Violent showers"
        case 95: "Thunderstorms"
        case 96, 99: "Thunderstorms with hail"
        default: "—"
        }
    }

    static func symbol(_ code: Int, isDay: Bool) -> String {
        switch code {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51, 53, 55: "cloud.drizzle.fill"
        case 61, 63, 80, 81: isDay ? "cloud.sun.rain.fill" : "cloud.rain.fill"
        case 65, 82: "cloud.heavyrain.fill"
        case 56, 57, 66, 67: "cloud.sleet.fill"
        case 71, 73, 75, 77, 85, 86: "cloud.snow.fill"
        case 95, 96, 99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }
}

enum Temperature {
    /// Whole degrees Fahrenheit (weather is fetched in °C and shown in °F).
    static func f(_ celsius: Double) -> Int { Int((celsius * 9 / 5 + 32).rounded()) }

    /// "93°"
    static func deg(_ celsius: Double) -> String { "\(f(celsius))°" }

    /// "93°F"
    static func both(_ celsius: Double) -> String { "\(f(celsius))°F" }

    /// "93°F"
    static func short(_ celsius: Double) -> String { "\(f(celsius))°F" }
}

/// Cities you can check weather for before you get there (all on Thailand time).
struct WeatherPlace: Identifiable, Hashable {
    let name: String
    let latitude: Double
    let longitude: Double
    var id: String { name }

    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
    static let thailandTimeZone = TimeZone(identifier: "Asia/Bangkok")!

    static let cities: [WeatherPlace] = [
        .init(name: "Bangkok", latitude: 13.7563, longitude: 100.5018),
        .init(name: "Chiang Mai", latitude: 18.7883, longitude: 98.9853),
        .init(name: "Chiang Rai", latitude: 19.9105, longitude: 99.8406),
        .init(name: "Ayutthaya", latitude: 14.3532, longitude: 100.5689),
        .init(name: "Pattaya", latitude: 12.9236, longitude: 100.8825),
        .init(name: "Hua Hin", latitude: 12.5684, longitude: 99.9577),
        .init(name: "Phuket", latitude: 7.8804, longitude: 98.3923),
        .init(name: "Krabi / Ao Nang", latitude: 8.0355, longitude: 98.8199),
        .init(name: "Koh Samui", latitude: 9.5120, longitude: 100.0136),
        .init(name: "Koh Phangan", latitude: 9.7319, longitude: 100.0136),
        .init(name: "Koh Tao", latitude: 10.0956, longitude: 99.8404),
        .init(name: "Koh Lanta", latitude: 7.6247, longitude: 99.0791),
        .init(name: "Koh Phi Phi", latitude: 7.7407, longitude: 98.7784),
    ]
}
