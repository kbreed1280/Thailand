import SwiftUI
import MapKit

/// Explore: places to eat, stay and see near you (or any city), plus offline guides.
struct ExploreTabView: View {
    @State private var model = ExploreModel()
    @ObservedObject private var network = NetworkMonitor.shared
    @State private var selected: PlaceResult?
    @State private var savedMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Category", selection: $model.segment) {
                        ForEach(ExploreSegment.allCases) { segment in
                            Label(segment.rawValue, systemImage: segment.systemImage).tag(segment)
                        }
                    }
                    .pickerStyle(.segmented)

                    guideCard

                    resultsHeader

                    if !network.isOnline {
                        EmptyStateView(
                            systemImage: "wifi.slash",
                            title: "You're Offline",
                            message: "Searching for places needs internet. The food, stay and etiquette guides above work offline."
                        )
                        .frame(height: 320)
                    } else if model.isLoading {
                        ProgressView("Finding places…")
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else if model.locationDenied && model.query.isEmpty {
                        VStack(spacing: 12) {
                            PermissionDeniedView(kind: .location)
                                .frame(height: 360)
                            Text("Or search for a city above, like \"Chiang Mai\".")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    } else if model.results.isEmpty && model.hasSearched {
                        EmptyStateView(
                            systemImage: "mappin.slash",
                            title: "Nothing Found",
                            message: "Try another search, or a city name like \"Krabi\"."
                        )
                        .frame(height: 320)
                    } else {
                        LazyVStack(spacing: 14) {
                            ForEach(model.results) { place in
                                PlaceCard(
                                    place: place,
                                    distance: model.distance(to: place),
                                    category: model.segment.itemCategory,
                                    onSaved: { savedMessage = "Saved to \($0)" }
                                )
                                .onTapGesture { selected = place }
                            }
                        }
                    }
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle("Explore")
            .searchable(text: $model.query, prompt: model.segment.searchPlaceholder)
            .onSubmit(of: .search) { Task { await model.load() } }
            .onChange(of: model.query) { _, newValue in
                if newValue.isEmpty { Task { await model.load() } }
            }
            .task(id: model.segment) { await model.load() }
            .refreshable { await model.load() }
            .sheet(item: $selected) { place in
                PlaceDetailSheet(place: place, category: model.segment.itemCategory, distance: model.distance(to: place))
            }
            .savedToast($savedMessage)
        }
    }

    @ViewBuilder
    private var guideCard: some View {
        switch model.segment {
        case .eat:
            GuideLinkCard(title: "Must-Try Thai Food", subtitle: "30 dishes with Thai script, spice level and allergens — works offline", systemImage: "fork.knife.circle.fill") {
                FoodGuideView()
            }
        case .stay:
            GuideLinkCard(title: "Where to Stay", subtitle: "Best neighborhoods in Bangkok, Chiang Mai, Phuket, Krabi and Koh Samui", systemImage: "building.2.crop.circle.fill") {
                StayGuideView { area in
                    Task { await model.searchAround(area: area) }
                }
            }
        case .see:
            GuideLinkCard(title: "Etiquette & Scams", subtitle: "Temple dress code, the wai, and tourist traps to avoid", systemImage: "hand.raised.circle.fill") {
                EtiquetteGuideView()
            }
        }
    }

    private var resultsHeader: some View {
        HStack {
            Text(model.query.isEmpty ? "Near \(model.originName)" : "Results near \(model.originName)")
                .font(.title3.bold())
            Spacer()
            if !model.results.isEmpty {
                Text("\(model.results.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct GuideLinkCard<Destination: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 34))
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline).foregroundStyle(.white)
                    Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.8))
            }
            .padding(16)
            .background(Theme.lagoonGradient, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}

/// Async Look Around / map preview image.
struct PlaceImage: View {
    let coordinate: CLLocationCoordinate2D
    @State private var image: UIImage?

    var body: some View {
        Color(.tertiarySystemFill)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    ProgressView()
                }
            }
            .clipped()
            .task(id: "\(coordinate.latitude),\(coordinate.longitude)") {
                image = await PlaceImageLoader.image(for: coordinate)
            }
            .accessibilityHidden(true)
    }
}

