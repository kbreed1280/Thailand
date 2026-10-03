import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            Tab("Trip", systemImage: "suitcase.fill") {
                TripTabView()
            }
            Tab("Nearby", systemImage: "location.circle.fill") {
                NearbyTabView()
            }
            Tab("Explore", systemImage: "fork.knife.circle.fill") {
                ExploreTabView()
            }
            Tab("Convert", systemImage: "bahtsign.circle.fill") {
                ConvertTabView()
            }
            Tab("Translate", systemImage: "character.bubble.fill") {
                TranslateTabView()
            }
        }
    }
}

#Preview {
    RootTabView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
