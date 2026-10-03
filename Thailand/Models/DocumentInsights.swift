import Foundation

/// Things found in a booking's text with NSDataDetector + a money regex. No network, no AI.
struct DocumentInsights: Equatable {
    struct DetectedDate: Equatable, Hashable {
        var date: Date
        var hasTime: Bool
    }

    struct Amount: Equatable, Hashable {
        var value: Double
        var currency: Currency
    }

    var title: String = ""
    var dates: [DetectedDate] = []
    var phones: [String] = []
    var addresses: [String] = []
    var links: [URL] = []
    var amounts: [Amount] = []
    var category: ItemCategory = .place

    var isEmpty: Bool { dates.isEmpty && phones.isEmpty && addresses.isEmpty && links.isEmpty && amounts.isEmpty }

    static func analyze(_ text: String) -> DocumentInsights {
        var insights = DocumentInsights()
        insights.title = suggestedTitle(from: text)
        insights.category = guessCategory(text)
        insights.amounts = amounts(in: text)

        let types: NSTextCheckingResult.CheckingType = [.date, .phoneNumber, .address, .link]
        guard let detector = try? NSDataDetector(types: types.rawValue) else { return insights }
        let range = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, options: [], range: range) {
            switch match.resultType {
            case .date:
                if let date = match.date {
                    let matched = Range(match.range, in: text).map { String(text[$0]) } ?? ""
                    let detected = DetectedDate(date: date, hasTime: containsTime(matched))
                    if !insights.dates.contains(detected) { insights.dates.append(detected) }
                }
            case .phoneNumber:
                if let phone = match.phoneNumber, !insights.phones.contains(phone) {
                    insights.phones.append(phone)
                }
            case .address:
                if let range = Range(match.range, in: text) {
                    let address = text[range].replacingOccurrences(of: "\n", with: ", ")
                    if !insights.addresses.contains(address) { insights.addresses.append(address) }
                }
            case .link:
                if let url = match.url, !(url.scheme ?? "").hasPrefix("mailto"), !insights.links.contains(url) {
                    insights.links.append(url)
                }
            default:
                break
            }
        }
        insights.dates.sort { $0.date < $1.date }
        return insights
    }

    /// First meaningful line (skips "Booking confirmation"-style boilerplate when possible).
    static func suggestedTitle(from text: String) -> String {
        let boilerplate = ["booking confirmation", "confirmation", "receipt", "e-ticket", "itinerary", "your booking", "reservation"]
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 3 }
        let candidate = lines.first { line in
            !boilerplate.contains { line.lowercased().hasPrefix($0) } && line.rangeOfCharacter(from: .letters) != nil
        } ?? lines.first ?? ""
        return String(candidate.prefix(60))
    }

    static func guessCategory(_ text: String) -> ItemCategory {
        let lower = text.lowercased()
        if ["hotel", "check-in", "check in", "room", "hostel", "resort", "airbnb", "nights"].contains(where: { lower.contains($0) }) { return .hotel }
        if ["flight", "airline", "boarding", "departure", "train", "ferry", "bus", "gate"].contains(where: { lower.contains($0) }) { return .transport }
        if ["restaurant", "dinner", "lunch", "table for", "menu"].contains(where: { lower.contains($0) }) { return .meal }
        if ["tour", "ticket", "admission", "class", "excursion", "activity", "cruise"].contains(where: { lower.contains($0) }) { return .activity }
        return .place
    }

    /// "฿1,200", "THB 450.50", "1,200 baht", "1200 บาท", "$35.99", "USD 20".
    static func amounts(in text: String) -> [Amount] {
        let number = #"([0-9]{1,3}(?:,[0-9]{3})+(?:\.[0-9]{1,2})?|[0-9]+(?:\.[0-9]{1,2})?)"#
        let patterns: [(String, Currency)] = [
            (#"(?:฿|THB)\s?"# + number, .thb),
            (number + #"\s?(?:THB|baht|Baht|BAHT|บาท)"#, .thb),
            (#"(?:US\$|\$|USD)\s?"# + number, .usd),
            (number + #"\s?USD"#, .usd)
        ]
        var found: [Amount] = []
        for (pattern, currency) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range(at: 1), in: text),
                      let value = Double(text[range].replacingOccurrences(of: ",", with: "")),
                      value > 0 else { continue }
                let amount = Amount(value: value, currency: currency)
                if !found.contains(amount) { found.append(amount) }
            }
        }
        return found
    }

    private static func containsTime(_ text: String) -> Bool {
        text.range(of: #"\d{1,2}[:.]\d{2}|\d\s?(am|pm|AM|PM)|noon|midnight"#, options: .regularExpression) != nil
    }
}
