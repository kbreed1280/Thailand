import Foundation

/// The polite ending Thai speakers add to most sentences: men say "khráp", women say "khâ".
enum PoliteParticle: String, CaseIterable, Identifiable {
    case khrap
    case kha

    static let storageKey = "politeParticle"

    var id: String { rawValue }
    var thai: String { self == .khrap ? "ครับ" : "ค่ะ" }
    var romanized: String { self == .khrap ? "khráp" : "khâ" }
    var label: String { self == .khrap ? "ครับ khráp (male speaker)" : "ค่ะ khâ (female speaker)" }

    static var current: PoliteParticle {
        PoliteParticle(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .khrap
    }
}

enum PhraseCategory: String, CaseIterable, Identifiable {
    case greetings = "Greetings"
    case food = "Food & Ordering"
    case directions = "Directions & Taxi"
    case shopping = "Shopping & Bargaining"
    case hotel = "Hotel"
    case emergency = "Emergency & Medical"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .greetings: "hand.wave.fill"
        case .food: "fork.knife"
        case .directions: "car.fill"
        case .shopping: "bag.fill"
        case .hotel: "bed.double.fill"
        case .emergency: "cross.case.fill"
        }
    }

    var colorHex: String {
        switch self {
        case .greetings: "#F4821C"
        case .food: "#E8505B"
        case .directions: "#2D88D9"
        case .shopping: "#6C5CE7"
        case .hotel: "#1BA39C"
        case .emergency: "#D63031"
        }
    }
}

struct Phrase: Identifiable, Hashable {
    let category: PhraseCategory
    let english: String
    let thai: String
    let romanized: String
    /// Whether the polite particle is appended when shown or spoken.
    let polite: Bool

    var id: String { "\(category.rawValue)|\(english)" }

    func thai(with particle: PoliteParticle) -> String {
        polite ? "\(thai)\(particle.thai)" : thai
    }

    func romanized(with particle: PoliteParticle) -> String {
        polite ? "\(romanized) \(particle.romanized)" : romanized
    }
}

/// Offline phrasebook. Romanization uses common tone-marked spelling (à low, â falling, á high, ǎ rising).
enum Phrasebook {
    static let all: [Phrase] = greetings + food + directions + shopping + hotel + emergency

    static func phrases(in category: PhraseCategory) -> [Phrase] {
        all.filter { $0.category == category }
    }

    private static func p(_ category: PhraseCategory, _ english: String, _ thai: String, _ romanized: String, polite: Bool = true) -> Phrase {
        Phrase(category: category, english: english, thai: thai, romanized: romanized, polite: polite)
    }

    static let greetings: [Phrase] = [
        p(.greetings, "Hello / Goodbye", "สวัสดี", "sà-wàt-dii"),
        p(.greetings, "Thank you", "ขอบคุณ", "khàwp-khun"),
        p(.greetings, "Thank you very much", "ขอบคุณมาก", "khàwp-khun mâak"),
        p(.greetings, "Sorry / Excuse me", "ขอโทษ", "khǎw-thôht"),
        p(.greetings, "Yes", "ใช่", "châi"),
        p(.greetings, "No", "ไม่ใช่", "mâi châi"),
        p(.greetings, "No problem / Never mind", "ไม่เป็นไร", "mâi bpen rai"),
        p(.greetings, "How are you?", "สบายดีไหม", "sà-baai dii mái"),
        p(.greetings, "I'm fine", "สบายดี", "sà-baai dii"),
        p(.greetings, "Nice to meet you", "ยินดีที่ได้รู้จัก", "yin-dii thîi dâai rúu-jàk"),
        p(.greetings, "I don't understand", "ไม่เข้าใจ", "mâi khâo-jai"),
        p(.greetings, "Do you speak English?", "พูดภาษาอังกฤษได้ไหม", "phûut phaa-sǎa ang-grìt dâai mái"),
        p(.greetings, "Please speak slowly", "พูดช้าๆ หน่อย", "phûut cháa-cháa nòi"),
        p(.greetings, "See you later", "แล้วเจอกัน", "láew jəə gan")
    ]

