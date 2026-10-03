import SwiftUI

@main
struct ThailandApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let persistence = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(\.managedObjectContext, persistence.viewContext)
                .task { await IdentityService.refreshDisplayName() }
        }
    }
}
