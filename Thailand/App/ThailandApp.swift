import SwiftUI

@main
struct ThailandApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    private let persistence = PersistenceController.shared

    init() {
        // Bold, rounded screen titles to match the app's look.
        func rounded(_ style: UIFont.TextStyle, _ weight: UIFont.Weight) -> UIFont {
            let base = UIFont.preferredFont(forTextStyle: style)
            let font = UIFont.systemFont(ofSize: base.pointSize, weight: weight)
            return UIFont(descriptor: font.fontDescriptor.withDesign(.rounded) ?? font.fontDescriptor, size: base.pointSize)
        }
        let nav = UINavigationBar.appearance()
        nav.largeTitleTextAttributes = [.font: rounded(.largeTitle, .heavy)]
        nav.titleTextAttributes = [.font: rounded(.headline, .bold)]
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(\.managedObjectContext, persistence.viewContext)
                .task {
                    if let trip = SpotSaver.currentTrip(in: persistence.viewContext) { ExchangeRateStore.shared.useTrip(trip) }
                    CalendarSyncService.shared.startObserving(persistence.viewContext)
                    CommunityService.shared.startObserving(persistence.viewContext)
                    #if DEBUG
                    if persistence.isCloudEnabled, UserDefaults.standard.bool(forKey: "initCloudKitSchema") {
                        Task { await CommunityService.shared.seedSchema() }
                    }
                    #endif
                    await Subscription.shared.start()
                    await IdentityService.refreshDisplayName()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await FlightStore.shared.refreshAllIfNeeded() }
                        DayPlanActivityController.shared.refresh(trip: SpotSaver.currentTrip(in: persistence.viewContext))
                    }
                }
        }
    }
}
