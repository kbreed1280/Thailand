import SwiftUI
import CoreLocation

/// A Wikipedia landmark: photo, summary, distance, walking directions and save to trip.
struct LandmarkDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let landmark: Landmark
    let userLocation: CLLocation?
    let onWalk: (WalkTarget) -> Void

    @State private var savedMessage: String?

    private var distance: CLLocationDistance? { userLocation.map(landmark.distance(from:)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AsyncImage(url: landmark.imageURL) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            PlaceImage(coordinate: landmark.coordinate)
                        }
                    }
                    .frame(height: 240)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(landmark.title).font(.title2.bold())
                        if let description = landmark.shortDescription, !description.isEmpty {
                            Text(description.prefix(1).uppercased() + description.dropFirst())
                                .foregroundStyle(.secondary)
                        }
                        if let distance {
                            Label("\(DistanceText.distance(distance)) away · \(DistanceText.walkingTime(distance))", systemImage: "figure.walk")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.lagoon)
                        }
                    }

                    if !landmark.summary.isEmpty {
                        Text(landmark.summary)
                            .font(.body)
                    }

                    Button {
                        onWalk(WalkTarget(name: landmark.title, coordinate: landmark.coordinate))
                    } label: {
                        Label("Walk There", systemImage: "figure.walk")
                    }
                    .buttonStyle(.primary)

                    PlaceActions(place: landmark.asPlace)

                    SaveToTripMenu(place: landmark.asPlace, category: .place, notes: landmark.summary, onSaved: { savedMessage = "Saved to \($0)" }) {
                        Label("Add to Wish List / Day…", systemImage: "plus")
                            .font(.headline)
                            .foregroundStyle(Theme.lagoon)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Theme.lagoon.opacity(0.14), in: Capsule())
                    }

                    if let url = landmark.articleURL {
                        Link(destination: url) {
                            Label("Read more on Wikipedia", systemImage: "book")
                                .font(.subheadline)
                        }
                    }
                }
                .padding()
            }
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .savedToast($savedMessage)
        }
    }
}
