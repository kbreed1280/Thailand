import CoreData
import CoreLocation
import UIKit

// MARK: - Enums stored as raw strings

enum ItemCategory: String, CaseIterable, Identifiable {
    case place, activity, meal, hotel, transport

    var id: String { rawValue }

    var title: String {
        switch self {
        case .place: "Place"
        case .activity: "Activity"
        case .meal: "Meal"
        case .hotel: "Hotel"
        case .transport: "Transport"
        }
    }

    var systemImage: String {
        switch self {
        case .place: "mappin.circle.fill"
        case .activity: "figure.walk.circle.fill"
        case .meal: "fork.knife.circle.fill"
        case .hotel: "bed.double.circle.fill"
        case .transport: "tram.circle.fill"
        }
    }

    var colorHex: String {
        switch self {
        case .place: "#F4821C"
        case .activity: "#1BA39C"
        case .meal: "#E8505B"
        case .hotel: "#6C5CE7"
        case .transport: "#2D88D9"
        }
    }
}

enum ItemStatus: String, CaseIterable, Identifiable {
    case wantToGo = "want"
    case booked
    case done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wantToGo: "Want to go"
        case .booked: "Booked"
        case .done: "Done"
        }
    }

    var systemImage: String {
        switch self {
        case .wantToGo: "star"
        case .booked: "ticket"
        case .done: "checkmark.circle.fill"
        }
    }
}

enum ExpenseSplit: String, CaseIterable, Identifiable {
    case equal
    case payerOnly
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .equal: "Split 50/50"
        case .payerOnly: "Just the payer"
        case .custom: "Custom split"
        }
    }
}

enum ExpenseCategory: String, CaseIterable, Identifiable {
    case food, transport, lodging, activities, shopping, other

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var systemImage: String {
        switch self {
        case .food: "fork.knife"
        case .transport: "tram.fill"
        case .lodging: "bed.double.fill"
        case .activities: "ticket.fill"
        case .shopping: "bag.fill"
        case .other: "ellipsis.circle.fill"
        }
    }
}

enum PackingCategory: String, CaseIterable, Identifiable {
    case essentials, documents, clothing, health, tech, todo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .essentials: "Essentials"
        case .documents: "Documents"
        case .clothing: "Clothing"
        case .health: "Health"
        case .tech: "Tech"
        case .todo: "Before we go"
        }
    }

    var systemImage: String {
        switch self {
        case .essentials: "bag.fill"
        case .documents: "doc.text.fill"
        case .clothing: "tshirt.fill"
        case .health: "cross.case.fill"
        case .tech: "bolt.fill"
        case .todo: "checklist"
        }
    }
}

// MARK: - Managed objects

@objc(Trip)
final class Trip: NSManagedObject {
    @NSManaged var uuid: UUID?
    @NSManaged var name: String?
    @NSManaged var startDate: Date?
    @NSManaged var endDate: Date?
    @NSManaged var notes: String?
    @NSManaged var hotelAddressThai: String?
    @NSManaged var createdAt: Date?
    @NSManaged var days: NSSet?
    @NSManaged var wishItems: NSSet?
    @NSManaged var visits: NSSet?
    @NSManaged var expenses: NSSet?
    @NSManaged var packingItems: NSSet?

    var displayName: String { (name ?? "").isEmpty ? "Untitled Trip" : (name ?? "") }

    var sortedDays: [Day] {
        (days as? Set<Day> ?? []).sorted {
            ($0.date ?? .distantPast, $0.sortIndex) < ($1.date ?? .distantPast, $1.sortIndex)
        }
    }

    var sortedWishItems: [Item] {
        (wishItems as? Set<Item> ?? []).sorted { $0.sortIndex < $1.sortIndex }
    }

    var allItems: [Item] {
        sortedWishItems + sortedDays.flatMap(\.sortedItems)
    }

