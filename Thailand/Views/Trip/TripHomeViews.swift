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
                                Text("\(Temperature.deg(w.highC))").font(.headline)
                                Text("Feels \(Temperature.deg(w.maxHeatIndexC))").font(.caption2.weight(.semibold)).opacity(0.85)
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Weather: high \(Temperature.f(w.highC)) degrees")
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(trip.displayName)
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let start = trip.startDate, let end = trip.endDate {
                    Text("\(start.formatted(.dateTime.month(.abbreviated).day())) – \(end.formatted(.dateTime.month(.abbreviated).day().year()))")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }

            let all = trip.allItems
            HStack(spacing: 8) {
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
                    AnimatedSky()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 1))
        }
        .shadow(color: Theme.ink.opacity(0.35), radius: 22, y: 12)
    }

    /// A frosted-glass chip with a big number.
    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 0) {
            Text(value).font(.title3.weight(.heavy).monospacedDigit()).foregroundStyle(.white)
            Text(LocalizedStringKey(label)).font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
    }
}

/// The trip card's sky: deep blue into a sunrise glow, clouds drifting by and a little plane
/// crossing now and then (still when Reduce Motion is on).
struct AnimatedSky: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    LinearGradient(colors: [Color(hex: "#1E3A8A"), Color(hex: "#2563EB"), Color(hex: "#60A5FA")],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    // Sunrise glow, gently breathing.
                    Circle()
                        .fill(RadialGradient(colors: [Theme.mangoLight.opacity(0.75), Theme.mango.opacity(0.25), .clear],
                                             center: .center, startRadius: 0, endRadius: 170))
                        .frame(width: 340, height: 340)
                        .scaleEffect(1 + 0.04 * sin(t / 3))
                        .position(x: w * 0.92, y: h * 0.05)
                    // Stars of light (a little sparkle).
                    ForEach(0..<6, id: \.self) { i in
                        Circle().fill(.white)
                            .frame(width: 3, height: 3)
                            .opacity(0.25 + 0.35 * (0.5 + 0.5 * sin(t * 1.3 + Double(i) * 1.7)))
                            .position(x: w * [0.12, 0.3, 0.48, 0.62, 0.2, 0.75][i], y: h * [0.12, 0.22, 0.08, 0.3, 0.42, 0.18][i])
                    }
                    // Clouds drifting left to right at different speeds.
                    cloud(width: 150, opacity: 0.22, x: drift(t, speed: 9, width: w, offset: 0), y: h * 0.72)
                    cloud(width: 110, opacity: 0.16, x: drift(t, speed: 6, width: w, offset: 0.45), y: h * 0.35)
                    cloud(width: 190, opacity: 0.28, x: drift(t, speed: 12, width: w, offset: 0.7), y: h * 0.92)
                    // The plane: crosses every 14 seconds on a gentle climb.
                    let p = (t / 14).truncatingRemainder(dividingBy: 1)
                    Image(systemName: "airplane")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white.opacity(0.55))
                        .rotationEffect(.degrees(-18))
                        .position(x: -40 + (w + 80) * p, y: h * 0.62 - h * 0.35 * p)
                        .opacity(p < 0.05 || p > 0.95 ? 0 : 1)
                }
            }
        }
    }

    private func drift(_ t: Double, speed: Double, width: CGFloat, offset: Double) -> CGFloat {
        let span = width + 240
        let x = (t * speed + offset * Double(span)).truncatingRemainder(dividingBy: Double(span))
        return CGFloat(x) - 120
    }

    private func cloud(width: CGFloat, opacity: Double, x: CGFloat, y: CGFloat) -> some View {
        Image(systemName: "cloud.fill")
            .resizable().scaledToFit()
            .frame(width: width)
            .foregroundStyle(.white.opacity(opacity))
            .blur(radius: 1.5)
            .position(x: x, y: y)
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
    @ObservedObject private var live = DayPlanActivityController.shared

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
                    HStack {
                        if remaining > 0 {
                            Text("+ \(remaining) more \(isToday ? "today" : "that day")").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isToday && live.isAvailable {
                            Button {
                                if live.isLive(day) { live.stop() } else { live.start(day, in: trip) }
                            } label: {
                                Label(live.isLive(day) ? "On Lock Screen" : "Show on Lock Screen",
                                      systemImage: live.isLive(day) ? "checkmark.circle.fill" : "lock.iphone")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .tint(live.isLive(day) ? .green : Theme.ink)
                        }
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

    enum TripTool { case converter, tdac, entry, weather, flights, transit, packing, documents, offline }

    private var tools: [(TripTool, String, String, Color)] {
        let packing = trip.sortedPackingItems
        let money = trip.localCurrency
        // Bangkok's train map and Thailand's arrival card only make sense on Thailand trips.
        let thailand = trip.isThailand
        return [
            (.converter, CurrencyContext.shortName(money), Destinations.symbolName(forCurrency: money), Theme.lagoon),
            (.weather, "Weather", "sun.max.fill", Theme.mango),
        ] + (thailand ? [(.transit, "BTS & MRT", "tram.fill", Color(hex: "#4C7BD9"))] : []) + [
            (.flights, "Flights", "airplane", Theme.ink),
        ] + (thailand ? [(.tdac, "TDAC", "person.text.rectangle.fill", Theme.coral)] : [(.entry, "Entry", "checkmark.seal.fill", Theme.coral)]) + [
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
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 54, height: 54)
                            .background(
                                LinearGradient(colors: [color.opacity(0.75), color], startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                            )
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 1))
                            .shadow(color: color.opacity(0.35), radius: 6, y: 3)
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
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(Theme.hairline.opacity(0.7), lineWidth: 0.5))
        .shadow(color: Theme.shadow.opacity(0.10), radius: 18, y: 8)
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
