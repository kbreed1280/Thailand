import Foundation

enum Allergen: String, CaseIterable, Identifiable {
    case peanuts = "Peanuts"
    case shellfish = "Shellfish"
    case fish = "Fish sauce"
    case egg = "Egg"
    case soy = "Soy"
    case gluten = "Gluten"
    case dairy = "Dairy"
    case coconut = "Coconut"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .peanuts: "leaf"
        case .shellfish: "tortoise"
        case .fish: "fish"
        case .egg: "oval"
        case .soy: "drop"
        case .gluten: "laurel.leading"
        case .dairy: "cup.and.saucer"
        case .coconut: "circle.circle"
        }
    }

    /// Thai request to leave it out, for "Show to vendor".
    var thaiNoRequest: String? {
        switch self {
        case .peanuts: "ไม่ใส่ถั่วลิสง"
        case .shellfish: "ไม่ใส่กุ้ง ไม่ใส่ปู"
        case .fish: "ไม่ใส่น้ำปลา"
        case .egg: "ไม่ใส่ไข่"
        default: nil
        }
    }
}

struct Dish: Identifiable, Hashable {
    let name: String
    let thai: String
    let pronunciation: String
    let description: String
    /// 0 = none, 3 = very spicy.
    let spice: Int
    let allergens: [Allergen]
    let symbol: String

    var id: String { name }
}

