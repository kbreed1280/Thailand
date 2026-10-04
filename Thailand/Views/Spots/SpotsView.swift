import CoreData
import MapKit
import PhotosUI
import SwiftUI

/// Save from anywhere: drafts imported from TikTok / Instagram / YouTube / Google Maps / web /
/// screenshots (grouped by post), saved spots by city, and folders for tip videos.
struct SpotsView: View {
    @ObservedObject var trip: Trip
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var pipeline = ImportPipeline.shared

    enum Tab: String, CaseIterable { case map = "Map", drafts = "Drafts", saved = "Saved", lists = "Lists" }
    @State private var tab: Tab = .map
    @State private var refreshTick = 0
    @State private var showingManualAdd = false
    @State private var screenshotItems: [PhotosPickerItem] = []
    @State private var readingScreenshots = false
    @State private var categoryFilter: SpotCategory?
    @State private var newFolderPrompt = false
    @State private var newFolderName = ""
    @State private var filing: SpotSource?
    @State private var showingAutoPlan = false
    @State private var showingSidequest = false
    @State private var showingTrending = false

    private var sources: [SpotSource] { _ = refreshTick; return trip.allSpotSources }
    private var draftSources: [SpotSource] {
        sources.filter { $0.status.isWorking || $0.status == .failed || !$0.draftSpots.isEmpty
            || ($0.status == .ready && $0.spots.isEmpty && ($0.folder ?? "").isEmpty) }
    }
    private var savedSpots: [Spot] { _ = refreshTick; return trip.confirmedSpots }
    private var folders: [String] {
        Array(Set(sources.compactMap { ($0.folder ?? "").isEmpty ? nil : $0.folder! } + TravelVideos.folders(in: trip))).sorted()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { t in
                        Text(t == .drafts && !draftSources.isEmpty ? "Drafts (\(draftSources.count))" : t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                switch tab {
                case .map: SpotsMapView(trip: trip, refreshTick: refreshTick)
                case .drafts: draftsList
                case .saved: savedList
                case .lists: SpotListsTab(trip: trip, refreshTick: refreshTick, folders: folders, sources: sources)
                }
            }
            .background(Theme.background)
            .navigationTitle("Spots")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { addMenu }
            }
            .task {
                // Open on Drafts when something new is waiting to be reviewed.
                if !SharedInbox.load().isEmpty || !trip.draftSpots.isEmpty { tab = .drafts }
                await refreshInbox()
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await refreshInbox() } } }
            .onChange(of: screenshotItems) { _, items in Task { await importScreenshots(items) } }
            .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: context)) { _ in
                refreshTick &+= 1
            }
            .sheet(isPresented: $showingAutoPlan) { AutoPlanView(trip: trip) }
            .fullScreenCover(isPresented: $showingSidequest) { SidequestView(trip: trip) }
            .sheet(isPresented: $showingTrending) { TrendingNearbyView(trip: trip) }
            .sheet(isPresented: $showingManualAdd) {
                SpotPlaceSearchSheet(title: "Add a spot", cityHint: nil) { item in addManual(item) }
            }
            .alert("New Folder", isPresented: $newFolderPrompt) {
                TextField("e.g. Tips, Scams to avoid", text: $newFolderName)
                Button("Create") {
                    let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    TravelVideos.createFolder(name)
                    if let filing { filing.folder = name; ItineraryStore(context: context).save() }
                    filing = nil
                    refreshTick &+= 1
                }
                Button("Cancel", role: .cancel) { filing = nil }
            }
        }
    }

    private var addMenu: some View {
        Menu {
            PasteButton(payloadType: String.self) { strings in
                guard let text = strings.first else { return }
                Task { @MainActor in
                    let url = SharedInbox.firstURL(in: text)
                    pipeline.addSource(url: url, text: url == nil ? text : nil, to: trip, context: context)
                    tab = .drafts
                    await pipeline.importPending(in: trip, context: context)
                }
            }
            Button("Search for a place", systemImage: "magnifyingglass") { showingManualAdd = true }
            Button("Auto-plan days", systemImage: "wand.and.sparkles") { showingAutoPlan = true }
            Button("Sidequest", systemImage: "dice") { showingSidequest = true }
            Button("Trending nearby", systemImage: "flame") { showingTrending = true }
            Divider()
            Button("New folder", systemImage: "folder.badge.plus") { newFolderName = ""; newFolderPrompt = true }
        } label: {
            Image(systemName: "plus.circle.fill").font(.title2)
        }
        .overlay(alignment: .topTrailing) { EmptyView() }
    }

    private func refreshInbox() async {
        await pipeline.processInbox(into: trip, context: context)
        refreshTick &+= 1
    }

    private func importScreenshots(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        readingScreenshots = true
        defer { readingScreenshots = false; screenshotItems = [] }
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { continue }
            let text = await ScreenshotText.recognize(image)
            if !text.isEmpty { pipeline.addSource(url: nil, text: text, to: trip, context: context) }
        }
        tab = .drafts
        await pipeline.importPending(in: trip, context: context)
    }

    private func addManual(_ item: MKMapItem) {
        let spot = Spot(context: context)
        spot.placeInSameStore(as: trip)
        spot.uuid = UUID()
        spot.status = .confirmed
        spot.addedBy = AppSettings.displayName
        spot.createdAt = .now
        spot.trip = trip
        spot.apply(item)
        ItineraryStore(context: context).save()
        tab = .saved
    }

    // MARK: Drafts

    private var draftsList: some View {
        List {
            Section {
                PhotosPicker(selection: $screenshotItems, maxSelectionCount: 10, matching: .screenshots) {
                    Label(readingScreenshots ? "Reading screenshots…" : "Add screenshots", systemImage: "text.viewfinder")
                }
                .disabled(readingScreenshots)
            } footer: {
                Text("In TikTok, Instagram, YouTube, Google Maps or Safari, tap Share → WanderHub. Places in the caption, description or on-screen text show up here as drafts to review.")
            }

            ForEach(draftSources) { source in
                Section {
                    SourceDraftCard(source: source, isWorking: pipeline.working.contains(source.objectID),
                                    onRetry: { Task { await pipeline.retry(source, context: context) } },
                                    onFile: { filing = source; newFolderName = ""; newFolderPrompt = true },
                                    folders: folders)
                }
            }
        }
        .overlay {
            if draftSources.isEmpty {
                ContentUnavailableView("No drafts", systemImage: "tray",
                                       description: Text("Share a TikTok, Reel, YouTube Short, Google Maps link or any web page to WanderHub, or tap + to paste a link."))
            }
        }
    }

    // MARK: Saved

    private var savedList: some View {
        let filtered = savedSpots.filter { categoryFilter == nil || $0.category == categoryFilter }
        let byCity = Dictionary(grouping: filtered) { ($0.city ?? "").isEmpty ? "Other" : $0.city! }
        return List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        CategoryChip(title: "All", systemImage: "square.grid.2x2", color: .secondary, selected: categoryFilter == nil) {
                            categoryFilter = nil
                        }
                        ForEach(SpotCategory.allCases) { c in
                            CategoryChip(title: c.title, systemImage: c.systemImage, color: c.color, selected: categoryFilter == c) {
                                categoryFilter = categoryFilter == c ? nil : c
                            }
                        }
                    }
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))

            ForEach(byCity.keys.sorted(), id: \.self) { city in
                Section("\(city) · \(byCity[city]?.count ?? 0)") {
                    ForEach(byCity[city] ?? []) { spot in
                        NavigationLink { SpotDetailView(spot: spot) } label: { SpotRow(spot: spot) }
                    }
                }
            }
        }
        .overlay {
            if savedSpots.isEmpty {
                ContentUnavailableView("No saved spots", systemImage: "mappin.slash",
                                       description: Text("Confirm drafts, or tap + → Search for a place."))
            }
        }
    }
}