    var sortedExpenses: [Expense] {
        (expenses as? Set<Expense> ?? []).sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    var sortedPackingItems: [PackingItem] {
        (packingItems as? Set<PackingItem> ?? []).sorted { $0.sortIndex < $1.sortIndex }
    }

    var sortedVisits: [VisitLog] {
        (visits as? Set<VisitLog> ?? []).sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// The day matching today's date, if the trip is underway.
    var today: Day? {
        sortedDays.first { day in
            guard let date = day.date else { return false }
            return Calendar.current.isDateInToday(date)
        }
    }
}

@objc(Day)
final class Day: NSManagedObject {
    @NSManaged var uuid: UUID?
    @NSManaged var date: Date?
    @NSManaged var title: String?
    @NSManaged var sortIndex: Int64
    @NSManaged var trip: Trip?
    @NSManaged var items: NSSet?

    var sortedItems: [Item] {
        (items as? Set<Item> ?? []).sorted { $0.sortIndex < $1.sortIndex }
    }

    /// "Day 3"
    var number: Int {
        (trip?.sortedDays.firstIndex(of: self) ?? 0) + 1
    }

    var heading: String {
        let datePart = date?.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) ?? ""
        return "Day \(number) · \(datePart)"
    }
}

@objc(Item)
final class Item: NSManagedObject {
    @NSManaged var uuid: UUID?
    @NSManaged var title: String?
    @NSManaged var categoryRaw: String?
    @NSManaged var time: Date?
    @NSManaged var notes: String?
    @NSManaged var address: String?
    @NSManaged var hasCoordinate: Bool
    @NSManaged var latitude: Double
    @NSManaged var longitude: Double
    @NSManaged var link: String?
    @NSManaged var costTHB: Double
    @NSManaged var statusRaw: String?
    @NSManaged var sortIndex: Int64
    @NSManaged var addedBy: String?
    @NSManaged var lastEditedBy: String?
    @NSManaged var createdAt: Date?
    @NSManaged var updatedAt: Date?
    @NSManaged var day: Day?
    @NSManaged var wishTrip: Trip?
    @NSManaged var photos: NSSet?

    var category: ItemCategory {
        get { ItemCategory(rawValue: categoryRaw ?? "") ?? .place }
        set { categoryRaw = newValue.rawValue }
    }

    var status: ItemStatus {
        get { ItemStatus(rawValue: statusRaw ?? "") ?? .wantToGo }
        set { statusRaw = newValue.rawValue }
    }

    var displayTitle: String { (title ?? "").isEmpty ? "Untitled" : (title ?? "") }

    var trip: Trip? { day?.trip ?? wishTrip }

    var isOnWishList: Bool { day == nil }

    var coordinate: CLLocationCoordinate2D? {
        get { hasCoordinate ? CLLocationCoordinate2D(latitude: latitude, longitude: longitude) : nil }
        set {
            hasCoordinate = newValue != nil
            latitude = newValue?.latitude ?? 0
            longitude = newValue?.longitude ?? 0
        }
    }

    var linkURL: URL? {
        guard let link, !link.isEmpty else { return nil }
        return URL(string: link.hasPrefix("http") ? link : "https://\(link)")
    }

    var sortedPhotos: [ItemPhoto] {
        (photos as? Set<ItemPhoto> ?? []).sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    /// Records who changed the item and when. Call after every user edit.
    func markEdited(by name: String = AppSettings.displayName) {
        lastEditedBy = name
        updatedAt = .now
    }
}

@objc(ItemPhoto)
final class ItemPhoto: NSManagedObject {
    @NSManaged var uuid: UUID?
    @NSManaged var imageData: Data?
    @NSManaged var thumbnailData: Data?
    @NSManaged var createdAt: Date?
    @NSManaged var item: Item?

    var thumbnail: UIImage? { (thumbnailData ?? imageData).flatMap(UIImage.init(data:)) }
    var image: UIImage? { imageData.flatMap(UIImage.init(data:)) }
}

@objc(VisitLog)
final class VisitLog: NSManagedObject {
    @NSManaged var uuid: UUID?
    @NSManaged var date: Date?
    @NSManaged var placeName: String?
    @NSManaged var latitude: Double
    @NSManaged var longitude: Double
    @NSManaged var trip: Trip?
}

@objc(Expense)
final class Expense: NSManagedObject {
    @NSManaged var uuid: UUID?
    @NSManaged var title: String?
    @NSManaged var amountTHB: Double
    @NSManaged var paidBy: String?
    @NSManaged var splitRaw: String?
    /// Fraction (0...1) of the expense the payer owes themselves when the split is custom.
    @NSManaged var payerShare: Double
    @NSManaged var categoryRaw: String?
    @NSManaged var date: Date?
    @NSManaged var addedBy: String?
    @NSManaged var trip: Trip?

    var split: ExpenseSplit {
        get { ExpenseSplit(rawValue: splitRaw ?? "") ?? .equal }
        set { splitRaw = newValue.rawValue }
    }

    var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw ?? "") ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
}

@objc(PackingItem)
final class PackingItem: NSManagedObject {
    @NSManaged var uuid: UUID?
    @NSManaged var title: String?
    @NSManaged var categoryRaw: String?
    @NSManaged var isDone: Bool
    @NSManaged var sortIndex: Int64
    @NSManaged var addedBy: String?
    @NSManaged var trip: Trip?

    var category: PackingCategory {
        get { PackingCategory(rawValue: categoryRaw ?? "") ?? .essentials }
        set { categoryRaw = newValue.rawValue }
    }
}
