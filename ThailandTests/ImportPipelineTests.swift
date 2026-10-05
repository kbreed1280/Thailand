import CoreData
import MapKit
import XCTest
@testable import Thailand

// MARK: - Link parsing

final class LinkReaderTests: XCTestCase {
    func testReadsTikTokLocationTag() {
        let html = #"…"itemStruct":{"desc":"best bar","poi":{"name":"Secret Mountain Bar","address":"Ko Pha-ngan District, Surat Thani 84280, Thailand","city":"Ko Pha-ngan","note":"a {brace} in text","ttTypeNameTiny":"Bar","ttTypeNameMedium":"Nightlife"},"other":1}…"#
        let poi = LinkReader.parseTikTokPOI(html)
        XCTAssertEqual(poi?.name, "Secret Mountain Bar")
        XCTAssertEqual(poi?.city, "Ko Pha-ngan")
        XCTAssertEqual(poi?.isArea, false)
        let island = LinkReader.parseTikTokPOI(#""poi":{"name":"Ko Pha Ngan Island","address":"Ko Pha-ngan District","city":"Ko Pha-ngan","ttTypeNameTiny":"Island"}"#)
        XCTAssertEqual(island?.isArea, true, "an island narrows the search, it isn't a spot")
        XCTAssertNil(LinkReader.parseTikTokPOI("no tag here"))
    }

    func testHashtagsBecomeSearchPhrases() {
        let caption = "This is 1000% the best bar I’ve been to so far #Thailand #KohPhaNgan #SoloTravel #Secretbar #Travelvlog #rooftopbar #nightmarket"
        XCTAssertEqual(ImportPipeline.searchKeywords(from: caption), ["secret bar", "rooftop bar", "night market"])
    }

    func testTikTokShareLinksAreShortLinks() {
        XCTAssertTrue(LinkReader.isShortLink(URL(string: "https://www.tiktok.com/t/ZPLRKLpWT/")!))
        XCTAssertTrue(LinkReader.isShortLink(URL(string: "https://tiktok.com/t/ZPLRKLpWT/")!))
        XCTAssertTrue(LinkReader.isShortLink(URL(string: "https://vm.tiktok.com/ZMabc/")!))
        XCTAssertFalse(LinkReader.isShortLink(URL(string: "https://www.tiktok.com/@a/video/1")!))
    }

    func testTikTokPhotoSlideshowFallsBackToVideoPath() {
        let photo = URL(string: "https://www.tiktok.com/@digital.travels_/photo/7686750233367301398?_r=1&_t=ZP-9AH")!
        XCTAssertEqual(LinkReader.tiktokVideoURL(forPhoto: photo)?.absoluteString,
                       "https://www.tiktok.com/@digital.travels_/video/7686750233367301398")
        XCTAssertNil(LinkReader.tiktokVideoURL(forPhoto: URL(string: "https://www.tiktok.com/@a/video/1")!))
    }

    func testPlatformDetection() {
        XCTAssertEqual(SourcePlatform(url: URL(string: "https://www.tiktok.com/@x/video/1")), .tiktok)
        XCTAssertEqual(SourcePlatform(url: URL(string: "https://www.instagram.com/reel/Cabc/")), .instagram)
        XCTAssertEqual(SourcePlatform(url: URL(string: "https://youtube.com/shorts/abc")), .youtube)
        XCTAssertEqual(SourcePlatform(url: URL(string: "https://maps.app.goo.gl/AbC123")), .googleMaps)
        XCTAssertEqual(SourcePlatform(url: URL(string: "https://www.google.com/maps/place/Wat+Arun")), .googleMaps)
        XCTAssertEqual(SourcePlatform(url: URL(string: "https://www.timeout.com/bangkok/restaurants")), .web)
        XCTAssertEqual(SourcePlatform(url: nil), .screenshot)
    }

    func testGoogleMapsPlaceLink() {
        let url = URL(string: "https://www.google.com/maps/place/Jay+Fai/@13.7524,100.5045,17z/data=!3m1!4b1!4m6!3m5!1s0x0:0x0!8m2!3d13.752418!4d100.504536")!
        let place = LinkReader.parseGoogleMaps(url)
        XCTAssertEqual(place?.name, "Jay Fai")
        XCTAssertEqual(place?.coordinate?.latitude ?? 0, 13.752418, accuracy: 1e-6) // the pin, not the map center
        XCTAssertEqual(place?.coordinate?.longitude ?? 0, 100.504536, accuracy: 1e-6)
    }

    func testGoogleMapsQueryLinks() {
        XCTAssertEqual(LinkReader.parseGoogleMaps(URL(string: "https://maps.google.com/?q=Chatuchak+Weekend+Market")!)?.name,
                       "Chatuchak Weekend Market")
        let pinned = LinkReader.parseGoogleMaps(URL(string: "https://www.google.com/maps?q=13.7563,100.5018")!)
        XCTAssertEqual(pinned?.name, "Pinned location")
        XCTAssertEqual(pinned?.coordinate?.latitude ?? 0, 13.7563, accuracy: 1e-6)
    }

    func testOpenGraphAndTitle() {
        let html = """
        <html><head><title>Ignored &amp; title</title>
        <meta property="og:title" content="10 Bangkok eats you can&#39;t miss">
        <meta property="og:description" content='📍 Jay Fai – crab omelette'>
        <meta name="description" content="fallback">
        </head></html>
        """
        let og = LinkReader.parseOpenGraph(html)
        XCTAssertEqual(og["og:title"], "10 Bangkok eats you can't miss")
        XCTAssertEqual(og["og:description"], "📍 Jay Fai – crab omelette")
        XCTAssertEqual(og["description"], "fallback")
        XCTAssertEqual(LinkReader.parseTitle(html), "Ignored & title")
    }

    func testJSONLDPlacesIncludingListsAndGraph() {
        let html = """
        <script type="application/ld+json">
        {"@context":"https://schema.org","@graph":[
          {"@type":"WebPage","name":"Guide"},
          {"@type":"ItemList","itemListElement":[
            {"@type":"ListItem","item":{"@type":"Restaurant","name":"Jay Fai",
              "address":{"streetAddress":"327 Maha Chai Rd","addressLocality":"Bangkok"},
              "geo":{"latitude":13.7524,"longitude":100.5045}}},
            {"@type":"ListItem","item":{"@type":"CafeOrCoffeeShop","name":"Gallery Drip Coffee"}}
          ]}
        ]}
        </script>
        """
        let places = LinkReader.parseJSONLDPlaces(html)
        XCTAssertEqual(places.map(\.name), ["Jay Fai", "Gallery Drip Coffee"])
        XCTAssertEqual(places[0].address, "327 Maha Chai Rd, Bangkok")
        XCTAssertEqual(places[0].coordinate?.latitude ?? 0, 13.7524, accuracy: 1e-6)
    }

    func testVisibleTextStripsScriptsAndTags() {
        let text = LinkReader.visibleText("<style>.a{}</style><p>Try <b>Jok Prince</b></p><script>var x=1</script><li>Nai Mong</li>", limit: 100)
        XCTAssertTrue(text.contains("Try Jok Prince"))
        XCTAssertTrue(text.contains("Nai Mong"))
        XCTAssertFalse(text.contains("var x"))
    }

    func testOEmbedParsing() {
        let json = #"{"title":"Best pad thai 🍜 #bangkok","author_unique_id":"eatwithme","thumbnail_url":"https://p16.example/t.jpg"}"#
        let o = LinkReader.parseOEmbed(Data(json.utf8))
        XCTAssertEqual(o?.title, "Best pad thai 🍜 #bangkok")
        XCTAssertEqual(o?.author, "@eatwithme")
        XCTAssertEqual(o?.thumbnail?.host, "p16.example")
    }

    func testShortLinks() {
        XCTAssertTrue(LinkReader.isShortLink(URL(string: "https://vm.tiktok.com/ZMabc/")!))
        XCTAssertTrue(LinkReader.isShortLink(URL(string: "https://maps.app.goo.gl/xyz")!))
        XCTAssertFalse(LinkReader.isShortLink(URL(string: "https://www.tiktok.com/@x/video/1")!))
    }
}

// MARK: - Extraction

final class PlaceExtractionTests: XCTestCase {
    func testPinEmojiAndNumberedLists() {
        let caption = """
        3 must-eats in Bangkok's old town 🔥
        📍 Jay Fai – crab omelette, book ahead
        2. Thipsamai Pad Thai: the orange juice too
        3) Krua Apsorn
        #bangkokfood #fyp
        """
        let names = CaptionRulesExtractor.places(in: caption).map(\.name)
        XCTAssertEqual(names, ["Jay Fai", "Thipsamai Pad Thai", "Krua Apsorn"])
        let first = CaptionRulesExtractor.places(in: caption)[0]
        XCTAssertEqual(first.cityHint, "Bangkok")
        XCTAssertTrue(first.recommendation.contains("crab omelette"))
    }

