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

    // Обычная страница; ждём .pageLoaded (холодный старт WebKit в тестах может быть долгим), затем сбрасываем события.
    private func loadPlainPageAndWait() throws {
        try load(page(script: ""))
        waitUntil(150) { self.events.contains(.pageLoaded) }
        XCTAssertTrue(events.contains(.pageLoaded), "страница не загрузилась: \(events)")
        events.removeAll()
    }

    // Настоящие переходы из страницы (проходят через WKNavigationDelegate). Пробуем способы по очереди,
    // пока делегат не получит ожидаемое событие. Возвращает название сработавшего способа (nil — ни один).
    @discardableResult
    private func navigateFromPage(to target: String, expecting event: FocusBridgeEvent) -> String? {
        let scripts: [(String, String)] = [
            ("location.href", "location.href = '\(target)';"),
            ("anchor click", "var a = document.createElement('a'); a.href = '\(target)'; document.body.appendChild(a); a.click();"),
            ("location.assign", "window.location.assign('\(target)');")
        ]
        for (name, js) in scripts {
            webView.evaluateJavaScript(js, completionHandler: nil)
            waitUntil(6) { self.events.contains(event) }
            if events.contains(event) { return name }
        }
        return nil
    }

    private func assertStillOnLocalPage(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(webView.url?.isFileURL, true, "url: \(String(describing: webView.url))", file: file, line: line)
        XCTAssertEqual(webView.url?.lastPathComponent, "index.html", file: file, line: line)
        XCTAssertFalse(webView.isLoading, file: file, line: line)
    }

    func testExternalNavigationBlocked() throws {
        try loadPlainPageAndWait()
        let via = navigateFromPage(to: "https://example.com/", expecting: .navigationBlocked("https"))
        XCTAssertNotNil(via, "события: \(events)")
        assertStillOnLocalPage()
    }

    func testUnknownSchemeBlocked() throws {
        try loadPlainPageAndWait()
        let via = navigateFromPage(to: "focus-app://finance", expecting: .navigationBlocked("focus-app"))
        XCTAssertNotNil(via, "события: \(events), url: \(String(describing: webView.url))")
        XCTAssertFalse(events.contains(.deepLinkToday))
        assertStillOnLocalPage()
    }

    func testForeignFileBlockedWhenPageNavigates() throws {
        try loadPlainPageAndWait()
        let via = navigateFromPage(to: "file:///etc/hosts", expecting: .navigationBlocked("file"))
        // Допустимо два исхода: делегат отклонил переход (via != nil) либо WebKit сам не начал переход
        // (за пределами allowingReadAccessTo). В обоих случаях /etc/hosts не должен открыться.
        print("DIAG foreign-file page navigation: via=\(via ?? "none") events=\(events) url=\(String(describing: webView.url))")
        assertStillOnLocalPage()
        XCTAssertNotEqual(webView.url?.path, "/etc/hosts")
    }

    func testDeepLinkTodayHandledNatively() throws {
        try loadPlainPageAndWait()
        let via = navigateFromPage(to: "focus-app://today", expecting: .deepLinkToday)
        print("DIAG deep-link page navigation: via=\(via ?? "none") events=\(events) url=\(String(describing: webView.url))")
        XCTAssertNotNil(via, "ни один способ перехода из страницы не дошёл до делегата. события: \(events)")
        XCTAssertFalse(events.contains(where: { if case .navigationBlocked = $0 { return true } else { return false } }), "события: \(events)")
        assertStillOnLocalPage()
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
