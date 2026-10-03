import SwiftUI

/// Flights you follow, with live status, gate and baggage belt.
struct FlightsView: View {
    let trip: Trip?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = FlightStore.shared
    @ObservedObject private var network = NetworkMonitor.shared
    @State private var showingAdd = false
    @State private var showingSettings = false
    @State private var hasKey = FlightKeychain.apiKey?.isEmpty == false

    var body: some View {
        NavigationStack {
            Group {
                if store.flights.isEmpty {
                    EmptyStateView(
                        systemImage: "airplane.departure",
                        title: "Track Your Flights",
                        message: "Add a flight number and date to see live delays, terminal, gate and baggage belt, with alerts when anything changes."
                    ) {
                        Button { showingAdd = true } label: { Label("Add a Flight", systemImage: "plus") }
                            .buttonStyle(.primary)
                    }
                } else {
                    list
                }
            }
            .background(Theme.background)
            .navigationTitle("Flights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Flight settings")
                    Button { showingAdd = true } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                        .accessibilityLabel("Add flight")
                }
            }
            .navigationDestination(for: UUID.self) { id in
                FlightDetailView(flightID: id)
            }
            .sheet(isPresented: $showingAdd) { AddFlightView(trip: trip) }
            .sheet(isPresented: $showingSettings, onDismiss: { hasKey = FlightKeychain.apiKey?.isEmpty == false }) {
                FlightSettingsView()
            }
            .task { await store.refreshAllIfNeeded() }
            .refreshable {
                for flight in store.upcoming { await store.refresh(flight.id, force: true) }
            }
        }
    }

    private var list: some View {
        List {
            if !hasKey {
                Section {
                    Button { showingSettings = true } label: {
                        Label("Add your free flight-data key to get live status", systemImage: "key.fill")
                    }
                }
            }
            if !network.isOnline {
                Section { OfflineBadge(text: "Offline · showing last saved status") }
                    .listRowBackground(Color.clear)
            }
            if !store.upcoming.isEmpty {
                Section("Upcoming") {
                    ForEach(store.upcoming) { flight in
                        NavigationLink(value: flight.id) { FlightRow(flight: flight, isRefreshing: store.refreshing.contains(flight.id)) }
                    }
                    .onDelete { offsets in offsets.map { store.upcoming[$0] }.forEach(store.delete) }
                }
            }
            if !store.past.isEmpty {
                Section("Past") {
                    ForEach(store.past) { flight in
                        NavigationLink(value: flight.id) { FlightRow(flight: flight, isRefreshing: false) }
                    }
                    .onDelete { offsets in offsets.map { store.past[$0] }.forEach(store.delete) }
                }
            }
        }
    }
}

// MARK: - Row

struct FlightRow: View {
    let flight: TrackedFlight
    var isRefreshing: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "airplane")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Theme.lagoonGradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(flight.title).font(.headline)
                if let departure = flight.departureDate {
                    Text(FlightFormat.dayTime(departure, in: flight.status?.departure.tz))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isRefreshing {
                ProgressView()
            } else {
                FlightStatusPill(flight: flight)
            }
        }
        .padding(.vertical, 2)
    }
}

struct FlightStatusPill: View {
    let flight: TrackedFlight

    var body: some View {
        let (text, tint) = Self.describe(flight)
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.14), in: Capsule())
    }

    static func describe(_ flight: TrackedFlight) -> (String, Color) {
        guard let status = flight.status else { return ("Not checked", .secondary) }
        if status.isCanceled { return ("Canceled", Theme.coral) }
        if status.hasLanded { return ("Landed", Theme.lagoon) }
        let delay = status.departure.delayMinutes
        if delay >= 15 { return ("Delayed \(delay)m", Theme.mango) }
        return (status.statusText == "Unknown" || status.statusText == "Expected" ? "On time" : status.statusText, Theme.lagoon)
    }
}

enum FlightFormat {
    static func dayTime(_ date: Date, in tz: TimeZone?) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .shortened)
        style.timeZone = tz ?? .current
        return date.formatted(style)
    }

    static func time(_ date: Date, in tz: TimeZone?) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = tz ?? .current
        return date.formatted(style)
    }

    /// Thai name of airports you'd ask a driver to take you to.
    static func thaiAirport(_ iata: String?) -> (thai: String, english: String)? {
        switch iata {
        case "BKK": ("สนามบินสุวรรณภูมิ", "Suvarnabhumi Airport")
        case "DMK": ("สนามบินดอนเมือง", "Don Mueang Airport")
        case "CNX": ("สนามบินเชียงใหม่", "Chiang Mai Airport")
        case "HKT": ("สนามบินภูเก็ต", "Phuket Airport")
        case "KBV": ("สนามบินกระบี่", "Krabi Airport")
        case "USM": ("สนามบินสมุย", "Samui Airport")
        case "CEI": ("สนามบินเชียงราย", "Chiang Rai Airport")
        case "UTP": ("สนามบินอู่ตะเภา", "U-Tapao Airport")
        default: nil
        }
    }
}

