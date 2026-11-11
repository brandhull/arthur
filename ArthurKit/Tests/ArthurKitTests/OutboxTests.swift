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

final class FolderParseTests: XCTestCase {
    func testNestedFoldersAndMissingCounts() {
        let text = """
        * <A> Personal (23 docs)
          * <B> Blog
            * <C> 02 Ready
          * <D> Apps (12 docs)
        * <E> Church (6 docs)
        """
        let f = CraftClient.parseFolders(text)
        XCTAssertEqual(f.map(\.path), ["Personal", "Personal / Blog", "Personal / Blog / 02 Ready", "Personal / Apps", "Church"])
        XCTAssertEqual(f[2].id, "C")
        XCTAssertEqual(f[2].name, "02 Ready")
    }
}
