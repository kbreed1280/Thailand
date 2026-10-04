import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// One place mentioned in a post, plus the creator's "inside scoop" about it.
struct ExtractedPlace: Equatable {
    var name: String
    var cityHint: String = ""
    var category: SpotCategory = .explore
    var recommendation: String = ""
    var whatToOrder: String = ""
    var whyItMatters: String = ""
    /// A low-confidence guess (hashtag / first line): kept only if Apple Maps finds a real place.
    var isGuess: Bool = false
}

protocol PlaceExtracting {
    /// "apple-intelligence" or "caption-rules", saved on the source for transparency.
    var name: String { get }
    func extract(from content: LinkContent) async throws -> [ExtractedPlace]
}

/// Picks the best extractor this iPhone supports, and always includes places the page declares itself.
struct PlaceExtractor {
    static var current: PlaceExtracting {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), OnDeviceExtractor.isAvailable { return OnDeviceExtractor() }
        #endif
        return CaptionRulesExtractor()
    }

    /// Declared places (JSON-LD, Google Maps) first, then the extractor's; de-duplicated by name.
    static func extract(from content: LinkContent, using extractor: PlaceExtracting = current) async -> (places: [ExtractedPlace], extractor: String) {
        var places = content.declaredPlaces.map { ExtractedPlace(name: $0.name, cityHint: $0.address ?? "") }
        var used = extractor.name
        do {
            places += try await extractor.extract(from: content)
        } catch {
            // On-device model can fail (busy, guardrails, unsupported Simulator); fall back to rules.
            places += (try? await CaptionRulesExtractor().extract(from: content)) ?? []
            used = CaptionRulesExtractor().name
            print("[import] on-device extraction failed, used caption rules: \(error)")
        }
        // Generic names ("Night Market") from any extractor must match Apple Maps strictly.
        for i in places.indices where NameMatch.isGeneric(places[i].name) { places[i].isGuess = true }
        var seen = Set<String>()
        let unique = places.filter { p in
            let key = p.name.lowercased().filter { $0.isLetter || $0.isNumber }
            return !key.isEmpty && seen.insert(key).inserted
        }
        return (Array(unique.prefix(15)), used)
    }
}

// MARK: - Apple Intelligence (on-device, free, private)

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable(description: "Places mentioned in a travel post")
struct GeneratedPlaces {
    @Guide(description: "Every specific, named place: restaurants, street-food stalls, cafés, bars, markets, temples, sights, beaches, hotels, shops. Not generic things like 'street food' or 'a temple'.")
    var places: [GeneratedPlace]
}

@available(iOS 26.0, *)
@Generable
struct GeneratedPlace {
    @Guide(description: "The place's proper name as written, e.g. 'Jay Fai' or 'Wat Arun'")
    var name: String
    @Guide(description: "City or area if stated or obvious, e.g. 'Bangkok', 'Chiang Mai'; empty if unknown")
    var city: String
    @Guide(description: "One of: eat, brew, sip, vibe, explore, go")
    var category: String
    @Guide(description: "The creator's recommendation in one short sentence, from the text only; empty if none")
    var recommendation: String
    @Guide(description: "Dishes or drinks the creator says to order; empty if none")
    var whatToOrder: String
    @Guide(description: "Why it's worth going (price, view, history, famous for…), from the text only; empty if none")
    var whyItMatters: String
}

@available(iOS 26.0, *)
struct OnDeviceExtractor: PlaceExtracting {
    let name = "apple-intelligence"

    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    func extract(from content: LinkContent) async throws -> [ExtractedPlace] {
        let text = String(content.text.prefix(3_000)) // keep well inside the on-device context window
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let session = LanguageModelSession(instructions: """
            You extract places from travel social posts (captions, descriptions, on-screen text), mostly about Thailand.
            List every specific named place a traveler could visit. Use only facts in the text; never invent places, dishes or details.
            If the text mentions no specific place, return an empty list.
            """)
        let prompt = """
            Post from \(content.platform.title)\(content.creator.isEmpty ? "" : " by \(content.creator)"):
            \(text)
            """
        let response = try await session.respond(to: prompt, generating: GeneratedPlaces.self)
        return response.content.places.map {
            ExtractedPlace(name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                           cityHint: $0.city, category: SpotCategory(word: $0.category),
                           recommendation: $0.recommendation, whatToOrder: $0.whatToOrder, whyItMatters: $0.whyItMatters)
        }
    }
}
#endif

