import SwiftUI
import MapKit
import CoreData

/// Trip journal: places auto-logged while the Nearby tab was open, grouped by day.
struct JournalView: View {
    @Environment(\.managedObjectContext) private var context
    @ObservedObject var trip: Trip
    @State private var refreshTick = 0

    private var days: [(day: Date, visits: [VisitLog])] {
        let grouped = Dictionary(grouping: trip.sortedVisits) { Calendar.current.startOfDay(for: $0.date ?? .distantPast) }
        return grouped
            .map { (day: $0.key, visits: $0.value.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        let _ = refreshTick
        List {
            ForEach(days, id: \.day) { group in
                Section(group.day.formatted(.dateTime.weekday(.wide).month().day())) {
                    Map(initialPosition: .automatic, interactionModes: []) {
                        ForEach(Array(group.visits.enumerated()), id: \.element.objectID) { index, visit in
                            Annotation(visit.placeName ?? "", coordinate: CLLocationCoordinate2D(latitude: visit.latitude, longitude: visit.longitude)) {
                                NumberedPin(number: index + 1, colorHex: "#1BA39C", isSelected: false, compact: true)
                            }
                        }
                    }
                    .frame(height: 160)
                    .listRowInsets(EdgeInsets())

                    ForEach(group.visits) { visit in
                        HStack {
                            Text(visit.date?.formatted(date: .omitted, time: .shortened) ?? "")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(Theme.mango)
                                .frame(width: 70, alignment: .leading)
                            Text(visit.placeName ?? "Somewhere")
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { group.visits[$0] }.forEach(context.delete)
                        ItineraryStore(context: context).save()
                    }
                }
            }
        }
        .overlay {
            if days.isEmpty {
                EmptyStateView(
                    systemImage: "book.closed.fill",
                    title: "Your Journal Is Empty",
                    message: "Turn on \"Auto-log places we visit\" on the Nearby tab. Each new spot you open the app at is saved here."
                )
            }
        }
        .navigationTitle("Trip Journal")
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: context)) { _ in
            refreshTick &+= 1
        }
    }
}