    static let food: [Phrase] = [
        p(.food, "Not spicy", "ไม่เผ็ด", "mâi phèt"),
        p(.food, "A little spicy", "เผ็ดนิดหน่อย", "phèt nít-nòi"),
        p(.food, "Very spicy, please", "เผ็ดมาก", "phèt mâak"),
        p(.food, "No peanuts, please", "ไม่ใส่ถั่วลิสง", "mâi sài thùa-lí-sǒng"),
        p(.food, "I'm allergic to peanuts", "ฉันแพ้ถั่วลิสง", "chǎn pháe thùa-lí-sǒng"),
        p(.food, "I'm allergic to shrimp and crab", "ฉันแพ้กุ้งและปู", "chǎn pháe gûng láe bpuu"),
        p(.food, "I'm vegetarian", "ฉันกินมังสวิรัติ", "chǎn gin mang-sà-wí-rát"),
        p(.food, "No meat", "ไม่ใส่เนื้อสัตว์", "mâi sài nʉ́a-sàt"),
        p(.food, "No fish sauce", "ไม่ใส่น้ำปลา", "mâi sài nám-bplaa"),
        p(.food, "No MSG", "ไม่ใส่ผงชูรส", "mâi sài phǒng-chuu-rót"),
        p(.food, "No sugar", "ไม่ใส่น้ำตาล", "mâi sài nám-dtaan"),
        p(.food, "No ice", "ไม่ใส่น้ำแข็ง", "mâi sài nám-khǎeng"),
        p(.food, "Water, please", "ขอน้ำเปล่า", "khǎw nám-bplào"),
        p(.food, "The menu, please", "ขอเมนู", "khǎw mee-nuu"),
        p(.food, "I'd like this one", "เอาอันนี้", "ao an-níi"),
        p(.food, "Delicious!", "อร่อยมาก", "à-ròi mâak"),
        p(.food, "The bill, please", "เช็คบิลด้วย", "chék bin dûai"),
        p(.food, "To take away", "ห่อกลับบ้าน", "hàw glàp bâan"),
        p(.food, "Chicken", "ไก่", "gài", polite: false),
        p(.food, "Pork", "หมู", "mǔu", polite: false),
        p(.food, "Beef", "เนื้อ", "nʉ́a", polite: false),
        p(.food, "Shrimp", "กุ้ง", "gûng", polite: false)
    ]

    static let directions: [Phrase] = [
        p(.directions, "Where is the toilet?", "ห้องน้ำอยู่ที่ไหน", "hâwng-náam yùu thîi-nǎi"),
        p(.directions, "Please take me to this address", "ช่วยพาไปที่อยู่นี้", "chûai phaa bpai thîi-yùu níi"),
        p(.directions, "Please use the meter", "ช่วยเปิดมิเตอร์", "chûai bpə̀ət mí-dtə̂ə"),
        p(.directions, "How much to go there?", "ไปที่นั่นเท่าไหร่", "bpai thîi-nân thâo-rài"),
        p(.directions, "Turn left", "เลี้ยวซ้าย", "líao sáai"),
        p(.directions, "Turn right", "เลี้ยวขวา", "líao khwǎa"),
        p(.directions, "Go straight", "ตรงไป", "dtrong bpai"),
        p(.directions, "Stop here", "จอดที่นี่", "jàwt thîi-nîi"),
        p(.directions, "Is it far?", "ไกลไหม", "glai mái"),
        p(.directions, "Can I walk there?", "เดินไปได้ไหม", "dəən bpai dâai mái"),
        p(.directions, "I'm lost", "ฉันหลงทาง", "chǎn lǒng-thaang"),
        p(.directions, "Train station", "สถานีรถไฟ", "sà-thǎa-nii rót-fai", polite: false),
        p(.directions, "Airport", "สนามบิน", "sà-nǎam-bin", polite: false),
        p(.directions, "Pier (boat)", "ท่าเรือ", "thâa-rʉa", polite: false)
    ]

