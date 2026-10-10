import MapKit
import SwiftUI

/// Money changers near you, closest first, with walking directions.
struct MoneyExchangeView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var rates = ExchangeRateStore.shared
    @ObservedObject private var location = LocationService.shared

    @State private var here: CLLocation?
    @State private var places: [MKMapItem] = []
    @State private var loading = true
    @State private var walkTarget: WalkTarget?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if loading {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if places.isEmpty {
                        Text(here == nil ? "Turn on location to find money changers near you." : "No money changers found within 5 km. Banks and airport counters also exchange money.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(places, id: \.self) { item in row(item) }
                } footer: {
                    if let rate = rates.table?.rate(local: rates.localCode, home: rates.homeCode) {
                        Text("Today's market rate: 1 \(rates.homeCode) = \(String(format: rate >= 100 ? "%.0f" : "%.2f", rate)) \(rates.localCode). A good changer's board is close to this; airports and hotels usually pay less.")
                    }
                }
            }
            .navigationTitle("Money Exchange")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task {
                await load()
                await rates.refreshIfNeeded()
            }
            .refreshable { await load() }
            .fullScreenCover(item: $walkTarget) { target in
                WalkingRouteView(destinationName: target.name, coordinate: target.coordinate)
            }
        }
    }

    private func row(_ item: MKMapItem) -> some View {
        let name = item.name ?? "Money exchange"
        let d = item.placemark.location.map { here?.distance(from: $0) ?? 0 } ?? 0
        return HStack(spacing: 12) {
            Image(systemName: "dollarsign.arrow.circlepath")
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color(hex: "#2F9E5B"), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.body.weight(.semibold)).lineLimit(1)
                Text("\(DistanceText.distance(d)) · \(DistanceText.walkingTime(d))")
                    .font(.caption).foregroundStyle(Theme.lagoon)
                if let street = item.placemark.thoroughfare {
                    Text(street).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Button {
                walkTarget = WalkTarget(name: name, coordinate: item.placemark.coordinate)
            } label: {
                Image(systemName: "figure.walk")
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Theme.ink, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Walk to \(name)")
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        if here == nil { here = await location.currentLocation() }
        guard let here else { return }
        var found: [MKMapItem] = []
        for query in ["currency exchange", "money exchange"] {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = MKCoordinateRegion(center: here.coordinate, latitudinalMeters: 8_000, longitudinalMeters: 8_000)
            request.resultTypes = .pointOfInterest
            found += (try? await MKLocalSearch(request: request).start().mapItems) ?? []
        }
        var seen = Set<String>()
        places = found
            .filter { ($0.placemark.location?.distance(from: here) ?? .infinity) < 5_000 }
            .filter { seen.insert("\($0.name ?? "")|\(String(format: "%.4f", $0.placemark.coordinate.latitude))").inserted }
            .sorted { ($0.placemark.location?.distance(from: here) ?? 0) < ($1.placemark.location?.distance(from: here) ?? 0) }
            .prefix(15).map { $0 }
    }
}

#Preview {
    MoneyExchangeView()
}
