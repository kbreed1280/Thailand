import SwiftUI
import Charts

/// A shareable recap of the trip — the "Tripsy Book" idea: days, places, km walked, photos,
/// spending, the busiest day and favorite kinds of places.
struct TripBookView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var trip: Trip
    @StateObject private var rates = ExchangeRateStore.shared

    @State private var walked: WalkStats = .zero
    @State private var walkedDays = 0
    @State private var shareImage: UIImage?

    private var stats: TripBookStats { TripBookStats(trip: trip) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    TripBookContent(stats: stats, walked: walked, walkedDays: walkedDays, thbPerUSD: rates.thbPerUSD)
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle("Trip Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    if let shareImage {
                        let image = Image(uiImage: shareImage)
                        ShareLink(item: image, preview: SharePreview(trip.displayName, image: image)) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .task {
                await loadWalking()
                renderShareImage()
            }
        }
    }

    private func loadWalking() async {
        var total = WalkStats.zero
        var counted = 0
        for day in trip.sortedDays {
            guard let date = day.date, let stats = await PedometerService.shared.stats(for: date), stats.steps > 0 else { continue }
            total.steps += stats.steps
            total.meters += stats.meters
            counted += 1
        }
        walked = total
        walkedDays = counted
    }

    private func renderShareImage() {
        let card = TripBookContent(stats: stats, walked: walked, walkedDays: walkedDays, thbPerUSD: rates.thbPerUSD)
            .padding(20)
            .frame(width: 400)
            .background(Color(.systemGroupedBackground))
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        shareImage = renderer.uiImage
    }
}

/// Numbers for the book, computed from the trip.
struct TripBookStats {
    struct DayCount: Identifiable {
        let label: String
        let count: Int
        var id: String { label }
    }

    let name: String
    let dateRange: String
    let accentHex: String
    let dayCount: Int
    let placesTotal: Int
    let placesDone: Int
    let photoCount: Int
    let journalStops: Int
    let spentTHB: Double
    let perDay: [DayCount]
    let topCategories: [(category: ItemCategory, count: Int)]
    let members: [String]

    @MainActor
    init(trip: Trip) {
        name = trip.displayName
        accentHex = trip.accentHex
        if let start = trip.startDate, let end = trip.endDate {
            dateRange = "\(start.formatted(.dateTime.month(.abbreviated).day())) – \(end.formatted(.dateTime.month(.abbreviated).day().year()))"
        } else {
            dateRange = ""
        }
        let items = trip.allItems
        dayCount = trip.sortedDays.count
        placesTotal = items.count
        placesDone = items.filter { $0.status == .done }.count
        photoCount = items.reduce(0) { $0 + ($1.photos?.count ?? 0) }
        journalStops = trip.sortedVisits.count
        spentTHB = trip.sortedExpenses.reduce(0) { $0 + $1.amountTHB }
        perDay = trip.sortedDays.map { DayCount(label: "D\($0.number)", count: $0.sortedItems.count) }
        topCategories = Dictionary(grouping: items, by: \.category)
            .map { (category: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
            .prefix(3)
            .map { $0 }
        members = [AppSettings.displayName] + PersistenceController.shared.participantNames(for: trip)
    }

    var busiestDay: DayCount? { perDay.max { $0.count < $1.count } }
}

/// The visual book (used on screen and rendered to an image for sharing).
struct TripBookContent: View {
    let stats: TripBookStats
    let walked: WalkStats
    let walkedDays: Int
    let thbPerUSD: Double

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Image(systemName: "sun.horizon.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.white)
                Text(stats.name)
                    .font(.title.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(stats.dateRange)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                Text(ListFormatter.localizedString(byJoining: stats.members))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(22)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: [Color(hex: stats.accentHex).opacity(0.75), Color(hex: stats.accentHex)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
            )

            LazyVGrid(columns: columns, spacing: 12) {
                tile("\(stats.dayCount)", "days", "calendar", Theme.mango)
                tile("\(stats.placesDone)/\(stats.placesTotal)", "places done", "checkmark.seal.fill", .green)
                tile(walked.steps > 0 ? walked.kilometersText : "—", walkedDays > 0 ? "walked (\(walkedDays) days)" : "walked", "figure.walk", Theme.lagoon)
                tile(walked.steps > 0 ? walked.steps.formatted() : "—", "steps", "shoeprints.fill", Theme.lagoon)
                tile("\(stats.photoCount)", "photos", "photo.fill", .purple)
                tile(CurrencyMath.format(stats.spentTHB, .thb), CurrencyMath.format(CurrencyMath.convert(stats.spentTHB, from: .thb, thbPerUSD: thbPerUSD), .usd) + " spent", "bahtsign.circle.fill", Theme.coral)
            }

            if !stats.perDay.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Plans per day").font(.headline)
                    Chart(stats.perDay) { entry in
                        BarMark(x: .value("Day", entry.label), y: .value("Places", entry.count))
                            .foregroundStyle(entry.label == stats.busiestDay?.label ? Theme.mango : Theme.lagoon.opacity(0.6))
                            .cornerRadius(4)
                    }
                    .frame(height: 140)
                    if let busiest = stats.busiestDay, busiest.count > 0 {
                        Text("Busiest: \(busiest.label.replacingOccurrences(of: "D", with: "Day ")) with \(busiest.count) plans")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .card()
            }

            if !stats.topCategories.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Favorite things").font(.headline)
                    ForEach(stats.topCategories, id: \.category) { entry in
                        HStack {
                            CategoryBadge(category: entry.category, size: 30)
                            Text(entry.category.title)
                            Spacer()
                            Text("\(entry.count)").font(.headline.monospacedDigit())
                        }
                    }
                }
                .card()
            }

            if stats.journalStops > 0 {
                Label("\(stats.journalStops) stops in the trip journal", systemImage: "book.closed.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("Made with Thailand Trip")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func tile(_ value: String, _ label: String, _ systemImage: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage).foregroundStyle(tint)
            Text(value)
                .font(.title2.bold().monospacedDigit())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    TripBookView(trip: SampleTrip.create(in: PersistenceController.preview.viewContext))
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
