import CoreData
import MapKit
import SwiftUI

/// Pick saved spots (from TikTok, Maps, web…) on a map and add them to a day. Picked spots are
/// put in walking order after what's already planned, with times filled in.
struct SpotPickerSheet: View {
    @ObservedObject var trip: Trip
    @ObservedObject var day: Day
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var picked: [NSManagedObjectID] = []
    @State private var category: SpotCategory?
    @State private var search = ""
    @State private var camera: MapCameraPosition = .automatic

    private var planned: [Item] { trip.sortedDays.flatMap(\.sortedItems) }

    private var spots: [Spot] {
        trip.confirmedSpots.filter { spot in
            spot.hasCoordinate
                && (category == nil || spot.category == category)
                && (search.isEmpty || [spot.displayName, spot.city ?? ""].contains { $0.localizedCaseInsensitiveContains(search) })
        }
    }

    private func dayNumber(of spot: Spot) -> Int? {
        trip.sortedDays.first { $0.sortedItems.contains { AutoPlanView.same($0, spot) } }?.number
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Map(position: $camera) {
                    ForEach(spots) { spot in
                        if let c = spot.coordinate {
                            Annotation(spot.displayName, coordinate: c) {
                                pin(spot)
                            }
                        }
                    }
                    UserAnnotation()
                }
                .frame(height: 320)
                .overlay(alignment: .top) { categoryPills.padding(.top, 8) }

                List {
                    Section {
                        ForEach(spots) { spot in
                            row(spot)
                        }
                    } footer: {
                        if trip.confirmedSpots.isEmpty {
                            Text("No saved spots yet. Share TikToks, Reels or Google Maps links to WanderHub, then confirm the drafts in Spots.")
                        } else {
                            Text("Tap pins or rows to pick. They're added in walking order after what's already on Day \(day.number).")
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search your spots")
            .navigationTitle("Add to Day \(day.number)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(picked.isEmpty ? "Add" : "Add \(picked.count)") { add() }
                        .fontWeight(.semibold)
                        .disabled(picked.isEmpty)
                }
            }
        }
    }

    private var categoryPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                CategoryChip(title: "All", systemImage: "square.grid.2x2", color: .secondary, selected: category == nil) { category = nil }
                ForEach(SpotCategory.allCases) { c in
                    CategoryChip(title: c.title, systemImage: c.systemImage, color: c.color, selected: category == c) {
                        category = category == c ? nil : c
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func pin(_ spot: Spot) -> some View {
        let index = picked.firstIndex(of: spot.objectID)
        return Button { toggle(spot) } label: {
            ZStack {
                Circle().fill(index != nil ? Theme.lagoon : spot.category.color)
                if let index {
                    Text("\(index + 1)").font(.caption.weight(.bold)).foregroundStyle(.white)
                } else {
                    Image(systemName: spot.category.systemImage).font(.caption2.weight(.bold)).foregroundStyle(.white)
                }
            }
            .frame(width: index != nil ? 32 : 26, height: index != nil ? 32 : 26)
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(radius: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(spot.displayName), \(index != nil ? "picked" : "not picked")")
    }

    private func row(_ spot: Spot) -> some View {
        let index = picked.firstIndex(of: spot.objectID)
        return Button { toggle(spot) } label: {
            HStack(spacing: 12) {
                SpotThumbnail(spot: spot)
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(spot.displayName).font(.body.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                    HStack(spacing: 6) {
                        Text(spot.city ?? spot.category.title).lineLimit(1)
                        if let n = dayNumber(of: spot) {
                            Text("On Day \(n)").font(.caption2.weight(.bold)).foregroundStyle(Theme.lagoon)
                        }
                        if spot.sources.contains(where: { $0.platform == .tiktok }) {
                            Image(systemName: SourcePlatform.tiktok.systemImage).font(.caption2)
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: index != nil ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(index != nil ? Theme.lagoon : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ spot: Spot) {
        if let i = picked.firstIndex(of: spot.objectID) {
            picked.remove(at: i)
        } else {
            picked.append(spot.objectID)
            if let c = spot.coordinate, picked.count == 1 {
                withAnimation { camera = .region(MKCoordinateRegion(center: c, latitudinalMeters: 4_000, longitudinalMeters: 4_000)) }
            }
        }
    }

    private func add() {
        let chosen = picked.compactMap { id in spots.first { $0.objectID == id } ?? trip.confirmedSpots.first { $0.objectID == id } }
        let existing = day.sortedItems
        let start = existing.last { $0.coordinate != nil }?.coordinate
        let stops = chosen.compactMap { spot -> AutoPlanner.Stop? in
            guard let c = spot.coordinate, let id = spot.uuid else { return nil }
            return AutoPlanner.Stop(id: id, name: spot.displayName, coordinate: c, category: spot.category)
        }
        let ordered = AutoPlanner.shortestRoute(stops, from: start).compactMap { stop in chosen.first { $0.uuid == stop.id } }

        // Times: after the last timed item on the day (plus its duration), else 10:00.
        let date = day.date ?? .now
        let lastEnd = existing.compactMap { item in item.time.map { $0.addingTimeInterval(TimeInterval(max(item.durationMinutes, 60) * 60)) } }.max()
        var clock = lastEnd ?? Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: date) ?? date
        var previous = start

        let store = ItineraryStore(context: context)
        for spot in ordered {
            if let p = previous, let c = spot.coordinate { clock = clock.addingTimeInterval(AutoPlanner.travelSeconds(from: p, to: c)) }
            clock = ScheduleMath.roundedUpToFiveMinutes(clock)
            let item = store.addItem(title: spot.displayName, category: AutoPlanView.itemCategory(spot.category), to: day, in: trip,
                                     address: spot.address ?? "", coordinate: spot.coordinate, notes: AutoPlanView.notes(for: spot))
            item.link = spot.sources.first?.urlString ?? ""
            let minutes = AutoPlanner.duration(for: spot.category)
            item.time = clock
            item.durationMinutes = Int64(minutes)
            clock = clock.addingTimeInterval(TimeInterval(minutes * 60))
            previous = spot.coordinate
        }
        store.save()
        Task { await DayReminders.reschedule(for: trip) }
        dismiss()
    }
}