/// Offline "Must-try Thai food" guide. Allergens are typical; recipes vary, so always ask.
enum FoodGuide {
    static let dishes: [Dish] = [
        Dish(name: "Pad Kra Pao", thai: "ผัดกะเพรา", pronunciation: "phàt gà-phrao",
             description: "Stir-fried holy basil with minced pork or chicken, chili and garlic over rice. Add a crispy fried egg (khài dao).",
             spice: 3, allergens: [.fish, .soy, .shellfish, .egg], symbol: "flame.fill"),
        Dish(name: "Pad Thai", thai: "ผัดไทย", pronunciation: "phàt thai",
             description: "Rice noodles stir-fried with tamarind, egg, tofu, shrimp and bean sprouts, topped with crushed peanuts.",
             spice: 1, allergens: [.peanuts, .egg, .shellfish, .fish, .soy], symbol: "fork.knife"),
        Dish(name: "Khao Soi", thai: "ข้าวซอย", pronunciation: "khâo sɔɔi",
             description: "Chiang Mai's curry noodle soup: coconut curry, soft egg noodles, crispy noodles on top, pickled mustard greens and lime.",
             spice: 2, allergens: [.gluten, .egg, .coconut, .fish], symbol: "takeoutbag.and.cup.and.straw.fill"),
        Dish(name: "Som Tam", thai: "ส้มตำ", pronunciation: "sôm-dtam",
             description: "Green papaya salad pounded with chili, lime, fish sauce, palm sugar, tomatoes, dried shrimp and peanuts.",
             spice: 3, allergens: [.peanuts, .fish, .shellfish], symbol: "leaf.fill"),
        Dish(name: "Massaman Curry", thai: "แกงมัสมั่น", pronunciation: "gaeng mát-sà-màn",
             description: "Mild, rich curry with potatoes, peanuts, cinnamon and cardamom — usually beef or chicken.",
             spice: 1, allergens: [.peanuts, .coconut, .fish], symbol: "flame"),
        Dish(name: "Mango Sticky Rice", thai: "ข้าวเหนียวมะม่วง", pronunciation: "khâo nǐao má-mûang",
             description: "Sweet sticky rice with salty coconut cream and ripe mango. Best in mango season (March–June).",
             spice: 0, allergens: [.coconut], symbol: "birthday.cake.fill"),
        Dish(name: "Boat Noodles", thai: "ก๋วยเตี๋ยวเรือ", pronunciation: "gǔai-tǐao rʉa",
             description: "Tiny bowls of rich, dark beef or pork noodle soup. Locals stack up 5–10 bowls.",
             spice: 2, allergens: [.fish, .soy, .gluten], symbol: "sailboat.fill"),
        Dish(name: "Tom Yum Goong", thai: "ต้มยำกุ้ง", pronunciation: "dtôm-yam gûng",
             description: "Hot and sour shrimp soup with lemongrass, galangal, kaffir lime leaves and chili. The creamy version adds milk.",
             spice: 3, allergens: [.shellfish, .fish, .dairy], symbol: "drop.fill"),
        Dish(name: "Tom Kha Gai", thai: "ต้มข่าไก่", pronunciation: "dtôm khàa gài",
             description: "Creamy coconut soup with chicken, galangal and lime — tangy and gentle.",
             spice: 1, allergens: [.coconut, .fish], symbol: "cup.and.saucer.fill"),
        Dish(name: "Green Curry", thai: "แกงเขียวหวาน", pronunciation: "gaeng khǐao-wǎan",
             description: "Coconut curry with green chilies, Thai eggplant and sweet basil. Usually with chicken.",
             spice: 3, allergens: [.coconut, .fish, .shellfish], symbol: "leaf.circle.fill"),
        Dish(name: "Khao Man Gai", thai: "ข้าวมันไก่", pronunciation: "khâo man gài",
             description: "Poached chicken on fragrant rice cooked in chicken stock, with ginger-soy-chili sauce and a bowl of broth.",
             spice: 1, allergens: [.soy, .gluten], symbol: "bird.fill"),
        Dish(name: "Moo Ping", thai: "หมูปิ้ง", pronunciation: "mǔu bpîng",
             description: "Sweet grilled pork skewers — a street breakfast with a bag of sticky rice.",
             spice: 0, allergens: [.soy, .fish], symbol: "flame.circle.fill"),
        Dish(name: "Gai Yang", thai: "ไก่ย่าง", pronunciation: "gài yâang",
             description: "Marinated grilled chicken. Classic with som tam and sticky rice.",
             spice: 0, allergens: [.fish, .soy], symbol: "bird"),
        Dish(name: "Larb", thai: "ลาบ", pronunciation: "lâap",
             description: "Minced meat salad with lime, chili, mint, shallots and toasted rice powder.",
             spice: 3, allergens: [.fish], symbol: "leaf"),
        Dish(name: "Pad See Ew", thai: "ผัดซีอิ๊ว", pronunciation: "phàt sii-íu",
             description: "Wide rice noodles stir-fried with dark soy sauce, egg and Chinese broccoli. Smoky, not spicy.",
             spice: 0, allergens: [.soy, .gluten, .egg], symbol: "fork.knife.circle"),
        Dish(name: "Rad Na", thai: "ราดหน้า", pronunciation: "râat nâa",
             description: "Wide noodles under a thick, savory gravy with greens and pork or chicken.",
             spice: 0, allergens: [.soy, .gluten, .shellfish], symbol: "fork.knife.circle.fill"),
        Dish(name: "Khao Pad", thai: "ข้าวผัด", pronunciation: "khâo phàt",
             description: "Thai fried rice with egg and onion, your choice of meat or shrimp, served with lime and cucumber.",
             spice: 0, allergens: [.egg, .fish, .soy], symbol: "circle.grid.cross.fill"),
        Dish(name: "Panang Curry", thai: "แกงพะแนง", pronunciation: "gaeng phá-naeng",
             description: "Thick, slightly sweet red curry with kaffir lime leaves, often finished with peanuts.",
             spice: 2, allergens: [.peanuts, .coconut, .fish, .shellfish], symbol: "flame"),
        Dish(name: "Noodle Soup", thai: "ก๋วยเตี๋ยวน้ำ", pronunciation: "gǔai-tǐao náam",
             description: "Everyday noodle soup. Pick your noodle (sen lék thin, sen yài wide, bà-mìi egg) and season at the table.",
             spice: 0, allergens: [.fish, .soy, .gluten], symbol: "takeoutbag.and.cup.and.straw"),
        Dish(name: "Yam Woon Sen", thai: "ยำวุ้นเส้น", pronunciation: "yam wún-sên",
             description: "Spicy glass-noodle salad with shrimp, minced pork, lime, chili and herbs.",
             spice: 3, allergens: [.shellfish, .fish], symbol: "sparkles"),
        Dish(name: "Hoy Tod", thai: "หอยทอด", pronunciation: "hɔ̌ɔi thɔ̂ɔt",
             description: "Crispy mussel or oyster omelette on bean sprouts — a night-market favorite.",
             spice: 0, allergens: [.shellfish, .egg, .gluten], symbol: "frying.pan.fill"),
        Dish(name: "Sai Ua", thai: "ไส้อั่ว", pronunciation: "sâi ùa",
             description: "Northern herbal pork sausage with lemongrass, kaffir lime and chili. Great at Chiang Mai markets.",
             spice: 2, allergens: [], symbol: "flame"),
        Dish(name: "Gaeng Hang Lay", thai: "แกงฮังเล", pronunciation: "gaeng hang-lee",
             description: "Northern pork belly curry — sweet, tangy, ginger-heavy and made without coconut milk.",
             spice: 1, allergens: [.peanuts, .soy], symbol: "flame"),
        Dish(name: "Khanom Jeen Nam Ya", thai: "ขนมจีนน้ำยา", pronunciation: "khà-nǒm jiin nám-yaa",
             description: "Fresh rice noodles with fish curry sauce and a pile of fresh vegetables and herbs.",
             spice: 2, allergens: [.fish, .coconut], symbol: "fish.fill"),
        Dish(name: "Roti", thai: "โรตี", pronunciation: "roo-dtii",
             description: "Pan-fried flatbread with banana, egg, condensed milk and sugar — late-night street dessert.",
             spice: 0, allergens: [.gluten, .dairy, .egg], symbol: "circle.hexagongrid.fill"),
        Dish(name: "Khanom Krok", thai: "ขนมครก", pronunciation: "khà-nǒm khrók",
             description: "Little coconut-rice pancakes, crispy outside and custardy inside.",
             spice: 0, allergens: [.coconut], symbol: "circle.grid.2x2.fill"),
        Dish(name: "Thai Iced Tea (Cha Yen)", thai: "ชาเย็น", pronunciation: "chaa yen",
             description: "Strong orange tea with condensed and evaporated milk over ice. Say \"wǎan nɔ́i\" for less sweet.",
             spice: 0, allergens: [.dairy], symbol: "mug.fill"),
        Dish(name: "Thai Fried Chicken", thai: "ไก่ทอด", pronunciation: "gài thɔ̂ɔt",
             description: "Crispy marinated fried chicken topped with fried shallots (Hat Yai style).",
             spice: 0, allergens: [.gluten, .fish], symbol: "bird.circle.fill"),
        Dish(name: "Salt-Grilled Fish (Pla Pao)", thai: "ปลาเผา", pronunciation: "bplaa phǎo",
             description: "Whole fish in a salt crust stuffed with lemongrass, eaten with herbs, noodles and a spicy dipping sauce.",
             spice: 1, allergens: [.fish], symbol: "fish"),
        Dish(name: "Thai Omelette (Kai Jeow)", thai: "ไข่เจียว", pronunciation: "khài jiao",
             description: "Puffy, crispy deep-fried omelette over rice with chili sauce. Comfort food, never spicy.",
             spice: 0, allergens: [.egg, .fish], symbol: "oval.fill")
    ]
}

