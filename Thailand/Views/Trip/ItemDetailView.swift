import SwiftUI
import MapKit

/// Everything about one place: photos, when, where (with directions), link, cost and notes.
struct ItemDetailView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var item: Item
    @State private var showingEditor = false
    @State private var confirmingDelete = false
    @State private var walkTarget: WalkTarget?

    private var store: ItineraryStore { ItineraryStore(context: context) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !item.sortedPhotos.isEmpty {
                    photoCarousel
                }

                headerCard

                if let coordinate = item.coordinate {
                    locationCard(coordinate)
                    if BangkokRail.covers(coordinate) {
                        StopRailCard(item: item, coordinate: coordinate)
                    }
                } else if let address = item.address, !address.isEmpty {
                    infoCard(title: "Address", systemImage: "mappin.and.ellipse") {
                        Text(address).textSelection(.enabled)
                    }
                }

                if let url = item.linkURL {
                    infoCard(title: "Link", systemImage: "link") {
                        Link(destination: url) {
                            Text(url.absoluteString)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }

                if item.costTHB > 0 {
                    infoCard(title: "Cost", systemImage: "bahtsign.circle") {
                        Text("฿\(item.costTHB.formatted(.number.precision(.fractionLength(0...2))))")
                            .font(.title3.weight(.semibold))
                    }
                }

                if let notes = item.notes, !notes.isEmpty {
                    infoCard(title: "Notes", systemImage: "text.alignleft") {
                        Text(notes).textSelection(.enabled)
                    }
                }

                footer
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle(item.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showingEditor = true }
            }
        }
        .sheet(isPresented: $showingEditor) {
            if let trip = item.trip {
                ItemEditorView(item: item, trip: trip, initialDay: item.day)
            }
        }
        .fullScreenCover(item: $walkTarget) { target in
            WalkingRouteView(destinationName: target.name, coordinate: target.coordinate)
        }
        .confirmationDialog("Delete \(item.displayTitle)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                store.delete(item)
                store.save()
                dismiss()
            }
        }
    }

    // MARK: Pieces

    private var photoCarousel: some View {
        TabView {
            ForEach(item.sortedPhotos) { photo in
                if let image = photo.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .accessibilityLabel("Photo of \(item.displayTitle)")
                }
            }
        }
        .tabViewStyle(.page)
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                CategoryBadge(category: item.category, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayTitle)
                        .font(.title3.bold())
                    Text(whenText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Picker("Status", selection: Binding(
                get: { item.status },
                set: { store.setStatus($0, for: item); store.save() }
            )) {
                ForEach(ItemStatus.allCases) { status in
                    Text(status.title).tag(status)
                }
            }
            .pickerStyle(.segmented)
            .sensoryFeedback(.selection, trigger: item.status)
        }
        .card()
    }

    private var whenText: String {
        let dayText = item.day.map { $0.heading } ?? "On the wish list"
        guard let time = item.time else { return dayText }
        return "\(dayText) · \(time.formatted(date: .omitted, time: .shortened))"
    }

    private func locationCard(_ coordinate: CLLocationCoordinate2D) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Where", systemImage: "mappin.and.ellipse")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 800, longitudinalMeters: 800))) {
                Marker(item.displayTitle, systemImage: item.category.systemImage, coordinate: coordinate)
                    .tint(Color(hex: item.category.colorHex))
            }
            .frame(height: 170)
            .clipShape(RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
            .allowsHitTesting(false)

            if let address = item.address, !address.isEmpty {
                Text(address)
                    .font(.subheadline)
                    .textSelection(.enabled)
            }

            Button {
                walkTarget = WalkTarget(name: item.displayTitle, coordinate: coordinate)
            } label: {
                Label("Walk There", systemImage: "figure.walk")
            }
            .buttonStyle(.primary)

            PlaceActions(place: PlaceResult(
                name: item.displayTitle,
                address: item.address ?? "",
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                phone: nil,
                url: item.linkURL,
                categoryName: nil
            ))
        }
        .card()
    }

    private func infoCard<Content: View>(title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .card()
    }

    private var footer: some View {
        VStack(spacing: 10) {
            VStack(spacing: 2) {
                if let addedBy = item.addedBy, !addedBy.isEmpty {
                    Text("Added by \(addedBy)\(item.createdAt.map { " · " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "")")
                }
                if let editedBy = item.lastEditedBy, !editedBy.isEmpty, let updated = item.updatedAt {
                    Text("Last edited by \(editedBy) · \(updated.formatted(.relative(presentation: .named)))")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Button("Delete", role: .destructive) { confirmingDelete = true }
                .font(.subheadline)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }
}
