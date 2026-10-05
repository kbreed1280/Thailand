import CoreData
import SwiftUI

/// Collections: your stats, lists, the posts you saved from (references) and cities with a
/// photo collage of their spots.
struct SpotCollectionsHome: View {
    @ObservedObject var trip: Trip
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var creating = false
    @State private var refreshTick = 0

    private var spots: [Spot] { _ = refreshTick; return trip.confirmedSpots }
    private var lists: [SpotCollection] { _ = refreshTick; return trip.sortedCollections }
    private var references: [SpotSource] {
        _ = refreshTick
        return trip.allSpotSources.filter { $0.url != nil && $0.status == .ready }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }
    private var cities: [(name: String, spots: [Spot])] {
        Dictionary(grouping: spots) { ($0.city ?? "").isEmpty ? "Other" : $0.city! }
            .map { ($0.key, $0.value) }
            .sorted { $0.spots.count > $1.spots.count }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    stats
                    Button { creating = true } label: {
                        Label("New Collection", systemImage: "plus")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(PlotStyle.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                            .overlay(Capsule().stroke(PlotStyle.ink, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)

                    if !lists.isEmpty {
                        section("Collections", count: lists.count) {
                            ForEach(lists) { list in
                                NavigationLink { CollectionDetailView(collection: list) } label: { listCard(list) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    if !references.isEmpty {
                        section("References", count: references.count) {
                            ForEach(references.prefix(20)) { source in
                                Button { if let url = source.url { openURL(url) } } label: { referenceCard(source) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    if !cities.isEmpty {
                        section("Cities", count: cities.count) {
                            ForEach(cities, id: \.name) { city in
                                NavigationLink { CitySpotsView(name: city.name, spots: city.spots) } label: { cityCard(city.name, city.spots) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding()
            }
            .background(PlotStyle.paper)
            .navigationTitle("Collections")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $creating) { CollectionEditor(trip: trip, collection: nil) }
            .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: context)) { _ in
                refreshTick &+= 1
            }
        }
        .fontDesign(.rounded)
    }

    // MARK: Pieces

    private var stats: some View {
        let visited = spots.filter(\.isVisited).count
        return HStack {
            stat("\(spots.count)", "spots")
            Divider().frame(height: 44)
            stat("\(cities.filter { $0.name != "Other" }.count)", "cities")
            Divider().frame(height: 44)
            stat(spots.isEmpty ? "0%" : "\(visited * 100 / spots.count)%", "visited")
        }
        .padding(.vertical, 20)
        .background(PlotStyle.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 40, weight: .semibold, design: .rounded)).foregroundStyle(PlotStyle.ink)
            Text(LocalizedStringKey(label)).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func section<Content: View>(_ title: String, count: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(LocalizedStringKey(title)).font(.title2.weight(.medium))
                Spacer()
                Text("\(count)").font(.headline).foregroundStyle(PlotStyle.ink)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) { content() }
                    .padding(.bottom, 8)
            }
            .scrollClipDisabled()
        }
    }

    private func listCard(_ list: SpotCollection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            collage(list.spots)
                .overlay(alignment: .topLeading) {
                    Text(list.emoji ?? "📍").font(.title2).padding(8)
                        .background(.regularMaterial, in: Circle()).padding(10)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(list.displayName).font(.headline).lineLimit(1)
                Text("\(list.spots.count) spots").font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(14)
        }
        .frame(width: 230)
        .background(PlotStyle.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
    }

    private func referenceCard(_ source: SpotSource) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let thumb = source.thumbnailURL.flatMap(URL.init(string:)) {
                    AsyncImage(url: thumb) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() } else { PlotStyle.chip }
                    }
                } else {
                    ZStack {
                        PlotStyle.chip
                        Image(systemName: source.platform.systemImage).font(.largeTitle).foregroundStyle(PlotStyle.ink)
                    }
                }
            }
            .frame(width: 180, height: 220)
            .clipped()
            VStack(alignment: .leading, spacing: 2) {
                Label {
                    Text(source.title ?? "Post").lineLimit(1)
                } icon: {
                    Image(systemName: source.platform.systemImage)
                }
                .font(.subheadline.weight(.medium))
                Text(source.creator ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(12)
        }
        .frame(width: 180)
        .background(PlotStyle.card)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
    }

    private func cityCard(_ name: String, _ spots: [Spot]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            collage(spots)
            VStack(alignment: .leading, spacing: 2) {
                Text("🇹🇭 \(name)").font(.title3.weight(.medium)).lineLimit(1)
                Text("\(spots.count) spots").font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(14)
        }
        .frame(width: 230)
        .background(PlotStyle.card)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
    }

    /// 2×2 grid of spot pictures.
    private func collage(_ spots: [Spot]) -> some View {
        let picks = Array(spots.prefix(4))
        return Grid(horizontalSpacing: 2, verticalSpacing: 2) {
            GridRow {
                tile(picks, 0)
                tile(picks, 1)
            }
            GridRow {
                tile(picks, 2)
                tile(picks, 3)
            }
        }
        .frame(width: 230, height: 230)
        .clipped()
    }

    @ViewBuilder private func tile(_ picks: [Spot], _ i: Int) -> some View {
        Group {
            if i < picks.count { SpotThumbnail(spot: picks[i]) } else { PlotStyle.chip }
        }
        .frame(width: 114, height: 114)
        .clipped()
    }
}

/// All spots in one city, as cards.
struct CitySpotsView: View {
    let name: String
    let spots: [Spot]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(spots) { spot in
                    NavigationLink { SpotDetailView(spot: spot) } label: {
                        SpotCard(spot: spot, distance: nil) {}
                            .allowsHitTesting(false)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .background(PlotStyle.paper)
        .navigationTitle(name)
    }
}
