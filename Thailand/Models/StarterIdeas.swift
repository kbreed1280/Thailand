import Foundation
import CoreLocation

/// Hand-picked, optional ideas per city. Shown in "Starter Ideas"; one tap adds one to the wish list.
/// Coordinates are approximate (good enough for maps and walking directions).
struct StarterIdea: Identifiable, Hashable {
    let city: StarterCity
    let title: String
    let category: ItemCategory
    let blurb: String
    let address: String
    let latitude: Double
    let longitude: Double

    var id: String { "\(city.rawValue)-\(title)" }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

enum StarterCity: String, CaseIterable, Identifiable {
    case bangkok = "Bangkok"
    case chiangMai = "Chiang Mai"
    case phuket = "Phuket"
    case krabi = "Krabi"
    case kohSamui = "Koh Samui"

    var id: String { rawValue }

    var ideas: [StarterIdea] { StarterIdeas.all.filter { $0.city == self } }
}

enum StarterIdeas {
    static let all: [StarterIdea] = [
        // Bangkok
        .init(city: .bangkok, title: "Grand Palace & Wat Phra Kaew", category: .place,
              blurb: "Thailand's most famous sight. Go at opening (8:30) to beat heat and crowds. Shoulders and knees covered.",
              address: "Na Phra Lan Rd, Phra Nakhon, Bangkok", latitude: 13.7500, longitude: 100.4913),
        .init(city: .bangkok, title: "Wat Pho (Reclining Buddha)", category: .place,
              blurb: "46 m golden reclining Buddha, a short walk from the Grand Palace. Traditional Thai massage school on site.",
              address: "2 Sanam Chai Rd, Phra Nakhon, Bangkok", latitude: 13.7465, longitude: 100.4927),
        .init(city: .bangkok, title: "Wat Arun at sunset", category: .place,
              blurb: "Temple of Dawn on the river. Cross by the 5-baht ferry from Tha Tien pier, or watch sunset from the far bank.",
              address: "158 Wang Doem Rd, Bangkok Yai, Bangkok", latitude: 13.7437, longitude: 100.4888),
        .init(city: .bangkok, title: "Yaowarat (Chinatown) street food", category: .meal,
              blurb: "Best after dark: grilled seafood, noodles, mango sticky rice and fruit stalls along Yaowarat Road.",
              address: "Yaowarat Rd, Samphanthawong, Bangkok", latitude: 13.7400, longitude: 100.5100),
        .init(city: .bangkok, title: "Chatuchak Weekend Market", category: .activity,
              blurb: "15,000+ stalls, Saturday & Sunday. Go early, bring cash and water.",
              address: "Kamphaeng Phet 2 Rd, Chatuchak, Bangkok", latitude: 13.7999, longitude: 100.5503),
        .init(city: .bangkok, title: "Lumphini Park", category: .activity,
              blurb: "Green escape downtown with monitor lizards, paddle boats and an evening aerobics crowd.",
              address: "Rama IV Rd, Pathum Wan, Bangkok", latitude: 13.7307, longitude: 100.5418),
        .init(city: .bangkok, title: "Chao Phraya Express Boat", category: .transport,
              blurb: "Cheap, breezy way along the river between sights. Orange-flag boats run to most piers.",
              address: "Sathorn Pier, Bangkok", latitude: 13.7187, longitude: 100.5136),
        .init(city: .bangkok, title: "Jim Thompson House", category: .place,
              blurb: "Teak houses and silk history in a quiet garden; guided tours only.",
              address: "6 Kasem San 2 Alley, Pathum Wan, Bangkok", latitude: 13.7492, longitude: 100.5283),

        // Chiang Mai
        .init(city: .chiangMai, title: "Wat Phra That Doi Suthep", category: .place,
              blurb: "Golden mountaintop temple with city views. Songthaew from the zoo, then 306 steps (or the tram).",
              address: "Suthep, Mueang Chiang Mai", latitude: 18.8048, longitude: 98.9216),
        .init(city: .chiangMai, title: "Old City temples walk", category: .activity,
              blurb: "Wat Chedi Luang, Wat Phra Singh and dozens of smaller temples inside the moat — easy on foot.",
              address: "Wat Chedi Luang, Phra Pokklao Rd, Chiang Mai", latitude: 18.7871, longitude: 98.9866),
        .init(city: .chiangMai, title: "Sunday Walking Street", category: .activity,
              blurb: "Huge night market from Tha Phae Gate along Ratchadamnoen Rd, Sundays from ~5pm.",
              address: "Tha Phae Gate, Chiang Mai", latitude: 18.7877, longitude: 98.9933),
        .init(city: .chiangMai, title: "Khao soi lunch", category: .meal,
              blurb: "Chiang Mai's signature curry noodle soup. Try it at a local shop near the Old City.",
              address: "Old City, Chiang Mai", latitude: 18.7958, longitude: 98.9853),
        .init(city: .chiangMai, title: "Nimmanhaemin cafés", category: .meal,
              blurb: "Trendy neighborhood of coffee shops, dessert spots and small boutiques.",
              address: "Nimmanhaemin Rd, Chiang Mai", latitude: 18.7990, longitude: 98.9680),
        .init(city: .chiangMai, title: "Warorot Market", category: .activity,
              blurb: "Local market for northern snacks (sai ua sausage, nam prik), dried fruit and souvenirs.",
              address: "Wichayanon Rd, Chiang Mai", latitude: 18.7905, longitude: 99.0005),
        .init(city: .chiangMai, title: "Ethical elephant sanctuary", category: .activity,
              blurb: "Choose a no-riding sanctuary (e.g. Elephant Nature Park). Book ahead; hotel pickup included.",
              address: "Mae Taeng, Chiang Mai", latitude: 19.2151, longitude: 98.8586),

        // Phuket
        .init(city: .phuket, title: "Old Phuket Town", category: .activity,
              blurb: "Colorful Sino-Portuguese shophouses on Thalang & Soi Romanee. Great for a morning walk and coffee.",
              address: "Thalang Rd, Phuket Town", latitude: 7.8847, longitude: 98.3882),
        .init(city: .phuket, title: "Big Buddha", category: .place,
              blurb: "45 m white marble Buddha on Nakkerd Hill with views over Chalong Bay.",
              address: "Karon, Mueang Phuket", latitude: 7.8278, longitude: 98.3128),
        .init(city: .phuket, title: "Promthep Cape sunset", category: .place,
              blurb: "Phuket's classic sunset viewpoint at the island's southern tip. Arrive 45 minutes early.",
              address: "Rawai, Mueang Phuket", latitude: 7.7621, longitude: 98.3054),
        .init(city: .phuket, title: "Kata Beach", category: .activity,
              blurb: "Calmer than Patong, good swimming in the dry season.",
              address: "Kata, Karon, Phuket", latitude: 7.8203, longitude: 98.2984),
        .init(city: .phuket, title: "Phang Nga Bay day trip", category: .activity,
              blurb: "Limestone karsts, sea caves by canoe and 'James Bond Island'. Book a longtail or speedboat tour.",
              address: "Phang Nga Bay", latitude: 8.2750, longitude: 98.5010),
        .init(city: .phuket, title: "Lard Yai Sunday Walking Street", category: .meal,
              blurb: "Sunday evening street-food market in Old Town.",
              address: "Thalang Rd, Phuket Town", latitude: 7.8836, longitude: 98.3907),

        // Krabi
        .init(city: .krabi, title: "Railay Beach", category: .activity,
              blurb: "Cliff-backed peninsula reachable only by longtail boat from Ao Nang (~15 min).",
              address: "Railay, Ao Nang, Krabi", latitude: 8.0110, longitude: 98.8378),
        .init(city: .krabi, title: "Phra Nang Cave Beach", category: .place,
              blurb: "One of Thailand's prettiest beaches, a short walk from Railay East.",
              address: "Railay, Krabi", latitude: 8.0063, longitude: 98.8366),
        .init(city: .krabi, title: "Four Islands tour", category: .activity,
              blurb: "Koh Poda, Chicken Island, Tup Island sandbar and Phra Nang by longtail. Half or full day.",
              address: "Koh Poda, Krabi", latitude: 7.9707, longitude: 98.8095),
        .init(city: .krabi, title: "Tiger Cave Temple", category: .place,
              blurb: "1,260 steps to a summit shrine with huge views. Start early and bring water.",
              address: "Krabi Noi, Mueang Krabi", latitude: 8.1260, longitude: 98.9230),
        .init(city: .krabi, title: "Emerald Pool", category: .place,
              blurb: "Natural turquoise hot-spring pool in the jungle. Go early before tour buses.",
              address: "Khlong Thom, Krabi", latitude: 7.9240, longitude: 99.2650),
        .init(city: .krabi, title: "Krabi Town Walking Street", category: .meal,
              blurb: "Weekend night market with food stalls and live music.",
              address: "Maharat Soi 8, Krabi Town", latitude: 8.0617, longitude: 98.9180),

        // Koh Samui
        .init(city: .kohSamui, title: "Big Buddha (Wat Phra Yai)", category: .place,
              blurb: "12 m golden Buddha on a small islet joined by a causeway.",
              address: "Bophut, Koh Samui", latitude: 9.5710, longitude: 100.0601),
        .init(city: .kohSamui, title: "Fisherman's Village", category: .meal,
              blurb: "Charming Bophut beachfront; Friday night walking street market.",
              address: "Bophut, Koh Samui", latitude: 9.5590, longitude: 100.0270),
        .init(city: .kohSamui, title: "Ang Thong Marine Park", category: .activity,
              blurb: "42 jungle islands, kayaking and a viewpoint hike. Full-day boat trip.",
              address: "Ang Thong National Marine Park", latitude: 9.6290, longitude: 99.6800),
        .init(city: .kohSamui, title: "Chaweng Beach", category: .activity,
              blurb: "Samui's busiest beach: long white sand, bars and restaurants.",
              address: "Chaweng, Koh Samui", latitude: 9.5320, longitude: 100.0610),
        .init(city: .kohSamui, title: "Na Muang Waterfall", category: .place,
              blurb: "Two-tier waterfall; the lower one is an easy walk and good for a swim.",
              address: "Na Mueang, Koh Samui", latitude: 9.4710, longitude: 99.9890),
        .init(city: .kohSamui, title: "Hin Ta & Hin Yai rocks", category: .place,
              blurb: "Famous 'grandfather and grandmother' rock formations near Lamai.",
              address: "Lamai, Koh Samui", latitude: 9.4570, longitude: 100.0470)
    ]
}
