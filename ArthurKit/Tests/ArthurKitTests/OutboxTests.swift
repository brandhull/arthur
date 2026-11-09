import XCTest
@testable import ArthurKit

final class OutboxTests: XCTestCase {
    func testOnlyClearOfflineErrorsQueue() {
        XCTAssertTrue(isClearlyOffline(URLError(.notConnectedToInternet)))
        XCTAssertTrue(isClearlyOffline(URLError(.dataNotAllowed)))
        XCTAssertFalse(isClearlyOffline(URLError(.timedOut)))
        XCTAssertFalse(isClearlyOffline(URLError(.networkConnectionLost)))
        XCTAssertFalse(isClearlyOffline(BaserowError.http(500, "x")))
    }

    func testItemRoundTrips() throws {
        let item = OutboxItem(kind: .craftPage, text: "hi", pageId: "p", pageTitle: "T")
        let back = try JSONDecoder().decode(OutboxItem.self, from: JSONEncoder().encode(item))
        XCTAssertEqual(item, back)
        XCTAssertEqual(back.label, "T")
    }
}
