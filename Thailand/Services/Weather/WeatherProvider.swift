import Foundation
import CoreLocation
import WeatherKit

/// What the Nearby tab needs to show and to warn about.
struct WeatherSnapshot: Equatable {
    struct Hour: Equatable, Identifiable {
        var date: Date
        var temperatureC: Double
        var precipitationChance: Double
        var symbolName: String
        var id: Date { date }
    }

    var temperatureC: Double
    var feelsLikeC: Double
    var conditionText: String
    var symbolName: String
    var uvIndex: Int
    var humidity: Double
    var highC: Double
    var lowC: Double
    var hours: [Hour]
    var attributionLogoLight: URL?
    var attributionLogoDark: URL?
    var attributionLink: URL?

    /// Heads-ups for a day on foot.
    var alerts: [String] {
        var messages: [String] = []
        if feelsLikeC >= 40 {
            messages.append("Extreme heat (feels like \(Int(feelsLikeC.rounded()))°C). Walk early or after 4 PM, rest in shade, drink plenty of water.")
        } else if feelsLikeC >= 33 {
            messages.append("Hot out (feels like \(Int(feelsLikeC.rounded()))°C). Carry water and plan shade or café breaks.")
        }
        if uvIndex >= 8 {
            messages.append("Very high UV (\(uvIndex)). Sunscreen, hat and sunglasses.")
        }
        if let rainy = hours.prefix(8).first(where: { $0.precipitationChance >= 0.6 }) {
            messages.append("Rain likely around \(rainy.date.formatted(date: .omitted, time: .shortened)) — bring an umbrella or poncho.")
        }
        return messages
    }
}

/// Weather source behind a protocol so the app still works if WeatherKit isn't set up.
protocol WeatherProvider {
    func snapshot(for location: CLLocation) async throws -> WeatherSnapshot
}

struct WeatherKitProvider: WeatherProvider {
    func snapshot(for location: CLLocation) async throws -> WeatherSnapshot {
        let service = WeatherService.shared
        let (current, hourly, daily) = try await service.weather(for: location, including: .current, .hourly, .daily)
        let attribution = try? await service.attribution
        let today = daily.forecast.first

        return WeatherSnapshot(
            temperatureC: current.temperature.converted(to: .celsius).value,
            feelsLikeC: current.apparentTemperature.converted(to: .celsius).value,
            conditionText: current.condition.description,
            symbolName: current.symbolName,
            uvIndex: current.uvIndex.value,
            humidity: current.humidity,
            highC: today?.highTemperature.converted(to: .celsius).value ?? current.temperature.converted(to: .celsius).value,
            lowC: today?.lowTemperature.converted(to: .celsius).value ?? current.temperature.converted(to: .celsius).value,
            hours: hourly.forecast
                .filter { $0.date >= Date().addingTimeInterval(-1_800) }
                .prefix(12)
                .map {
                    WeatherSnapshot.Hour(
                        date: $0.date,
                        temperatureC: $0.temperature.converted(to: .celsius).value,
                        precipitationChance: $0.precipitationChance,
                        symbolName: $0.symbolName
                    )
                },
            attributionLogoLight: attribution?.combinedMarkLightURL,
            attributionLogoDark: attribution?.combinedMarkDarkURL,
            attributionLink: attribution?.legalPageURL
        )
    }
}

enum Temperature {
    /// "34°C · 93°F"
    static func both(_ celsius: Double) -> String {
        let fahrenheit = celsius * 9 / 5 + 32
        return "\(Int(celsius.rounded()))°C · \(Int(fahrenheit.rounded()))°F"
    }
}
