import CoreLocation
import MapKit
import SwiftUI

/// A place tapped on the Spots map (or a dropped pin) waiting to be added.
struct PlaceToAdd: Identifiable {
    let id = UUID()
    var mapItem: MKMapItem?
    var coordinate: CLLocationCoordinate2D
}

/// "Add to Spots" card: name, category (Stay for hotels), and an option to put it on a day.
struct AddPlaceSheet: View {
    let place: PlaceToAdd
    @ObservedObject var trip: Trip
    var onAdded: (Spot) -> Void = { _ in }

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var city = ""
    @State private var category: SpotCategory = .explore
    @State private var photo: URL?

    private var existing: Spot? {
        ImportPipeline.existingSpot(name: name, coordinate: place.coordinate,
                                    appleMapsID: place.mapItem?.identifier?.rawValue, in: trip.allSpots)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if let photo {
                    AsyncImage(url: photo) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() } else { Theme.insetBackground }
                    }
                    .frame(height: 170)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                HStack(spacing: 14) {
                    Image(systemName: category.systemImage)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 54, height: 54)
                        .background(category.color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        if place.mapItem == nil {
                            TextField("Name (e.g. My Airbnb)", text: $name).font(.title3.weight(.semibold))
                        } else {
                            Text(name).font(.title3.weight(.semibold)).lineLimit(2)
                        }
                        Text(address.isEmpty ? "Finding the address…" : address)
                            .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(SpotCategory.allCases) { c in
                            CategoryChip(title: c.title, systemImage: c.systemImage, color: c.color, selected: category == c) {
                                category = c
                            }
                        }
                    }
                }

                if let existing {
                    Label("Already in your spots as \(existing.displayName)", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.lagoon)
                } else {
                    Button { add() } label: {
                        Label(category == .stay ? "Add as a place to stay" : "Add to Spots", systemImage: "plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .foregroundStyle(.white)
                            .background(Theme.ink, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .presentationDetents([.height(photo == nil ? 330 : 510)])
        .presentationBackground(Theme.background)
        .task { await load() }
    }

    private func load() async {
        if let item = place.mapItem {
            name = item.name ?? ""
            address = item.placemark.title ?? ""
            city = item.placemark.locality ?? item.placemark.administrativeArea ?? ""
            category = SpotCategory(poi: item.pointOfInterestCategory)
            if let site = item.url {
                photo = await PlacePhotos.shared.photo(name: name, coordinate: place.coordinate, website: site)
            }
        } else {
            category = .stay
            let location = CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
            if let mark = try? await CLGeocoder().reverseGeocodeLocation(location).first {
                address = [mark.subThoroughfare, mark.thoroughfare, mark.subLocality, mark.locality].compactMap { $0 }.joined(separator: " ")
                city = mark.locality ?? mark.administrativeArea ?? ""
                if name.isEmpty { name = mark.name ?? "" }
            }
            if address.isEmpty { address = String(format: "%.5f, %.5f", place.coordinate.latitude, place.coordinate.longitude) }
        }
    }

    private func add() {
        let spot = Spot(context: context)
        spot.placeInSameStore(as: trip)
        spot.uuid = UUID()
        spot.status = .confirmed
        spot.addedBy = AppSettings.displayName
        spot.createdAt = .now
        spot.trip = trip
        if let item = place.mapItem { spot.apply(item) }
        spot.name = name.trimmingCharacters(in: .whitespaces)
        spot.address = address
        spot.city = city
        spot.coordinate = place.coordinate
        spot.category = category
        ItineraryStore(context: context).save()
        onAdded(spot)
        dismiss()
    }
}
