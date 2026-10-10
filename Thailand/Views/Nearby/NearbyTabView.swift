import SwiftUI
import MapKit
import CoreData

/// "Where am I": your neighborhood, a photo carousel of the area and nearby landmarks,
/// today's walking plan, steps, weather and the trip journal.
struct NearbyTabView: View {
    @Environment(\.managedObjectContext) private var context
    @ObservedObject private var location = LocationService.shared
    @ObservedObject private var network = NetworkMonitor.shared
    @ObservedObject private var pedometer = PedometerService.shared
    @AppStorage("autoLogVisits") private var autoLog = false

    @State private var areaName = ""
    @State private var cityName = ""
    @State private var landmarks: [Landmark] = WikipediaService.cachedLandmarks()
    @State private var lookAroundScene: MKLookAroundScene?
    @State private var weather: WeatherSnapshot?
    @State private var weatherFailed = false
    @State private var isLoading = false
    @State private var lastLoadedAt: CLLocation?
    @State private var selectedLandmark: Landmark?
    @State private var walkTarget: WalkTarget?
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var savedMessage: String?
    @State private var showingEmergency = false
    @State private var showingSevenEleven = false
    @State private var essential: Essential?

    /// Apple Weather, falling back to Open-Meteo if WeatherKit isn't available.
    private let weatherProvider: WeatherProvider = AutomaticWeatherProvider()

