import CoreData
import SwiftUI

struct RootTabView: View {
    /// Reopens on the tab you were last using.
    @AppStorage("selectedTab") private var selectedTab = 0
    /// A shared list (.wanderhub file) opened from Messages, Mail, AirDrop or Files.
    @State private var incoming: IncomingCollection?
    @State private var badFile = false
    #if DEBUG
    /// Debug-only: launch with `-showWeather YES` to open the weather screen directly.
    @State private var showWeather = UserDefaults.standard.bool(forKey: "showWeather")
    /// Debug-only: `-showSevenEleven YES` opens the 7-Eleven map.
    @State private var showSevenEleven = UserDefaults.standard.bool(forKey: "showSevenEleven")
    /// Debug-only: `-showRailMap YES` opens the BTS/MRT network map.
    @State private var showRailMap = UserDefaults.standard.bool(forKey: "showRailMap")
    /// Debug-only: `-debugImportURL <link>` imports a link into the first trip and opens Spots.
    @State private var debugSpotsTrip: Trip?
    /// Debug-only: `-showAutoPlan YES` (with `-debugImportURL`) opens Auto-plan after importing.
    @State private var debugPlanTrip: Trip?
    @Environment(\.managedObjectContext) private var debugContext
    #endif

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Trip", systemImage: "suitcase.fill", value: 0) {
                TripTabView()
            }
            Tab("Spots", systemImage: "map.fill", value: 5) {
                SpotsTabView()
            }
            Tab("Nearby", systemImage: "location.circle.fill", value: 1) {
                NearbyTabView()
            }
            Tab("Explore", systemImage: "fork.knife.circle.fill", value: 2) {
                ExploreTabView()
            }
            Tab("Translate", systemImage: "character.bubble.fill", value: 4) {
                TranslateTabView()
            }
        }
        .tint(Theme.ink)
        .fontDesign(.rounded)
        .onAppear { if selectedTab == 3 { selectedTab = 0 } } // Convert moved to the Trip screen
        .onOpenURL { url in
            guard url.isFileURL else { return }
            if let file = IncomingCollection.load(from: url) { incoming = file } else { badFile = true }
        }
        .sheet(item: $incoming) { SharedCollectionImportView(shared: $0.collection) }
        .alert("Couldn't open that file", isPresented: $badFile) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("It isn't a WanderHub list, or it was made by a newer version of the app.")
        }
        #if DEBUG
        .sheet(isPresented: $showWeather) { WeatherSheet() }
        .fullScreenCover(isPresented: $showSevenEleven) { SevenElevenMapView() }
        .fullScreenCover(isPresented: $showRailMap) { RailNetworkMapView() }
        .sheet(item: $debugSpotsTrip) { trip in
            // Debug-only: `-showSpotPicker YES` opens "Add to Day 1" from saved spots.
            if UserDefaults.standard.bool(forKey: "showSpotPicker"), let day = trip.sortedDays.first {
                SpotPickerSheet(trip: trip, day: day)
            } else {
                SpotsView(trip: trip)
            }
        }
        .sheet(item: $debugPlanTrip) { trip in
            if UserDefaults.standard.bool(forKey: "showSidequest") { SidequestView(trip: trip) } else { AutoPlanView(trip: trip) }
        }
        .task {
            guard let link = UserDefaults.standard.string(forKey: "debugImportURL"), let url = URL(string: link) else { return }
            try? await Task.sleep(for: .seconds(2))
            let trips = (try? debugContext.fetch(NSFetchRequest<Trip>(entityName: "Trip"))) ?? []
            let trip = trips.first ?? ItineraryStore(context: debugContext).createTrip(name: "Debug Trip", start: .now, end: .now.addingTimeInterval(7 * 86_400))
            let debugSource = ImportPipeline.shared.addSource(url: url, text: nil, to: trip, context: debugContext)
            if UserDefaults.standard.bool(forKey: "debugResearch") {
                // Debug-only: `-debugResearch YES` imports, then runs Research on the post.
                await ImportPipeline.shared.importPending(in: trip, context: debugContext)
                if let debugSource { await ImportPipeline.shared.research(debugSource, context: debugContext) }
            }
            if UserDefaults.standard.bool(forKey: "debugConfirmAll") {
                // Debug-only: `-debugConfirmAll YES` imports, confirms every pinned draft, then opens Spots (Map).
                await ImportPipeline.shared.importPending(in: trip, context: debugContext)
                trip.draftSpots.filter { !$0.isUnplotted }.forEach { $0.status = .confirmed }
                trip.draftSpots.forEach(debugContext.delete)
                try? debugContext.save()
            }
            if UserDefaults.standard.bool(forKey: "showAutoPlan") || UserDefaults.standard.bool(forKey: "showSidequest") { debugPlanTrip = trip } else { debugSpotsTrip = trip }
        }
        #endif
    }
}

#Preview {
    RootTabView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