/// Neighborhoods to stay in each major city, with a one-line "good for…".
struct StayArea: Identifiable, Hashable {
    let city: StarterCity
    let name: String
    let goodFor: String
    let latitude: Double
    let longitude: Double

    var id: String { "\(city.rawValue)-\(name)" }
}

enum StayGuide {
    static let areas: [StayArea] = [
        StayArea(city: .bangkok, name: "Sukhumvit", goodFor: "Nightlife, malls, restaurants and easy BTS Skytrain access.", latitude: 13.7380, longitude: 100.5600),
        StayArea(city: .bangkok, name: "Riverside", goodFor: "Luxury hotels, river views and boats to the big temples.", latitude: 13.7236, longitude: 100.5146),
        StayArea(city: .bangkok, name: "Silom / Sathorn", goodFor: "Central business district, Lumphini Park, night markets, BTS + MRT.", latitude: 13.7246, longitude: 100.5300),
        StayArea(city: .bangkok, name: "Old Town (Rattanakosin)", goodFor: "Walk to the Grand Palace and Wat Pho; quieter at night.", latitude: 13.7520, longitude: 100.4950),
        StayArea(city: .bangkok, name: "Siam", goodFor: "The shopping heart of the city and the main transit hub.", latitude: 13.7457, longitude: 100.5340),
        StayArea(city: .bangkok, name: "Ari", goodFor: "Local café neighborhood, relaxed and good value.", latitude: 13.7797, longitude: 100.5446),
        StayArea(city: .chiangMai, name: "Old City", goodFor: "Walkable temples and the Sunday Walking Street.", latitude: 18.7883, longitude: 98.9853),
        StayArea(city: .chiangMai, name: "Nimman", goodFor: "Trendy cafés, bars and boutiques; younger crowd.", latitude: 18.7990, longitude: 98.9680),
        StayArea(city: .chiangMai, name: "Riverside", goodFor: "Quieter, upscale hotels along the Ping River.", latitude: 18.7880, longitude: 99.0040),
        StayArea(city: .chiangMai, name: "Night Bazaar", goodFor: "Central, markets every evening, lots of hotel choice.", latitude: 18.7856, longitude: 99.0003),
        StayArea(city: .phuket, name: "Patong", goodFor: "Busy beach and nightlife (Bangla Road). Lively, not quiet.", latitude: 7.8961, longitude: 98.2961),
        StayArea(city: .phuket, name: "Kata / Karon", goodFor: "Family-friendly beaches, calmer evenings, good swimming.", latitude: 7.8200, longitude: 98.2980),
        StayArea(city: .phuket, name: "Old Phuket Town", goodFor: "Culture, food and colorful streets — not on a beach.", latitude: 7.8847, longitude: 98.3882),
        StayArea(city: .phuket, name: "Kamala / Surin", goodFor: "Upscale resorts and quieter bays.", latitude: 7.9550, longitude: 98.2830),
        StayArea(city: .krabi, name: "Ao Nang", goodFor: "Base for island boats, plenty of restaurants.", latitude: 8.0310, longitude: 98.8230),
        StayArea(city: .krabi, name: "Railay", goodFor: "Car-free beaches and rock climbing; boat access only.", latitude: 8.0110, longitude: 98.8378),
        StayArea(city: .krabi, name: "Krabi Town", goodFor: "Local life, cheap eats, night markets.", latitude: 8.0617, longitude: 98.9180),
        StayArea(city: .kohSamui, name: "Chaweng", goodFor: "Busiest beach, nightlife and shopping.", latitude: 9.5320, longitude: 100.0610),
        StayArea(city: .kohSamui, name: "Bophut / Fisherman's Village", goodFor: "Charming and walkable with great restaurants.", latitude: 9.5590, longitude: 100.0270),
        StayArea(city: .kohSamui, name: "Lamai", goodFor: "Relaxed, mid-range, good beach.", latitude: 9.4700, longitude: 100.0470),
        StayArea(city: .kohSamui, name: "Choeng Mon", goodFor: "Quiet bays, good for families.", latitude: 9.5700, longitude: 100.0800)
    ]
}

