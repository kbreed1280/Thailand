import Foundation

/// Online forms travelers commonly complete before arriving, by destination country, with the
/// official sites. Rules change, so the app always says to confirm on the official site.
enum EntryRequirements {
    struct Form: Identifiable, Equatable {
        var name: String
        var detail: String
        var url: URL
        var id: String { name }
    }

    /// Last time this list was reviewed (shown in the app).
    static let reviewed = "October 2026"

    /// U.S. State Department travel pages (visa rules depend on your passport).
    static let stateDepartment = URL(string: "https://travel.state.gov/content/travel/en/international-travel/International-Travel-Country-Information-Pages.html")!

    private static let schengen: Set<String> = ["AT", "BE", "BG", "CH", "CZ", "DE", "DK", "EE", "ES", "FI", "FR", "GR", "HR", "HU",
                                                "IS", "IT", "LI", "LT", "LU", "LV", "MT", "NL", "NO", "PL", "PT", "RO", "SE", "SI", "SK"]

    static func forms(forCountry code: String) -> [Form] {
        let c = code.uppercased()
        if schengen.contains(c) {
            return [form("EU Entry/Exit System (EES)", "Your fingerprints and photo are registered at the border on your first entry. Check whether ETIAS travel authorization is required yet.",
                         "https://travel-europe.europa.eu")]
        }
        return table[c] ?? []
    }

    private static func form(_ name: String, _ detail: String, _ url: String) -> Form {
        Form(name: name, detail: detail, url: URL(string: url)!)
    }

    private static let table: [String: [Form]] = [
        "TH": [form("Thailand Digital Arrival Card (TDAC)", "Submit within 3 days before you arrive. Free on the official site.", "https://tdac.immigration.go.th")],
        "GB": [form("UK Electronic Travel Authorisation (ETA)", "Needed by most visitors who don't need a visa, including U.S. citizens. Apply before you travel.", "https://www.gov.uk/eta")],
        "SG": [form("SG Arrival Card", "Submit within 3 days before you arrive. Free on the official site.", "https://eservices.ica.gov.sg/sgarrivalcard")],
        "MY": [form("Malaysia Digital Arrival Card (MDAC)", "Submit within 3 days before you arrive.", "https://imigresen-online.imi.gov.my/mdac/main")],
        "PH": [form("eTravel", "Register within 72 hours before your flight.", "https://etravel.gov.ph")],
        "ID": [form("All Indonesia arrival card", "Customs, health and immigration in one form before you land.", "https://allindonesia.imigrasi.go.id"),
               form("Visa on Arrival (e-VOA)", "Many nationalities can buy it online before the trip.", "https://evisa.imigrasi.go.id")],
        "JP": [form("Visit Japan Web", "Optional: fill in immigration and customs details ahead to get QR codes for the airport.", "https://vjw-lp.digital.go.jp/en/")],
        "KR": [form("K-ETA", "Required for many visa-free visitors; some nationalities are exempt. Check before you fly.", "https://www.k-eta.go.kr")],
        "TW": [form("Online Arrival Card", "Fill in before you land to skip the paper card.", "https://niaspeedy.immigration.gov.tw/webacard/")],
        "VN": [form("Vietnam e-Visa", "Most visitors apply online before the trip.", "https://evisa.gov.vn")],
        "KH": [form("Cambodia e-Visa / e-Arrival", "Apply for the visa online and complete the arrival form before you fly.", "https://www.evisa.gov.kh")],
        "IN": [form("India e-Visa", "Apply online at least a few days before travel.", "https://indianvisaonline.gov.in/evisa/")],
        "LK": [form("Sri Lanka ETA", "Electronic travel authorization before arrival.", "https://www.eta.gov.lk")],
        "AU": [form("Australian ETA", "Apply in the AustralianETA app (eligible passports) or for an eVisitor visa.", "https://immi.homeaffairs.gov.au")],
        "NZ": [form("NZeTA", "Electronic travel authority for visa-waiver visitors. Apply in the app or online.", "https://www.immigration.govt.nz/nzeta")],
        "CA": [form("Canada eTA", "Needed by visa-exempt visitors flying in. U.S. citizens don't need one.", "https://www.canada.ca/en/immigration-refugees-citizenship/services/visit-canada/eta.html")],
        "US": [form("ESTA", "For Visa Waiver Program travelers. Apply at least 72 hours before you fly.", "https://esta.cbp.dhs.gov")],
        "TR": [form("Türkiye e-Visa", "Needed by some nationalities; apply online.", "https://www.evisa.gov.tr")],
        "EG": [form("Egypt e-Visa", "Apply online or buy a visa on arrival, depending on your passport.", "https://www.visa2egypt.gov.eg")],
        "KE": [form("Kenya Electronic Travel Authorization (eTA)", "Apply online before you travel.", "https://www.etakenya.go.ke")],
    ]

    // MARK: Passport

    enum PassportStatus: Equatable {
        case unknown
        /// Expires before the trip ends.
        case expiresDuringTrip(Date)
        /// Valid for the trip but less than 6 months after it (many countries require 6).
        case underSixMonths(Date)
        case ok(Date)
    }

    static func passportStatus(expires: Date?, tripEnd: Date?, calendar: Calendar = .current) -> PassportStatus {
        guard let expires else { return .unknown }
        let end = tripEnd ?? .now
        if expires < end { return .expiresDuringTrip(expires) }
        if let sixMonths = calendar.date(byAdding: .month, value: 6, to: end), expires < sixMonths { return .underSixMonths(expires) }
        return .ok(expires)
    }
}
