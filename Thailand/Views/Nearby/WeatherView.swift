import Charts
import CoreLocation
import SwiftUI

/// Full weather: current conditions with heat index, best walking times, a 24-hour heat
/// chart and the 10-day forecast, for your location or any Thai city.
struct WeatherView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var location = LocationService.shared
    @ObservedObject private var network = NetworkMonitor.shared
    /// "" = my location, otherwise a WeatherPlace name.
    @AppStorage("weatherPlace") private var placeName = ""

    @State private var weather: WeatherSnapshot?
    @State private var loading = false
    @State private var failed = false

    private let provider: WeatherProvider = AutomaticWeatherProvider()
    private var place: WeatherPlace? { WeatherPlace.cities.first { $0.name == placeName } }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                placePicker

                if let weather {
                    nowCard(weather)
                    walkingCard(weather)
                    hourlyCard(weather).id("hourly")
                    tenDayCard(weather).id("tenDay")
                    HeatGuideCard()
                    attribution(weather)
                } else if loading {
                    ProgressView("Loading forecast…").frame(maxWidth: .infinity, minHeight: 200)
                } else if failed || !network.isOnline {
                    ContentUnavailableView("Weather unavailable",
                                           systemImage: "cloud.slash",
                                           description: Text(network.isOnline ? "Couldn't load the forecast. Pull to try again." : "Weather needs an internet connection."))
                }
            }
            .padding()
        }
        #if DEBUG
        // Debug-only: launch with `-weatherScroll tenDay` to jump to the forecast.
        .onChange(of: weather) {
            if let target = UserDefaults.standard.string(forKey: "weatherScroll") { proxy.scrollTo(target, anchor: .top) }
        }
        #endif
        }
        .background(Theme.background)
        .navigationTitle("Weather")
        .refreshable { await load() }
        .task(id: placeName) { await load() }
    }

    // MARK: Loading

    private func load() async {
        loading = true
        defer { loading = false }
        let target: (CLLocation, TimeZone)?
        if let place {
            target = (place.location, WeatherPlace.thailandTimeZone)
        } else if let here = await location.currentLocation() {
            target = (here, await LocalTimeZone.at(here))
        } else {
            // No location permission: show Bangkok instead of nothing.
            target = (WeatherPlace.cities[0].location, WeatherPlace.thailandTimeZone)
        }
        guard let (loc, tz) = target else { return }
        do {
            weather = try await provider.snapshot(for: loc, timeZone: tz)
            failed = false
        } catch {
            failed = weather == nil
        }
    }

    // MARK: Sections

    private var placePicker: some View {
        Menu {
            Button("My location", systemImage: "location.fill") { placeName = "" }
            Divider()
            ForEach(WeatherPlace.cities) { city in
                Button(city.name) { placeName = city.name }
            }
        } label: {
            HStack {
                Image(systemName: place == nil ? "location.fill" : "mappin.circle.fill")
                Text(place?.name ?? "My location").font(.headline)
                Image(systemName: "chevron.down").font(.caption.weight(.bold))
                Spacer()
                if place != nil {
                    Text("Thailand time").font(.caption).foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(Theme.mango)
        }
    }

    private func nowCard(_ w: WeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                WeatherSymbol(name: w.symbolName)
                    .font(.system(size: 48))
                VStack(alignment: .leading, spacing: 2) {
                    Text(Temperature.both(w.temperatureC)).font(.title2.bold())
                    Text(w.conditionText).foregroundStyle(.secondary)
                    Text("H \(Temperature.short(w.highC))  L \(Temperature.short(w.lowC))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HeatIndexBadge(heatIndexC: w.heatIndexC, label: "Heat index now")
            Text(w.heatLevel.advice).font(.subheadline)
            HStack(spacing: 16) {
                stat("Humidity", "\(Int((w.humidity * 100).rounded()))%", "humidity.fill")
                stat("UV", "\(w.uvIndex)", "sun.max.fill", tint: w.uvIndex >= 8 ? Theme.coral : nil)
                if let rain = w.days.first?.precipitationChance {
                    stat("Rain today", "\(Int((rain * 100).rounded()))%", "cloud.rain.fill")
                }
            }
            ForEach(w.alerts, id: \.self) { alert in
                Label(alert, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline).foregroundStyle(Theme.coral)
            }
        }
        .card()
    }

    private func stat(_ title: String, _ value: String, _ symbol: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: symbol).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(tint ?? .primary)
        }
    }

    private func walkingCard(_ w: WeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Best times to walk today", systemImage: "figure.walk").font(.headline)
            let windows = w.bestWalkingWindows
            if windows.isEmpty {
                Text("No comfortable stretch left today. Keep outdoor time short and take Grab or the BTS between stops.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text(WindowText.format(windows, timeZone: w.timeZone)).font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.lagoon)
            }
            if let hot = w.hottestWindowToday {
                Label("Hottest: \(WindowText.format([hot], timeZone: w.timeZone)). Plan temples, malls or a pool then.",
                      systemImage: "sun.max.trianglebadge.exclamationmark")
                    .font(.subheadline).foregroundStyle(Theme.coral)
            }
        }
        .card()
    }

    private func hourlyCard(_ w: WeatherSnapshot) -> some View {
        let hours = w.next24Hours
        var hourStyle = Date.FormatStyle.dateTime.hour()
        hourStyle.timeZone = w.timeZone
        return VStack(alignment: .leading, spacing: 10) {
            Text("Next 24 hours").font(.headline)
            Chart {
                ForEach(hours) { h in
                    AreaMark(x: .value("Time", h.date), yStart: .value("Base", yDomain(hours).lowerBound), yEnd: .value("Heat index", h.heatIndexC))
                        .foregroundStyle(Theme.coral.opacity(0.15))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Time", h.date), y: .value("Heat index", h.heatIndexC), series: .value("", "Heat index"))
                        .foregroundStyle(Theme.coral)
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Time", h.date), y: .value("Temp", h.temperatureC), series: .value("", "Temperature"))
                        .foregroundStyle(Theme.mango.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .interpolationMethod(.monotone)
                }
                // 32 °C = start of "extreme caution", 39.4 °C = "danger"
                RuleMark(y: .value("Extreme caution", 32.2))
                    .foregroundStyle(HeatIndex.Level.extremeCaution.color.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                RuleMark(y: .value("Danger", 39.4))
                    .foregroundStyle(HeatIndex.Level.danger.color.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Danger").font(.caption2).foregroundStyle(HeatIndex.Level.danger.color)
                    }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel { if let d = value.as(Date.self) { Text(d.formatted(hourStyle)) } }
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel { if let c = value.as(Double.self) { Text("\(Int(c))°") } }
                }
            }
            .chartYScale(domain: yDomain(hours))
            .frame(height: 180)
            HStack(spacing: 14) {
                Label("Heat index", systemImage: "line.diagonal").foregroundStyle(Theme.coral)
                Label("Temperature", systemImage: "line.diagonal").foregroundStyle(Theme.mango)
            }
            .font(.caption2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(hours) { h in
                        VStack(spacing: 4) {
                            Text(h.date.formatted(hourStyle)).font(.caption2)
                            WeatherSymbol(name: h.symbolName)
                            Text("\(Int(h.temperatureC.rounded()))°").font(.caption.weight(.semibold))
                            Text("\(Int(h.heatIndexC.rounded()))°")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .background(h.heatLevel.color, in: Capsule())
                            Text(h.precipitationChance >= 0.2 ? "\(Int(h.precipitationChance * 100))%" : " ")
                                .font(.caption2).foregroundStyle(.blue)
                        }
                    }
                }
            }
            Text("Colored pill = heat index (feels like).").font(.caption2).foregroundStyle(.secondary)
        }
        .card()
    }

    /// Just the range the lines use, so a 5° swing isn't flattened.
    private func yDomain(_ hours: [WeatherSnapshot.Hour]) -> ClosedRange<Double> {
        let values = hours.flatMap { [$0.temperatureC, $0.heatIndexC] }
        let low = (values.min() ?? 24) - 2
        let high = max((values.max() ?? 36) + 2, 40) // keep the "Danger" line visible
        return low...high
    }

    private func tenDayCard(_ w: WeatherSnapshot) -> some View {
        let lowest = w.days.map(\.lowC).min() ?? 20
        let highest = w.days.map(\.highC).max() ?? 35
        var dayStyle = Date.FormatStyle.dateTime.weekday(.abbreviated)
        dayStyle.timeZone = w.timeZone
        var dateStyle = Date.FormatStyle.dateTime.month(.abbreviated).day()
        dateStyle.timeZone = w.timeZone
        return VStack(alignment: .leading, spacing: 10) {
            Text("\(w.days.count)-day forecast").font(.headline)
            ForEach(Array(w.days.enumerated()), id: \.element.id) { index, day in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(index == 0 ? "Today" : day.date.formatted(dayStyle)).font(.subheadline.weight(.semibold))
                        Text(day.date.formatted(dateStyle)).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(width: 52, alignment: .leading)

                    VStack(spacing: 0) {
                        WeatherSymbol(name: day.symbolName)
                        Text(day.precipitationChance >= 0.2 ? "\(Int((day.precipitationChance * 100).rounded()))%" : " ")
                            .font(.caption2.weight(.semibold)).foregroundStyle(.blue)
                    }
                    .frame(width: 34)

                    Text("\(Int(day.lowC.rounded()))°").font(.subheadline).foregroundStyle(.secondary).frame(width: 30, alignment: .trailing)
                    TempRangeBar(low: day.lowC, high: day.highC, minimum: lowest, maximum: highest)
                    Text("\(Int(day.highC.rounded()))°").font(.subheadline.weight(.semibold)).frame(width: 30, alignment: .leading)

                    Text("\(Int(day.maxHeatIndexC.rounded()))°")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 38)
                        .padding(.vertical, 3)
                        .background(day.heatLevel.color, in: RoundedRectangle(cornerRadius: 6))
                        .accessibilityLabel("Heat index up to \(Int(day.maxHeatIndexC.rounded())) degrees, \(day.heatLevel.title)")
                }
                if index < w.days.count - 1 { Divider() }
            }
            HStack(spacing: 6) {
                Text("Last column: peak heat index.").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("°C").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    @ViewBuilder
    private func attribution(_ w: WeatherSnapshot) -> some View {
        HStack(spacing: 6) {
            switch w.source {
            case .apple:
                AsyncImage(url: colorScheme == .dark ? w.attributionLogoDark : w.attributionLogoLight) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Text(" Weather").font(.caption2.weight(.semibold))
                }
                .frame(height: 12)
                if let link = w.attributionLink { Link("Data sources", destination: link).font(.caption2) }
            case .openMeteo:
                if let link = w.attributionLink { Link("Weather data by Open-Meteo.com", destination: link).font(.caption2) }
            }
        }
        .foregroundStyle(.secondary)
    }
}

