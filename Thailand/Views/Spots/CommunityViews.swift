import CoreData
import MapKit
import SwiftUI

/// Places several WanderHub travelers saved near a city, with tips only where sources agree.
struct TrendingNearbyView: View {
    @ObservedObject var trip: Trip
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var community = CommunityService.shared
    @AppStorage(CommunityService.enabledKey) private var enabled = false

    @State private var cityName = WeatherPlace.cities[0].name
    @State private var places: [CommunityPlace] = []
    @State private var loading = false
    @State private var saved: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("City", selection: $cityName) {
                        ForEach(WeatherPlace.cities) { Text($0.name).tag($0.name) }
                    }
                } footer: {
                    Text("Places at least \(CommunityAggregator.agreement) travelers or posts saved independently. \(enabled ? "" : "Turn on community sharing in Profile to add your spots.")")
                }
                ForEach(places) { place in
                    Section {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: place.category.systemImage).foregroundStyle(.white)
                                .frame(width: 32, height: 32).background(place.category.color, in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text(place.name).font(.headline)
                                Label("Saved by \(place.sourceCount) sources", systemImage: "flame.fill")
                                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.mango)
                                CommunityConsensusText(place: place)
                            }
                            Spacer()
                            if saved.contains(place.placeKey) || trip.allSpots.contains(where: { s in
                                s.coordinate.map { CommunityAggregator.placeKey(name: s.displayName, appleMapsID: s.appleMapsID, coordinate: $0) == place.placeKey } ?? false
                            }) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title3)
                            } else {
                                Button { save(place) } label: { Image(systemName: "plus.circle").font(.title3) }.buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
            .overlay {
                if loading { ProgressView() }
                else if places.isEmpty {
                    ContentUnavailableView("Nothing trending yet", systemImage: "flame",
                                           description: Text(community.lastError ?? "As more travelers share spots in \(cityName), the popular ones show up here."))
                }
            }
            .navigationTitle("Trending nearby")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .task(id: cityName) { await load() }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        let center = (WeatherPlace.cities.first { $0.name == cityName } ?? WeatherPlace.cities[0]).location.coordinate
        places = await community.trending(near: center)
    }

    private func save(_ place: CommunityPlace) {
        let tips = place.agreedOrders.isEmpty ? [] : [SharedCollection.Tip(recommendation: place.agreedTip ?? "", whatToOrder: place.agreedOrders.joined(separator: ", "),
                                                                             whyItMatters: "Community pick (\(place.sourceCount) sources)", sourceURL: "", creator: "")]
        let shared = SharedCollection.SharedSpot(name: place.name, address: "", city: place.city,
                                                 latitude: place.coordinate.latitude, longitude: place.coordinate.longitude,
                                                 category: place.category.rawValue, appleMapsID: place.placeKey.hasPrefix("apple:") ? String(place.placeKey.dropFirst(6)) : "",
                                                 note: "", tips: tips)
        CollectionImporter.save(shared, into: nil, trip: trip, context: context)
        ItineraryStore(context: context).save()
        saved.insert(place.placeKey)
    }
}

struct CommunityConsensusText: View {
    let place: CommunityPlace

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !place.agreedOrders.isEmpty {
                Text("Order: \(place.agreedOrders.prefix(3).joined(separator: ", "))").font(.caption)
            }
            if let tip = place.agreedTip { Text("“\(tip)”").font(.caption).italic() }
            if !place.credits.isEmpty {
                Text("Via \(place.credits.prefix(4).joined(separator: ", "))").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

/// "Community says" on a spot, only when enough independent sources agree.
struct SpotCommunitySection: View {
    let spot: Spot
    @State private var place: CommunityPlace?

    var body: some View {
        Group {
            if let place {
                Section {
                    CommunityConsensusText(place: place)
                } header: {
                    Label("Community · \(place.sourceCount) sources", systemImage: "person.3.fill")
                }
            }
        }
        .task { place = await CommunityService.shared.consensus(for: spot) }
    }
}
