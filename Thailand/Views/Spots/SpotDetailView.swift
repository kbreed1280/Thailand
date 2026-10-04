import MapKit
import SwiftUI

/// A saved spot: map, Apple's place card (photos, hours, rating), inside scoop from each post,
/// notes, favorite / visited, report, and add to a day.
struct SpotDetailView: View {
    @ObservedObject var spot: Spot
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var placeCard: MKMapItem?
    @State private var loadingCard = false
    @State private var editing = false
    @State private var reporting = false
    @State private var fixing = false
    @State private var walkTarget: WalkTarget?
    @State private var notes = ""

    var body: some View {
        List {
            if let c = spot.coordinate {
                Section {
                    Map(initialPosition: .region(MKCoordinateRegion(center: c, latitudinalMeters: 600, longitudinalMeters: 600))) {
                        Marker(spot.displayName, systemImage: spot.category.systemImage, coordinate: c).tint(spot.category.color)
                    }
                    .frame(height: 170)
                    .listRowInsets(EdgeInsets())
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label(spot.category.title, systemImage: spot.category.systemImage)
                        .font(.caption.weight(.semibold)).foregroundStyle(spot.category.color)
                    Text(spot.displayName).font(.title3.bold())
                    if let address = spot.address, !address.isEmpty { Text(address).font(.subheadline).foregroundStyle(.secondary) }
                }
                if !(spot.appleMapsID ?? "").isEmpty {
                    Button {
                        Task { await showPlaceCard() }
                    } label: {
                        HStack {
                            Label("Photos, hours & reviews", systemImage: "photo.on.rectangle.angled")
                            if loadingCard { Spacer(); ProgressView() }
                        }
                    }
                }
                HStack {
                    Toggle(isOn: Binding(get: { spot.isFavorite }, set: { spot.isFavorite = $0; save() })) {
                        Label("Favorite", systemImage: spot.isFavorite ? "heart.fill" : "heart")
                    }
                    .toggleStyle(.button).tint(Theme.coral)
                    Toggle(isOn: Binding(get: { spot.isVisited }, set: { spot.isVisited = $0; save() })) {
                        Label(spot.isVisited ? "Visited" : "Mark visited", systemImage: "checkmark.seal")
                    }
                    .toggleStyle(.button).tint(Theme.lagoon)
                }
            }

            let scoops = spot.sortedScoops
            if !scoops.isEmpty {
                Section("Inside scoop") {
                    ForEach(scoops) { scoop in
                        VStack(alignment: .leading, spacing: 6) {
                            if let source = scoop.source { SourceHeader(source: source) }
                            if let r = scoop.recommendation, !r.isEmpty { Text("💬 \(r)").font(.subheadline) }
                            if let o = scoop.whatToOrder, !o.isEmpty { Text("🍽 Order: \(o)").font(.subheadline) }
                            if let w = scoop.whyItMatters, !w.isEmpty { Text("⭐️ \(w)").font(.subheadline) }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("Your notes") {
                TextField("Notes (best time to go, who recommended it…)", text: $notes, axis: .vertical)
                    .lineLimit(2...6)
                    .onSubmit { spot.notes = notes; save() }
            }

            Section {
                if let c = spot.coordinate {
                    Button("Walk there", systemImage: "figure.walk") { walkTarget = WalkTarget(name: spot.displayName, coordinate: c) }
                    Button("Directions in Google Maps", systemImage: "map") { ExternalApps.openGoogleMaps(stops: [c]) }
                }
                if let phone = spot.phone, !phone.isEmpty, let url = URL(string: "tel://\(phone.filter { $0.isNumber || $0 == "+" })") {
                    Button("Call", systemImage: "phone") { openURL(url) }
                }
                if let site = spot.website, let url = URL(string: site), !site.isEmpty {
                    Button("Website", systemImage: "safari") { openURL(url) }
                }
                Button("Add to Wish List", systemImage: "star") { addToWishList() }
                AddToDayMenu(spot: spot)
                AddToCollectionMenu(spot: spot)
            }

            Section {
                Button("Edit", systemImage: "pencil") { editing = true }
                Button("Report incorrect point", systemImage: "exclamationmark.bubble") { reporting = true }
                if let reason = spot.reportReason, !reason.isEmpty {
                    Text("Reported: \(reason)").font(.caption).foregroundStyle(.secondary)
                }
                Button("Delete spot", systemImage: "trash", role: .destructive) {
                    context.delete(spot)
                    save()
                    dismiss()
                }
            }
        }
        .navigationTitle(spot.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { notes = spot.notes ?? "" }
        .onDisappear { if notes != (spot.notes ?? "") { spot.notes = notes; save() } }
        .mapItemDetailSheet(item: $placeCard, displaysMap: false)
        .sheet(isPresented: $editing) { NavigationStack { SpotEditor(spot: spot) } }
        .sheet(isPresented: $fixing) {
            SpotPlaceSearchSheet(title: "Find the right place", initialQuery: spot.displayName, cityHint: spot.city) { item in
                spot.apply(item)
                save()
            }
        }
        .confirmationDialog("What's wrong?", isPresented: $reporting, titleVisibility: .visible) {
            ForEach(["Wrong location", "Wrong place (different business)", "Permanently closed", "Not in the post", "Duplicate"], id: \.self) { reason in
                Button(reason) { report(reason) }
            }
        } message: {
            Text("Fix it now. Your report is saved with the spot.")
        }
        .fullScreenCover(item: $walkTarget) { target in
            WalkingRouteView(destinationName: target.name, coordinate: target.coordinate)
        }
    }

    private func report(_ reason: String) {
        spot.reportReason = reason
        spot.touch()
        save()
        switch reason {
        case "Wrong location", "Wrong place (different business)": fixing = true
        case "Not in the post", "Duplicate":
            context.delete(spot); save(); dismiss()
        default: break
        }
    }

    /// Apple's place card shows photos, hours, ratings and more without the app storing them.
    private func showPlaceCard() async {
        guard let raw = spot.appleMapsID, let id = MKMapItem.Identifier(rawValue: raw) else { return }
        loadingCard = true
        defer { loadingCard = false }
        placeCard = try? await MKMapItemRequest(mapItemIdentifier: id).mapItem
    }

    private func addToWishList() {
        guard let trip = spot.trip else { return }
        let item = ItineraryStore(context: context).addItem(
            title: spot.displayName,
            category: spot.category == .eat || spot.category == .brew ? .meal : spot.category == .go ? .hotel : .place,
            to: nil, in: trip, address: spot.address ?? "", coordinate: spot.coordinate,
            notes: spot.sortedScoops.compactMap { $0.recommendation }.filter { !$0.isEmpty }.joined(separator: "\n"))
        item.link = spot.sources.first?.urlString ?? ""
        save()
    }

    private func save() { ItineraryStore(context: context).save() }
}

/// Edit name, category, notes; move the pin by searching.
struct SpotEditor: View {
    @ObservedObject var spot: Spot
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @State private var name = ""
    @State private var category: SpotCategory = .explore
    @State private var searching = false

    var body: some View {
        Form {
            Section("Spot") {
                TextField("Name", text: $name)
                Picker("Category", selection: $category) {
                    ForEach(SpotCategory.allCases) { c in Label(c.title, systemImage: c.systemImage).tag(c) }
                }
            }
            Section {
                if spot.isUnplotted {
                    Label("Not on the map yet", systemImage: "mappin.slash").foregroundStyle(.orange)
                } else {
                    Text(spot.address ?? "").font(.subheadline)
                }
                Button(spot.isUnplotted ? "Find it on the map" : "Change location", systemImage: "magnifyingglass") { searching = true }
            } header: {
                Text("Location")
            }
        }
        .navigationTitle("Edit Spot")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    spot.name = name
                    spot.category = category
                    spot.touch()
                    ItineraryStore(context: context).save()
                    dismiss()
                }
            }
        }
        .onAppear { name = spot.name ?? ""; category = spot.category }
        .sheet(isPresented: $searching) {
            SpotPlaceSearchSheet(title: "Find on map", initialQuery: name, cityHint: spot.city) { item in
                spot.apply(item)
                name = spot.name ?? name
                category = spot.category
            }
        }
    }
}

/// Apple Maps place search (manual add and fixing unplotted/incorrect spots).
struct SpotPlaceSearchSheet: View {
    let title: String
    var initialQuery: String = ""
    let cityHint: String?
    let onPick: (MKMapItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var searching = false
    @State private var area: TravelArea?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Near", selection: $area) {
                        Text("All of Thailand").tag(TravelArea?.none)
                        ForEach(TravelArea.all) { Text($0.name).tag(Optional($0)) }
                    }
                }
                Section {
                    if searching { ProgressView() }
                    ForEach(results, id: \.self) { item in
                        Button {
                            onPick(item)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name ?? "Place").font(.subheadline.weight(.semibold))
                                Text(item.placemark.title ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                    if results.isEmpty && !searching && !query.isEmpty {
                        Text("No matches. Try the name in English or the area.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Restaurant, temple, café…")
            .onSubmit(of: .search) { Task { await search() } }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task {
                query = initialQuery
                area = cityHint.flatMap { TravelArea.detect(in: $0) }
                if !query.isEmpty { await search() }
            }
            .onChange(of: area) { _, _ in Task { await search() } }
        }
    }

    private func search() async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        searching = true
        defer { searching = false }
        results = await AppleMapsLocator().search(query, near: area)
    }
}
