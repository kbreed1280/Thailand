import SwiftUI

// MARK: - Hero

/// Trip name, countdown, dates, today's weather and a one-line summary.
struct TripHero: View {
    @ObservedObject var trip: Trip
    var members: [String] = []
    var isSharedWithMe = false
    var canEdit = true
    let onFlights: () -> Void
    let onWeather: () -> Void
    /// Opens Apple's sharing sheet (invite by Messages, Mail or link; view-only or can edit).
    var onShare: (() -> Void)?
    var isPreparingShare = false

    @ObservedObject private var flights = FlightStore.shared
    @ObservedObject private var forecast = TripForecast.shared

    private var countdown: String {
        guard let start = trip.startDate, let end = trip.endDate else { return "Your trip" }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        if today < start {
            let days = calendar.dateComponents([.day], from: today, to: start).day ?? 0
            return days == 1 ? "Starts tomorrow" : "\(days) days to go"
        } else if today <= end, let day = trip.today {
            return "Day \(day.number) of \(trip.sortedDays.count)"
        } else {
            return "Trip complete"
        }
    }

    private var weather: WeatherSnapshot.Day? {
        let date = (trip.startDate.map { max($0, .now) }) ?? .now
        return forecast.day(date, in: trip) ?? forecast.forecast(for: trip)?.days.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Text(countdown.uppercased())
                    .font(.caption.weight(.heavy))
                    .tracking(0.8)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.white.opacity(0.18), in: Capsule())
                Spacer()
                if let w = weather {
                    Button(action: onWeather) {
                        HStack(spacing: 6) {
                            Image(systemName: w.symbolName).symbolRenderingMode(.multicolor)
                            VStack(alignment: .leading, spacing: 0) {
                                Text("\(Int(w.highC.rounded()))°").font(.headline)
                                Text("Feels \(Int(w.maxHeatIndexC.rounded()))°").font(.caption2.weight(.semibold)).opacity(0.85)
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Weather: high \(Int(w.highC.rounded())) degrees")
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(trip.displayName)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let start = trip.startDate, let end = trip.endDate {
                    Text("\(start.formatted(.dateTime.month(.abbreviated).day())) – \(end.formatted(.dateTime.month(.abbreviated).day().year()))")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }

            let all = trip.allItems
            HStack(spacing: 14) {
                stat("\(trip.sortedDays.count)", "days")
                stat("\(all.count)", "stops")
                stat("\(trip.confirmedSpots.count)", "spots")
                stat("\(all.filter { $0.status == .booked }.count)", "booked")
            }

            HStack(spacing: 10) {
                if !members.isEmpty {
                    Label("With \(ListFormatter.localizedString(byJoining: members))", systemImage: "person.2.fill")
                        .lineLimit(1)
                } else if isSharedWithMe {
                    Label("Shared with you", systemImage: "person.2.fill")
                }
                if !canEdit { Label("View only", systemImage: "eye.fill") }
                Spacer(minLength: 0)
                if let onShare, !isSharedWithMe {
                    Button(action: onShare) {
                        HStack(spacing: 6) {
                            if isPreparingShare { ProgressView().tint(.white) } else { Image(systemName: "person.crop.circle.badge.plus") }
                            Text(members.isEmpty ? "Invite" : "Manage")
                        }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.white, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isPreparingShare)
                    .accessibilityLabel(members.isEmpty ? "Invite people to this trip" : "Manage who's on this trip")
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.9))

            if let next = flights.nextActive {
                Button(action: onFlights) {
                    let (status, _) = FlightStatusPill.describe(next)
                    HStack {
                        Image(systemName: "airplane")
                        Text("\(next.title) · \(status)").lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.bold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                if let cover = trip.coverPhoto?.image {
                    Image(uiImage: cover).resizable().scaledToFill()
                        .overlay(LinearGradient(colors: [.black.opacity(0.2), .black.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                } else {
                    Theme.sunsetGradient
                        .overlay(alignment: .topTrailing) {
                            // A low evening sun.
                            Circle()
                                .fill(RadialGradient(colors: [Theme.mangoLight.opacity(0.55), .clear], center: .center, startRadius: 0, endRadius: 140))
                                .frame(width: 280, height: 280)
                                .offset(x: 90, y: -120)
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .shadow(color: Theme.inkDeep.opacity(0.25), radius: 16, y: 8)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.title3.weight(.bold)).foregroundStyle(.white)
            Text(LocalizedStringKey(label)).font(.caption).foregroundStyle(.white.opacity(0.75))
        }
    }
}

// MARK: - Today / up next

/// What's next: the next stop today (with directions), or a preview of day 1 before the trip.
struct TodayCard: View {
    @ObservedObject var trip: Trip
    let onDirections: (Item) -> Void
    let onOpenDay: (Day) -> Void
    let onAddSpots: (Day) -> Void
    let onSidequest: () -> Void

    private var focusDay: (day: Day, isToday: Bool)? {
        if let today = trip.today { return (today, true) }
        if let start = trip.startDate, start > .now, let first = trip.sortedDays.first { return (first, false) }
        return nil
    }

    private func nextItem(in day: Day) -> Item? {
        let items = day.sortedItems.filter { $0.status != .done }
        let soon = Date.now.addingTimeInterval(-30 * 60)
        return items.first { ($0.time ?? .distantFuture) >= soon } ?? items.first
    }

    var body: some View {
        if let (day, isToday) = focusDay {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(isToday ? "Today · Day \(day.number)" : "First day · \(day.date?.formatted(.dateTime.weekday(.wide).month().day()) ?? "")",
                          systemImage: isToday ? "sun.horizon.fill" : "calendar")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Button("See day") { onOpenDay(day) }.font(.subheadline.weight(.semibold))
                }

                if let item = nextItem(in: day) {
                    HStack(spacing: 12) {
                        CategoryBadge(category: item.category)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isToday ? "Up next" : "First stop").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(item.displayTitle).font(.headline).lineLimit(1)
                            if let time = item.time {
                                Text(time.formatted(date: .omitted, time: .shortened)).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if item.hasCoordinate {
                            Button { onDirections(item) } label: {
                                Image(systemName: "figure.walk")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                                    .background(Theme.ink, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Walk to \(item.displayTitle)")
                        }
                    }
                    let remaining = day.sortedItems.filter { $0.status != .done }.count - 1
                    if remaining > 0 {
                        Text("+ \(remaining) more \(isToday ? "today" : "that day")").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text(isToday ? "Nothing planned today." : "Nothing planned yet for your first day.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        if !trip.confirmedSpots.isEmpty {
                            Button { onAddSpots(day) } label: {
                                Label("Add from Spots", systemImage: "mappin.and.ellipse").foregroundStyle(.white)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.ink)
                        }
                        Button(action: onSidequest) { Label("Sidequest", systemImage: "dice") }
                            .buttonStyle(.bordered)
                    }
                    .font(.subheadline.weight(.semibold))
                    .buttonBorderShape(.capsule)
                }
            }
            .padding(16)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
        }
    }
}

// MARK: - Travel tools

struct TravelToolsGrid: View {
    @ObservedObject var trip: Trip
    let onAction: (TripTool) -> Void

    enum TripTool { case converter, tdac, weather, flights, transit, packing, documents, offline }

    private var tools: [(TripTool, String, String, Color)] {
        let packing = trip.sortedPackingItems
        return [
            (.converter, "Baht", "bahtsign.circle.fill", Theme.lagoon),
            (.weather, "Weather", "sun.max.fill", Theme.mango),
            (.transit, "BTS & MRT", "tram.fill", Color(hex: "#4C7BD9")),
            (.flights, "Flights", "airplane", Theme.ink),
            (.tdac, "TDAC", "person.text.rectangle.fill", Theme.coral),
            (.packing, packing.isEmpty ? "Packing" : "Packing \(packing.filter(\.isDone).count)/\(packing.count)", "suitcase.rolling.fill", Color(hex: "#8E6BD8")),
            (.documents, "Documents", "lock.doc.fill", Color(hex: "#5F6B7A")),
            (.offline, "Offline", "arrow.down.circle.fill", Color(hex: "#2F9E5B")),
        ]
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 14) {
            ForEach(tools, id: \.1) { tool, title, icon, color in
                Button { onAction(tool) } label: {
                    VStack(spacing: 6) {
                        Image(systemName: icon)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(color)
                            .frame(width: 54, height: 54)
                            .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                        Text(title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }
}

// MARK: - Empty day

/// A day with nothing planned: quick ways to fill it (and still a drop target).
struct EmptyDayRow: View {
    var canAddSpots: Bool
    let onSpots: () -> Void
    let onAdd: () -> Void
    let onDrop: ([String]) -> Bool
    @State private var isTargeted = false

    var body: some View {
        HStack(spacing: 10) {
            Text("Free day").font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            if canAddSpots {
                Button(action: onSpots) { Label("Spots", systemImage: "mappin.and.ellipse") }
                    .buttonStyle(.bordered)
            }
            Button(action: onAdd) { Label("Add", systemImage: "plus") }
                .buttonStyle(.bordered)
        }
        .font(.subheadline.weight(.semibold))
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .frame(minHeight: 40)
        .listRowBackground(isTargeted ? Theme.ink.opacity(0.12) : Theme.cardBackground)
        .dropDestination(for: String.self) { ids, _ in onDrop(ids) } isTargeted: { isTargeted = $0 }
    }
}
