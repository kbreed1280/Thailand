import CoreData
import CoreLocation

/// All itinerary mutations go through here so ordering, "added by" and saving stay consistent.
struct ItineraryStore {
    let context: NSManagedObjectContext

    // MARK: Trips

    @discardableResult
    func createTrip(name: String, start: Date, end: Date, notes: String = "") -> Trip {
        let trip = Trip(context: context)
        trip.uuid = UUID()
        trip.name = name
        trip.notes = notes
        trip.createdAt = .now
        setDates(of: trip, start: start, end: end)
        return trip
    }

    /// Adds days for new dates and removes days outside the range.
    /// Items on a removed day go back to the wish list so nothing is lost.
    func setDates(of trip: Trip, start: Date, end: Date) {
        let dates = ItineraryOrdering.dayDates(from: start, to: end)
        trip.startDate = dates.first
        trip.endDate = dates.last

        let calendar = Calendar.current
        var existing: [Date: Day] = [:]
        for day in trip.sortedDays {
            guard let date = day.date else { continue }
            let key = calendar.startOfDay(for: date)
            if dates.contains(key), existing[key] == nil {
                existing[key] = day
            } else {
                for item in day.sortedItems {
                    move(item, toDay: nil, in: trip, before: nil)
                }
                day.trip = nil
                context.delete(day)
            }
        }

        for (index, date) in dates.enumerated() {
            let day = existing[date] ?? {
                let day = Day(context: context)
                day.placeInSameStore(as: trip)
                day.uuid = UUID()
                day.date = date
                day.trip = trip
                return day
            }()
            day.sortIndex = Int64(index)
        }
    }

    func delete(_ trip: Trip) {
        context.delete(trip)
    }

    // MARK: Items

    @discardableResult
    func addItem(
        title: String,
        category: ItemCategory,
        to day: Day?,
        in trip: Trip,
        address: String = "",
        coordinate: CLLocationCoordinate2D? = nil,
        notes: String = ""
    ) -> Item {
        let item = Item(context: context)
        item.placeInSameStore(as: trip)
        item.uuid = UUID()
        item.title = title
        item.category = category
        item.address = address
        item.coordinate = coordinate
        item.notes = notes
        item.status = .wantToGo
        item.createdAt = .now
        item.addedBy = AppSettings.displayName
        item.markEdited()
        attach(item, to: day, in: trip)
        let siblings = day?.sortedItems ?? trip.sortedWishItems
        item.sortIndex = (siblings.filter { $0 != item }.map(\.sortIndex).max() ?? -1) + 1
        return item
    }

    /// Moves an item onto a day (or the wish list when `day` is nil), placing it before `target`
    /// or at the end. Both the old and new lists are renumbered.
    func move(_ item: Item, toDay day: Day?, in trip: Trip, before target: Item?) {
        let oldDay = item.day
        let wasOnWishList = item.isOnWishList

        attach(item, to: day, in: trip)

        let siblings = day?.sortedItems ?? trip.sortedWishItems
        let order = ItineraryOrdering.inserting(item.objectID, before: target?.objectID, in: siblings.map(\.objectID))
        renumber(order, among: siblings)

        if let oldDay, oldDay != day {
            renumber(oldDay.sortedItems.map(\.objectID), among: oldDay.sortedItems)
        } else if wasOnWishList, day != nil {
            renumber(trip.sortedWishItems.map(\.objectID), among: trip.sortedWishItems)
        }
        item.markEdited()
    }

    /// Reorders within one list (used by List's `onMove`).
    func reorder(_ items: [Item], fromOffsets source: IndexSet, toOffset destination: Int) {
        let reordered = ItineraryOrdering.moving(items, fromOffsets: source, toOffset: destination)
        for (index, item) in reordered.enumerated() {
            item.sortIndex = Int64(index)
        }
    }

    func setStatus(_ status: ItemStatus, for item: Item) {
        item.status = status
        item.markEdited()
    }

    func delete(_ item: Item) {
        let day = item.day
        let trip = item.wishTrip
        // Detach first: a deleted object stays in relationships until pending changes are processed.
        item.day = nil
        item.wishTrip = nil
        context.delete(item)
        if let day {
            renumber(day.sortedItems.map(\.objectID), among: day.sortedItems)
        } else if let trip {
            renumber(trip.sortedWishItems.map(\.objectID), among: trip.sortedWishItems)
        }
    }

    func save() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            context.rollback()
            print("Save failed: \(error)")
        }
    }

    // MARK: Helpers

    private func attach(_ item: Item, to day: Day?, in trip: Trip) {
        if let day {
            item.wishTrip = nil
            item.day = day
        } else {
            item.day = nil
            item.wishTrip = trip
        }
    }

    private func renumber(_ order: [NSManagedObjectID], among items: [Item]) {
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.objectID, $0) })
        for (index, id) in order.enumerated() {
            byID[id]?.sortIndex = Int64(index)
        }
    }
}
