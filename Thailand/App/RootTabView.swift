import SwiftUI

struct RootTabView: View {
    /// Reopens on the tab you were last using.
    @AppStorage("selectedTab") private var selectedTab = 0
    #if DEBUG
    /// Debug-only: launch with `-showWeather YES` to open the weather screen directly.
    @State private var showWeather = UserDefaults.standard.bool(forKey: "showWeather")
    /// Debug-only: `-showSevenEleven YES` opens the 7-Eleven map.
    @State private var showSevenEleven = UserDefaults.standard.bool(forKey: "showSevenEleven")
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
        #endif
    }
}

#Preview {
    RootTabView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