/// Offline etiquette tips and common scams.
struct GuideTip: Identifiable, Hashable {
    let title: String
    let detail: String
    let systemImage: String
    var id: String { title }
}

struct GuideSection: Identifiable {
    let title: String
    let tips: [GuideTip]
    var id: String { title }
}

enum EtiquetteGuide {
    static let sections: [GuideSection] = [
        GuideSection(title: "Temples", tips: [
            GuideTip(title: "Cover shoulders and knees", detail: "Wear sleeves and long pants or a long skirt. Many temples rent or lend sarongs.", systemImage: "tshirt"),
            GuideTip(title: "Shoes off", detail: "Take shoes off before entering a temple building (look for the pile of shoes).", systemImage: "shoeprints.fill"),
            GuideTip(title: "Mind your feet", detail: "Never point your feet at a Buddha image or at people. Sit with feet tucked behind you.", systemImage: "figure.seated.side"),
            GuideTip(title: "Monks", detail: "Women shouldn't touch monks or hand things to them directly. Give way to monks on transport.", systemImage: "person.fill")
        ]),
        GuideSection(title: "Everyday manners", tips: [
            GuideTip(title: "The wai", detail: "Palms together with a slight bow to greet or thank. Return a wai if given one; you don't need to wai staff.", systemImage: "hands.clap.fill"),
            GuideTip(title: "Heads and feet", detail: "The head is sacred and the feet are lowest — don't touch heads or step over people.", systemImage: "hand.raised.fill"),
            GuideTip(title: "Stay calm", detail: "\"Jai yen yen\" — keep a cool heart. Raising your voice loses face and rarely helps.", systemImage: "heart.fill"),
            GuideTip(title: "The monarchy", detail: "Never criticize the royal family (it's illegal). Stand for the royal anthem before films.", systemImage: "crown.fill")
        ]),
        GuideSection(title: "Common scams", tips: [
            GuideTip(title: "\"The palace is closed today\"", detail: "A friendly stranger says your sight is closed and offers a tuk-tuk tour instead. It's almost never closed — walk to the entrance.", systemImage: "exclamationmark.triangle.fill"),
            GuideTip(title: "Gem and tailor shop detours", detail: "Cheap tuk-tuk rides that stop at gem or suit shops earn the driver commission. Say no to unplanned stops.", systemImage: "diamond.fill"),
            GuideTip(title: "No meter", detail: "Taxis should use the meter. If they won't, get out or book Grab/Bolt for a fixed price.", systemImage: "car.fill"),
            GuideTip(title: "Jet ski \"damage\"", detail: "Photograph rentals before you ride. Better: book through your hotel.", systemImage: "camera.fill"),
            GuideTip(title: "Hidden bar bills", detail: "Some \"free entry\" shows add huge drink charges. Ask for prices first.", systemImage: "wineglass.fill")
        ]),
        GuideSection(title: "Money & safety", tips: [
            GuideTip(title: "Carry small notes", detail: "Street vendors and taxis may not have change for ฿1,000.", systemImage: "banknote.fill"),
            GuideTip(title: "ATM fees", detail: "Thai ATMs charge about ฿220 per foreign-card withdrawal. Withdraw larger amounts less often.", systemImage: "creditcard.fill"),
            GuideTip(title: "Water", detail: "Drink bottled or filtered water. Ice in restaurants is generally fine.", systemImage: "waterbottle.fill"),
            GuideTip(title: "Traffic drives on the left", detail: "Look right first when crossing. Use footbridges in Bangkok.", systemImage: "figure.walk")
        ])
    ]
}