// MARK: - Draft card (one source and its draft spots)

private struct SourceDraftCard: View {
    @ObservedObject var source: SpotSource
    let isWorking: Bool
    let onRetry: () -> Void
    let onFile: () -> Void
    let folders: [String]

    @Environment(\.managedObjectContext) private var context
    @State private var editing: Spot?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SourceHeader(source: source)

            if source.status.isWorking {
                ProgressView(value: source.status.progress) { Text(source.status.title).font(.caption) }
                    .tint(Theme.mango)
            } else if source.status == .failed {
                Label(source.errorMessage ?? "Couldn't import.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(Theme.coral)
                Button("Try again", systemImage: "arrow.clockwise", action: onRetry).font(.caption.weight(.semibold))
            } else if source.spots.isEmpty {
                Text(source.errorMessage ?? "No specific places found.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Menu {
                        ForEach(folders, id: \.self) { f in Button(f) { source.folder = f; save() } }
                        Button("New folder…", action: onFile)
                    } label: { Label("File in folder", systemImage: "folder") }
                    Spacer()
                    Button("Remove", role: .destructive) { context.delete(source); save() }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
            }

            let drafts = source.draftSpots
            ForEach(drafts) { spot in
                DraftSpotRow(spot: spot, scoop: spot.sortedScoops.first { $0.source == source },
                             onConfirm: { spot.status = .confirmed; spot.touch(); save() },
                             onEdit: { editing = spot },
                             onDelete: { delete(spot) })
            }
            if drafts.count > 1 {
                let plotted = drafts.filter { !$0.isUnplotted }
                Button {
                    plotted.forEach { $0.status = .confirmed; $0.touch() }
                    save()
                } label: {
                    Label("Confirm all \(plotted.count) pinned spots", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Theme.lagoon)
                .disabled(plotted.isEmpty)
            }
            let unplotted = drafts.filter(\.isUnplotted).count
            if unplotted > 0 {
                Label("\(unplotted) spot\(unplotted == 1 ? "" : "s") couldn't be found on the map. Tap Fix to search.", systemImage: "mappin.slash")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
        .sheet(item: $editing) { spot in NavigationStack { SpotEditor(spot: spot) } }
    }

    private func delete(_ spot: Spot) {
        for scoop in spot.sortedScoops where scoop.source == source { context.delete(scoop) }
        if spot.sortedScoops.filter({ $0.source != source }).isEmpty { context.delete(spot) }
        save()
    }

    private func save() { ItineraryStore(context: context).save() }
}

/// Thumbnail, title, creator and a Watch/Open link back to the post.
struct SourceHeader: View {
    @ObservedObject var source: SpotSource
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AsyncImage(url: URL(string: source.thumbnailURL ?? "")) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                ZStack {
                    Theme.insetBackground
                    Image(systemName: source.platform.systemImage).foregroundStyle(.secondary)
                }
            }
            .frame(width: 48, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(source.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(3)
                HStack(spacing: 4) {
                    Image(systemName: source.platform.systemImage)
                    Text([source.platform.title, source.creator ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                    if source.extractor == "apple-intelligence" {
                        Image(systemName: "apple.intelligence").help("Places found with Apple Intelligence")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                if let url = source.url {
                    Button(source.platform.isVideo ? "Watch" : "Open", systemImage: source.platform.isVideo ? "play.fill" : "safari") {
                        openURL(url)
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderless)
                }
            }
        }
    }
}

private struct DraftSpotRow: View {
    @ObservedObject var spot: Spot
    let scoop: SpotScoop?
    let onConfirm: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: spot.category.systemImage)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(spot.category.color, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(spot.displayName).font(.subheadline.weight(.semibold))
                if spot.isUnplotted {
                    Label("Not found on map", systemImage: "mappin.slash").font(.caption).foregroundStyle(.orange)
                } else {
                    Text(spot.address ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if let scoop, scoop.hasContent {
                    Text("💬 " + [scoop.recommendation, scoop.whatToOrder.map { $0.isEmpty ? "" : "Order: \($0)" }]
                        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                if spot.sortedScoops.count > 1 {
                    Label("Already in your spots, adding this post's tips", systemImage: "link").font(.caption2).foregroundStyle(Theme.lagoon)
                }
            }
            Spacer(minLength: 4)
            VStack(spacing: 6) {
                if spot.isUnplotted {
                    Button("Fix", action: onEdit).buttonStyle(.borderedProminent).tint(.orange).controlSize(.small)
                } else {
                    Button(action: onConfirm) { Image(systemName: "checkmark") }
                        .buttonStyle(.borderedProminent).tint(Theme.lagoon).controlSize(.small)
                        .accessibilityLabel("Confirm \(spot.displayName)")
                }
                HStack(spacing: 10) {
                    Button(action: onEdit) { Image(systemName: "pencil") }.accessibilityLabel("Edit")
                    Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }.accessibilityLabel("Delete")
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
    }
}

struct SpotRow: View {
    @ObservedObject var spot: Spot

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: spot.category.systemImage)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(spot.category.color, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(spot.displayName).font(.subheadline.weight(.semibold))
                    if spot.isFavorite { Image(systemName: "heart.fill").font(.caption2).foregroundStyle(Theme.coral) }
                }
                Text([spot.category.title, spot.sources.isEmpty ? nil : "\(spot.sources.count) post\(spot.sources.count == 1 ? "" : "s")"]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if spot.isVisited { Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.lagoon) }
        }
    }
}

struct CategoryChip: View {
    let title: String
    let systemImage: String
    let color: Color
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .foregroundStyle(selected ? .white : .primary)
                .background(selected ? color : Theme.cardBackground, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
