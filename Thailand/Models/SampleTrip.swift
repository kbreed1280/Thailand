import CoreData
import CoreLocation

/// Demo content: used by SwiftUI previews and the "Load Demo Trip" button.
enum SampleTrip {
    @discardableResult
    static func create(in context: NSManagedObjectContext, startingIn days: Int = 30) -> Trip {
        let store = ItineraryStore(context: context)
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: .now)) ?? .now
        let end = calendar.date(byAdding: .day, value: 5, to: start) ?? start

        let trip = store.createTrip(
            name: "Demo: Bangkok & Chiang Mai",
            start: start,
            end: end,
            notes: "A sample trip to try the app. Delete it any time."
        )
        let tripDays = trip.sortedDays

        func add(_ ideaTitle: String, day index: Int?, time: (Int, Int)? = nil, status: ItemStatus = .wantToGo, cost: Double = 0) {
            guard let idea = StarterIdeas.all.first(where: { $0.title == ideaTitle }) else { return }
            let day = index.flatMap { tripDays.indices.contains($0) ? tripDays[$0] : nil }
            let item = store.addItem(
                title: idea.title,
                category: idea.category,
                to: day,
                in: trip,
                address: idea.address,
                coordinate: idea.coordinate,
                notes: idea.blurb
            )
            item.status = status
            item.costTHB = cost
            item.addedBy = "Demo"
            item.lastEditedBy = "Demo"
            if let time, let date = day?.date {
                item.time = calendar.date(bySettingHour: time.0, minute: time.1, second: 0, of: date)
            }
        }

        // Day 1–3 Bangkok
        let hotel = store.addItem(title: "Check in: riverside hotel", category: .hotel, to: tripDays.first, in: trip,
                                  address: "Charoen Krung Rd, Bang Rak, Bangkok",
                                  coordinate: CLLocationCoordinate2D(latitude: 13.7236, longitude: 100.5146))
        hotel.status = .booked
        hotel.costTHB = 3_200
        hotel.addedBy = "Demo"
        add("Chao Phraya Express Boat", day: 0, time: (16, 0), cost: 32)
        add("Yaowarat (Chinatown) street food", day: 0, time: (19, 0), cost: 400)
        add("Grand Palace & Wat Phra Kaew", day: 1, time: (8, 30), status: .booked, cost: 1_000)
        add("Wat Pho (Reclining Buddha)", day: 1, time: (11, 0), cost: 600)
        add("Wat Arun at sunset", day: 1, time: (17, 0), cost: 200)
        add("Chatuchak Weekend Market", day: 2, time: (9, 0))
        add("Lumphini Park", day: 2, time: (16, 30))

        // Day 4–6 Chiang Mai
        add("Old City temples walk", day: 3, time: (9, 0))
        add("Khao soi lunch", day: 3, time: (12, 30), cost: 120)
        add("Sunday Walking Street", day: 3, time: (18, 0))
        add("Wat Phra That Doi Suthep", day: 4, time: (8, 0), cost: 60)
        add("Nimmanhaemin cafés", day: 4, time: (14, 0))
        add("Warorot Market", day: 5, time: (10, 0))

        // Wish list
        add("Jim Thompson House", day: nil)
        add("Ethical elephant sanctuary", day: nil)

        // Packing
        let packing: [(String, PackingCategory, Bool)] = [
            ("Passports (6+ months valid)", .documents, true),
            ("Travel insurance details", .documents, false),
            ("Universal plug adapter", .tech, false),
            ("Sunscreen & mosquito repellent", .health, false),
            ("Light clothes that cover shoulders & knees (temples)", .clothing, false),
            ("Install an eSIM / buy a local SIM", .todo, false)
        ]
        for (index, entry) in packing.enumerated() {
            let item = PackingItem(context: context)
            item.uuid = UUID()
            item.title = entry.0
            item.category = entry.1
            item.isDone = entry.2
            item.sortIndex = Int64(index)
            item.addedBy = "Demo"
            item.trip = trip
        }

        // Expenses
        let expenses: [(String, Double, String, ExpenseCategory)] = [
            ("Street food dinner", 420, "Me", .food),
            ("Grand Palace tickets", 1_000, "Partner", .activities),
            ("Taxi to hotel", 350, "Me", .transport)
        ]
        for (index, entry) in expenses.enumerated() {
            let expense = Expense(context: context)
            expense.uuid = UUID()
            expense.title = entry.0
            expense.amountTHB = entry.1
            expense.paidBy = entry.2
            expense.category = entry.3
            expense.split = .equal
            expense.date = calendar.date(byAdding: .day, value: index, to: start)
            expense.addedBy = "Demo"
            expense.trip = trip
        }

        store.save()
        return trip
    }
}