    func testHashtagFallback() {
        let names = CaptionRulesExtractor.places(in: "Sunset vibes 🌅 #WatArun #fyp #thailand").map(\.name)
        XCTAssertTrue(names.contains("Wat Arun"))
        XCTAssertFalse(names.contains("fyp"))
    }

    func testDeclaredPlacesComeFirstAndDeduplicate() async {
        struct Stub: PlaceExtracting {
            let name = "stub"
            func extract(from content: LinkContent) async throws -> [ExtractedPlace] {
                [ExtractedPlace(name: "jay fai"), ExtractedPlace(name: "Krua Apsorn")]
            }
        }
        var content = LinkContent(url: nil, platform: .web, text: "x")
        content.declaredPlaces = [.init(name: "Jay Fai", address: "Bangkok", coordinate: nil)]
        let result = await PlaceExtractor.extract(from: content, using: Stub())
        XCTAssertEqual(result.places.map(\.name), ["Jay Fai", "Krua Apsorn"])
        XCTAssertEqual(result.extractor, "stub")
    }

    func testFallsBackToRulesWhenModelFails() async {
        struct Failing: PlaceExtracting {
            let name = "apple-intelligence"
            struct Boom: Error {}
            func extract(from content: LinkContent) async throws -> [ExtractedPlace] { throw Boom() }
        }
        let content = LinkContent(url: nil, platform: .tiktok, text: "📍 Jodd Fairs – night market")
        let result = await PlaceExtractor.extract(from: content, using: Failing())
        XCTAssertEqual(result.places.map(\.name), ["Jodd Fairs"])
        XCTAssertEqual(result.extractor, "caption-rules")
    }

