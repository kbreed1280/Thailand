import SwiftUI

@main
struct ThailandApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    private let persistence = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(\.managedObjectContext, persistence.viewContext)
                .task {
                    CalendarSyncService.shared.startObserving(persistence.viewContext)
                    await IdentityService.refreshDisplayName()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await FlightStore.shared.refreshAllIfNeeded() }
                    }
                }
        }
    }
}