struct PlaceCard: View {
    let place: PlaceResult
    let distance: CLLocationDistance?
    let category: ItemCategory
    var onSaved: ((String) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlaceImage(coordinate: place.coordinate)
                .frame(height: 150)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(place.name).font(.headline).lineLimit(2)
                        if !place.address.isEmpty {
                            Text(place.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer()
                    SaveToTripMenu(place: place, category: category, onSaved: onSaved) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title)
                            .foregroundStyle(Theme.mango)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Save \(place.name) to your trip")
                }
                HStack(spacing: 6) {
                    if let categoryName = place.categoryName {
                        StatPill(systemImage: "tag", text: categoryName)
                    }
                    if let distance {
                        StatPill(systemImage: "figure.walk", text: "\(DistanceText.distance(distance)) · \(DistanceText.walkingTime(distance))", tint: Theme.lagoon)
                    }
                }
            }
            .padding(14)
        }
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 10, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Details for a place: Look Around, directions, call, website, ride apps and save.
struct PlaceDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let place: PlaceResult
    let category: ItemCategory
    let distance: CLLocationDistance?

    @State private var scene: MKLookAroundScene?
    @State private var savedMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Group {
                        if let scene {
                            LookAroundPreview(initialScene: scene)
                        } else {
                            PlaceImage(coordinate: place.coordinate)
                        }
                    }
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(place.name).font(.title2.bold())
                        if let categoryName = place.categoryName {
                            Text(categoryName).foregroundStyle(.secondary)
                        }
                        if !place.address.isEmpty {
                            Label(place.address, systemImage: "mappin.and.ellipse").font(.subheadline)
                        }
                        if let distance {
                            Label("\(DistanceText.distance(distance)) away · \(DistanceText.walkingTime(distance))", systemImage: "figure.walk")
                                .font(.subheadline)
                                .foregroundStyle(Theme.lagoon)
                        }
                    }

                    PlaceActions(place: place)

                    SaveToTripMenu(place: place, category: category, onSaved: { savedMessage = "Saved to \($0)" }) {
                        Label("Save to Trip", systemImage: "plus")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Theme.sunsetGradient, in: Capsule())
                    }
                }
                .padding()
            }
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { scene = await PlaceImageLoader.lookAroundScene(at: place.coordinate) }
            .savedToast($savedMessage)
        }
        .presentationDetents([.large])
    }
}

/// Walk there (Apple / Google Maps), call, website, Grab and Bolt.
struct PlaceActions: View {
    let place: PlaceResult
    @State private var copiedFor: ExternalApps.RideApp?

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                actionButton("Walk (Apple)", systemImage: "figure.walk", tint: Theme.lagoon) {
                    ExternalApps.openAppleMaps(to: place.coordinate, name: place.name)
                }
                actionButton("Google Maps", systemImage: "map.fill", tint: Color(hex: "#4285F4")) {
                    ExternalApps.openGoogleMaps(stops: [place.coordinate])
                }
            }
            HStack(spacing: 10) {
                if let phone = place.phone {
                    actionButton("Call", systemImage: "phone.fill", tint: .green) {
                        ExternalApps.call(phone)
                    }
                }
                if let url = place.url {
                    actionButton("Website", systemImage: "safari.fill", tint: .blue) {
                        UIApplication.shared.open(url)
                    }
                }
            }
            HStack(spacing: 10) {
                ForEach(ExternalApps.RideApp.allCases) { app in
                    actionButton(app.rawValue, systemImage: "car.fill", tint: Color(hex: app.colorHex)) {
                        copiedFor = app
                        ExternalApps.openRide(app, destinationName: place.name, address: place.address)
                    }
                }
            }
            if let copiedFor {
                Label("Destination copied — paste it into \(copiedFor.rawValue)'s \"Where to?\" box.", systemImage: "doc.on.clipboard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func actionButton(_ title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 46)
                .foregroundStyle(tint)
                .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}

#Preview {
    ExploreTabView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
