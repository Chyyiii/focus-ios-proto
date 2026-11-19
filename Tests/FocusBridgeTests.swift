import XCTest

// B3 §14.1–14.3: политика моста, ссылки, навигация, хранилище. Данные синтетические.
final class FocusBridgeTests: XCTestCase {
    private let page = URL(fileURLWithPath: "/tmp/web/index.html")
    private let now = ISO8601DateFormatter().date(from: "2026-11-18T06:00:00Z")!

    private func snapshotObject(generatedAt: String = "2026-11-18T05:12:00Z") -> [String: Any] {
        return ["schema": 1, "generatedAt": generatedAt, "forDate": "2026-11-18",
                "day": ["done": 1, "total": 3]]
    }

    private func eval(name: String = "focusSnapshot", main: Bool = true, proto: String = "file",
                      url: URL? = nil, expected: URL? = nil, body: Any) -> FocusBridgePolicy.Decision {
        return FocusBridgePolicy.evaluate(messageName: name, isMainFrame: main, originProtocol: proto,
                                          frameURL: url, expectedPage: expected, body: body)
    }

    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("focus-b3-" + UUID().uuidString)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: Bridge

    func testValidMessageAccepted() {
        guard case .accept(let data) = eval(body: ["snapshot": snapshotObject()]) else { return XCTFail("expected accept") }
        XCTAssertNoThrow(try SnapshotParser.parse(data))
    }

    func testWrongMessageNameRejected() {
        XCTAssertEqual(eval(name: "other", body: ["snapshot": snapshotObject()]), .reject(.unknownMessage))
    }

    func testNonMainFrameRejected() {
        XCTAssertEqual(eval(main: false, body: ["snapshot": snapshotObject()]), .reject(.notMainFrame))
    }

    func testNonFileOriginRejected() {
        XCTAssertEqual(eval(proto: "https", body: ["snapshot": snapshotObject()]), .reject(.blockedOrigin))
    }

    func testDocumentMustMatchExpectedPage() {
        let other = URL(fileURLWithPath: "/tmp/other/evil.html")
        XCTAssertEqual(eval(url: other, expected: page, body: ["snapshot": snapshotObject()]), .reject(.blockedOrigin))
        XCTAssertEqual(eval(url: nil, expected: page, body: ["snapshot": snapshotObject()]), .reject(.blockedOrigin))
        if case .accept = eval(url: page, expected: page, body: ["snapshot": snapshotObject()]) {} else { XCTFail("same page must pass") }
    }

    func testStructureRules() {
        XCTAssertEqual(eval(body: "text"), .reject(.badStructure))
        XCTAssertEqual(eval(body: [Any]()), .reject(.badStructure))
        XCTAssertEqual(eval(body: [String: Any]()), .reject(.badStructure))
        XCTAssertEqual(eval(body: ["snapshot": snapshotObject(), "extra": 1]), .reject(.badStructure))
        XCTAssertEqual(eval(body: ["other": snapshotObject()]), .reject(.badStructure))
        XCTAssertEqual(eval(body: ["snapshot": "string"]), .reject(.badStructure))
        XCTAssertEqual(eval(body: ["snapshot": [1, 2]]), .reject(.badStructure))
    }

    func testOversizedRejectedByUTF8Bytes() {
        var obj = snapshotObject()
        obj["pad"] = String(repeating: "я", count: 33_000) // 66 000 байт в UTF-8, но 33 000 символов
        XCTAssertEqual(eval(body: ["snapshot": obj]), .reject(.tooLarge))
    }

    func testB2ParserRulesApplied() {
        var noDate = snapshotObject(); noDate.removeValue(forKey: "forDate")
        XCTAssertEqual(eval(body: ["snapshot": noDate]), .reject(.invalidSnapshot))
        var badSchema = snapshotObject(); badSchema["schema"] = 2
        XCTAssertEqual(eval(body: ["snapshot": badSchema]), .reject(.invalidSnapshot))
        XCTAssertEqual(eval(body: ["snapshot": snapshotObject(generatedAt: "вчера")]), .reject(.invalidSnapshot))
    }