// MARK: - Detail

struct FlightDetailView: View {
    let flightID: UUID

    @StateObject private var store = FlightStore.shared
    @State private var showContent: ShowModeContent?
    @State private var editingNote = false
    @State private var note = ""

    private var flight: TrackedFlight? { store.flights.first { $0.id == flightID } }

    var body: some View {
        ScrollView {
            if let flight {
                VStack(spacing: 16) {
                    header(flight)
                    if let error = flight.lastError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(Theme.mango)
                            .card()
                    }
                    endpointCard(title: "Departure", systemImage: "airplane.departure", endpoint: flight.status?.departure, showsGate: true)
                    endpointCard(title: "Arrival", systemImage: "airplane.arrival", endpoint: flight.status?.arrival, showsGate: false)
                    actions(flight)
                    if let status = flight.status {
                        Text("Updated \(status.fetchedAt.formatted(.relative(presentation: .named))) · Flight data: AeroDataBox")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
        }
        .background(Theme.background)
        .navigationTitle(flight?.number ?? "Flight")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await store.refresh(flightID, force: true) }
                } label: {
                    if store.refreshing.contains(flightID) { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                }
                .accessibilityLabel("Refresh status")
            }
        }
        .fullScreenCover(item: $showContent) { ShowModeView(content: $0) }
        .alert("Note", isPresented: $editingNote) {
            TextField("Seat, booking code…", text: $note)
            Button("Save") {
                if var f = flight { f.note = note; store.update(f) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func header(_ flight: TrackedFlight) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(flight.status?.airline ?? "Flight").font(.subheadline).foregroundStyle(.white.opacity(0.85))
                    Text(flight.number).font(.largeTitle.bold()).foregroundStyle(.white)
                }
                Spacer()
                FlightStatusPill(flight: flight)
                    .background(.white, in: Capsule())
            }
            if let status = flight.status {
                HStack(alignment: .firstTextBaseline) {
                    Text(status.departure.airportIATA ?? "—").font(.title.bold())
                    Image(systemName: "airplane").font(.title3)
                    Text(status.arrival.airportIATA ?? "—").font(.title.bold())
                }
                .foregroundStyle(.white)
                if let departure = flight.departureDate {
                    Text(countdown(to: departure, flight: flight))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            } else {
                Text(flight.lastError == nil ? "Checking status…" : "Departs \(flight.day)")
                    .foregroundStyle(.white.opacity(0.9))
            }
            if !flight.note.isEmpty {
                Label(flight.note, systemImage: "note.text").font(.subheadline).foregroundStyle(.white)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.lagoonGradient, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    private func countdown(to date: Date, flight: TrackedFlight) -> String {
        if flight.status?.hasLanded == true { return "Landed" }
        let seconds = date.timeIntervalSinceNow
        if seconds < 0 { return "Departed" }
        let hours = Int(seconds / 3600), minutes = Int(seconds.truncatingRemainder(dividingBy: 3600) / 60)
        if hours >= 48 { return "Departs in \(hours / 24) days" }
        return "Departs in \(hours) h \(minutes) min"
    }

    private func endpointCard(title: String, systemImage: String, endpoint: FlightEndpoint?, showsGate: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            if let endpoint {
                Text(endpoint.displayAirport.isEmpty ? "—" : endpoint.displayAirport).font(.headline)
                HStack(alignment: .top, spacing: 24) {
                    if let scheduled = endpoint.scheduled {
                        timeBlock("Scheduled", FlightFormat.time(scheduled, in: endpoint.tz), struck: endpoint.delayMinutes >= 5)
                    }
                    if let best = endpoint.best, endpoint.delayMinutes != 0 || endpoint.runway != nil {
                        timeBlock(endpoint.runway != nil ? "Actual" : "Expected", FlightFormat.time(best, in: endpoint.tz), struck: false,
                                  tint: endpoint.delayMinutes >= 15 ? Theme.mango : Theme.lagoon)
                    }
                }
                HStack(spacing: 10) {
                    if let terminal = endpoint.terminal { bigFact("Terminal", terminal) }
                    if showsGate { bigFact("Gate", endpoint.gate ?? "TBA") }
                    if showsGate, let desk = endpoint.checkInDesk { bigFact("Check-in", desk) }
                    if !showsGate { bigFact("Bags", endpoint.baggageBelt ?? "TBA") }
                }
            } else {
                Text("Live details appear once the status is checked.").foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private func timeBlock(_ label: String, _ value: String, struck: Bool, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit().strikethrough(struck).foregroundStyle(struck ? .secondary : tint)
        }
    }

    private func bigFact(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.bold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Theme.insetBackground, in: RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
    }

    @ViewBuilder
    private func actions(_ flight: TrackedFlight) -> some View {
        VStack(spacing: 10) {
            if let airport = FlightFormat.thaiAirport(flight.status?.departure.airportIATA), !(flight.departureDate.map { $0 < .now } ?? false) {
                Button {
                    showContent = ShowModeContent(thai: "ไป\(airport.thai)\nครับ/ค่ะ", english: "Please take me to \(airport.english)." + (flight.status?.departure.terminal.map { " Terminal \($0)." } ?? ""))
                } label: {
                    Label("Show the driver: \(airport.english)", systemImage: "car.fill")
                }
                .buttonStyle(.primary)
            }
            if let url = URL(string: "https://www.flightaware.com/live/flight/\(flight.number.replacingOccurrences(of: " ", with: ""))") {
                Link(destination: url) {
                    Label("Track on FlightAware", systemImage: "safari")
                }
                .buttonStyle(.secondary)
            }
            Button {
                note = flight.note
                editingNote = true
            } label: {
                Label(flight.note.isEmpty ? "Add a Note (seat, booking code)" : "Edit Note", systemImage: "square.and.pencil")
            }
            .buttonStyle(.secondary)
        }
    }
}

// MARK: - Add

struct AddFlightView: View {
    let trip: Trip?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = FlightStore.shared
    @State private var number = ""
    @State private var date = Date()
    @State private var note = ""

    private var suggestions: [String] {
        guard let trip else { return [] }
        let text = trip.sortedDocuments.map { [$0.title ?? "", $0.text ?? ""].joined(separator: " ") }.joined(separator: "\n")
        let tracked = Set(store.flights.map(\.number))
        return FlightStore.detectFlights(in: text).filter { !tracked.contains($0) }
    }

    private var isValid: Bool {
        TrackedFlight.normalize(number).wholeMatch(of: /[A-Z0-9]{2} [0-9]{1,4}[A-Z]?/) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                if !suggestions.isEmpty {
                    Section("Found in your bookings") {
                        ForEach(suggestions, id: \.self) { flight in
                            Button { number = flight } label: {
                                Label(flight, systemImage: "doc.text.magnifyingglass")
                            }
                        }
                    }
                }
                Section {
                    TextField("Flight number, e.g. TG 103", text: $number)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    DatePicker("Departure date", selection: $date, displayedComponents: .date)
                    TextField("Note (optional): seat, booking code", text: $note)
                } footer: {
                    Text("Use the departure date printed on your ticket, in the departure city's local time.")
                }
            }
            .navigationTitle("Add Flight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        store.add(number: number, day: Self.localDay(date), note: note)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    static func localDay(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 2026, c.month ?? 1, c.day ?? 1)
    }
}

// MARK: - Settings

struct FlightSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var key = FlightKeychain.apiKey ?? ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("RapidAPI key", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("AeroDataBox key")
                } footer: {
                    Text("Stored only in this iPhone's Keychain. Each traveler adds their own key.")
                }
                Section("How to get a free key (5 minutes)") {
                    Text("1. Open the AeroDataBox page on RapidAPI and sign up (free).")
                    Text("2. Choose the free **Basic** plan and subscribe.")
                    Text("3. Copy the **X-RapidAPI-Key** shown in the code panel and paste it above.")
                    Link("Open AeroDataBox on RapidAPI", destination: URL(string: "https://rapidapi.com/aedbx-aedbx/api/aerodatabox")!)
                }
                Section {
                    Text("The free plan allows about 200 checks a month. The app checks each flight once a day until two days before, every 6 hours after that, and every 20–30 minutes on travel day (about 30 checks per flight). Pull down on the flight list to check now.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Flight Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        FlightKeychain.apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
                        dismiss()
                        Task { await FlightStore.shared.refreshAllIfNeeded() }
                    }
                }
            }
        }
    }
}
