import CoreData
import MapKit
import SwiftUI

// MARK: - Save any place to Spots

enum SpotSaver {
    /// The trip selected on the Trip tab.
    static func currentTrip(in context: NSManagedObjectContext) -> Trip? {
        let request = NSFetchRequest<Trip>(entityName: "Trip")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        let selected = UserDefaults.standard.string(forKey: AppSettings.selectedTripKey)
        let trips = (try? context.fetch(request)) ?? []
        return trips.first { $0.uuid?.uuidString == selected } ?? trips.first
    }

    /// Saves a place as a confirmed spot (or returns the one you already have). Nil when there's no trip.
    @MainActor @discardableResult
    static func save(name: String, coordinate: CLLocationCoordinate2D, address: String, category: SpotCategory,
                     mapItem: MKMapItem? = nil, context: NSManagedObjectContext) -> Spot? {
        guard let trip = currentTrip(in: context) else { return nil }
        if let existing = ImportPipeline.existingSpot(name: name, coordinate: coordinate,
                                                      appleMapsID: mapItem?.identifier?.rawValue, in: trip.allSpots) {
            existing.status = .confirmed
            ItineraryStore(context: context).save()
            return existing
        }
        let spot = Spot(context: context)
        spot.placeInSameStore(as: trip)
        spot.uuid = UUID()
        spot.status = .confirmed
        spot.addedBy = AppSettings.displayName
        spot.createdAt = .now
        spot.trip = trip
        if let mapItem { spot.apply(mapItem) }
        spot.name = name
        spot.address = address
        spot.coordinate = coordinate
        spot.category = category
        ItineraryStore(context: context).save()
        return spot
    }

    static func isSaved(name: String, coordinate: CLLocationCoordinate2D, context: NSManagedObjectContext) -> Bool {
        guard let trip = currentTrip(in: context) else { return false }
        return ImportPipeline.existingSpot(name: name, coordinate: coordinate, appleMapsID: nil, in: trip.confirmedSpots) != nil
    }
}

/// Heart button that saves a place to Spots.
struct SaveToSpotsButton: View {
    let name: String
    let coordinate: CLLocationCoordinate2D
    let address: String
    let category: SpotCategory
    var mapItem: MKMapItem?
    var onDark = false
    var onSaved: (String) -> Void = { _ in }

    @Environment(\.managedObjectContext) private var context
    @State private var saved = false

    var body: some View {
        Button {
            if SpotSaver.save(name: name, coordinate: coordinate, address: address, category: category, mapItem: mapItem, context: context) != nil {
                withAnimation(.snappy) { saved = true }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onSaved("Spots")
            }
        } label: {
            Image(systemName: saved ? "heart.fill" : "heart")
                .font(.headline)
                .foregroundStyle(saved ? Theme.coral : (onDark ? .white : Theme.ink))
                .frame(width: 40, height: 40)
                .background(onDark ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Theme.insetBackground), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(saved ? "Saved to Spots" : "Save \(name) to Spots")
        .onAppear { saved = SpotSaver.isSaved(name: name, coordinate: coordinate, context: context) }
    }
}

// MARK: - Essentials nearby

enum Essential: String, CaseIterable, Identifiable {
    case pharmacy, atm, sevenEleven, coffee, massage, toilet
    var id: String { rawValue }

    var title: String {
        switch self {
        case .pharmacy: "Pharmacy"
        case .atm: "ATM"
        case .sevenEleven: "7-Eleven"
        case .coffee: "Coffee"
        case .massage: "Massage"
        case .toilet: "Toilets"
        }
    }

    var systemImage: String {
        switch self {
        case .pharmacy: "cross.case.fill"
        case .atm: "banknote.fill"
        case .sevenEleven: "storefront.fill"
        case .coffee: "cup.and.saucer.fill"
        case .massage: "hands.and.sparkles.fill"
        case .toilet: "toilet.fill"
        }
    }

    var color: Color {
        switch self {
        case .pharmacy: Theme.coral
        case .atm: Color(hex: "#2F9E5B")
        case .sevenEleven: Theme.mango
        case .coffee: Color(hex: "#8B5A3C")
        case .massage: Color(hex: "#E0559A")
        case .toilet: Color(hex: "#4C7BD9")
        }
    }