/// "Heat index 41°C · 106°F  DANGER"
struct HeatIndexBadge: View {
    let heatIndexC: Double
    var label = "Heat index"

    var body: some View {
        let level = HeatIndex.Level(heatIndexC: heatIndexC)
        HStack(spacing: 8) {
            Image(systemName: level.symbol)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.caption2.weight(.semibold)).opacity(0.85)
                Text(Temperature.both(heatIndexC)).font(.headline)
            }
            Spacer(minLength: 4)
            Text(level.title.uppercased()).font(.caption.weight(.heavy)).multilineTextAlignment(.trailing)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(level.color, in: RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
    }
}

/// Weather icon that stays visible on light cards: full color for sun, rain and storms,
/// tinted gray for plain clouds and fog (multicolor clouds are white).
struct WeatherSymbol: View {
    let name: String

    var body: some View {
        if name.hasPrefix("cloud") {
            // Gray cloud, colored accent (multicolor clouds are white and vanish on light cards).
            Image(systemName: name)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.gray, accent, hasRain ? .blue : accent)
        } else {
            Image(systemName: name).symbolRenderingMode(.multicolor)
        }
    }

    private var hasRain: Bool { ["rain", "drizzle"].contains { name.contains($0) } }

    private var accent: Color {
        if name.contains("bolt") || name.contains("sun") { return .yellow }
        if name.contains("snow") || name.contains("sleet") { return .cyan }
        if name.contains("moon") { return .indigo }
        return .blue
    }
}

