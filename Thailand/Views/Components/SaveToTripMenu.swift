import SwiftUI
import CoreLocation

/// "Save to Wish List / Add to Day…" menu for any place found in Explore or Nearby.
struct SaveToTripMenu<Label: View>: View {
    @Environment(\.managedObjectContext) private var context
    let place: PlaceResult
    let category: ItemCategory
    var notes = ""
    var onSaved: ((String) -> Void)? = nil
    @ViewBuilder let label: () -> Label

    var body: some View {
        CurrentTripReader { trip in
            if let trip {
                Menu {
                    Button {
                        save(to: nil, in: trip)
                    } label: {
                        SwiftUI.Label("Wish List", systemImage: "star")
                    }
                    Section("Add to Day") {
                        ForEach(trip.sortedDays) { day in
                            Button(day.heading) { save(to: day, in: trip) }
                        }
                    }
                } label: {
                    label()
                }
            }
        }
    }

    private func save(to day: Day?, in trip: Trip) {
        let store = ItineraryStore(context: context)
        let item = store.addItem(
            title: place.name,
            category: category,
            to: day,
            in: trip,
            address: place.address,
            coordinate: place.coordinate,
            notes: [notes, place.phone.map { "Phone: \($0)" } ?? ""].filter { !$0.isEmpty }.joined(separator: "\n")
        )
        item.link = place.url?.absoluteString ?? ""
        store.save()
        onSaved?(day?.heading ?? "Wish List")
    }
}

/// A short confirmation that fades out ("Saved to Day 2").
struct SavedToast: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.lagoon, in: Capsule())
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

extension View {
    /// Shows `SavedToast` at the bottom for two seconds whenever `message` becomes non-nil.
    func savedToast(_ message: Binding<String?>) -> some View {
        overlay(alignment: .bottom) {
            if let text = message.wrappedValue {
                SavedToast(text: text)
                    .padding(.bottom, 24)
                    .task(id: text) {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation { message.wrappedValue = nil }
                    }
            }
        }
        .animation(.snappy, value: message.wrappedValue)
        .sensoryFeedback(.success, trigger: message.wrappedValue) { _, new in new != nil }
    }
}

enum DistanceText {
    /// "350 m" / "2.4 km"
    static func distance(_ meters: CLLocationDistance) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }

    /// Rough walking time at ~4.8 km/h.
    static func walkingTime(_ meters: CLLocationDistance) -> String {
        let minutes = max(1, Int((meters / 80).rounded()))
        if minutes < 60 { return "\(minutes) min walk" }
        return "\(minutes / 60) h \(minutes % 60) min walk"
    }
}