    var query: String {
        switch self {
        case .pharmacy: "pharmacy"
        case .atm: "ATM"
        case .sevenEleven: "7-Eleven"
        case .coffee: "coffee"
        case .massage: "Thai massage"
        case .toilet: "public toilet"
        }
    }

    var poiFilter: MKPointOfInterestFilter? {
        switch self {
        case .pharmacy: MKPointOfInterestFilter(including: [.pharmacy])
        case .atm: MKPointOfInterestFilter(including: [.atm, .bank])
        case .coffee: MKPointOfInterestFilter(including: [.cafe, .bakery])
        case .toilet: MKPointOfInterestFilter(including: [.restroom])
        case .sevenEleven, .massage: nil
        }
    }

    var spotCategory: SpotCategory {
        switch self {
        case .coffee: .brew
        case .massage: .vibe
        default: .go
        }
    }
}

struct EssentialsRow: View {
    let onPick: (Essential) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Essentials nearby").font(.title3.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Essential.allCases) { e in
                        Button { onPick(e) } label: {
                            VStack(spacing: 6) {
                                Image(systemName: e.systemImage)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(e.color)
                                    .frame(width: 56, height: 56)
                                    .background(e.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                Text(e.title).font(.caption.weight(.medium)).foregroundStyle(.primary)
                            }
                            .frame(width: 70)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollClipDisabled()
        }
    }
}

/// The closest pharmacies / ATMs / 7-Elevens… with walking distance and one-tap directions.
struct EssentialsSheet: View {
    let essential: Essential
    let here: CLLocation
    let onWalk: (WalkTarget) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var items: [MKMapItem] = []
    @State private var loading = true

    var body: some View {
        NavigationStack {
            List {
                if loading {
                    ProgressView().frame(maxWidth: .infinity)
                } else if items.isEmpty {
                    Text("Nothing found within 2 km.").foregroundStyle(.secondary)
                }
                ForEach(items, id: \.self) { item in
                    let d = item.placemark.location.map(here.distance(from:)) ?? 0
                    HStack(spacing: 12) {
                        Image(systemName: essential.systemImage)
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(essential.color, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name ?? essential.title).font(.body.weight(.semibold)).lineLimit(1)
                            Text("\(DistanceText.distance(d)) · \(DistanceText.walkingTime(d))")
                                .font(.caption).foregroundStyle(Theme.lagoon)
                        }
                        Spacer()
                        Button {
                            dismiss()
                            onWalk(WalkTarget(name: item.name ?? essential.title, coordinate: item.placemark.coordinate))
                        } label: {
                            Image(systemName: "figure.walk")
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(Theme.ink, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Walk to \(item.name ?? essential.title)")
                    }
                }
            }
            .navigationTitle(essential.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await load() }
        }
        .presentationDetents([.medium, .large])
    }

    private func load() async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = essential.query
        request.region = MKCoordinateRegion(center: here.coordinate, latitudinalMeters: 4_000, longitudinalMeters: 4_000)
        request.resultTypes = .pointOfInterest
        if let filter = essential.poiFilter { request.pointOfInterestFilter = filter }
        let found = (try? await MKLocalSearch(request: request).start().mapItems) ?? []
        items = found
            .filter { ($0.placemark.location?.distance(from: here) ?? .infinity) < 2_500 }
            .sorted { ($0.placemark.location?.distance(from: here) ?? 0) < ($1.placemark.location?.distance(from: here) ?? 0) }
            .prefix(12).map { $0 }
        loading = false
    }
}

// MARK: - Big photo card with the name over the image

struct PhotoPlaceCard<Photo: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    var badge: String?
    var width: CGFloat? = 260
    var height: CGFloat = 210
    @ViewBuilder let photo: () -> Photo
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        photo()
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .clipped()
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 3) {
                    if let badge {
                        Text(badge).font(.caption2.weight(.heavy)).foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(.black.opacity(0.35), in: Capsule())
                    }
                    Text(title).font(.headline).foregroundStyle(.white).lineLimit(2)
                    if let subtitle { Text(subtitle).font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.9)).lineLimit(1) }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom))
            }
            .overlay(alignment: .topTrailing) { trailing().padding(10) }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }
}
