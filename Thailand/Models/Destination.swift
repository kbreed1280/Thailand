import CoreData
import CoreLocation
import Foundation
import NaturalLanguage

// MARK: - Where a trip is

extension Trip {
    @NSManaged var currencyCode: String?
    @NSManaged var countryCode: String?
    @NSManaged var destinationLatitude: Double
    @NSManaged var destinationLongitude: Double

    /// ISO country code of the destination. Trips made before destinations existed were Thailand trips.
    var country: String { (countryCode ?? "").isEmpty ? "TH" : countryCode!.uppercased() }

    /// ISO 4217 code of the money used there (THB for older trips).
    var localCurrency: String {
        if let code = currencyCode, !code.isEmpty { return code.uppercased() }
        return Destinations.currency(forCountry: country) ?? "THB"
    }

    var isThailand: Bool { country == "TH" }

    /// The destination's map point, if known; older Thailand trips fall back to Bangkok.
    var destinationCoordinate: CLLocationCoordinate2D? {
        if destinationLatitude != 0 || destinationLongitude != 0 {
            return CLLocationCoordinate2D(latitude: destinationLatitude, longitude: destinationLongitude)
        }
        return isThailand && (countryCode ?? "").isEmpty ? Destinations.bangkok : nil
    }

    /// "Japan", "Thailand"…
    var countryName: String { Locale.current.localizedString(forRegionCode: country) ?? country }
}

// MARK: - Countries, currencies, languages

enum Destinations {
    static let bangkok = CLLocationCoordinate2D(latitude: 13.7563, longitude: 100.5018)

    /// Currency used in a country (from the system's region data; euro countries → EUR).
    static func currency(forCountry code: String) -> String? {
        Locale(identifier: "en_\(code.uppercased())").currency?.identifier
    }

    /// Main language spoken in a country, for translation (BCP-47 language code).
    static func language(forCountry code: String) -> String {
        let c = code.uppercased()
        if let override = mainLanguage[c] { return override }
        // The most common language the system associates with the region.
        let match = Locale.availableIdentifiers
            .map(Locale.init(identifier:))
            .first { $0.region?.identifier == c && $0.language.languageCode?.identifier != "en" }
        return match?.language.languageCode?.identifier ?? "en"
    }

    /// Where the system guess isn't the language travelers need.
    private static let mainLanguage: [String: String] = [
        "TH": "th", "JP": "ja", "KR": "ko", "CN": "zh", "TW": "zh", "HK": "zh", "VN": "vi", "ID": "id", "MY": "ms",
        "PH": "en", "SG": "en", "IN": "hi", "FR": "fr", "ES": "es", "MX": "es", "IT": "it", "DE": "de", "AT": "de",
        "CH": "de", "PT": "pt", "BR": "pt", "NL": "nl", "BE": "nl", "GR": "el", "TR": "tr", "RU": "ru", "PL": "pl",
        "CZ": "cs", "HU": "hu", "SE": "sv", "NO": "nb", "DK": "da", "FI": "fi", "AE": "ar", "EG": "ar", "MA": "ar",
        "IL": "he", "KH": "km", "LA": "lo", "MM": "my", "NP": "ne", "LK": "si", "AR": "es", "CO": "es", "PE": "es",
        "CL": "es", "CR": "es", "US": "en", "GB": "en", "IE": "en", "AU": "en", "NZ": "en", "CA": "en", "ZA": "en",
    ]

