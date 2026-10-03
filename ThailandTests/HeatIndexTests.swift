import XCTest
@testable import Thailand

final class HeatIndexTests: XCTestCase {

    // MARK: NWS heat index chart values (°F, ±1)

    func testMatchesNWSChart() {
        XCTAssertEqual(HeatIndex.fahrenheit(temperatureF: 90, humidityPercent: 70), 106, accuracy: 1)
        XCTAssertEqual(HeatIndex.fahrenheit(temperatureF: 96, humidityPercent: 50), 108, accuracy: 1)
        XCTAssertEqual(HeatIndex.fahrenheit(temperatureF: 86, humidityPercent: 90), 105, accuracy: 1)
        XCTAssertEqual(HeatIndex.fahrenheit(temperatureF: 100, humidityPercent: 40), 109, accuracy: 1)
    }

    func testMildConditionsUseSimpleFormula() {
        // Below ~80 °F the heat index is about the air temperature.
        XCTAssertEqual(HeatIndex.fahrenheit(temperatureF: 75, humidityPercent: 50), 75, accuracy: 1.5)
    }

    func testCelsiusWrapper() {
        // Typical Bangkok afternoon: 34 °C at 60% humidity ≈ 43 °C heat index.
        XCTAssertEqual(HeatIndex.celsius(temperatureC: 34, humidity: 0.6), 42.6, accuracy: 1)
    }

    // MARK: Levels

    func testLevels() {
        XCTAssertEqual(HeatIndex.Level(heatIndexC: 25), .comfortable)
        XCTAssertEqual(HeatIndex.Level(heatIndexC: 29), .caution)        // 84 °F
        XCTAssertEqual(HeatIndex.Level(heatIndexC: 35), .extremeCaution) // 95 °F
        XCTAssertEqual(HeatIndex.Level(heatIndexC: 42), .danger)         // 108 °F
        XCTAssertEqual(HeatIndex.Level(heatIndexC: 53), .extremeDanger)  // 127 °F
    }

    // MARK: Walking windows

    private var bangkok: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        return cal
    }

    /// A day where it's mild early and late and very hot midday.
    private func hotDay() -> [WeatherSnapshot.Hour] {
        let start = bangkok.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 0))!
        return (0..<24).map { h in
            let temp: Double = switch h {
            case 0..<8: 26
            case 8..<10: 29
            case 10..<17: 34
            case 17..<19: 30
            default: 27
            }
            return WeatherSnapshot.Hour(date: start.addingTimeInterval(Double(h) * 3600), temperatureC: temp,
                                        humidity: 0.6, precipitationChance: 0.1, uvIndex: 5, symbolName: "sun.max.fill")
        }
    }

    func testBestWalkingWindowsAreEarlyAndLate() {
        let windows = HeatIndex.bestWalkingWindows(hours: hotDay(), sunrise: nil, sunset: nil, calendar: bangkok)
        let hours = windows.map { (bangkok.component(.hour, from: $0.start), bangkok.component(.hour, from: $0.end)) }
        XCTAssertEqual(hours.first?.0, 6)   // from sunrise
        XCTAssertEqual(hours.first?.1, 10)  // 29 °C at 8–9 AM is only "caution"; 34 °C from 10 AM is not
        XCTAssertEqual(hours.last?.0, 19)   // evening
    }

    func testHottestWindowIsMidday() {
        let hot = HeatIndex.hottestWindow(hours: hotDay())!
        XCTAssertEqual(bangkok.component(.hour, from: hot.start), 10)
        XCTAssertEqual(bangkok.component(.hour, from: hot.end), 17)
    }

    func testRainyHoursAreNotWalkingWindows() {
        let rainy = hotDay().map { var h = $0; h.precipitationChance = 0.8; return h }
        XCTAssertTrue(HeatIndex.bestWalkingWindows(hours: rainy, sunrise: nil, sunset: nil, calendar: bangkok).isEmpty)
    }

    func testWMOCodes() {
        XCTAssertEqual(WMOCode.text(95), "Thunderstorms")
        XCTAssertEqual(WMOCode.symbol(0, isDay: false), "moon.stars.fill")
    }
}
