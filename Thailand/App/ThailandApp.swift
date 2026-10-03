import SwiftUI

@main
struct ThailandApp: App {
    private let persistence = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(\.managedObjectContext, persistence.viewContext)
        }
    }
}