    func testCategories() {
        XCTAssertEqual(SpotCategory(word: "rooftop bar"), .sip)
        XCTAssertEqual(SpotCategory(word: "specialty coffee"), .brew)
        XCTAssertEqual(SpotCategory(word: "street food"), .eat)
        XCTAssertEqual(SpotCategory(word: "temple"), .explore)
        XCTAssertEqual(SpotCategory(poi: .cafe), .brew)
        XCTAssertEqual(SpotCategory(poi: .nightlife), .sip)
        XCTAssertEqual(SpotCategory(poi: .hotel), .go)
    }
}

// MARK: - Matching & dedup

final class PlaceMatchingTests: XCTestCase {
    private func item(_ name: String, _ lat: Double, _ lon: Double) -> MKMapItem {
        let i = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)))
        i.name = name
        return i
    }

    func testNameSimilarity() {
        XCTAssertGreaterThanOrEqual(NameMatch.similarity("Jay Fai", "Raan Jay Fai"), 0.9)
        XCTAssertLessThan(NameMatch.similarity("Jay Fai", "Wat Arun"), 0.3)
    }

    func testBestMatchPrefersNameAndProximityAndRejectsJunk() {
        let bangkok = CLLocationCoordinate2D(latitude: 13.75, longitude: 100.50)
        let results = [item("Jay Fai Phuket Branch", 7.88, 98.39), item("Raan Jay Fai", 13.7524, 100.5045)]
        XCTAssertEqual(AppleMapsLocator.bestMatch(for: "Jay Fai", in: results, near: bangkok)?.name, "Raan Jay Fai")
        XCTAssertNil(AppleMapsLocator.bestMatch(for: "Jay Fai", in: [item("7-Eleven", 13.75, 100.5)], near: bangkok))
    }

    @MainActor
    func testDedupByCoordinatesAndName() throws {
        let context = PersistenceController(inMemory: true).viewContext
        let trip = ItineraryStore(context: context).createTrip(name: "T", start: .now, end: .now)
        let existing = Spot(context: context)
        existing.name = "Jay Fai"
        existing.coordinate = CLLocationCoordinate2D(latitude: 13.7524, longitude: 100.5045)
        existing.trip = trip

        let near = CLLocationCoordinate2D(latitude: 13.7526, longitude: 100.5046) // ~25 m away
        XCTAssertEqual(ImportPipeline.existingSpot(name: "Raan Jay Fai", coordinate: near, appleMapsID: nil, in: trip.allSpots), existing)
        XCTAssertNil(ImportPipeline.existingSpot(name: "Thipsamai", coordinate: near, appleMapsID: nil, in: trip.allSpots))
        let far = CLLocationCoordinate2D(latitude: 13.80, longitude: 100.55)
        XCTAssertNil(ImportPipeline.existingSpot(name: "Jay Fai", coordinate: far, appleMapsID: nil, in: trip.allSpots))
    }
}

// MARK: - Full pipeline (stubbed network)

