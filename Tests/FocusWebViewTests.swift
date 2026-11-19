import XCTest
import WebKit

// B3 §14.4: реальный WKWebView в симуляторе. Страницы — временные, снимки синтетические.
// Отправитель — настоящий Web/FocusSnapshotSender.js (ресурс тестового бандла).
final class FocusWebViewTests: XCTestCase {
    private var dir: URL!
    private var webView: WKWebView!
    private var events: [FocusBridgeEvent] = []
    private var navDelegate: FocusNavigationDelegate!
    private var store: AppGroupSnapshotStore!
    private var stored: XCTestExpectation?

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("focus-wv-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let sender = try XCTUnwrap(Bundle(for: FocusWebViewTests.self).url(forResource: "FocusSnapshotSender", withExtension: "js"),
                                   "FocusSnapshotSender.js не найден в тестовом бандле")
        try FileManager.default.copyItem(at: sender, to: dir.appendingPathComponent("FocusSnapshotSender.js"))
        store = AppGroupSnapshotStore(directory: dir.appendingPathComponent("store", isDirectory: true))
        events = []
    }

    private func nowISO() -> String { return ISO8601DateFormatter().string(from: Date()) }

    private func makeWebView(page: String, expectedPage: URL) -> WKWebView {
        let handler = FocusBridgeHandler(expectedPage: expectedPage, store: { [unowned self] in .success(self.store) },
                                         onEvent: { [unowned self] in self.events.append($0) })
        let config = FocusWebConfig.makeConfiguration(handler: handler)
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 600), configuration: config)
        navDelegate = FocusNavigationDelegate(webRoot: dir, onEvent: { [unowned self] in self.events.append($0) })
        web.navigationDelegate = navDelegate
        return web
    }

    private func load(_ html: String, file: String = "index.html") throws {
        let url = dir.appendingPathComponent(file)
        try html.write(to: url, atomically: true, encoding: .utf8)
        webView = makeWebView(page: html, expectedPage: url)
        webView.loadFileURL(url, allowingReadAccessTo: dir)
    }

    private func waitUntil(_ timeout: TimeInterval = 15, _ condition: () -> Bool) {
        let end = Date().addingTimeInterval(timeout)
        while !condition() && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
    }

    private func page(script: String) -> String {
        return "<!doctype html><html><head><script src=\"FocusSnapshotSender.js\"></script></head><body><script>\(script)</script></body></html>"
    }

    func testRealSenderDeliversSnapshotToStorage() throws {
        let js = "window.FOCUSNativeSnapshot.send(function(){return {schema:1,generatedAt:'\(nowISO())',forDate:'2026-11-18',day:{done:1,total:2}};});"
        try load(page(script: js))
        waitUntil { self.events.contains(.snapshotStored) }
        XCTAssertTrue(events.contains(.snapshotStored), "события: \(events)")
        guard case .snapshot(let snap, _) = store.load() else { return XCTFail("снимок не прочитан") }
        XCTAssertEqual(snap.forDate, "2026-11-18")
    }

    func testExtraKeyRejectedAndNothingStored() throws {
        let js = "window.webkit.messageHandlers.focusSnapshot.postMessage({snapshot:{schema:1},extra:1});"
        try load(page(script: js))
        waitUntil { !self.events.filter { if case .snapshotRejected = $0 { return true } else { return false } }.isEmpty }
        XCTAssertTrue(events.contains(.snapshotRejected(.badStructure)), "события: \(events)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.primaryURL.path))
    }

    func testInvalidSnapshotRejectedAndNothingStored() throws {
        let js = "window.webkit.messageHandlers.focusSnapshot.postMessage({snapshot:{schema:1,generatedAt:'x',forDate:'y'}});"
        try load(page(script: js))
        waitUntil { self.events.contains(.snapshotRejected(.invalidSnapshot)) }
        XCTAssertTrue(events.contains(.snapshotRejected(.invalidSnapshot)), "события: \(events)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.primaryURL.path))
    }

    func testSenderRefusesOversizedBeforePosting() throws {
        let js = "window.__r = window.FOCUSNativeSnapshot.send(function(){return {schema:1,generatedAt:'\(nowISO())',forDate:'2026-11-18',day:{done:1,total:2},pad:new Array(40000).join('я')};});"
        try load(page(script: js))
        waitUntil { self.events.contains(.pageLoaded) }
        var result: Any?
        let done = expectation(description: "js")
        webView.evaluateJavaScript("window.__r") { value, _ in result = value; done.fulfill() }
        wait(for: [done], timeout: 10)
        XCTAssertEqual(result as? Bool, false)
        XCTAssertFalse(events.contains(.snapshotStored))
    }

    func testMessageFromChildFrameRejected() throws {
        let child = "<!doctype html><html><body><script>window.webkit.messageHandlers.focusSnapshot.postMessage({snapshot:{schema:1,generatedAt:'\(nowISO())',forDate:'2026-11-18',day:{done:1,total:2}}});</script></body></html>"
        try child.write(to: dir.appendingPathComponent("child.html"), atomically: true, encoding: .utf8)
        try load("<!doctype html><html><body><iframe src=\"child.html\"></iframe></body></html>")
        waitUntil { self.events.contains(.snapshotRejected(.notMainFrame)) }
        XCTAssertTrue(events.contains(.snapshotRejected(.notMainFrame)), "события: \(events)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.primaryURL.path))
    }

    func testExternalNavigationBlocked() throws {
        try load(page(script: "setTimeout(function(){ location.href = 'https://example.com/'; }, 200);"))
        waitUntil { self.events.contains(.navigationBlocked("https")) }
        XCTAssertTrue(events.contains(.navigationBlocked("https")), "события: \(events)")
        XCTAssertEqual(webView.url?.isFileURL, true)
    }

    func testUnknownSchemeAndForeignFileBlocked() throws {
        try load(page(script: "setTimeout(function(){ location.href = 'focus-app://finance'; }, 200); setTimeout(function(){ location.href = 'file:///etc/hosts'; }, 600);"))
        waitUntil { self.events.filter { $0 == .navigationBlocked("file") }.count >= 1 }
        XCTAssertTrue(events.contains(.navigationBlocked("focus-app")), "события: \(events)")
        XCTAssertTrue(events.contains(.navigationBlocked("file")), "события: \(events)")
        XCTAssertEqual(webView.url?.isFileURL, true)
    }

    func testDeepLinkTodayHandledNatively() throws {
        try load(page(script: "setTimeout(function(){ location.href = 'focus-app://today'; }, 200);"))
        waitUntil { self.events.contains(.deepLinkToday) }
        XCTAssertTrue(events.contains(.deepLinkToday), "события: \(events)")
        XCTAssertEqual(webView.url?.isFileURL, true)
    }

    func testNetworkRulesCompile() {
        let done = expectation(description: "rules")
        var compiled: WKContentRuleList?
        FocusWebConfig.compileNetworkRules { compiled = $0; done.fulfill() }
        wait(for: [done], timeout: 20)
        XCTAssertNotNil(compiled)
    }

    func testWebsiteDataStoreIsNonPersistentByDefault() {
        let handler = FocusBridgeHandler(expectedPage: nil, store: { .failure(.containerUnavailable) }, onEvent: { _ in })
        XCTAssertFalse(FocusWebConfig.persistentWebStorage)
        XCTAssertFalse(FocusWebConfig.makeConfiguration(handler: handler).websiteDataStore.isPersistent)
        XCTAssertTrue(FocusWebConfig.makeConfiguration(handler: handler, persistent: true).websiteDataStore.isPersistent)
    }

    func testStoreUnavailableReported() throws {
        let handler = FocusBridgeHandler(expectedPage: nil, store: { .failure(.containerUnavailable) }, onEvent: { [unowned self] in self.events.append($0) })
        let config = FocusWebConfig.makeConfiguration(handler: handler)
        let url = dir.appendingPathComponent("index.html")
        let js = "window.FOCUSNativeSnapshot.send(function(){return {schema:1,generatedAt:'\(nowISO())',forDate:'2026-11-18',day:{done:1,total:2}};});"
        try page(script: js).write(to: url, atomically: true, encoding: .utf8)
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 600), configuration: config)
        webView.loadFileURL(url, allowingReadAccessTo: dir)
        waitUntil { self.events.contains(.storeUnavailable) }
        XCTAssertTrue(events.contains(.storeUnavailable), "события: \(events)")
    }

    func testWebRootNilWithoutBundledPage() {
        XCTAssertNil(FocusWebConfig.webRoot(bundle: Bundle(for: FocusWebViewTests.self)))
    }
}
