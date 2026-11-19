import SwiftUI
import WebKit

// Владелец WebView, моста и хранилища. Страница загружается только после установки правил блокировки сети.
final class FocusWebController: ObservableObject {
    @Published private(set) var lines: [String] = []
    @Published private(set) var storedCount = 0

    private var webView: WKWebView?
    private var navigationDelegate: FocusNavigationDelegate?
    private var storeResult: Result<AppGroupSnapshotStore, AppGroupStoreError>?
    private var pageLoaded = false
    private var pendingToday = false

    func makeWebView() -> WKWebView {
        if let existing = webView { return existing }
        let webRoot = FocusWebConfig.webRoot()
        let page = webRoot?.appendingPathComponent("index.html")
        let handler = FocusBridgeHandler(
            expectedPage: page,
            store: { [weak self] in self?.resolveStore() ?? .failure(.containerUnavailable) },
            onEvent: { [weak self] event in self?.record(event) }
        )
        let config = FocusWebConfig.makeConfiguration(handler: handler)
        let delegate = FocusNavigationDelegate(webRoot: webRoot, onEvent: { [weak self] event in self?.record(event) })
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = delegate
        web.isOpaque = false
        web.backgroundColor = UIColor.black
        web.scrollView.backgroundColor = UIColor.black
        webView = web
        navigationDelegate = delegate

        FocusWebConfig.compileNetworkRules { [weak self, weak web] rules in
            guard let self = self, let web = web else { return }
            if let rules = rules {
                web.configuration.userContentController.add(rules)
            } else {
                self.record(.contentRulesFailed)
            }
            if let page = page, let root = webRoot {
                web.loadFileURL(page, allowingReadAccessTo: root)
            } else {
                web.loadHTMLString("<main style='font:16px -apple-system;color:white;background:#111;padding:24px'>FOCUS: embedded Web/index.html is missing.</main>", baseURL: nil)
            }
        }
        return web
    }

    // Ссылка из виджета или со страницы. Разрешена только focus-app://today.
    func handleOpenURL(_ url: URL) {
        guard FocusDeepLinkPolicy.allows(url) else {
            record(.navigationBlocked(url.scheme ?? "none"))
            return
        }
        record(.deepLinkToday)
    }

    private func resolveStore() -> Result<AppGroupSnapshotStore, AppGroupStoreError> {
        if let cached = storeResult, case .success = cached { return cached }
        let created: Result<AppGroupSnapshotStore, AppGroupStoreError>
        do {
            created = .success(try AppGroupSnapshotStore())
        } catch {
            created = .failure(.containerUnavailable)
        }
        storeResult = created
        return created
    }

    private func openTodayTab() {
        guard pageLoaded, let web = webView else {
            pendingToday = true
            return
        }
        web.evaluateJavaScript("(function(){var b=document.querySelector('[data-tab=\"today\"]'); if(b){b.click();}})();", completionHandler: nil)
    }

    private func record(_ event: FocusBridgeEvent) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.record(event) }
            return
        }
        switch event {
        case .deepLinkToday:
            openTodayTab()
        case .pageLoaded:
            pageLoaded = true
            if pendingToday {
                pendingToday = false
                openTodayTab()
            }
            runLaunchHooks()
        case .snapshotStored:
            storedCount += 1
        default:
            break
        }
        lines.append(event.text)
        if lines.count > 8 { lines.removeFirst(lines.count - 8) }
    }

    // Тестовый хук CI (только Debug): нажать «демо-данные», чтобы снимок не был пустым.
    private func runLaunchHooks() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-focusAutoDemo") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.webView?.evaluateJavaScript("(function(){var b=document.getElementById('devDemo'); if(b){b.click();}})();", completionHandler: nil)
            }
        }
        #endif
    }
}

struct FocusWebView: UIViewRepresentable {
    let controller: FocusWebController

    func makeUIView(context: Context) -> WKWebView {
        return controller.makeWebView()
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