@MainActor
final class ImportPipelineTests: XCTestCase {
    struct StubLocator: PlaceLocating {
        func search(_ query: String, near area: TravelArea?) async -> [MKMapItem] { [] }
        func locate(_ place: ExtractedPlace, near area: TravelArea?, declared: CLLocationCoordinate2D?) async -> MKMapItem? {
            guard place.name != "Mystery Stall" else { return nil } // simulates "not found"
            let i = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 13.75, longitude: 100.5 + Double(place.name.count) / 1000)))
            i.name = place.name
            return i
        }
    }

    private func makePipeline(text: String) -> ImportPipeline {
        let p = ImportPipeline()
        p.locator = StubLocator()
        p.reader = { url, _ in LinkContent(url: url, platform: .tiktok, title: "Old town eats", creator: "@eater", text: text) }
        p.extractor = { CaptionRulesExtractor() }
        return p
    }

    func testImportCreatesDraftsWithScoopsAndFlagsUnplotted() async throws {
        let context = PersistenceController(inMemory: true).viewContext
        let trip = ItineraryStore(context: context).createTrip(name: "T", start: .now, end: .now)
        let pipeline = makePipeline(text: "📍 Jay Fai – crab omelette\n📍 Mystery Stall – no idea where")
        let source = try XCTUnwrap(pipeline.addSource(url: URL(string: "https://www.tiktok.com/@eater/video/1"), text: nil, to: trip, context: context))
        await pipeline.importPending(in: trip, context: context)

        XCTAssertEqual(source.status, .ready)
        XCTAssertEqual(source.creator, "@eater")
        XCTAssertEqual(source.draftSpots.map(\.displayName).sorted(), ["Jay Fai", "Mystery Stall"])
        let jay = try XCTUnwrap(source.draftSpots.first { $0.displayName == "Jay Fai" })
        XCTAssertFalse(jay.isUnplotted)
        XCTAssertTrue(jay.sortedScoops.first?.recommendation?.contains("crab omelette") == true)
        XCTAssertTrue(source.draftSpots.first { $0.displayName == "Mystery Stall" }!.isUnplotted)
    }

    func testSameLinkIsNotImportedTwiceAndSecondPostMergesIntoSpot() async throws {
        let context = PersistenceController(inMemory: true).viewContext
        let trip = ItineraryStore(context: context).createTrip(name: "T", start: .now, end: .now)
        let pipeline = makePipeline(text: "📍 Jay Fai – crab omelette")
        let url = URL(string: "https://www.tiktok.com/@eater/video/1")!
        pipeline.addSource(url: url, text: nil, to: trip, context: context)
        XCTAssertNil(pipeline.addSource(url: url, text: nil, to: trip, context: context))
        await pipeline.importPending(in: trip, context: context)

        pipeline.addSource(url: URL(string: "https://www.tiktok.com/@other/video/2"), text: nil, to: trip, context: context)
        await pipeline.importPending(in: trip, context: context)
        XCTAssertEqual(trip.allSpots.count, 1, "Second post about the same place should add a scoop, not a spot")
        XCTAssertEqual(trip.allSpots.first?.sortedScoops.count, 2)
    }

    func testUnreadablePostFailsWithHelpfulMessage() async throws {
        let context = PersistenceController(inMemory: true).viewContext
        let trip = ItineraryStore(context: context).createTrip(name: "T", start: .now, end: .now)
        let pipeline = makePipeline(text: "")
        let source = try XCTUnwrap(pipeline.addSource(url: URL(string: "https://www.instagram.com/reel/x/"), text: nil, to: trip, context: context))
        await pipeline.importPending(in: trip, context: context)
        XCTAssertEqual(source.status, .failed)
        XCTAssertFalse((source.errorMessage ?? "").isEmpty)
    }

    func testScreenshotTextImport() async throws {
        let context = PersistenceController(inMemory: true).viewContext
        let trip = ItineraryStore(context: context).createTrip(name: "T", start: .now, end: .now)
        let pipeline = makePipeline(text: "")
        let source = try XCTUnwrap(pipeline.addSource(url: nil, text: "📍 Krua Apsorn – crab curry", to: trip, context: context))
        await pipeline.importPending(in: trip, context: context)
        XCTAssertEqual(source.platform, .screenshot)
        XCTAssertEqual(source.draftSpots.map(\.displayName), ["Krua Apsorn"])
    }
}

