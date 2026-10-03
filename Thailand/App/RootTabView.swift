import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            Tab("Trip", systemImage: "suitcase.fill") {
                TripTabView()
            }
            Tab("Nearby", systemImage: "location.circle.fill") {
                ComingSoonView(
                    title: "Nearby",
                    systemImage: "location.circle.fill",
                    message: "Where you are, photos of nearby sights, walking directions and the weather. Coming in step 5."
                )
            }
            Tab("Explore", systemImage: "fork.knife.circle.fill") {
                ComingSoonView(
                    title: "Explore",
                    systemImage: "fork.knife.circle.fill",
                    message: "Places to eat, stay and see, plus the Thai food guide. Coming in step 4."
                )
            }
            Tab("Convert", systemImage: "bahtsign.circle.fill") {
                ComingSoonView(
                    title: "Convert",
                    systemImage: "bahtsign.circle.fill",
                    message: "Baht ⇄ dollar converter and shared expenses. Coming in step 2."
                )
            }
            Tab("Translate", systemImage: "character.bubble.fill") {
                ComingSoonView(
                    title: "Translate",
                    systemImage: "character.bubble.fill",
                    message: "English ⇄ Thai translator, voice mode and phrasebook. Coming in step 3."
                )
            }
        }
    }
}

#Preview {
    RootTabView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
