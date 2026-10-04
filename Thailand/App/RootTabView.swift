import CoreData
import SwiftUI

struct RootTabView: View {
    /// Reopens on the tab you were last using.
    @AppStorage("selectedTab") private var selectedTab = 0
    #if DEBUG
    /// Debug-only: launch with `-showWeather YES` to open the weather screen directly.
    @State private var showWeather = UserDefaults.standard.bool(forKey: "showWeather")
    /// Debug-only: `-showSevenEleven YES` opens the 7-Eleven map.
    @State private var showSevenEleven = UserDefaults.standard.bool(forKey: "showSevenEleven")
    /// Debug-only: `-showRailMap YES` opens the BTS/MRT network map.
    @State private var showRailMap = UserDefaults.standard.bool(forKey: "showRailMap")
    /// Debug-only: `-debugImportURL <link>` imports a link into the first trip and opens Spots.
    @State private var debugSpotsTrip: Trip?
    @Environment(\.managedObjectContext) private var debugContext
    #endif

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Trip", systemImage: "suitcase.fill", value: 0) {
                TripTabView()
            }
            Tab("Nearby", systemImage: "location.circle.fill", value: 1) {
                NearbyTabView()
            }
            Tab("Explore", systemImage: "fork.knife.circle.fill", value: 2) {
                ExploreTabView()
            }
            Tab("Convert", systemImage: "bahtsign.circle.fill", value: 3) {
                ConvertTabView()
            }
            Tab("Translate", systemImage: "character.bubble.fill", value: 4) {
                TranslateTabView()
            }
        }
        #if DEBUG
        .sheet(isPresented: $showWeather) { WeatherSheet() }
        .fullScreenCover(isPresented: $showSevenEleven) { SevenElevenMapView() }
        .fullScreenCover(isPresented: $showRailMap) { RailNetworkMapView() }
        .sheet(item: $debugSpotsTrip) { trip in SpotsView(trip: trip) }
        .task {
            guard let link = UserDefaults.standard.string(forKey: "debugImportURL"), let url = URL(string: link) else { return }
            try? await Task.sleep(for: .seconds(2))
            let trips = (try? debugContext.fetch(NSFetchRequest<Trip>(entityName: "Trip"))) ?? []
            let trip = trips.first ?? ItineraryStore(context: debugContext).createTrip(name: "Debug Trip", start: .now, end: .now.addingTimeInterval(7 * 86_400))
            ImportPipeline.shared.addSource(url: url, text: nil, to: trip, context: debugContext)
            debugSpotsTrip = trip
        }
        #endif
    }
}

#Preview {
    RootTabView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
