import AppIntents
import CoreData
import Foundation

// Siri & Shortcuts. Intents run in the app's process and use the same Core Data stack
// (`PersistenceController.shared`), so changes sync to your travel partner like any other edit.

/// Finds trips for intents.
@MainActor
enum TripLookup {
    static var context: NSManagedObjectContext { PersistenceController.shared.viewContext }

    static func allTrips() -> [Trip] {
        let request = NSFetchRequest<Trip>(entityName: "Trip")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        return (try? context.fetch(request)) ?? []
    }

    /// The trip selected on the Trip tab (or the newest).
    static func currentTrip() -> Trip? {
        let trips = allTrips()
        let selected = UserDefaults.standard.string(forKey: AppSettings.selectedTripKey)
        return trips.first { $0.uuid?.uuidString == selected } ?? trips.first
    }

    static func trip(for entity: TripEntity?) -> Trip? {
        guard let entity else { return currentTrip() }
        return allTrips().first { $0.uuid == entity.id } ?? currentTrip()
    }
}

struct TripEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Trip"
    static let defaultQuery = TripQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }

    @MainActor
    init?(_ trip: Trip) {
        guard let id = trip.uuid else { return nil }
        self.init(id: id, name: trip.displayName)
    }
}

struct TripQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [TripEntity] {
        TripLookup.allTrips().filter { identifiers.contains($0.uuid ?? UUID()) }.compactMap(TripEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [TripEntity] {
        TripLookup.allTrips().filter { $0.displayName.localizedCaseInsensitiveContains(string) }.compactMap(TripEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [TripEntity] {
        TripLookup.allTrips().compactMap(TripEntity.init)
    }
}

// MARK: - Intents

struct AddToWishListIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to Wish List"
    static let description = IntentDescription("Adds a place to your Thailand trip's wish list.")

    @Parameter(title: "Place", requestValueDialog: "What place should I add?")
    var place: String

    @Parameter(title: "Trip")
    var trip: TripEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let target = TripLookup.trip(for: trip) else {
            return .result(dialog: "You don't have a trip yet. Open WanderHub to create one.")
        }
        let store = ItineraryStore(context: TripLookup.context)
        store.addItem(title: place, category: .place, to: nil, in: target)
        store.save()
        return .result(dialog: "Added \(place) to the \(target.displayName) wish list.")
    }
}

struct TodaysPlanIntent: AppIntent {
    static let title: LocalizedStringResource = "Today's Plan"
    static let description = IntentDescription("Reads today's itinerary.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let trip = TripLookup.currentTrip() else {
            return .result(dialog: "You don't have a trip yet.")
        }
        guard let today = trip.today else {
            if let start = trip.startDate, start > .now {
                let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: start).day ?? 0
                return .result(dialog: "\(trip.displayName) starts in \(days) days.")
            }
            return .result(dialog: "Today isn't one of the trip days.")
        }
        let stops = today.sortedItems.filter { $0.status != .done }
        guard !stops.isEmpty else {
            return .result(dialog: "Nothing left on the plan for day \(today.number). Enjoy!")
        }
        let list = stops.prefix(6).map { item in
            if let time = item.time {
                return "\(time.formatted(date: .omitted, time: .shortened)) \(item.displayTitle)"
            }
            return item.displayTitle
        }
        return .result(dialog: "Day \(today.number): \(ListFormatter.localizedString(byJoining: list)).")
    }
}

struct ConvertBahtIntent: AppIntent {
    static let title: LocalizedStringResource = "Convert Baht to Dollars"
    static let description = IntentDescription("Converts Thai baht to US dollars with the last saved rate.")

    @Parameter(title: "Baht", requestValueDialog: "How many baht?")
    var amount: Double

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let rates = ExchangeRateStore.shared
        await rates.refreshIfNeeded()
        let dollars = CurrencyMath.convert(amount, from: .thb, thbPerUSD: rates.thbPerUSD)
        return .result(dialog: "\(CurrencyMath.format(amount, .thb)) is about \(CurrencyMath.format(dollars, .usd)).")
    }
}

struct StartWalkingRouteIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Today's Walk"
    static let description = IntentDescription("Opens today's stops as a walking route in Google Maps.")

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        guard let today = TripLookup.currentTrip()?.today else {
            throw TripIntentError("There's no plan for today.")
        }
        let stops = today.sortedItems.filter { $0.status != .done }.compactMap(\.coordinate)
        guard let url = ExternalApps.googleMapsWebURL(stops: stops, travelMode: "walking") else {
            throw TripIntentError("None of today's plans have a location yet.")
        }
        return .result(opensIntent: OpenURLIntent(url))
    }
}

/// A friendly message Siri reads when an intent can't run.
struct TripIntentError: Error, CustomLocalizedStringResourceConvertible {
    let localizedStringResource: LocalizedStringResource

    init(_ message: LocalizedStringResource) {
        localizedStringResource = message
    }
}

struct ThailandShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TodaysPlanIntent(),
            phrases: [
                "What's my plan today in \(.applicationName)",
                "Today's plan in \(.applicationName)"
            ],
            shortTitle: "Today's Plan",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: AddToWishListIntent(),
            phrases: [
                "Add a place in \(.applicationName)",
                "Add to my wish list in \(.applicationName)"
            ],
            shortTitle: "Add to Wish List",
            systemImageName: "star.fill"
        )
        AppShortcut(
            intent: ConvertBahtIntent(),
            phrases: [
                "Convert baht in \(.applicationName)",
                "How much is it in dollars in \(.applicationName)"
            ],
            shortTitle: "Convert Baht",
            systemImageName: "bahtsign.circle"
        )
        AppShortcut(
            intent: StartWalkingRouteIntent(),
            phrases: [
                "Start today's walk in \(.applicationName)",
                "Walk today's plan in \(.applicationName)"
            ],
            shortTitle: "Start Today's Walk",
            systemImageName: "figure.walk"
        )
    }
}
