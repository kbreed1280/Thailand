import CoreData
#if canImport(FoundationModels)
import FoundationModels
#endif
import MapKit
import SwiftUI

/// Builds day plans from your saved spots: nearby spots share a day, each day is ordered
/// around the heat, and (optionally) gaps are filled with ideas that fit the trip's vibe.
/// Describe your perfect trip and it also finds places for you (Apple Intelligence turns the
/// wishes into Apple Maps searches on supported iPhones), so it can build a trip from nothing.
struct AutoPlanView: View {
    /// A place the planner found for you (not one of your saved spots).
    struct Suggestion {
        var name: String
        var coordinate: CLLocationCoordinate2D
        var address: String
        var url: URL?
        var reason: String
    }

    @ObservedObject var trip: Trip
    /// Plan just this list (from a list's screen); nil = all saved spots.
    var collection: SpotCollection?

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var forecast = TripForecast.shared

    @State private var destination = ""
    @State private var vibe: AutoPlanner.Vibe = .foodie
    @State private var pace: AutoPlanner.Pace = .balanced
    @State private var onlyEmptyDays = true
    @State private var fillGaps = true
    @State private var plan: AutoPlanner.Plan?
    @State private var suggestions: [UUID: Suggestion] = [:]
    @State private var planning = false
    @State private var wishes = ""
    @State private var usedAI = false
    @State private var planError: String?

    private var spots: [Spot] {
        let all = collection?.spots ?? trip.confirmedSpots
        let planned = trip.sortedDays.flatMap(\.sortedItems)
        return all.filter { spot in
            spot.coordinate != nil && spot.category != .stay && !planned.contains { Self.same($0, spot) }
        }
    }

