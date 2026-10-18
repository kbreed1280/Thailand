import SwiftUI
import MapKit
import CoreData

/// The planner's Map tab: every stop in the trip, numbered and colored by day, plus unscheduled places.
/// Chips filter to one day; tap a pin for the place, then open its day's route.
struct TripMapView: View {
    @ObservedObject var trip: Trip
    let onOpenDay: (Day) -> Void

    @State private var position: MapCameraPosition = .automatic
    @State private var filterDayID: NSManagedObjectID?
    @State private var showUnscheduled = true
    @State private var selected: Item?

    static let dayColors = ["#2563EB", "#F97316", "#0EA5A4", "#7C3AED", "#F43F5E", "#16A34A", "#CA8A04", "#DB2777", "#0891B2", "#9333EA"]
    static func color(forDay number: Int) -> String { dayColors[(max(number, 1) - 1) % dayColors.count] }

    private struct Pin: Identifiable {
        let item: Item
        let label: String
        let colorHex: String
        let coordinate: CLLocationCoordinate2D
        var id: NSManagedObjectID { item.objectID }
    }

    private var days: [Day] { trip.sortedDays.filter { $0.sortedItems.contains(where: \.hasCoordinate) } }

    private var pins: [Pin] {
        var result: [Pin] = []
        for day in trip.sortedDays where filterDayID == nil || day.objectID == filterDayID {
            let stops = day.sortedItems.filter(\.hasCoordinate)
            for (index, item) in stops.enumerated() {
                if let c = item.coordinate {
                    result.append(Pin(item: item, label: "\(index + 1)", colorHex: Self.color(forDay: day.number), coordinate: c))
                }
            }
        }
        if showUnscheduled && filterDayID == nil {
            for item in trip.sortedWishItems where !item.isFolderVideo {
                if let c = item.coordinate {
                    result.append(Pin(item: item, label: "★", colorHex: "#64748B", coordinate: c))
                }
            }
        }
        return result
    }

    /// Straight lines joining each day's stops in order (the day map draws real routes).
    private var lines: [(colorHex: String, points: [CLLocationCoordinate2D])] {
        trip.sortedDays
            .filter { filterDayID == nil || $0.objectID == filterDayID }
            .map { (colorHex: Self.color(forDay: $0.number), points: $0.sortedItems.compactMap(\.coordinate)) }
            .filter { $0.points.count > 1 }
    }

    var body: some View {
        Map(position: $position, selection: Binding(get: { selected?.objectID }, set: { id in
            selected = pins.first { $0.id == id }?.item
        })) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                MapPolyline(coordinates: line.points)
                    .stroke(Color(hex: line.colorHex).opacity(0.7), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 5]))
            }
            ForEach(pins) { pin in
                Annotation(pin.item.displayTitle, coordinate: pin.coordinate) {
                    Text(pin.label)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color(hex: pin.colorHex), in: Circle())
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                        .scaleEffect(selected == pin.item ? 1.3 : 1)
                }
                .tag(pin.id)
            }
            UserAnnotation()
        }
        .mapLook()
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .safeAreaInset(edge: .top, spacing: 0) { dayChips }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let selected {
                selectedCard(selected)
            } else if pins.isEmpty {
                Text("Places with a location show up here. Add stops to your days or lists.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.smallCornerRadius))
                    .padding()
            }
        }
        .onChange(of: filterDayID) { _, _ in
            selected = nil
            withAnimation { position = .automatic }
        }
    }

    private var dayChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All days", colorHex: "#334155", isOn: filterDayID == nil) { filterDayID = nil }
                ForEach(days) { day in
                    chip("Day \(day.number)", colorHex: Self.color(forDay: day.number), isOn: filterDayID == day.objectID) {
                        filterDayID = filterDayID == day.objectID ? nil : day.objectID
                    }
                }
                if filterDayID == nil {
                    chip("Lists", colorHex: "#64748B", isOn: showUnscheduled) { showUnscheduled.toggle() }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private func chip(_ title: String, colorHex: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle().fill(Color(hex: colorHex)).frame(width: 9, height: 9)
                Text(title).font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(isOn ? Color(hex: colorHex).opacity(0.18) : Theme.cardBackground, in: Capsule())
            .overlay(Capsule().strokeBorder(isOn ? Color(hex: colorHex) : Theme.hairline))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func selectedCard(_ item: Item) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.category.systemImage)
                .font(.title2)
                .foregroundStyle(Color(hex: item.category.colorHex))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle).font(.headline).lineLimit(1)
                Text(item.day?.heading ?? (item.listName.flatMap { $0.isEmpty ? nil : $0 } ?? "Wish List"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            NavigationLink(value: item) {
                Image(systemName: "info.circle").font(.title3)
            }
            .accessibilityLabel("Details")
            if let day = item.day {
                Button("Route") { onOpenDay(day) }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.ink)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.smallCornerRadius))
        .padding()
    }
}
