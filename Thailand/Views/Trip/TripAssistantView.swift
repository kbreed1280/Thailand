import SwiftUI
import MapKit
import CoreData
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Trip assistant: chat about the trip with Apple Intelligence (on this iPhone, free and private).
/// It knows the days, stops, lists and budget, answers questions and suggests places you can add in one tap.
struct TripAssistantView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @ObservedObject var trip: Trip

    struct Suggestion: Identifiable, Equatable {
        let id = UUID()
        var name: String
        var area: String
        var why: String
        /// 0 = Wish List.
        var dayNumber: Int
        var added = false
    }

    struct Message: Identifiable, Equatable {
        let id = UUID()
        var fromUser: Bool
        var text: String
        var suggestions: [Suggestion] = []
    }

    @State private var messages: [Message] = []
    @State private var draft = ""
    @State private var isThinking = false
    @State private var sessionBox = SessionBox()
    @FocusState private var focused: Bool

    private var canEdit: Bool { PersistenceController.shared.canEdit(trip) }

    private var quickPrompts: [String] {
        var prompts = ["Fill my empty days with ideas", "What should we eat near our stops?", "Rainy-day backup plan"]
        if let first = trip.sortedDays.first(where: { $0.sortedItems.count >= 3 }) {
            prompts.insert("Is Day \(first.number) too packed?", at: 0)
        }
        return prompts
    }

    var body: some View {
        NavigationStack {
            Group {
                if TripAssistant.isAvailable {
                    chat
                } else {
                    EmptyStateView(
                        systemImage: "apple.intelligence",
                        title: "Needs Apple Intelligence",
                        message: TripAssistant.unavailableReason
                    ) { EmptyView() }
                }
            }
            .navigationTitle("Trip Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                if !messages.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("New Chat", systemImage: "square.and.pencil") {
                            messages = []
                            sessionBox = SessionBox()
                        }
                    }
                }
            }
        }
    }

    private var chat: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if messages.isEmpty {
                        intro
                    }
                    ForEach($messages) { $message in
                        bubble($message)
                            .id(message.id)
                    }
                    if isThinking {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Thinking…").foregroundStyle(.secondary)
                        }
                        .id("thinking")
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in
                withAnimation {
                    if isThinking {
                        proxy.scrollTo("thinking", anchor: .bottom)
                    } else if let last = messages.last?.id {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
            .onChange(of: isThinking) { _, thinking in
                if thinking { withAnimation { proxy.scrollTo("thinking", anchor: .bottom) } }
            }
            .safeAreaInset(edge: .bottom) { inputBar }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Ask about \(trip.displayName)", systemImage: "sparkles")
                .font(.headline)
            Text("I can see your days, stops, lists and budget. Ask for ideas, timing, or what to swap. Everything stays on this iPhone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            PromptChips(items: quickPrompts) { send($0) }
        }
        .card()
    }

    private func bubble(_ message: Binding<Message>) -> some View {
        let m = message.wrappedValue
        return VStack(alignment: m.fromUser ? .trailing : .leading, spacing: 8) {
            Text(m.text)
                .padding(12)
                .foregroundStyle(m.fromUser ? .white : .primary)
                .background(m.fromUser ? Theme.ink : Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
                .frame(maxWidth: .infinity, alignment: m.fromUser ? .trailing : .leading)
                .textSelection(.enabled)
            ForEach(message.suggestions) { $suggestion in
                suggestionRow($suggestion)
            }
        }
    }

    private func suggestionRow(_ suggestion: Binding<Suggestion>) -> some View {
        let s = suggestion.wrappedValue
        let target = s.dayNumber > 0 ? trip.sortedDays.first { $0.number == s.dayNumber } : nil
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "mappin.circle.fill").font(.title2).foregroundStyle(Theme.mango)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.name).font(.subheadline.weight(.semibold))
                if !s.why.isEmpty { Text(s.why).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if canEdit {
                Button {
                    Task { await add(suggestion, to: target) }
                } label: {
                    if s.added {
                        Label("Added", systemImage: "checkmark")
                    } else {
                        Text(target.map { "Add to Day \($0.number)" } ?? "Add to Wish List")
                    }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .disabled(s.added)
            }
        }
        .padding(10)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.smallCornerRadius))
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask about your trip…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($focused)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 18))
                .submitLabel(.send)
                .onSubmit { send(draft) }
            Button {
                send(draft)
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 32))
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isThinking)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func send(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isThinking else { return }
        draft = ""
        messages.append(Message(fromUser: true, text: question))
        isThinking = true
        Task {
            let reply = await TripAssistant.ask(question, trip: trip, box: sessionBox)
            isThinking = false
            messages.append(reply)
        }
    }

    /// Finds the suggested place on Apple Maps near the trip and adds it.
    private func add(_ suggestion: Binding<Suggestion>, to day: Day?) async {
        let s = suggestion.wrappedValue
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = [s.name, s.area].filter { !$0.isEmpty }.joined(separator: " ")
        if let center = trip.destinationCoordinate {
            request.region = MKCoordinateRegion(center: center, latitudinalMeters: 80_000, longitudinalMeters: 80_000)
        }
        let match = try? await MKLocalSearch(request: request).start().mapItems.first
        let store = ItineraryStore(context: context)
        let item = store.addItem(
            title: s.name,
            category: .place,
            to: day,
            in: trip,
            address: match?.placemark.title ?? s.area,
            coordinate: match?.placemark.coordinate,
            notes: s.why
        )
        item.link = match?.url?.absoluteString ?? ""
        store.save()
        suggestion.wrappedValue.added = true
    }
}

