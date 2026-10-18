import SwiftUI
import CoreData

/// Overview / Itinerary / Map, like a planner's top tabs.
enum PlannerTab: String, CaseIterable, Identifiable {
    case overview, itinerary, map
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// Free-form trip notes (flight numbers, hotel check-in rules, ideas), editable in place.
struct TripNotesCard: View {
    @Environment(\.managedObjectContext) private var context
    @ObservedObject var trip: Trip
    let canEdit: Bool
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Notes", systemImage: "note.text").font(.headline)
            TextField("Write anything: check-in times, reminders, ideas…", text: $text, axis: .vertical)
                .lineLimit(2...8)
                .focused($focused)
                .disabled(!canEdit)
                .font(.subheadline)
        }
        .onAppear { text = trip.notes ?? "" }
        .onChange(of: trip.notes) { _, new in if !focused { text = new ?? "" } }
        .onChange(of: focused) { _, isFocused in if !isFocused { save() } }
        .onDisappear { save() }
        .toolbar {
            if focused {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = false }
                }
            }
        }
    }

    private func save() {
        guard canEdit, text != (trip.notes ?? "") else { return }
        trip.notes = text
        ItineraryStore(context: context).save()
    }
}

/// Entry point to the trip assistant.
struct AssistantCard: View {
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Theme.auroraGradient, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ask the Trip Assistant").font(.headline).foregroundStyle(.primary)
                    Text("Ideas for empty days, timing, what to eat. Private, on your iPhone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Bookings row: count of saved confirmations, open them or import a new one.
struct BookingsSummaryRow: View {
    @ObservedObject var trip: Trip
    let canEdit: Bool
    let onOpen: () -> Void
    let onImport: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    Image(systemName: "ticket.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.violet)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reservations & bookings").font(.headline).foregroundStyle(.primary)
                        let count = trip.sortedDocuments.count
                        Text(count == 0 ? "Flights, hotels and tickets in one place" : "\(count) saved")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            if canEdit {
                Button("Import", systemImage: "wand.and.stars", action: onImport)
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Import a booking from a screenshot, PDF or text")
            }
        }
    }
}

/// Builds the Google My Maps file for a trip.
enum PlannerExport {
    static func kmlFile(for trip: Trip) -> URL? {
        func places(_ items: [Item]) -> [MapExport.Place] {
            items.compactMap { item in
                item.coordinate.map {
                    MapExport.Place(name: item.displayTitle,
                                    notes: [item.address ?? "", item.notes ?? ""].filter { !$0.isEmpty }.joined(separator: "\n"),
                                    latitude: $0.latitude, longitude: $0.longitude)
                }
            }
        }
        var folders: [(name: String, places: [MapExport.Place])] = trip.sortedDays.map { day in
            (name: day.heading, places: places(day.sortedItems))
        }
        folders.append((name: "Wish List", places: places(trip.wishListPlaces)))
        for name in trip.customListNames {
            folders.append((name: name, places: places(trip.listItems(name))))
        }
        guard folders.contains(where: { !$0.places.isEmpty }) else { return nil }
        let kml = MapExport.kml(title: trip.displayName, folders: folders)
        let safe = trip.displayName.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
        let url = FileManager.default.temporaryDirectory.appending(path: "\(safe.isEmpty ? "Trip" : safe).kml")
        do {
            try kml.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}

/// Export row: share the trip as a KML file to import in Google My Maps.
struct ExportMapsRow: View {
    @ObservedObject var trip: Trip
    @State private var fileURL: URL?
    @State private var showingHelp = false

    var body: some View {
        HStack {
            if let fileURL {
                ShareLink(item: fileURL) {
                    Label("Export to Google Maps", systemImage: "square.and.arrow.up")
                }
            } else {
                Label("Export to Google Maps", systemImage: "square.and.arrow.up")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showingHelp = true
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("How to open it in Google Maps")
        }
        .task(id: trip.allItems.count) { fileURL = PlannerExport.kmlFile(for: trip) }
        .alert("Open in Google Maps", isPresented: $showingHelp) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Save the file, then on a computer go to google.com/mymaps → Create a new map → Import and pick the file. Each day becomes a layer, and the map appears in Google Maps under Saved → Maps on your phone.")
        }
    }
}
