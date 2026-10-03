import XCTest
import CoreLocation
@testable import Thailand

final class TravelVideoTests: XCTestCase {
    func testDetectsAreaFromCaption() {
        XCTAssertEqual(TravelArea.detect(in: "Best khao soi in Chiang Mai 🍜 #chiangmai #thailand")?.name, "Chiang Mai")
        XCTAssertEqual(TravelArea.detect(in: "Railay beach at sunset is unreal #krabi")?.name, "Krabi / Ao Nang")
        XCTAssertEqual(TravelArea.detect(in: "Jodd Fairs night market food tour")?.name, "Bangkok")
        XCTAssertEqual(TravelArea.detect(in: "Maya Bay is open again!")?.name, "Koh Phi Phi")
        XCTAssertNil(TravelArea.detect(in: "My morning routine ☕️"))
    }

    func testNearestArea() {
        let grandPalace = CLLocationCoordinate2D(latitude: 13.7500, longitude: 100.4913)
        XCTAssertEqual(TravelArea.nearest(to: grandPalace)?.name, "Bangkok")
        let tokyo = CLLocationCoordinate2D(latitude: 35.68, longitude: 139.76)
        XCTAssertNil(TravelArea.nearest(to: tokyo))
    }

    func testSearchQueriesFromCaption() {
        let q = TravelVideos.candidateQueries(from: "Must-try mango sticky rice 🥭 #KorPanich #fyp #thailand")
        XCTAssertEqual(q.first, "Must-try mango sticky rice")
        XCTAssertTrue(q.contains("Kor Panich"))
        XCTAssertFalse(q.contains("fyp"))
    }

    func testVideoLinks() {
        XCTAssertTrue(TravelVideos.isVideoLink("https://www.tiktok.com/@x/video/123"))
        XCTAssertTrue(TravelVideos.isVideoLink("https://vm.tiktok.com/ZMabc/"))
        XCTAssertFalse(TravelVideos.isVideoLink("https://www.grandpalace.thailand.com"))
        XCTAssertFalse(TravelVideos.isVideoLink(nil))
    }

    func testFirstURLInSharedText() {
        let text = "Check this out! https://vm.tiktok.com/ZMh123abc/ #bangkok"
        XCTAssertEqual(SharedInbox.firstURL(in: text)?.absoluteString, "https://vm.tiktok.com/ZMh123abc/")
    }
}