    private var days: [Day] {
        trip.sortedDays.filter { $0.date != nil && (!onlyEmptyDays || $0.sortedItems.isEmpty) }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let plan {
                    preview(plan)
                } else {
                    setup
                }
            }
            .navigationTitle(plan == nil ? "Plan my trip" : "Your plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if plan == nil { Button("Cancel") { dismiss() } } else { Button("Back") { plan = nil } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if let plan {
                        Button("Add to trip") { apply(plan) }.disabled(plan.days.allSatisfy(\.stops.isEmpty))
                    } else {
                        Button("Plan") { Task { await makePlan() } }.disabled(!canPlan || planning)
                    }
                }
            }
            .overlay { if planning { ProgressView("Planning…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
            .onAppear {
                destination = trip.destination ?? ""
                vibe = AutoPlanner.Vibe(rawValue: trip.vibe ?? "") ?? .foodie
            }
            .task {
                await forecast.refresh(trip)
                #if DEBUG
                // Debug-only: `-debugAutoRunPlan YES` presses Plan, for screenshots.
                if UserDefaults.standard.bool(forKey: "debugAutoRunPlan") { await makePlan() }
                #endif
            }
        }
    }

    /// Plan saved spots, or (with wishes or a known destination) build days from scratch.
    private var canPlan: Bool {
        !days.isEmpty && (!spots.isEmpty || !wishes.trimmingCharacters(in: .whitespaces).isEmpty || trip.destinationCoordinate != nil)
    }

    // MARK: Setup

    @ViewBuilder private var setup: some View {
        Section {
            TextField("e.g. ramen, jazz bars, art museums, a sunset viewpoint, no early mornings", text: $wishes, axis: .vertical)
                .lineLimit(2...5)
        } header: {
            Label("Describe your perfect trip", systemImage: "sparkles")
        } footer: {
            Text(Self.aiAvailable
                 ? "Apple Intelligence turns this into real places near your destination, then plans them around your saved spots."
                 : "We'll search for these near your destination and plan them around your saved spots.")
        }
        if let planError {
            Section { Label(planError, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
        }
        Section {
            TextField("Destination (e.g. Bangkok)", text: $destination)
            VStack(alignment: .leading, spacing: 8) {
                Text("Vibe").font(.subheadline.weight(.semibold))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(AutoPlanner.Vibe.allCases) { v in
                            Button { vibe = v } label: {
                                Text("\(v.emoji) \(v.title)")
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(vibe == v ? Theme.mango : Color.secondary.opacity(0.12), in: Capsule())
                                    .foregroundStyle(vibe == v ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Picker("Pace", selection: $pace) {
                ForEach(AutoPlanner.Pace.allCases) { Text("\($0.title) (\($0.stopsPerDay)/day)").tag($0) }
            }
        } header: {
            Text("Trip")
        }

        Section {
            LabeledContent("Spots to plan", value: "\(spots.count)")
            LabeledContent("Days", value: "\(days.count)")
            Toggle("Only days with nothing planned", isOn: $onlyEmptyDays)
            Toggle("Fill gaps with ideas for my vibe", isOn: $fillGaps)
        } footer: {
            if spots.isEmpty && wishes.isEmpty {
                Text("No saved spots to plan yet, so we'll fill your days with popular places for your vibe. Or describe what you'd love above.")
            } else if days.isEmpty {
                Text("No free days. Turn off \"Only days with nothing planned\" to add to days that already have plans.")
            } else {
                Text("Nearby spots go on the same day. Coffee and temples go in the morning before the heat, malls and spas go in the midday heat, and rooftops and night markets go after sunset. Spots already on a day are skipped.")
            }
        }
    }

    // MARK: Preview

    @ViewBuilder private func preview(_ plan: AutoPlanner.Plan) -> some View {
        if usedAI {
            Section { Label("Built with Apple Intelligence from your wishes", systemImage: "sparkles").foregroundStyle(Theme.lagoon) }
        }
        ForEach(Array(plan.days.enumerated()), id: \.offset) { _, day in
            Section {
                if day.stops.isEmpty {
                    Text("Free day").foregroundStyle(.secondary)
                }
                ForEach(day.stops) { planned in
                    HStack(spacing: 12) {
                        Text(planned.start.formatted(date: .omitted, time: .shortened))
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .frame(width: 64, alignment: .leading)
                        Image(systemName: planned.stop.category.systemImage)
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(planned.stop.category.color, in: Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(planned.stop.name).font(.subheadline.weight(.semibold))
                            if planned.stop.isSuggestion {
                                Text(suggestions[planned.stop.id]?.reason ?? "Suggested for \(vibe.title.lowercased())")
                                    .font(.caption2).foregroundStyle(Theme.lagoon)
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text(day.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    Spacer()
                    if let w = forecast.day(day.date, in: trip) {
                        Label("\(Temperature.deg(w.highC))", systemImage: w.symbolName)
                            .foregroundStyle(w.heatLevel.color)
                    }
                }
            }
        }
        if !plan.leftOver.isEmpty {
            Section {
                ForEach(plan.leftOver) { Text($0.name) }
            } header: {
                Text("Didn't fit at this pace")
            } footer: {
                Text("Try a faster pace, or plan these on days that already have plans.")
            }
        }
    }

    // MARK: Planning

    private func makePlan() async {
        planning = true
        defer { planning = false }
        trip.destination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        trip.vibe = vibe.rawValue
        ItineraryStore(context: context).save()
        await forecast.refresh(trip)

        let stops = spots.compactMap { spot -> AutoPlanner.Stop? in
            guard let c = spot.coordinate, let id = spot.uuid else { return nil }
            return AutoPlanner.Stop(id: id, name: spot.displayName, coordinate: c, category: spot.category)
        }
        planError = nil
        usedAI = false
        let ideaStops = await ideas(room: max(0, days.count * pace.stopsPerDay - stops.count), excluding: Set(stops.map { $0.name.localizedLowercase }))
        let hot = forecast.hotDays(in: trip)
        var result = AutoPlanner.plan(stops + ideaStops, dates: days.compactMap(\.date), pace: pace, hotDays: hot)
        if fillGaps { result = await fill(result, hot: hot) }
        plan = result
    }

    /// Places matching your wishes (or your vibe when there's nothing to plan yet) near the destination.
    private func ideas(room: Int, excluding used: Set<String>) async -> [AutoPlanner.Stop] {
        let wish = wishes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard room > 0, !wish.isEmpty || spots.isEmpty else { return [] }
        var center = trip.destinationCoordinate
        if center == nil, let found = await Destinations.find(destination) {
            center = CLLocationCoordinate2D(latitude: found.latitude, longitude: found.longitude)
        }
        guard let center else {
            planError = "Add where you're going (Edit Trip → Where to?) so we can find places there."
            return []
        }
        let (searches, ai) = await DestinationIdeas.searches(for: wish, destination: destination, vibe: vibe)
        usedAI = ai
        let found = await DestinationIdeas.find(searches.map { ($0, nil) }, around: center, perQuery: 2)
        var out: [AutoPlanner.Stop] = []
        for idea in found where out.count < room && idea.category != .stay {
            guard !used.contains(idea.name.localizedLowercase) else { continue }
            let id = UUID()
            let reason = wish.isEmpty ? "Popular for \(vibe.title.lowercased())" : "Matches your wishes"
            suggestions[id] = Suggestion(name: idea.name, coordinate: idea.coordinate, address: idea.address, url: idea.url, reason: reason)
            out.append(AutoPlanner.Stop(id: id, name: idea.name, coordinate: idea.coordinate, category: idea.category, isSuggestion: true))
        }
        if out.isEmpty && !wish.isEmpty { planError = "Couldn't find places for that near your destination. Try different words." }
        return out
    }

    /// Adds one Apple Maps place per gap, near the middle of that day's spots.
    private func fill(_ plan: AutoPlanner.Plan, hot: Set<Date>) async -> AutoPlanner.Plan {
        var plan = plan
        var used = Set(plan.days.flatMap(\.stops).map(\.stop.name.localizedLowercase))
        for i in plan.days.indices where !plan.days[i].gaps.isEmpty && !plan.days[i].stops.isEmpty {
            let center = AutoPlanner.centroid(plan.days[i].stops.map(\.stop))
            var stops = plan.days[i].stops.map(\.stop)
            for gap in plan.days[i].gaps {
                let queries = gap == .eat ? (vibe == .foodie ? vibe.fillQueries : ["local restaurant", "street food"]) : vibe.fillQueries
                guard let item = await search(queries, near: center, excluding: used),
                      let name = item.name else { continue }
                let id = UUID()
                suggestions[id] = Suggestion(name: name, coordinate: item.placemark.coordinate, address: item.placemark.title ?? "",
                                             url: item.url, reason: "Suggested for \(vibe.title.lowercased())")
                used.insert(name.localizedLowercase)
                let category = gap == .eat ? SpotCategory.eat : SpotCategory(poi: item.pointOfInterestCategory)
                stops.append(AutoPlanner.Stop(id: id, name: name, coordinate: item.placemark.coordinate, category: category, isSuggestion: true))
            }
            let date = plan.days[i].date
            let isHot = hot.contains { Calendar.current.isDate($0, inSameDayAs: date) }
            plan.days[i].stops = AutoPlanner.schedule(AutoPlanner.order(stops, hot: isHot), on: date, hot: isHot, calendar: .current)
            plan.days[i].gaps = []
        }
        return plan
    }

    private func search(_ queries: [String], near center: CLLocationCoordinate2D, excluding used: Set<String>) async -> MKMapItem? {
        for query in queries {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.resultTypes = .pointOfInterest
            request.region = MKCoordinateRegion(center: center, latitudinalMeters: 2_000, longitudinalMeters: 2_000)
            guard let items = try? await MKLocalSearch(request: request).start().mapItems else { continue }
            let here = CLLocation(latitude: center.latitude, longitude: center.longitude)
            if let hit = items.first(where: { item in
                guard let name = item.name, !used.contains(name.localizedLowercase) else { return false }
                return (item.placemark.location?.distance(from: here) ?? .infinity) < 2_500
            }) { return hit }
        }
        return nil
    }

    // MARK: Apply

    private func apply(_ plan: AutoPlanner.Plan) {
        let store = ItineraryStore(context: context)
        let byID = Dictionary(spots.compactMap { s in s.uuid.map { ($0, s) } }, uniquingKeysWith: { a, _ in a })
        for dayPlan in plan.days {
            guard let day = trip.sortedDays.first(where: { $0.date.map { Calendar.current.isDate($0, inSameDayAs: dayPlan.date) } ?? false }) else { continue }
            for planned in dayPlan.stops {
                let item: Item
                if let spot = byID[planned.stop.id] {
                    item = store.addItem(title: spot.displayName, category: Self.itemCategory(spot.category), to: day, in: trip,
                                         address: spot.address ?? "", coordinate: spot.coordinate,
                                         notes: Self.notes(for: spot))
                    item.link = spot.sources.first?.urlString ?? ""
                } else if let suggestion = suggestions[planned.stop.id] {
                    item = store.addItem(title: planned.stop.name, category: Self.itemCategory(planned.stop.category), to: day, in: trip,
                                         address: suggestion.address, coordinate: suggestion.coordinate,
                                         notes: "\(suggestion.reason) (Plan my trip)")
                    item.link = suggestion.url?.absoluteString ?? ""
                } else { continue }
                item.time = planned.start
                item.durationMinutes = Int64(planned.durationMinutes)
            }
        }
        store.save()
        Task { await DayReminders.reschedule(for: trip) }
        dismiss()
    }

    /// Whether this iPhone can run Apple Intelligence (iOS 26+, supported device, turned on).
    static var aiAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), case .available = SystemLanguageModel.default.availability { return true }
        #endif
        return false
    }

    static func itemCategory(_ c: SpotCategory) -> ItemCategory {
        switch c {
        case .eat, .brew: .meal
        case .explore: .place
        case .vibe, .sip: .activity
        case .go: .activity
        case .stay: .hotel
        }
    }

    static func notes(for spot: Spot) -> String {
        var lines: [String] = []
        for scoop in spot.sortedScoops {
            if let r = scoop.recommendation, !r.isEmpty { lines.append(r) }
            if let o = scoop.whatToOrder, !o.isEmpty { lines.append("Order: \(o)") }
        }
        if let n = spot.notes, !n.isEmpty { lines.append(n) }
        return lines.joined(separator: "\n")
    }

    /// Whether an itinerary item is this spot (same name, or within 60 m with a similar name).
    static func same(_ item: Item, _ spot: Spot) -> Bool {
        if item.displayTitle.localizedCaseInsensitiveCompare(spot.displayName) == .orderedSame { return true }
        guard let a = item.coordinate, let b = spot.coordinate else { return false }
        return AutoPlanner.distance(a, b) < 60 && NameMatch.similarity(item.displayTitle, spot.displayName) >= 0.5
    }
}

// MARK: - "Add to Day" (spot detail)

struct AddToDayMenu: View {
    @ObservedObject var spot: Spot
    @Environment(\.managedObjectContext) private var context
    @State private var added: String?

    var body: some View {
        if let trip = spot.trip, !trip.sortedDays.isEmpty {
            let onDay = trip.sortedDays.first { $0.sortedItems.contains { AutoPlanView.same($0, spot) } }
            Menu {
                ForEach(trip.sortedDays) { day in
                    Button {
                        let item = ItineraryStore(context: context).addItem(
                            title: spot.displayName, category: AutoPlanView.itemCategory(spot.category), to: day, in: trip,
                            address: spot.address ?? "", coordinate: spot.coordinate, notes: AutoPlanView.notes(for: spot))
                        item.link = spot.sources.first?.urlString ?? ""
                        item.durationMinutes = Int64(AutoPlanner.duration(for: spot.category))
                        ItineraryStore(context: context).save()
                        added = "Day \(day.number)"
                    } label: {
                        Text("Day \(day.number)" + (day.date.map { " · " + $0.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) } ?? ""))
                    }
                }
            } label: {
                if let onDay {
                    Label("On Day \(onDay.number)", systemImage: "calendar.badge.checkmark")
                } else {
                    Label(added.map { "Added to \($0)" } ?? "Add to Day", systemImage: "calendar.badge.plus")
                }
            }
        }
    }
}