final class ArticleExtractionTests: XCTestCase {
    func testProperNamesFromListHeadings() {
        XCTAssertEqual(CaptionRulesExtractor.properNames(in: "Admire the grandeur of Wat Phra Kaew and the Grand Palace"),
                       ["Wat Phra Kaew", "Grand Palace"])
        XCTAssertEqual(CaptionRulesExtractor.properNames(in: "Browse thousands of stalls at Chatuchak Weekend Market"),
                       ["Chatuchak Weekend Market"])
        XCTAssertEqual(CaptionRulesExtractor.properNames(in: "Feast on Bangkok’s famous street food"), [])
    }

    func testArticleTextSkipsNavigationAndPutsHeadingsFirst() {
        let html = """
        <header><nav><a>Destinations</a><a>Europe</a></nav></header>
        <article><h1>16 best things to do in Bangkok</h1><p>Intro text.</p>
        <h2>1. Admire the grandeur of Wat Phra Kaew and the Grand Palace</h2><p>Details…</p>
        <h2>6. Marvel at the majesty of Wat Pho</h2></article>
        <footer>Cookie settings</footer>
        """
        let text = LinkReader.articleText(html, limit: 2_000)
        XCTAssertFalse(text.contains("Destinations"))
        XCTAssertFalse(text.contains("Cookie"))
        XCTAssertTrue(text.hasPrefix("16 best things to do in Bangkok"))
        let places = CaptionRulesExtractor.places(in: text).map(\.name)
        XCTAssertTrue(places.contains("Wat Phra Kaew"))
        XCTAssertTrue(places.contains("Grand Palace"))
        XCTAssertTrue(places.contains("Wat Pho"))
    }
}

final class ArticleStructureTests: XCTestCase {
    func testPrefersMainOverRelatedArticleCards() {
        let html = """
        <main><h2>1. Marvel at the majesty of Wat Pho</h2><p>\(String(repeating: "Text. ", count: 50))</p></main>
        <aside><article><h3>Related: Best beaches in Krabi</h3></article></aside>
        <article><h3>Related: Chiang Mai guide</h3></article>
        """
        let text = LinkReader.articleText(html, limit: 2_000)
        XCTAssertTrue(text.contains("Wat Pho"))
        XCTAssertFalse(text.contains("Chiang Mai guide"))
    }
}

final class StrictMatchTests: XCTestCase {
    private func item(_ name: String) -> MKMapItem {
        let i = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 13.74, longitude: 100.51)))
        i.name = name
        return i
    }

    func testGuessesNeedMutualMatch() {
        let anchor = CLLocationCoordinate2D(latitude: 13.75, longitude: 100.5)
        XCTAssertNil(AppleMapsLocator.bestMatch(for: "Chao Phraya River", in: [item("Four Seasons Hotel Bangkok at Chao Phraya River")], near: anchor, strict: true))
        XCTAssertNil(AppleMapsLocator.bestMatch(for: "Chinatown", in: [item("Chinatown Night Market Chaloem Buri")], near: anchor, strict: true))
        XCTAssertNil(AppleMapsLocator.bestMatch(for: "Chinatown", in: [item("I'm Chinatown")], near: anchor, strict: true))
        XCTAssertEqual(AppleMapsLocator.bestMatch(for: "Grand Palace", in: [item("The Grand Palace")], near: anchor, strict: true)?.name, "The Grand Palace")
        // Non-strict (explicit 📍 / AI names) still allows "Jay Fai" → "Raan Jay Fai".
        XCTAssertNotNil(AppleMapsLocator.bestMatch(for: "Jay Fai", in: [item("Raan Jay Fai")], near: anchor))
    }
}

final class GenericNameTests: XCTestCase {
    func testGenericNames() {
        XCTAssertTrue(NameMatch.isGeneric("Night Market"))
        XCTAssertTrue(NameMatch.isGeneric("Thai Massage"))
        XCTAssertTrue(NameMatch.isGeneric("Bangkok Shopping Spree"))
        XCTAssertFalse(NameMatch.isGeneric("Jim Thompson House"))
        XCTAssertFalse(NameMatch.isGeneric("Chatuchak Weekend Market"))
    }

    func testGenericAINamesBecomeStrictGuesses() async {
        struct Stub: PlaceExtracting {
            let name = "apple-intelligence"
            func extract(from content: LinkContent) async throws -> [ExtractedPlace] {
                [ExtractedPlace(name: "Night Market"), ExtractedPlace(name: "Wat Pho")]
            }
        }
        let result = await PlaceExtractor.extract(from: LinkContent(url: nil, platform: .web, text: "x"), using: Stub())
        XCTAssertEqual(result.places.first { $0.name == "Night Market" }?.isGuess, true)
        XCTAssertEqual(result.places.first { $0.name == "Wat Pho" }?.isGuess, false)
    }
}