    /// "Japanese", "Thai"…
    static func languageName(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    /// Emergency numbers by country (police, ambulance, fire, tourist police if any).
    struct Emergency { var police: String; var ambulance: String; var fire: String; var tourist: String? }

    static func emergency(forCountry code: String) -> Emergency {
        emergencyNumbers[code.uppercased()] ?? Emergency(police: "112", ambulance: "112", fire: "112", tourist: nil)
    }

    private static let emergencyNumbers: [String: Emergency] = [
        "TH": .init(police: "191", ambulance: "1669", fire: "199", tourist: "1155"),
        "US": .init(police: "911", ambulance: "911", fire: "911"), "CA": .init(police: "911", ambulance: "911", fire: "911"),
        "MX": .init(police: "911", ambulance: "911", fire: "911", tourist: "078"),
        "GB": .init(police: "999", ambulance: "999", fire: "999"), "IE": .init(police: "112", ambulance: "112", fire: "112"),
        "AU": .init(police: "000", ambulance: "000", fire: "000"), "NZ": .init(police: "111", ambulance: "111", fire: "111"),
        "JP": .init(police: "110", ambulance: "119", fire: "119"), "KR": .init(police: "112", ambulance: "119", fire: "119", tourist: "1330"),
        "CN": .init(police: "110", ambulance: "120", fire: "119"), "HK": .init(police: "999", ambulance: "999", fire: "999"),
        "TW": .init(police: "110", ambulance: "119", fire: "119"), "SG": .init(police: "999", ambulance: "995", fire: "995"),
        "MY": .init(police: "999", ambulance: "999", fire: "994"), "ID": .init(police: "110", ambulance: "118", fire: "113"),
        "VN": .init(police: "113", ambulance: "115", fire: "114"), "PH": .init(police: "911", ambulance: "911", fire: "911"),
        "KH": .init(police: "117", ambulance: "119", fire: "118"), "LA": .init(police: "191", ambulance: "195", fire: "190"),
        "IN": .init(police: "112", ambulance: "112", fire: "112"), "AE": .init(police: "999", ambulance: "998", fire: "997"),
        "TR": .init(police: "112", ambulance: "112", fire: "112"), "EG": .init(police: "122", ambulance: "123", fire: "180", tourist: "126"),
        "BR": .init(police: "190", ambulance: "192", fire: "193"), "AR": .init(police: "911", ambulance: "107", fire: "100"),
        "CO": .init(police: "123", ambulance: "123", fire: "123"), "PE": .init(police: "105", ambulance: "106", fire: "116"),
        "ZA": .init(police: "10111", ambulance: "10177", fire: "10177"),
    ]

    /// SF Symbol for a currency, or a generic banknote.
    static func symbolName(forCurrency code: String) -> String {
        let map = ["THB": "bahtsign", "USD": "dollarsign", "EUR": "eurosign", "GBP": "sterlingsign", "JPY": "yensign",
                   "INR": "indianrupeesign", "KRW": "wonsign", "VND": "dongsign", "PHP": "pesosign", "CNY": "chineseyuanrenminbisign",
                   "TRY": "turkishlirasign", "BRL": "brazilianrealsign", "AUD": "australsign", "CAD": "dollarsign", "MXN": "pesosign",
                   "CHF": "francsign", "RUB": "rublesign", "ILS": "shekelsign", "KZT": "tengesign", "UAH": "hryvniasign", "PLN": "polishzlotysign"]
        return map[code.uppercased()].map { "\($0).circle.fill" } ?? "banknote.fill"
    }

    /// Looks up a typed destination ("Tokyo", "Lisbon, Portugal"): country, map point and a display name.
    struct Found: Equatable { var name: String; var country: String; var latitude: Double; var longitude: Double }

    static func find(_ query: String) async -> Found? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2, let mark = try? await CLGeocoder().geocodeAddressString(q).first,
              let country = mark.isoCountryCode, let loc = mark.location else { return nil }
        let name = [mark.locality ?? mark.name, mark.country].compactMap { $0 }.removingDuplicates().joined(separator: ", ")
        return Found(name: name, country: country, latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
    }
}

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

// MARK: - Which money the screens use right now

/// The selected trip's local currency and your home currency. Stored in UserDefaults so non-UI code
/// (formatting, document parsing) can read it; `ExchangeRateStore` republishes changes for SwiftUI.
enum CurrencyContext {
    static let localKey = "currency.local"
    static let homeKey = "currency.home"

    static var localCode: String {
        get { UserDefaults.standard.string(forKey: localKey) ?? "THB" }
        set { UserDefaults.standard.set(newValue.uppercased(), forKey: localKey) }
    }

    /// Your own money, defaulting to the phone's region (USD in the US).
    static var homeCode: String {
        get { UserDefaults.standard.string(forKey: homeKey) ?? Locale.current.currency?.identifier ?? "USD" }
        set { UserDefaults.standard.set(newValue.uppercased(), forKey: homeKey) }
    }