    // MARK: Deep links

    func testOnlyTodayDeepLinkAllowed() {
        XCTAssertTrue(FocusDeepLinkPolicy.allows(URL(string: "focus-app://today")!))
        XCTAssertTrue(FocusDeepLinkPolicy.allows(URL(string: "focus-app://today/")!))
        XCTAssertTrue(FocusDeepLinkPolicy.allows(URL(string: "FOCUS-APP://TODAY")!))
        for bad in ["focus-app://finance", "focus-app://today/extra", "focus-app://today?x=1", "focus-app://today#a",
                    "focus-app://user@today", "focus-app://today:80", "focus-app://", "focus-app:today",
                    "https://today", "javascript:alert(1)", "file:///etc/passwd", "tel:123", "other://today"] {
            XCTAssertFalse(FocusDeepLinkPolicy.allows(URL(string: bad)!), bad)
        }
    }

    func testNavigationPolicy() {
        let root = URL(fileURLWithPath: "/tmp/web", isDirectory: true)
        XCTAssertEqual(FocusNavigationPolicy.decide(URL(fileURLWithPath: "/tmp/web/index.html"), webRoot: root), .allow)
        XCTAssertEqual(FocusNavigationPolicy.decide(URL(fileURLWithPath: "/tmp/web/sub/a.js"), webRoot: root), .allow)
        XCTAssertEqual(FocusNavigationPolicy.decide(URL(fileURLWithPath: "/tmp/web/../secret.txt"), webRoot: root), .cancel)
        XCTAssertEqual(FocusNavigationPolicy.decide(URL(fileURLWithPath: "/tmp/webx/index.html"), webRoot: root), .cancel)
        XCTAssertEqual(FocusNavigationPolicy.decide(URL(fileURLWithPath: "/etc/hosts"), webRoot: root), .cancel)
        XCTAssertEqual(FocusNavigationPolicy.decide(URL(fileURLWithPath: "/tmp/web/index.html"), webRoot: nil), .cancel)
        XCTAssertEqual(FocusNavigationPolicy.decide(URL(string: "https://example.com")!, webRoot: root), .cancel)
        XCTAssertEqual(FocusNavigationPolicy.decide(URL(string: "http://example.com")!, webRoot: root), .cancel)
        XCTAssertEqual(FocusNavigationPolicy.decide(URL(string: "data:text/html,hi")!, webRoot: root), .cancel)
        XCTAssertEqual(FocusNavigationPolicy.decide(URL(string: "javascript:alert(1)")!, webRoot: root), .cancel)
        XCTAssertEqual(FocusNavigationPolicy.decide(URL(string: "focus-app://today")!, webRoot: root), .deepLinkToday)
        XCTAssertEqual(FocusNavigationPolicy.decide(URL(string: "focus-app://other")!, webRoot: root), .cancel)
        XCTAssertEqual(FocusNavigationPolicy.decide(URL(string: "about:blank")!, webRoot: root), .allow)
    }

    func testSymlinkEscapeBlocked() throws {
        let root = tempDir().appendingPathComponent("web", isDirectory: true)
        let outside = tempDir()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "x".write(to: outside.appendingPathComponent("secret.txt"), atomically: true, encoding: .utf8)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        XCTAssertEqual(FocusNavigationPolicy.decide(link.appendingPathComponent("secret.txt"), webRoot: root), .cancel)
    }

    // MARK: Storage

    func testWriteValidatedAndRead() throws {
        let store = AppGroupSnapshotStore(directory: tempDir())
        let data = try JSONSerialization.data(withJSONObject: snapshotObject())
        try store.writeValidated(data, now: now)
        guard case .snapshot(let s, let prev) = store.load() else { return XCTFail("expected snapshot") }
        XCTAssertEqual(s.forDate, "2026-11-18")
        XCTAssertFalse(prev)
    }