/// The low–high bar in the 10-day list, scaled to the whole forecast's range.
private struct TempRangeBar: View {
    let low: Double
    let high: Double
    let minimum: Double
    let maximum: Double

    var body: some View {
        GeometryReader { geo in
            let span = max(1, maximum - minimum)
            let start = (low - minimum) / span * geo.size.width
            let width = max(6, (high - low) / span * geo.size.width)
            Capsule().fill(Theme.insetBackground)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: [Theme.lagoon, Theme.mangoLight, Theme.coral], startPoint: .leading, endPoint: .trailing))
                        .frame(width: width)
                        .offset(x: start)
                }
        }
        .frame(height: 6)
    }
}

/// Short heat-safety guide (offline).
private struct HeatGuideCard: View {
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(HeatIndex.Level.allCases.reversed(), id: \.self) { level in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(level.color).frame(width: 10, height: 10).padding(.top, 4)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(level.title).font(.subheadline.weight(.semibold))
                            Text(level.advice).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Divider()
                Text("Signs of heat exhaustion: heavy sweating, dizziness, nausea, headache, cramps. Get into AC, sip water or an electrolyte drink (7-Eleven sells them), and cool your neck and wrists. Confusion, hot dry skin or fainting can mean heat stroke: call **1669** (ambulance).")
                    .font(.caption)
            }
            .padding(.top, 8)
        } label: {
            Label("Heat safety guide", systemImage: "cross.case").font(.headline)
        }
        .card()
    }
}

/// Wraps WeatherView for presenting as a sheet.
struct WeatherSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WeatherView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
        }
    }
}