    /// "¥", "€", "฿", "$" — the short symbol people use, not "JP¥".
    static func symbol(_ code: String) -> String {
        if let s = shortSymbols[code.uppercased()] { return s }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = code
        f.locale = Locale(identifier: "en_US")
        return f.currencySymbol ?? code
    }

    private static let shortSymbols = ["USD": "$", "THB": "฿", "EUR": "€", "GBP": "£", "JPY": "¥", "CNY": "¥", "KRW": "₩",
                                       "VND": "₫", "INR": "₹", "PHP": "₱", "TRY": "₺", "ILS": "₪", "AUD": "A$", "CAD": "C$",
                                       "NZD": "NZ$", "SGD": "S$", "HKD": "HK$", "MXN": "MX$", "BRL": "R$", "CHF": "CHF ",
                                       "IDR": "Rp", "MYR": "RM", "KHR": "៛", "LAK": "₭", "ZAR": "R", "AED": "AED "]

    /// "Japanese yen"
    static func name(_ code: String) -> String {
        Locale.current.localizedString(forCurrencyCode: code)?.capitalizedFirst ?? code
    }

    /// "Yen", "Baht", "Euro": the short word for buttons.
    static func shortName(_ code: String) -> String {
        let full = Locale(identifier: "en_US").localizedString(forCurrencyCode: code) ?? code
        return full.split(separator: " ").last.map(String.init)?.capitalized ?? code
    }

    /// Flag of the country that uses the currency (🇪🇺 for euro).
    static func flag(_ code: String) -> String {
        let c = code.uppercased()
        if c == "EUR" { return "🇪🇺" }
        let region = String(c.prefix(2))
        return region.unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }.map(String.init).joined()
    }

    /// Decimal places shown for amounts (0 for yen, won, dong…).
    static func fractionDigits(_ code: String) -> Int {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = code
        return f.maximumFractionDigits
    }

    /// Every ISO currency, for pickers ("JPY · Japanese yen").
    static var allCodes: [String] {
        Locale.commonISOCurrencyCodes.sorted()
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - The selected trip's country (for code without a Trip at hand)

enum CurrentDestination {
    static let key = "trip.country"

    static var country: String {
        get { UserDefaults.standard.string(forKey: key) ?? "TH" }
        set { UserDefaults.standard.set(newValue.uppercased(), forKey: key) }
    }

    static var isThailand: Bool { country == "TH" }

    /// The destination's map point (nil when unknown).
    static var coordinate: CLLocationCoordinate2D? {
        get {
            let d = UserDefaults.standard
            guard d.object(forKey: "trip.latitude") != nil else { return nil }
            return CLLocationCoordinate2D(latitude: d.double(forKey: "trip.latitude"), longitude: d.double(forKey: "trip.longitude"))
        }
        set {
            let d = UserDefaults.standard
            if let newValue {
                d.set(newValue.latitude, forKey: "trip.latitude")
                d.set(newValue.longitude, forKey: "trip.longitude")
            } else {
                d.removeObject(forKey: "trip.latitude")
                d.removeObject(forKey: "trip.longitude")
            }
        }
    }
}

// MARK: - Which language the translator uses right now

/// The selected trip's language for translation and speech ("th" for Thailand, "ja" for Japan…).
enum LocalLanguage {
    static let key = "translate.local"

    static var code: String {
        get { UserDefaults.standard.string(forKey: key) ?? "th" }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static var isThai: Bool { code == "th" }

    /// "Japanese", "Thai"…
    static var name: String { Destinations.languageName(code) }

    /// Full locale for speech and text recognition ("th-TH", "ja-JP", "en-US").
    static func speechLocale(_ code: String) -> String {
        switch code {
        case "en": return "en-US"
        case "th": return "th-TH"
        case "zh": return "zh-CN"
        case "pt": return "pt-BR"
        case "es": return "es-ES"
        default:
            let region = Locale.Language(identifier: code).maximalIdentifier.split(separator: "-").last.map(String.init)
            return region.map { "\(code)-\($0)" } ?? code
        }
    }

    /// True when text looks like it's in the local language rather than English.
    static func looksLocal(_ text: String) -> Bool {
        if isThai { return ThaiText.containsThai(text) }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let lang = recognizer.dominantLanguage else { return false }
        return lang.rawValue != "en"
    }
}
