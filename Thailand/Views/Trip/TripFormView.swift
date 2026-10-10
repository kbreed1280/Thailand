import SwiftUI

/// Create (`trip == nil`) or edit a trip. Changing dates adds/removes days; places on a removed
/// day go back to the wish list.
struct TripFormView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    let trip: Trip?
    var onCreate: ((Trip) -> Void)? = nil

    @State private var name = ""
    @State private var start = Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
    @State private var end = Calendar.current.date(byAdding: .day, value: 40, to: .now) ?? .now
    @State private var notes = ""
    @State private var colorHex = ""
    @State private var coverPhotoID: UUID?
    @State private var didLoad = false
    @State private var destination = ""
    @State private var found: Destinations.Found?
    @State private var currency = ""
    /// The currency the form last filled in by itself; a different value means you picked it.
    @State private var autoCurrency = ""
    @State private var looking = false

    static let colors = ["#F4821C", "#E8505B", "#1BA39C", "#2D88D9", "#6C5CE7", "#D63384", "#2F9E44", "#8D6E63"]

    private var dayCount: Int {
        ItineraryOrdering.dayDates(from: start, to: end).count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Trip name (e.g. Japan 2027)", text: $name)
                        .font(.headline)
                }
                Section {
                    HStack {
                        TextField("Where to? (e.g. Tokyo, Lisbon, Bali)", text: $destination)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                        if looking { ProgressView() }
                    }
                    if let found {
                        LabeledContent("Country") {
                            Text("\(CurrencyContext.flag(found.country)) \(Locale.current.localizedString(forRegionCode: found.country) ?? found.country)")
                        }
                    }
                    Picker("Local currency", selection: $currency) {
                        if currency.isEmpty { Text("Choose…").tag("") }
                        ForEach(CurrencyContext.allCodes, id: \.self) { code in
                            Text("\(code) · \(CurrencyContext.name(code))").tag(code)
                        }
                    }
                } header: {
                    Text("Destination")
                } footer: {
                    Text("Sets the money converter, weather, place search and translator for this trip. The currency fills in automatically.")
                }
                Section {
                    DatePicker("Arrive", selection: $start, displayedComponents: .date)
                    DatePicker("Leave", selection: $end, in: start..., displayedComponents: .date)
                } header: {
                    Text("Dates")
                } footer: {
                    Text("\(dayCount) day\(dayCount == 1 ? "" : "s"). Each day gets its own plan.")
                }
                Section("Notes") {
                    TextField("Flights, visa, anything to remember", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                Section("Color") {
                    HStack(spacing: 10) {
                        ForEach(Self.colors, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 32, height: 32)
                                .overlay {
                                    if hex == (colorHex.isEmpty ? Self.colors[0] : colorHex) {
                                        Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                                    }
                                }
                                .onTapGesture { colorHex = hex }
                                .accessibilityLabel("Color \(hex)")
                                .accessibilityAddTraits(hex == colorHex ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }

                if let trip, !trip.allPhotos.isEmpty {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(trip.allPhotos.prefix(30)) { photo in
                                    Group {
                                        if let image = photo.thumbnail {
                                            Image(uiImage: image).resizable().scaledToFill()
                                        } else {
                                            Color.gray.opacity(0.2)
                                        }
                                    }
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(Theme.mango, lineWidth: photo.uuid == coverPhotoID ? 3 : 0)
                                    )
                                    .onTapGesture { coverPhotoID = photo.uuid }
                                    .accessibilityLabel(photo.uuid == coverPhotoID ? "Cover photo, selected" : "Use as cover photo")
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Text("Cover photo")
                    } footer: {
                        Text("Shown behind the trip header. If you don't pick one, the newest photo is used.")
                    }
                }
            }
            .navigationTitle(trip == nil ? "New Trip" : "Edit Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .bold()
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .task(id: destination) {
                // Look the destination up a moment after typing stops.
                guard didLoad else { return }
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled, destination.trimmingCharacters(in: .whitespaces).count >= 2 else { return }
                looking = true
                defer { looking = false }
                if let hit = await Destinations.find(destination) {
                    found = hit
                    if currency.isEmpty || currency == autoCurrency, let code = Destinations.currency(forCountry: hit.country) {
                        currency = code
                        autoCurrency = code
                    }
                }
            }
            .onChange(of: start) { _, newStart in
                if end < newStart { end = newStart }
            }
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                if let trip {
                    name = trip.name ?? ""
                    start = trip.startDate ?? start
                    end = trip.endDate ?? end
                    notes = trip.notes ?? ""
                    colorHex = trip.colorHex ?? ""
                    coverPhotoID = trip.coverPhotoID
                    destination = trip.destination ?? ""
                    currency = trip.localCurrency
                    if (trip.currencyCode ?? "").isEmpty { autoCurrency = currency }
                    if let c = trip.destinationCoordinate {
                        found = Destinations.Found(name: trip.destination ?? "", country: trip.country, latitude: c.latitude, longitude: c.longitude)
                    }
                }
            }
        }
    }

    private func save() {
        let store = ItineraryStore(context: context)
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let trip {
            trip.name = trimmed
            trip.notes = notes
            trip.colorHex = colorHex
            trip.coverPhotoID = coverPhotoID
            applyDestination(to: trip)
            store.setDates(of: trip, start: start, end: end)
            store.save()
            ExchangeRateStore.shared.useTrip(trip)
        } else {
            let newTrip = store.createTrip(name: trimmed, start: start, end: end, notes: notes)
            newTrip.colorHex = colorHex
            applyDestination(to: newTrip)
            store.save()
            ExchangeRateStore.shared.useTrip(newTrip)
            onCreate?(newTrip)
        }
        dismiss()
    }

    private func applyDestination(to trip: Trip) {
        trip.destination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        if let found {
            trip.countryCode = found.country
            trip.destinationLatitude = found.latitude
            trip.destinationLongitude = found.longitude
        }
        if !currency.isEmpty { trip.currencyCode = currency }
    }
}