/// Holds the model session across turns (opaque so the view compiles on iOS 18).
final class SessionBox {
    var session: AnyObject?
}

enum TripAssistant {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), case .available = SystemLanguageModel.default.availability { return true }
        #endif
        return false
    }

    static var unavailableReason: String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return ""
            case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence in Settings → Apple Intelligence & Siri to use the trip assistant."
            case .unavailable(.modelNotReady): return "Apple Intelligence is still downloading. Try again in a few minutes."
            default: return "The trip assistant needs an iPhone that supports Apple Intelligence (iPhone 15 Pro or newer)."
            }
        }
        #endif
        return "The trip assistant needs iOS 26 or later on an iPhone that supports Apple Intelligence."
    }

    /// A compact description of the trip for the model's instructions.
    static func context(for trip: Trip) -> String {
        var lines: [String] = []
        let destination = (trip.destination ?? "").isEmpty ? trip.countryName : (trip.destination ?? "")
        lines.append("Trip: \(trip.displayName), destination \(destination).")
        if let start = trip.startDate, let end = trip.endDate {
            lines.append("Dates: \(start.formatted(date: .abbreviated, time: .omitted)) to \(end.formatted(date: .abbreviated, time: .omitted)).")
        }
        for day in trip.sortedDays.prefix(21) {
            let stops = day.sortedItems.prefix(10).map { item -> String in
                let time = item.time.map { " at \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
                return "\(item.displayTitle) (\(item.category.title.lowercased())\(time))"
            }
            lines.append("Day \(day.number) \(day.date?.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) ?? ""): " + (stops.isEmpty ? "nothing planned" : stops.joined(separator: "; ")))
        }
        let wish = trip.wishListPlaces.prefix(15).map(\.displayTitle)
        if !wish.isEmpty { lines.append("Wish List: " + wish.joined(separator: "; ")) }
        for name in trip.customListNames.prefix(5) {
            let items = trip.listItems(name).prefix(10).map(\.displayTitle)
            if !items.isEmpty { lines.append("\(name) list: " + items.joined(separator: "; ")) }
        }
        if let hotel = trip.sortedSavedPlaces.first { lines.append("Staying at: \(hotel.displayName).") }
        let budget = trip.budgetSummary
        if budget.budget > 0 {
            lines.append("Budget \(CurrencyMath.format(budget.budget, .local)), spent \(CurrencyMath.format(budget.spent, .local)).")
        }
        return lines.joined(separator: "\n")
    }

    static func ask(_ question: String, trip: Trip, box: SessionBox) async -> TripAssistantView.Message {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), isAvailable {
            let session: LanguageModelSession
            if let existing = box.session as? LanguageModelSession {
                session = existing
            } else {
                session = LanguageModelSession(instructions: """
                    You are Trip Butler, a friendly, practical travel assistant for two people on this trip. \
                    Answer in 2 to 5 short sentences, specific to their plan. When you recommend places, \
                    give real, well-known places at the destination with the day number they fit (0 if no particular day). \
                    Never invent bookings or prices. Today is \(Date.now.formatted(date: .complete, time: .omitted)).

                    \(context(for: trip))
                    """)
                box.session = session
            }
            do {
                let response = try await session.respond(to: question, generating: AssistantReply.self)
                let reply = response.content
                let dayNumbers = Set(trip.sortedDays.map(\.number))
                let suggestions = reply.places.prefix(6).map { place in
                    TripAssistantView.Suggestion(name: place.name, area: place.area, why: place.why,
                                                 dayNumber: dayNumbers.contains(place.dayNumber) ? place.dayNumber : 0)
                }
                return .init(fromUser: false, text: reply.answer, suggestions: Array(suggestions))
            } catch {
                // A full context window starts a fresh conversation next time.
                box.session = nil
                return .init(fromUser: false, text: "Sorry, I couldn't answer that. Try asking in a different way, or start a new chat.")
            }
        }
        #endif
        return .init(fromUser: false, text: unavailableReason)
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct AssistantReply {
    @Guide(description: "The answer to the traveler, 2 to 5 short sentences")
    var answer: String
    @Guide(description: "Specific places recommended in the answer, up to 6; empty if none")
    var places: [AssistantPlace]
}

@available(iOS 26.0, *)
@Generable
struct AssistantPlace {
    @Guide(description: "The place's proper name, e.g. 'Wat Pho'")
    var name: String
    @Guide(description: "City or neighborhood, e.g. 'Bangkok'")
    var area: String
    @Guide(description: "Why it fits, one short sentence")
    var why: String
    @Guide(description: "Trip day number it fits best, or 0 for no particular day")
    var dayNumber: Int
}
#endif

/// Wrapping row of tappable prompt chips.
struct PromptChips: View {
    let items: [String]
    let onTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button { onTap(item) } label: {
                    Text(item)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Theme.insetBackground, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
