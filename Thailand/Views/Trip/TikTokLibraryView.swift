import CoreData
import MapKit
import SwiftUI

/// Videos shared from TikTok (Share → WanderHub), grouped by area of Thailand and pinned on a map.
/// Each one is a wish-list item on the trip, so your travel partner sees them too.
struct TikTokLibraryView: View {
    @ObservedObject var trip: Trip
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var inbox: [SharedLink] = SharedInbox.load()
    @State private var placing: SharedLink?
    @State private var showMap = false
    @State private var refreshTick = 0
    @State private var walkTarget: WalkTarget?
    @State private var selectedPin: Item?

    private var videos: [Item] {
        _ = refreshTick
        return TravelVideos.saved(in: trip)
    }

    var body: some View {
        NavigationStack {
            Group {
                if showMap { mapView } else { listView }
            }
            .navigationTitle("TikTok")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $showMap) {
                        Text("By area").tag(false)
                        Text("Map").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
                ToolbarItem(placement: .primaryAction) {
                    // PasteButton reads the clipboard without the "Allow Paste" prompt.
                    PasteButton(payloadType: String.self) { strings in
                        guard let text = strings.first, let url = SharedInbox.firstURL(in: text) else { return }
                        Task { @MainActor in
                            SharedInbox.append(url: url, text: text)
                            reloadInbox()
                            placing = inbox.first { $0.url == url }
                        }
                    }
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.circle)
                }
            }
            .sheet(item: $placing, onDismiss: reloadInbox) { link in
                PlaceVideoSheet(link: link, trip: trip) {
                    SharedInbox.remove(link.id)
                    refreshTick &+= 1
                }
            }
            .fullScreenCover(item: $walkTarget) { target in
                WalkingRouteView(destinationName: target.name, coordinate: target.coordinate)
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { reloadInbox() } }
            .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: context)) { _ in
                refreshTick &+= 1
            }
        }
    }

    private func reloadInbox() { inbox = SharedInbox.load() }

    // MARK: List

    private var listView: some View {
        List {
            if !inbox.isEmpty {
                Section {
                    ForEach(inbox) { link in
                        Button { placing = link } label: {
                            InboxRow(link: link)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Discard", role: .destructive) {
                                SharedInbox.remove(link.id)
                                reloadInbox()
                            }
                        }
                    }
                } header: {
                    Text("New · tap to place on your map")
                }
            }

            let grouped = Dictionary(grouping: videos, by: TravelVideos.area(of:))
            ForEach(areaOrder(grouped.keys), id: \.self) { area in
                Section("\(area) · \(grouped[area]?.count ?? 0)") {
                    ForEach(grouped[area] ?? []) { item in
                        VideoRow(item: item) { if let url = item.link.flatMap(URL.init(string:)) { openURL(url) } }
                            .swipeActions {
                                Button("Delete", role: .destructive) {
                                    context.delete(item)
                                    ItineraryStore(context: context).save()
                                }
                                if let c = item.coordinate {
                                    Button("Walk") { walkTarget = WalkTarget(name: item.title ?? "", coordinate: c) }
                                        .tint(Theme.mango)
                                }
                            }
                    }
                }
            }
        }
        .overlay {
            if videos.isEmpty && inbox.isEmpty {
                ContentUnavailableView {
                    Label("No TikToks yet", systemImage: "play.rectangle.on.rectangle")
                } description: {
                    Text("In TikTok, tap Share → More (…) → WanderHub. Or copy a TikTok link and tap the paste button above.\n\nEach video is saved to your trip's Wish List under its area, and pinned on the map when it's about a specific place.")
                }
            }
        }
    }

    /// Areas in the app's north-to-south order, "Elsewhere" last.
    private func areaOrder(_ names: Dictionary<String, [Item]>.Keys) -> [String] {
        let order = TravelArea.all.map(\.name)
        return names.sorted { (order.firstIndex(of: $0) ?? 999) < (order.firstIndex(of: $1) ?? 999) }
    }

    // MARK: Map

    private var mapView: some View {
        let pinned = videos.filter { $0.coordinate != nil }
        return Map(selection: $selectedPin) {
            UserAnnotation()
            ForEach(pinned) { item in
                if let c = item.coordinate {
                    Annotation(item.title ?? "", coordinate: c, anchor: .bottom) {
                        Image(systemName: "play.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.black, in: Circle())
                            .overlay(Circle().stroke(Color(hex: "#FE2C55"), lineWidth: 2.5))
                            .shadow(radius: 2)
                    }
                    .tag(item)
                }
            }
        }
        .mapControls { MapUserLocationButton() }
        .safeAreaInset(edge: .bottom) {
            if let item = selectedPin {
                VStack(alignment: .leading, spacing: 10) {
                    VideoRow(item: item) { if let url = item.link.flatMap(URL.init(string:)) { openURL(url) } }
                    HStack {
                        Button {
                            if let url = item.link.flatMap(URL.init(string:)) { openURL(url) }
                        } label: { Label("Watch", systemImage: "play.fill").frame(maxWidth: .infinity) }
                            .buttonStyle(.borderedProminent).tint(.black)
                        if let c = item.coordinate {
                            Button {
                                walkTarget = WalkTarget(name: item.title ?? "", coordinate: c)
                            } label: { Label("Walk There", systemImage: "figure.walk").frame(maxWidth: .infinity) }
                                .buttonStyle(.bordered)
                        }
                    }
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                .padding(.horizontal)
            } else if pinned.isEmpty {
                Text("Videos about a specific place show up here as pins.")
                    .font(.subheadline)
                    .padding(12)
                    .background(.regularMaterial, in: Capsule())
            }
        }
    }
}

// MARK: - Rows

/// Thumbnail + caption + creator, loaded from the video link.
private struct VideoThumb: View {
    let url: URL?
    @State private var info: VideoInfo?

    var body: some View {
        AsyncImage(url: info?.thumbnailURL) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            ZStack {
                Color.black
                Image(systemName: "play.fill").foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(width: 54, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "play.circle.fill").font(.caption).foregroundStyle(.white).padding(3)
        }
        .task(id: url) { if let url { info = await TravelVideos.info(for: url) } }
    }
}

private struct VideoRow: View {
    @ObservedObject var item: Item
    let onWatch: () -> Void

    var body: some View {
        Button(action: onWatch) {
            HStack(spacing: 12) {
                VideoThumb(url: item.link.flatMap(URL.init(string:)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title ?? "Video").font(.subheadline.weight(.semibold)).lineLimit(2)
                    let lines = (item.notes ?? "").split(separator: "\n")
                    if let first = lines.first { Text(first).font(.caption).foregroundStyle(.secondary) }
                    if item.coordinate != nil {
                        Label("On the map", systemImage: "mappin").font(.caption2).foregroundStyle(Theme.lagoon)
                    }
                }
                Spacer()
                Image(systemName: "play.fill").foregroundStyle(Color(hex: "#FE2C55"))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Watch \(item.title ?? "video") on TikTok")
    }
}

private struct InboxRow: View {
    let link: SharedLink
    @State private var info: VideoInfo?

    var body: some View {
        HStack(spacing: 12) {
            VideoThumb(url: link.url)
            VStack(alignment: .leading, spacing: 3) {
                Text(info?.title.isEmpty == false ? info!.title : link.url.absoluteString)
                    .font(.subheadline).lineLimit(2)
                Text("Shared \(link.sharedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("Place").font(.caption.weight(.semibold)).foregroundStyle(Theme.mango)
        }
        .task { info = await TravelVideos.info(for: link.url) }
    }
}

// MARK: - Place a video

/// Suggests where the video is (from its caption) and lets you pick a place or just an area.
struct PlaceVideoSheet: View {
    let link: SharedLink
    @ObservedObject var trip: Trip
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @Environment(\.openURL) private var openURL

    @State private var info: VideoInfo?
    @State private var area: String = TravelArea.elsewhere
    @State private var suggestions: [MKMapItem] = []
    @State private var searchText = ""
    @State private var searching = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        VideoThumb(url: link.url)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(info?.title.isEmpty == false ? info!.title : "TikTok video")
                                .font(.subheadline).lineLimit(5)
                            if let author = info?.author { Text(author).font(.caption).foregroundStyle(.secondary) }
                            Button("Watch", systemImage: "play.fill") { openURL(info?.canonicalURL ?? link.url) }
                                .font(.caption.weight(.semibold))
                        }
                    }
                }

                Section {
                    Picker("Area", selection: $area) {
                        ForEach(TravelArea.all) { Text($0.name).tag($0.name) }
                        Text(TravelArea.elsewhere).tag(TravelArea.elsewhere)
                    }
                    Button {
                        save(place: nil)
                    } label: {
                        Label("Save under \(area) (no specific place)", systemImage: "folder.fill")
                    }
                } header: {
                    Text("What area is it about?")
                } footer: {
                    Text("For videos like \"10 things to do in Chiang Mai\".")
                }

                Section {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search for the place in the video", text: $searchText)
                            .onSubmit { Task { await search(searchText) } }
                        if searching { ProgressView() }
                    }
                    ForEach(suggestions, id: \.self) { item in
                        Button { save(place: item) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name ?? "Place").font(.subheadline.weight(.semibold))
                                Text(item.placemark.title ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    if suggestions.isEmpty && !searching {
                        Text("No match from the caption. Search above for the place name.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Or pin it to a specific place")
                }
            }
            .navigationTitle("Place this video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Later") { dismiss() } }
            }
            .task { await prepare() }
            .onChange(of: area) { _, _ in Task { await search(searchText.isEmpty ? (info?.title ?? "") : searchText) } }
        }
    }

    private func prepare() async {
        info = await TravelVideos.info(for: link.url)
        let text = [info?.title, link.text].compactMap { $0 }.joined(separator: " ")
        if let detected = TravelArea.detect(in: text) { area = detected.name }
        await search(info?.title ?? link.text ?? "")
    }

    private func search(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { suggestions = []; return }
        searching = true
        defer { searching = false }
        suggestions = await TravelVideos.suggestPlaces(for: text, area: TravelArea.named(area))
    }

    private func save(place: MKMapItem?) {
        var areaName = area
        if let place, areaName == TravelArea.elsewhere, let nearest = TravelArea.nearest(to: place.placemark.coordinate) {
            areaName = nearest.name
        }
        TravelVideos.save(link: link.url, info: info, place: place, area: areaName, to: trip, context: context)
        onSaved()
        dismiss()
    }
}
