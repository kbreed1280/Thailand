import Foundation
import EventKit
import CoreData

/// Shows your calendar next to the itinerary and (optionally) mirrors timed itinerary items into
/// a calendar. The item → event mapping is per device, so each traveler controls their own calendar.
@MainActor
final class CalendarSyncService: ObservableObject {
    static let shared = CalendarSyncService()

    let store = EKEventStore()

    @Published private(set) var changeTick = 0

    private let defaults = UserDefaults.standard
    private var pendingDeletes: [String] = []
    private var observers: [NSObjectProtocol] = []

    // MARK: Settings

    var showEvents: Bool {
        get { defaults.bool(forKey: "calendar.showEvents") }
        set { defaults.set(newValue, forKey: "calendar.showEvents"); bump() }
    }

    var addItemsToCalendar: Bool {
        get { defaults.bool(forKey: "calendar.addItems") }
        set { defaults.set(newValue, forKey: "calendar.addItems"); bump() }
    }

    /// Calendars shown in the itinerary (empty = all).
    var shownCalendarIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: "calendar.shownIDs") ?? []) }
        set { defaults.set(Array(newValue), forKey: "calendar.shownIDs"); bump() }
    }

    var targetCalendarID: String? {
        get { defaults.string(forKey: "calendar.targetID") }
        set { defaults.set(newValue, forKey: "calendar.targetID"); bump() }
    }

    private var eventMap: [String: String] {
        get { defaults.dictionary(forKey: "calendar.eventMap") as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: "calendar.eventMap") }
    }

    // MARK: Access

    var hasAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    var isDenied: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        return status == .denied || status == .restricted
    }

    func requestAccess() async -> Bool {
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        bump()
        return granted
    }

    var calendars: [EKCalendar] { hasAccess ? store.calendars(for: .event) : [] }
    var writableCalendars: [EKCalendar] { calendars.filter(\.allowsContentModifications) }

    private var targetCalendar: EKCalendar? {
        targetCalendarID.flatMap { store.calendar(withIdentifier: $0) } ?? store.defaultCalendarForNewEvents
    }

    // MARK: Reading

    func events(on date: Date) -> [EKEvent] {
        guard showEvents, hasAccess else { return [] }
        let start = Calendar.current.startOfDay(for: date)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return [] }
        let ids = shownCalendarIDs
        let selected = ids.isEmpty ? nil : calendars.filter { ids.contains($0.calendarIdentifier) }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: selected)
        let mine = Set(eventMap.values)
        // Hide events this app created from your own itinerary.
        return store.events(matching: predicate).filter { !mine.contains($0.eventIdentifier ?? "") }
    }

    // MARK: Writing

    /// Mirrors item saves into the calendar when "Add itinerary items to my calendar" is on.
    func startObserving(_ context: NSManagedObjectContext) {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .NSManagedObjectContextWillSave, object: context, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let context = note.object as? NSManagedObjectContext else { return }
                self?.pendingDeletes = context.deletedObjects.compactMap { ($0 as? Item)?.uuid?.uuidString }
            }
        })
        observers.append(center.addObserver(forName: .NSManagedObjectContextDidSave, object: context, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                self?.handleSave(note)
            }
        })
        observers.append(center.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.bump() }
        })
    }

    private func handleSave(_ note: Notification) {
        defer { pendingDeletes = [] }
        guard addItemsToCalendar, hasAccess else { return }
        let inserted = note.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject> ?? []
        let updated = note.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject> ?? []
        for item in inserted.union(updated).compactMap({ $0 as? Item }) {
            sync(item)
        }
        pendingDeletes.forEach(removeEvent(forItemID:))
    }

    func sync(_ item: Item) {
        guard let id = item.uuid?.uuidString else { return }
        guard let start = item.time, item.day != nil else {
            removeEvent(forItemID: id)
            return
        }
        guard let calendar = targetCalendar else { return }
        let event = eventMap[id].flatMap { store.event(withIdentifier: $0) } ?? EKEvent(eventStore: store)
        event.calendar = event.calendar ?? calendar
        event.title = item.displayTitle
        event.startDate = start
        event.endDate = item.endTime ?? start.addingTimeInterval(3_600)
        event.location = item.address
        event.notes = [item.notes ?? "", "From WanderHub"].filter { !$0.isEmpty }.joined(separator: "\n\n")
        event.url = item.linkURL
        do {
            try store.save(event, span: .thisEvent)
            var map = eventMap
            map[id] = event.eventIdentifier
            eventMap = map
        } catch {
            print("Calendar save failed: \(error)")
        }
    }

    func removeEvent(forItemID id: String) {
        var map = eventMap
        if let eventID = map[id], let event = store.event(withIdentifier: eventID) {
            try? store.remove(event, span: .thisEvent)
        }
        map[id] = nil
        eventMap = map
    }

    /// Adds/updates every timed item of a trip (e.g. ones your partner added).
    func syncAll(_ trip: Trip) {
        guard addItemsToCalendar, hasAccess else { return }
        trip.sortedDays.flatMap(\.sortedItems).forEach(sync)
    }

    private func bump() {
        changeTick &+= 1
    }
}
