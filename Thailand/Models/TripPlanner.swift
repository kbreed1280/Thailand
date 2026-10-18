import CoreData
import CoreLocation

// Planner overview helpers: custom lists, budget and route optimizing on top of the Core Data model.

extension Trip {
    /// Custom lists in display order ("Restaurants", "Things to do"…); the Wish List isn't included.
    var customListNames: [String] {
        TripLists.names(stored: listNames, itemLists: sortedWishItems.compactMap(\.listName).filter { !$0.isEmpty })
    }

    /// Unscheduled places on a custom list.
    func listItems(_ name: String) -> [Item] {
        sortedWishItems.filter { !$0.isFolderVideo && ($0.listName ?? "") == name }
    }

    var categoryBudgets: [ExpenseCategory: Double] {
        get { BudgetMath.parse(budgetByCategory) }
        set { budgetByCategory = BudgetMath.format(newValue) }
    }

    var budgetSummary: BudgetMath.Summary {
        BudgetMath.summary(
            total: budgetTotal,
            perCategory: categoryBudgets,
            expenses: sortedExpenses.map { (category: $0.category, amount: $0.amountTHB) },
            plannedCosts: allItems.filter { $0.status != .done && $0.costTHB > 0 }.map(\.costTHB)
        )
    }

    var hasBudget: Bool { budgetTotal > 0 || !categoryBudgets.isEmpty }
}

extension ItineraryStore {
    /// Moves an unscheduled item onto a custom list ("" = Wish List), at the end.
    func move(_ item: Item, toList name: String, in trip: Trip) {
        if item.day != nil { move(item, toDay: nil, in: trip, before: nil) }
        item.listName = name
        item.markEdited()
    }

    func addList(_ name: String, to trip: Trip) {
        trip.listNames = TripLists.adding(name, to: trip.listNames)
    }

    func renameList(_ old: String, to new: String, in trip: Trip) {
        let clean = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean != old else { return }
        trip.listNames = TripLists.renaming(old, to: clean, in: trip.listNames)
        for item in trip.listItems(old) {
            item.listName = clean
            item.markEdited()
        }
    }

    /// Deletes the list; its places go back to the Wish List rather than being lost.
    func deleteList(_ name: String, in trip: Trip) {
        trip.listNames = TripLists.removing(name, from: trip.listNames)
        for item in trip.listItems(name) {
            item.listName = ""
            item.markEdited()
        }
    }

    /// Reorders a day's mappable stops for the shortest route between `start` and `end` (e.g. the hotel).
    /// Returns the straight-line meters saved (0 when the day was already in the best order).
    @discardableResult
    func optimizeRoute(for day: Day, start: CLLocationCoordinate2D?, end: CLLocationCoordinate2D?) -> Double {
        let items = day.sortedItems
        let mappable = items.filter(\.hasCoordinate)
        guard mappable.count >= 2 else { return 0 }
        let points = mappable.compactMap(\.coordinate)
        let current = Array(points.indices)
        let best = RouteOptimizer.order(points: points, start: start, end: end)
        let saved = RouteOptimizer.length(current, points: points, start: start, end: end)
            - RouteOptimizer.length(best, points: points, start: start, end: end)
        guard best != current, saved > 1 else { return 0 }
        let reordered = RouteOptimizer.merged(all: items, hasLocation: \.hasCoordinate, optimized: best.map { mappable[$0] })
        for (index, item) in reordered.enumerated() where item.sortIndex != Int64(index) {
            item.sortIndex = Int64(index)
            item.markEdited()
        }
        return saved
    }
}
