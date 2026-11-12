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

final class OutboxStage2Tests: XCTestCase {
    func testNewItemKindsRoundTripAndOldItemsDecode() throws {
        let payload = try JSONSerialization.data(withJSONObject: ["Quote": "x", "Done": true])
        let items = [
            OutboxItem(kind: .newPage, text: "body", title: "T", folderId: "F", createdPageId: "P"),
            OutboxItem(kind: .task, text: "do it", dueDay: "2026-11-12", inboxId: "I"),
            OutboxItem(kind: .baserow, text: "x", tableId: 7, fieldsJSON: payload)
        ]
        let back = try JSONDecoder().decode([OutboxItem].self, from: JSONEncoder().encode(items))
        XCTAssertEqual(items, back)
        // A stage-1 item (no new keys) still decodes.
        let old = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","kind":"bit","text":"hi","createdAt":0}"#
        let item = try JSONDecoder().decode(OutboxItem.self, from: Data(old.utf8))
        XCTAssertEqual(item.kind, .bit)
        XCTAssertNil(item.title)
    }
}
