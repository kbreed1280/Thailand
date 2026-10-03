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
    @State private var didLoad = false

    private var dayCount: Int {
        ItineraryOrdering.dayDates(from: start, to: end).count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Trip name (e.g. Thailand 2026)", text: $name)
                        .font(.headline)
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
            store.setDates(of: trip, start: start, end: end)
            store.save()
        } else {
            let newTrip = store.createTrip(name: trimmed, start: start, end: end, notes: notes)
            store.save()
            onCreate?(newTrip)
        }
        dismiss()
    }
}