    var body: some View {
        NavigationStack {
            Group {
                if location.isDenied {
                    PermissionDeniedView(kind: .location)
                } else {
                    content
                }
            }
            .background(Theme.background)
            .navigationTitle("Nearby")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingEmergency = true
                    } label: {
                        Label("Emergency", systemImage: "sos.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    CurrentTripReader { trip in
                        NavigationLink {
                            BangkokTransitView(trip: trip)
                        } label: {
                            Label("BTS & MRT", systemImage: "tram.fill")
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    CurrentTripReader { trip in
                        if let trip {
                            NavigationLink {
                                JournalView(trip: trip)
                            } label: {
                                Label("Journal", systemImage: "book.closed.fill")
                            }
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showingSevenEleven) { SevenElevenMapView() }
            .sheet(item: $selectedLandmark) { landmark in
                LandmarkDetailSheet(landmark: landmark, userLocation: location.lastLocation) { target in
                    selectedLandmark = nil
                    walkTarget = target
                }
            }
            .fullScreenCover(item: $walkTarget) { target in
                WalkingRouteView(destinationName: target.name, coordinate: target.coordinate)
            }
            .sheet(isPresented: $showingEmergency) {
                CurrentTripReader { trip in
                    EmergencyView(trip: trip)
                }
            }
            .onAppear {
                location.startUpdating()
                pedometer.startToday()
            }
            .onDisappear {
                location.stopUpdating()
                pedometer.stopToday()
            }
            .onChange(of: location.lastLocation) { _, newLocation in
                guard let newLocation else { return }
                // Reload when we've moved ~300 m since the last load.
                if lastLoadedAt.map({ $0.distance(from: newLocation) > 300 }) ?? true {
                    Task { await load(at: newLocation) }
                }
            }
            .refreshable {
                if let current = await location.currentLocation() { await load(at: current, force: true) }
            }
            .savedToast($savedMessage)
        }
    }

    // MARK: Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hereCard

                if let here = lastLoadedAt {
                    EssentialsRow { picked in
                        if picked == .sevenEleven { showingSevenEleven = true } else { essential = picked }
                    }
                    .sheet(item: $essential) { e in
                        EssentialsSheet(essential: e, here: here) { walkTarget = $0 }
                    }
                }


                if let weather {
                    NavigationLink { WeatherView() } label: { WeatherCard(weather: weather) }
                        .buttonStyle(.plain)
                } else if weatherFailed {
                    NavigationLink { WeatherView() } label: {
                        Label("Weather unavailable here. Tap for city forecasts.", systemImage: "cloud.sun")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card()
                    }
                    .buttonStyle(.plain)
                }

                CurrentTripReader { trip in
                    if let trip, let today = trip.today {
                        TodayWalkCard(day: today) { walkTarget = $0 }
                    }
                }

                carousel

                Map(position: $position) {
                    UserAnnotation()
                    ForEach(landmarks.prefix(15)) { landmark in
                        Marker(landmark.title, systemImage: "building.columns.fill", coordinate: landmark.coordinate)
                            .tint(Theme.mango)
                    }
                }
                .mapControls { MapUserLocationButton() }
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))



                Toggle(isOn: $autoLog) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-log places we visit").font(.subheadline.weight(.semibold))
                        Text("Adds stops to the trip journal while this tab is open. No background tracking.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(Theme.lagoon)
                .card()
            }
            .padding()
        }
    }

    private var hereCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("YOU'RE IN")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                if !network.isOnline { OfflineBadge() }
                if let weather {
                    HStack(spacing: 5) {
                        WeatherSymbol(name: weather.symbolName)
                        Text("\(Temperature.deg(weather.temperatureC))").font(.headline)
                        Text("feels \(Temperature.deg(weather.feelsLikeC))").font(.caption.weight(.semibold)).opacity(0.85)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.white.opacity(0.18), in: Capsule())
                }
            }
            Text(areaName.isEmpty ? (location.lastLocation == nil ? "Finding you…" : "Somewhere nice") : areaName)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            if !cityName.isEmpty {
                Text(cityName).font(.headline).foregroundStyle(.white.opacity(0.9))
            }
            if PedometerService.isAvailable {
                HStack(spacing: 8) {
                    Label("\(pedometer.today.steps.formatted()) steps", systemImage: "shoeprints.fill")
                    Label(pedometer.today.kilometersText, systemImage: "figure.walk")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                if pedometer.isDenied {
                    Button("Turn on Motion & Fitness to count steps") { PermissionCenter.openSettings() }
                        .font(.caption)
                        .foregroundStyle(.white)
                        .underline()
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            Theme.sunsetGradient
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(RadialGradient(colors: [Theme.mangoLight.opacity(0.5), .clear], center: .center, startRadius: 0, endRadius: 120))
                        .frame(width: 240, height: 240)
                        .offset(x: 80, y: -110)
                }
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .shadow(color: Theme.inkDeep.opacity(0.22), radius: 14, y: 6)
        .accessibilityElement(children: .combine)
    }

    private var carousel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Sights near you").font(.title3.bold())
                Spacer()
                if isLoading { ProgressView() }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    if let lookAroundScene {
                        VStack(alignment: .leading, spacing: 6) {
                            LookAroundPreview(initialScene: lookAroundScene)
                                .frame(width: 280, height: 190)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                            Text("Look Around here").font(.subheadline.weight(.semibold))
                        }
                    }
                    ForEach(landmarks) { landmark in
                        LandmarkCard(landmark: landmark, distance: location.lastLocation.map(landmark.distance(from:)))
                            .onTapGesture { selectedLandmark = landmark }
                    }
                }
            }
            if landmarks.isEmpty && !isLoading {
                Text(network.isOnline ? "No landmarks found within 5 km." : "Connect to the internet to load nearby sights.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Loading

    private func load(at here: CLLocation, force: Bool = false) async {
        guard force || !isLoading else { return }
        isLoading = true
        lastLoadedAt = here
        defer { isLoading = false }

        if let names = await location.placeName(for: here) {
            areaName = names.area
            cityName = names.city
        }
        if network.isOnline {
            if let found = try? await WikipediaService.landmarks(near: here.coordinate) {
                landmarks = found
            }
            lookAroundScene = await PlaceImageLoader.lookAroundScene(at: here.coordinate)
            do {
                weather = try await weatherProvider.snapshot(for: here)
                weatherFailed = false
            } catch {
                weatherFailed = weather == nil
            }
        }
        if autoLog { logVisit(at: here) }
    }

    /// Records a journal stop unless we already logged one within 250 m in the last 3 hours.
    private func logVisit(at here: CLLocation) {
        let request = NSFetchRequest<Trip>(entityName: "Trip")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        let selectedID = UserDefaults.standard.string(forKey: AppSettings.selectedTripKey)
        guard let trips = try? context.fetch(request),
              let trip = trips.first(where: { $0.uuid?.uuidString == selectedID }) ?? trips.first else { return }

        let recent = trip.sortedVisits.prefix(10).contains { visit in
            guard let date = visit.date, Date().timeIntervalSince(date) < 3 * 3600 else { return false }
            return CLLocation(latitude: visit.latitude, longitude: visit.longitude).distance(from: here) < 250
        }
        guard !recent else { return }

        let nearbyLandmark = landmarks.first { $0.distance(from: here) < 150 }
        let visit = VisitLog(context: context)
        visit.placeInSameStore(as: trip)
        visit.uuid = UUID()
        visit.date = .now
        visit.placeName = nearbyLandmark?.title ?? [areaName, cityName].filter { !$0.isEmpty }.joined(separator: ", ")
        visit.latitude = here.coordinate.latitude
        visit.longitude = here.coordinate.longitude
        visit.trip = trip
        ItineraryStore(context: context).save()
    }
}

// MARK: - Cards

private struct LandmarkCard: View {
    let landmark: Landmark
    let distance: CLLocationDistance?

    var body: some View {
        PhotoPlaceCard(title: landmark.title,
                       subtitle: distance.map { "\(DistanceText.distance($0)) · \(DistanceText.walkingTime($0))" } ?? landmark.shortDescription,
                       width: 240, height: 230) {
            AsyncImage(url: landmark.imageURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else if phase.error != nil || landmark.imageURL == nil {
                    PlaceImage(coordinate: landmark.coordinate)
                } else {
                    Color(.tertiarySystemFill).overlay(ProgressView())
                }
            }
        } trailing: {
            SaveToSpotsButton(name: landmark.title, coordinate: landmark.coordinate, address: landmark.shortDescription ?? "",
                              category: .explore, onDark: true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
    }
}

/// Today's itinerary stops with "walk there" and "walk the whole day in Google Maps".
struct TodayWalkCard: View {
    @ObservedObject var day: Day
    let onWalk: (WalkTarget) -> Void

    private var stops: [Item] {
        day.sortedItems.filter { $0.hasCoordinate && $0.status != .done }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Today's Plan", systemImage: "figure.walk.motion")
                    .font(.headline)
                Spacer()
                Text("Day \(day.number)").font(.subheadline).foregroundStyle(.secondary)
            }
            if stops.isEmpty {
                Text("Nothing left with a location today. Enjoy wandering!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(stops.prefix(4).enumerated()), id: \.element.objectID) { index, item in
                    HStack(spacing: 10) {
                        NumberedPin(number: index + 1, colorHex: item.category.colorHex, isSelected: false, compact: true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
                            if let time = item.time {
                                Text(time.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let coordinate = item.coordinate {
                            Button {
                                onWalk(WalkTarget(name: item.displayTitle, coordinate: coordinate))
                            } label: {
                                Image(systemName: "figure.walk.circle.fill")
                                    .font(.title)
                                    .foregroundStyle(Theme.lagoon)
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .accessibilityLabel("Walk to \(item.displayTitle)")
                        }
                    }
                }
                Button {
                    ExternalApps.openGoogleMaps(stops: stops.compactMap(\.coordinate))
                } label: {
                    Label("Walk Today's Plan in Google Maps", systemImage: "map.fill")
                }
                .buttonStyle(.primary)
            }
        }
        .card()
    }
}

/// Text then icon ("10-day forecast ›").
struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) { configuration.title; configuration.icon }
    }
}

struct WeatherCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let weather: WeatherSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                WeatherSymbol(name: weather.symbolName)
                    .font(.system(size: 40))
                VStack(alignment: .leading, spacing: 2) {
                    Text(Temperature.both(weather.temperatureC)).font(.title3.bold())
                    Text("\(weather.conditionText) · feels like \(Temperature.both(weather.feelsLikeC))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("H \(Temperature.deg(weather.highC)) L \(Temperature.deg(weather.lowC))").font(.caption.weight(.semibold))
                    Text("UV \(weather.uvIndex)").font(.caption).foregroundStyle(weather.uvIndex >= 8 ? Theme.coral : .secondary)
                }
            }

            HeatIndexBadge(heatIndexC: weather.heatIndexC)
            if let best = weather.bestWalkingWindows.first {
                Label("Best walking: \(WindowText.format(Array(weather.bestWalkingWindows.prefix(2)), timeZone: weather.timeZone))",
                      systemImage: "figure.walk")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.lagoon)
                    .accessibilityHint("Starts \(best.start.formatted(date: .omitted, time: .shortened))")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(weather.hours.prefix(12)) { hour in
                        VStack(spacing: 4) {
                            Text(hour.date.formatted(.dateTime.hour())).font(.caption2)
                            WeatherSymbol(name: hour.symbolName)
                            Text("\(Temperature.deg(hour.temperatureC))").font(.caption.weight(.semibold))
                            Circle().fill(hour.heatLevel.color).frame(width: 6, height: 6)
                            if hour.precipitationChance >= 0.3 {
                                Text("\(Int(hour.precipitationChance * 100))%").font(.caption2).foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }

            ForEach(weather.alerts, id: \.self) { alert in
                Label(alert, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.coral)
            }

            HStack(spacing: 6) {
                // Apple Weather attribution (required by WeatherKit).
                if weather.source == .apple {
                    AsyncImage(url: colorScheme == .dark ? weather.attributionLogoDark : weather.attributionLogoLight) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Text(" Weather").font(.caption2.weight(.semibold))
                    }
                    .frame(height: 12)
                } else {
                    Text("Open-Meteo.com").font(.caption2)
                }
                Spacer()
                Label("10-day forecast", systemImage: "chevron.right")
                    .labelStyle(TrailingIconLabelStyle())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.mango)
            }
            .foregroundStyle(.secondary)
        }
        .card()
    }
}

#Preview {
    NearbyTabView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
