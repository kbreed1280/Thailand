import SwiftUI
import MapKit

/// A day's stops on a map, numbered in visiting order and joined by a line.
struct DayMapView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @ObservedObject var day: Day

    @State private var position: MapCameraPosition = .automatic
    @State private var selectedStop: Int?

    private var stops: [(number: Int, item: Item)] {
        day.sortedItems
            .filter(\.hasCoordinate)
            .enumerated()
            .map { (number: $0.offset + 1, item: $0.element) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Map(position: $position) {
                    MapPolyline(coordinates: stops.compactMap { $0.item.coordinate })
                        .stroke(Theme.mango.opacity(0.7), style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [8, 6]))
                    ForEach(stops, id: \.number) { stop in
                        Annotation(stop.item.displayTitle, coordinate: stop.item.coordinate ?? CLLocationCoordinate2D()) {
                            NumberedPin(number: stop.number, colorHex: stop.item.category.colorHex, isSelected: selectedStop == stop.number)
                                .onTapGesture { withAnimation { selectedStop = stop.number } }
                        }
                    }
                    UserAnnotation()
                }
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                }

                stopList
            }
            .navigationTitle(day.heading)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear { LocationService.shared.requestPermission() }
        }
    }

    private var stopList: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(stops, id: \.number) { stop in
                        Button {
                            withAnimation {
                                selectedStop = stop.number
                                if let coordinate = stop.item.coordinate {
                                    position = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 900, longitudinalMeters: 900))
                                }
                            }
                        } label: {
                            HStack(spacing: 10) {
                                NumberedPin(number: stop.number, colorHex: stop.item.category.colorHex, isSelected: false, compact: true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(stop.item.displayTitle)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                    if let time = stop.item.time {
                                        Text(time.formatted(date: .omitted, time: .shortened))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                                if let coordinate = stop.item.coordinate {
                                    Button {
                                        if let url = PlaceLookup.appleMapsURL(to: coordinate, name: stop.item.displayTitle) {
                                            openURL(url)
                                        }
                                    } label: {
                                        Image(systemName: "figure.walk.circle.fill")
                                            .font(.title)
                                            .foregroundStyle(Theme.lagoon)
                                    }
                                    .accessibilityLabel("Walking directions to \(stop.item.displayTitle)")
                                }
                            }
                            .padding(12)
                            .frame(width: 250)
                            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous)
                                    .strokeBorder(selectedStop == stop.number ? Theme.mango : .clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                        .id(stop.number)
                    }
                }
                .padding()
            }
            .background(Theme.background)
            .onChange(of: selectedStop) { _, number in
                if let number { withAnimation { proxy.scrollTo(number, anchor: .center) } }
            }
        }
    }
}

struct NumberedPin: View {
    let number: Int
    let colorHex: String
    let isSelected: Bool
    var compact = false

    private var size: CGFloat { compact ? 30 : (isSelected ? 42 : 34) }

    var body: some View {
        Text("\(number)")
            .font(.system(size: size * 0.45, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color(hex: colorHex), in: Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: compact ? 0 : 2.5))
            .shadow(color: .black.opacity(compact ? 0 : 0.3), radius: 3, y: 2)
            .animation(.spring(duration: 0.25), value: isSelected)
            .accessibilityLabel("Stop \(number)")
    }
}