// MARK: - Caption rules (works on every iPhone)

/// Finds places using conventions travel creators use: "📍 Name", numbered lists,
/// "Name – description" lines, and place-like hashtags.
struct CaptionRulesExtractor: PlaceExtracting {
    let name = "caption-rules"

    func extract(from content: LinkContent) async throws -> [ExtractedPlace] {
        Self.places(in: content.text)
    }

    static func places(in text: String) -> [ExtractedPlace] {
        var found: [ExtractedPlace] = []
        let city = TravelArea.detect(in: text)?.name ?? ""
        for rawLine in text.split(whereSeparator: \.isNewline).map(String.init) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            var candidate: String?
            if let m = line.firstMatch(of: /📍\s*([^\n#|•–—\-:,(]+)/) {
                candidate = String(m.1)
            } else if let m = line.firstMatch(of: /^\s*(?:\d{1,2}[\.\)]|[•▪︎◦\-–])\s*([^\n#|•–—:,(]+?)(?:\s*[–—:\-(]|$)/) {
                candidate = String(m.1)
            }
            if var name = candidate?.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) {
                name = name.unicodeScalars.filter { !$0.properties.isEmojiPresentation }.map(String.init).joined()
                    .trimmingCharacters(in: .whitespaces)
                if name.count >= 3, name.count <= 60, name.split(separator: " ").count <= 5 {
                    let rest = line.replacingOccurrences(of: name, with: "").trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
                    found.append(ExtractedPlace(name: name, cityHint: city, category: SpotCategory(word: line),
                                                recommendation: rest.count > 8 ? String(rest.prefix(140)) : ""))
                } else {
                    // Long list headings ("1. Admire the grandeur of Wat Phra Kaew and the Grand Palace"):
                    // pull out the proper names.
                    for proper in properNames(in: name) {
                        found.append(ExtractedPlace(name: proper, cityHint: city, category: SpotCategory(word: line),
                                                    recommendation: String(name.prefix(140)), isGuess: true))
                    }
                }
            }
        }
        if found.isEmpty {
            // No explicit list: try place-like hashtags (#JayFai → "Jay Fai"), skipping generic tags.
            for tag in TravelVideos.candidateQueries(from: text).dropFirst() where TravelArea.detect(in: tag) == nil {
                found.append(ExtractedPlace(name: tag, cityHint: city, category: SpotCategory(word: text), isGuess: true))
            }
        }
        if found.isEmpty, let first = TravelVideos.candidateQueries(from: text).first, first.count <= 50 {
            // Last resort: a short first line; kept only if Apple Maps confirms it's a place.
            found.append(ExtractedPlace(name: first, cityHint: city, category: SpotCategory(word: text), isGuess: true))
        }
        return found
    }

    /// Runs of Capitalized words inside a sentence ("Wat Phra Kaew", "Grand Palace"), skipping the
    /// sentence's first word (usually a verb: "Admire", "Browse") and generic words like "Thai".
    static func properNames(in sentence: String) -> [String] {
        let generic: Set<String> = ["thai", "thailand", "bangkok", "bangkok's", "asia", "the", "a", "an", "i", "you", "we"]
        let connectors: Set<String> = ["of", "de", "la", "na"]
        // Normalize possessives ("Bangkok’s" / "Bangkok's" → "Bangkok") before the generic-word check.
        let words = sentence.split(separator: " ").map { raw -> String in
            var w = String(raw).replacingOccurrences(of: "’", with: "'").trimmingCharacters(in: .punctuationCharacters)
            if w.lowercased().hasSuffix("'s") { w = String(w.dropLast(2)) }
            return w
        }
        var names: [String] = []
        var current: [String] = []
        func flush() {
            while let last = current.last, connectors.contains(last.lowercased()) { current.removeLast() }
            let name = current.joined(separator: " ")
            if !current.isEmpty, !(current.count == 1 && generic.contains(name.lowercased())), name.count >= 4 { names.append(name) }
            current = []
        }
        for (i, word) in words.enumerated() {
            let capitalized = word.first?.isUppercase == true
            if i == 0 { continue }
            if capitalized && !generic.contains(word.lowercased()) || (!current.isEmpty && connectors.contains(word.lowercased())) {
                current.append(word)
            } else { flush() }
        }
        flush()
        return names
    }
}