    func testInvalidNotWritten() {
        let store = AppGroupSnapshotStore(directory: tempDir())
        XCTAssertThrowsError(try store.writeValidated(Data("{not json".utf8), now: now)) {
            XCTAssertEqual($0 as? AppGroupStoreError, .invalidSnapshot)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.primaryURL.path))
        XCTAssertEqual(store.load(), .noData)
    }

    func testNoDayNotWritten() throws {
        let store = AppGroupSnapshotStore(directory: tempDir())
        let data = Data(Fixtures.noDay.utf8)
        XCTAssertThrowsError(try store.writeValidated(data, now: now))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.primaryURL.path))
    }

    func testOversizedNotWritten() {
        let store = AppGroupSnapshotStore(directory: tempDir())
        var obj = snapshotObject(); obj["pad"] = String(repeating: "a", count: 70_000)
        let data = try! JSONSerialization.data(withJSONObject: obj)
        XCTAssertThrowsError(try store.writeValidated(data, now: now))
    }

    func testStaleAndFutureRejected() throws {
        let store = AppGroupSnapshotStore(directory: tempDir())
        let old = try JSONSerialization.data(withJSONObject: snapshotObject(generatedAt: "2026-11-10T00:00:00Z"))
        XCTAssertThrowsError(try store.writeValidated(old, now: now)) { XCTAssertEqual($0 as? AppGroupStoreError, .stale) }
        let future = try JSONSerialization.data(withJSONObject: snapshotObject(generatedAt: "2026-11-18T07:00:00Z"))
        XCTAssertThrowsError(try store.writeValidated(future, now: now)) { XCTAssertEqual($0 as? AppGroupStoreError, .invalidSnapshot) }
        let skew = try JSONSerialization.data(withJSONObject: snapshotObject(generatedAt: "2026-11-18T06:03:00Z"))
        XCTAssertNoThrow(try store.writeValidated(skew, now: now))
    }

    func testPreviousKeptAndUsedForRecovery() throws {
        let store = AppGroupSnapshotStore(directory: tempDir())
        let a = try JSONSerialization.data(withJSONObject: snapshotObject(generatedAt: "2026-11-18T05:00:00Z"))
        let b = try JSONSerialization.data(withJSONObject: snapshotObject(generatedAt: "2026-11-18T05:30:00Z"))
        try store.writeValidated(a, now: now)
        try store.writeValidated(b, now: now)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.previousURL.path))
        // портим основной файл — виджет должен прочитать .prev
        try Data("{broken".utf8).write(to: store.primaryURL)
        guard case .snapshot(_, let fromPrev) = store.load() else { return XCTFail("expected recovery") }
        XCTAssertTrue(fromPrev)
    }

    func testRepeatedSameSnapshotIsIdempotent() throws {
        let store = AppGroupSnapshotStore(directory: tempDir())
        let a = try JSONSerialization.data(withJSONObject: snapshotObject(), options: [.sortedKeys])
        try store.writeValidated(a, now: now)
        try store.writeValidated(a, now: now)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.previousURL.path))
    }

    func testMissingAppGroupHandled() {
        // Контейнер недоступен (поставщик возвращает nil) — должен быть именно .containerUnavailable.
        XCTAssertThrowsError(try AppGroupSnapshotStore(containerProvider: { _ in nil })) {
            XCTAssertEqual($0 as? AppGroupStoreError, .containerUnavailable)
        }
    }

    func testAvailableContainerProviderUsedWithWidgetSubdirectory() throws {
        let base = tempDir()
        let store = try AppGroupSnapshotStore(groupIdentifier: "group.test", containerProvider: { id in
            XCTAssertEqual(id, "group.test")
            return base
        })
        XCTAssertEqual(store.directory.lastPathComponent, "widget")
        XCTAssertTrue(store.directory.path.hasPrefix(base.path))
    }

    func testEmptyStoreIsNoData() {
        XCTAssertEqual(AppGroupSnapshotStore(directory: tempDir()).load(), .noData)
    }

    func testDefaultGroupIdentifier() {
        XCTAssertEqual(AppGroupSnapshotStore.defaultGroupIdentifier, "group.com.focusproto.app")
    }
}
