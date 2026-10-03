import SwiftUI
import CoreData

/// Places you come back to (hotel, Airbnb, a favorite café). Used as start/end of day routes.
struct SavedPlacesView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var trip: Trip

    @State private var showingSearch = false
    @State private var editing: SavedPlace?
    @State private var refreshTick = 0
    @State private var isLocating = false

    var body: some View {
        let _ = refreshTick
        NavigationStack {
            List {
                Section {
                    ForEach(trip.sortedSavedPlaces) { place in
                        Button {
                            editing = place
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: place.symbolName ?? "mappin")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(width: 38, height: 38)
                                    .background(Theme.lagoon, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(place.displayName).font(.headline).foregroundStyle(.primary)
                                    if let address = place.address, !address.isEmpty {
                                        Text(address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                    .onDelete { offsets in
                        let places = trip.sortedSavedPlaces
                        offsets.map { places[$0] }.forEach { place in
                            place.trip = nil
                            context.delete(place)
                        }
                        save()
                    }
                } footer: {
                    Text("Shared with everyone on this trip. Pick one as the start or end of a day route.")
                }

                Section {
                    Button {
                        showingSearch = true
                    } label: {
                        Label("Search Apple Maps", systemImage: "magnifyingglass")
                    }
                    Button(action: addCurrentLocation) {
                        HStack {
                            Label("Save My Current Location", systemImage: "location.fill")
                            Spacer()
                            if isLocating { ProgressView() }
                        }
                    }
                }
            }
            .overlay {
                if trip.sortedSavedPlaces.isEmpty {
                    EmptyStateView(
                        systemImage: "bed.double.fill",
                        title: "No Saved Places",
                        message: "Save your hotel (and anywhere else you keep coming back to) to start and end each day's route there."
                    )
                    .allowsHitTesting(false)
                    .padding(.bottom, 160)
                }
            }
            .navigationTitle("Saved Places")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showingSearch) {
                PlaceSearchSheet { result in
                    insert(name: result.name, address: result.address, latitude: result.latitude, longitude: result.longitude)
                }
            }
            .sheet(item: $editing) { place in
                SavedPlaceEditor(place: place) { save() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: context)) { _ in
                refreshTick &+= 1
            }
        }
    }

    private func addCurrentLocation() {
        isLocating = true
        Task {
            defer { isLocating = false }
            guard let location = await LocationService.shared.currentLocation() else { return }
            let names = await LocationService.shared.placeName(for: location)
            insert(
                name: "Our hotel",
                address: [names?.area ?? "", names?.city ?? ""].filter { !$0.isEmpty }.joined(separator: ", "),
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
        }
    }

    private func insert(name: String, address: String, latitude: Double, longitude: Double) {
        let place = SavedPlace(context: context)
        place.placeInSameStore(as: trip)
        place.uuid = UUID()
        place.name = name
        place.address = address
        place.latitude = latitude
        place.longitude = longitude
        place.symbolName = name.localizedCaseInsensitiveContains("hotel") ? "bed.double.fill" : "mappin"
        place.createdAt = .now
        place.updatedAt = .now
        place.trip = trip
        save()
    }

    private func save() {
        ItineraryStore(context: context).save()
        refreshTick &+= 1
    }
}

private struct SavedPlaceEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var place: SavedPlace
    let onSave: () -> Void

    @State private var name = ""
    @State private var symbol = "bed.double.fill"

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Section("Icon") {
                    HStack(spacing: 10) {
                        ForEach(SavedPlace.symbols, id: \.self) { option in
                            Image(systemName: option)
                                .frame(width: 36, height: 36)
                                .foregroundStyle(option == symbol ? .white : Theme.lagoon)
                                .background(option == symbol ? Theme.lagoon : Theme.lagoon.opacity(0.12), in: Circle())
                                .onTapGesture { symbol = option }
                                .accessibilityLabel(option)
                        }
                    }
                }
                if let address = place.address, !address.isEmpty {
                    Section("Address") { Text(address) }
                }
            }
            .navigationTitle("Edit Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        place.name = name
                        place.symbolName = symbol
                        place.updatedAt = .now
                        onSave()
                        dismiss()
                    }
                }
            }
            .onAppear {
                name = place.name ?? ""
                symbol = place.symbolName ?? "bed.double.fill"
            }
        }
        .presentationDetents([.medium])
    }
}
