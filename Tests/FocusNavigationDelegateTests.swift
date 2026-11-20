import XCTest
import WebKit

// Детерминированная проверка настоящего FocusNavigationDelegate: вызываем его метод решения
// с подставным WKNavigationAction (подкласс с заданным request). Без таймингов WebKit.
private final class StubNavigationAction: WKNavigationAction {
    var stubRequest = URLRequest(url: URL(string: "about:blank")!)
    override var request: URLRequest { return stubRequest }
}

final class FocusNavigationDelegateTests: XCTestCase {
    private var events: [FocusBridgeEvent] = []
    private var root: URL!

    override func setUp() {
        super.setUp()
        events = []
        root = FileManager.default.temporaryDirectory.appendingPathComponent("focus-nav-" + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func decide(_ url: URL, webRoot: URL?) -> (policy: WKNavigationActionPolicy?, decisions: [FocusNavigationPolicy.Decision]) {
        events = []
        let delegate = FocusNavigationDelegate(webRoot: webRoot, onEvent: { [unowned self] in self.events.append($0) })
        var observed: [FocusNavigationPolicy.Decision] = []
        delegate.onDecision = { _, decision in observed.append(decision) }
        let action = StubNavigationAction()
        action.stubRequest = URLRequest(url: url)
        var result: WKNavigationActionPolicy?
        delegate.webView(WKWebView(frame: .zero), decidePolicyFor: action, decisionHandler: { result = $0 })
        return (result, observed)
    }

    func testForeignFileURLIsCancelledAndReported() {
        let r = decide(URL(fileURLWithPath: "/etc/hosts"), webRoot: root)
        XCTAssertEqual(r.policy, .cancel)
        XCTAssertEqual(r.decisions, [.cancel])
        XCTAssertEqual(events, [.navigationBlocked("file")])
    }

    func testTraversalOutOfRootIsCancelled() {
        let r = decide(root.appendingPathComponent("../secret.txt"), webRoot: root)
        XCTAssertEqual(r.policy, .cancel)
        XCTAssertEqual(events, [.navigationBlocked("file")])
    }

    func testFileWithoutWebRootIsCancelled() {
        let r = decide(root.appendingPathComponent("index.html"), webRoot: nil)
        XCTAssertEqual(r.policy, .cancel)
        XCTAssertEqual(events, [.navigationBlocked("file")])
    }

    func testFileInsideRootIsAllowedWithoutEvents() {
        let r = decide(root.appendingPathComponent("index.html"), webRoot: root)
        XCTAssertEqual(r.policy, .allow)
        XCTAssertEqual(r.decisions, [.allow])
        XCTAssertTrue(events.isEmpty)
    }

    func testHttpsIsCancelledAndReported() {
        let r = decide(URL(string: "https://example.com/")!, webRoot: root)
        XCTAssertEqual(r.policy, .cancel)
        XCTAssertEqual(events, [.navigationBlocked("https")])
    }

    func testDeepLinkTodayIsCancelledNativelyAndReported() {
        let r = decide(URL(string: "focus-app://today")!, webRoot: root)
        XCTAssertEqual(r.policy, .cancel)
        XCTAssertEqual(r.decisions, [.deepLinkToday])
        XCTAssertEqual(events, [.deepLinkToday])
    }

    func testUnknownDeepLinkIsCancelledAndReportedAsBlocked() {
        let r = decide(URL(string: "focus-app://finance")!, webRoot: root)
        XCTAssertEqual(r.policy, .cancel)
        XCTAssertEqual(events, [.navigationBlocked("focus-app")])
    }

    func testJavascriptAndDataSchemesAreCancelled() {
        for s in ["javascript:alert(1)", "data:text/html,hi"] {
            let r = decide(URL(string: s)!, webRoot: root)
            XCTAssertEqual(r.policy, .cancel, s)
        }
    }
}