    static let shopping: [Phrase] = [
        p(.shopping, "How much is this?", "อันนี้เท่าไหร่", "an-níi thâo-rài"),
        p(.shopping, "Too expensive", "แพงไป", "phaeng bpai"),
        p(.shopping, "Can you lower the price?", "ลดได้ไหม", "lót dâai mái"),
        p(.shopping, "OK, I'll take it", "ตกลง เอาอันนี้", "dtòk-long ao an-níi"),
        p(.shopping, "Just looking", "ดูเฉยๆ", "duu chə̌əi-chə̌əi"),
        p(.shopping, "Do you have a bigger size?", "มีไซซ์ใหญ่กว่านี้ไหม", "mii sái yài gwàa níi mái"),
        p(.shopping, "Do you have a smaller size?", "มีไซซ์เล็กกว่านี้ไหม", "mii sái lék gwàa níi mái"),
        p(.shopping, "Can I pay by card?", "จ่ายด้วยบัตรได้ไหม", "jàai dûai bàt dâai mái"),
        p(.shopping, "Do you have change?", "มีเงินทอนไหม", "mii ngən thawn mái"),
        p(.shopping, "Can I try it on?", "ลองได้ไหม", "lawng dâai mái")
    ]

    static let hotel: [Phrase] = [
        p(.hotel, "I have a reservation", "ฉันจองห้องไว้แล้ว", "chǎn jawng hâwng wái láew"),
        p(.hotel, "What time is check-out?", "เช็คเอาท์กี่โมง", "chék-áo gìi moong"),
        p(.hotel, "What's the Wi-Fi password?", "รหัสไวไฟคืออะไร", "rá-hàt wai-fai khʉʉ à-rai"),
        p(.hotel, "The air conditioning is broken", "แอร์เสีย", "ae sǐa"),
        p(.hotel, "Can I leave my bags here?", "ฝากกระเป๋าไว้ได้ไหม", "fàak grà-bpǎo wái dâai mái"),
        p(.hotel, "Please clean the room", "ช่วยทำความสะอาดห้อง", "chûai tham khwaam-sà-àat hâwng"),
        p(.hotel, "More towels, please", "ขอผ้าเช็ดตัวเพิ่ม", "khǎw phâa-chét-dtua phə̂əm"),
        p(.hotel, "Please call a taxi", "ช่วยเรียกแท็กซี่ให้หน่อย", "chûai rîak tháek-sîi hâi nòi")
    ]

    static let emergency: [Phrase] = [
        p(.emergency, "Help!", "ช่วยด้วย", "chûai dûai", polite: false),
        p(.emergency, "Call the police", "เรียกตำรวจ", "rîak dtam-rùat"),
        p(.emergency, "Call an ambulance", "เรียกรถพยาบาล", "rîak rót phá-yaa-baan"),
        p(.emergency, "I need a doctor", "ฉันต้องการหมอ", "chǎn dtâwng-gaan mǎw"),
        p(.emergency, "Where is the hospital?", "โรงพยาบาลอยู่ที่ไหน", "roong-phá-yaa-baan yùu thîi-nǎi"),
        p(.emergency, "Where is a pharmacy?", "ร้านขายยาอยู่ที่ไหน", "ráan khǎai yaa yùu thîi-nǎi"),
        p(.emergency, "I feel sick", "ฉันไม่สบาย", "chǎn mâi sà-baai"),
        p(.emergency, "I have a fever", "ฉันมีไข้", "chǎn mii khâi"),
        p(.emergency, "I have a stomach ache", "ฉันปวดท้อง", "chǎn bpùat tháwng"),
        p(.emergency, "I have diarrhea", "ฉันท้องเสีย", "chǎn tháwng-sǐa"),
        p(.emergency, "I'm allergic to penicillin", "ฉันแพ้ยาเพนิซิลลิน", "chǎn pháe yaa phee-ní-sin-lin"),
        p(.emergency, "I lost my passport", "หนังสือเดินทางหาย", "nǎng-sʉ̌ʉ-dəən-thaang hǎai"),
        p(.emergency, "Someone stole my bag", "กระเป๋าถูกขโมย", "grà-bpǎo thùuk khà-mooi")
    ]
}
