import Foundation
import WebKit

// B3: WebKit-часть моста. Подключается к приложению и к тестам, в виджет НЕ входит.
// Все решения принимают чистые политики из Shared/FocusBridgeCore.swift.

enum FocusBridgeEvent: Equatable {
    case snapshotStored
    case snapshotRejected(FocusBridgePolicy.Reason)
    case snapshotNotStored(String)     // stale / invalid / writeFailed
    case storeUnavailable              // нет App Group контейнера (нет entitlement/подписи)
    case deepLinkToday
    case navigationBlocked(String)     // схема отклонённой ссылки
    case loadFailed(String)
    case pageLoaded
    case contentRulesFailed

    var text: String {
        switch self {
        case .snapshotStored: return "snapshot: stored"
        case .snapshotRejected(let r): return "snapshot: rejected (\(r.rawValue))"
        case .snapshotNotStored(let m): return "snapshot: not stored (\(m))"
        case .storeUnavailable: return "store: App Group unavailable"
        case .deepLinkToday: return "deep link: today"
        case .navigationBlocked(let s): return "navigation blocked (\(s))"
        case .loadFailed(let m): return "load failed (\(m))"
        case .pageLoaded: return "page loaded"
        case .contentRulesFailed: return "network block rules failed"
        }
    }
}

enum FocusWebConfig {
    // Решение владельца требуется до реальных данных: .nonPersistent стирает localStorage при каждом запуске.
    static let persistentWebStorage = false
    static let ruleListIdentifier = "focus.block-network.v1"
    // Блок любых http(s)-запросов страницы (в т.ч. подресурсов, например Google Fonts).
    static let blockNetworkRules = "[{\"trigger\":{\"url-filter\":\"^https?://\"},\"action\":{\"type\":\"block\"}}]"

    // Каталог Web встроенного пакета (папка-ссылка). nil, если страница не встроена.
    static func webRoot(bundle: Bundle = .main) -> URL? {
        return bundle.url(forResource: "index", withExtension: "html", subdirectory: "Web")?.deletingLastPathComponent()
    }

    static func compileNetworkRules(completion: @escaping (WKContentRuleList?) -> Void) {
        guard let store = WKContentRuleListStore.default() else {
            completion(nil)
            return
        }
        store.compileContentRuleList(forIdentifier: ruleListIdentifier, encodedContentRuleList: blockNetworkRules) { list, _ in
            DispatchQueue.main.async { completion(list) }
        }
    }

    static func makeConfiguration(handler: WKScriptMessageHandler, persistent: Bool = persistentWebStorage) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.userContentController.add(handler, name: FocusBridgePolicy.messageName)
        config.websiteDataStore = persistent ? WKWebsiteDataStore.default() : WKWebsiteDataStore.nonPersistent()
        return config
    }
}

// Принимает сообщение focusSnapshot, проверяет политикой и пишет в хранилище.
final class FocusBridgeHandler: NSObject, WKScriptMessageHandler {
    private let expectedPage: URL?
    private let store: () -> Result<AppGroupSnapshotStore, AppGroupStoreError>
    private let onEvent: (FocusBridgeEvent) -> Void

    init(expectedPage: URL?,
         store: @escaping () -> Result<AppGroupSnapshotStore, AppGroupStoreError>,
         onEvent: @escaping (FocusBridgeEvent) -> Void) {
        self.expectedPage = expectedPage
        self.store = store
        self.onEvent = onEvent
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let frame = message.frameInfo
        let decision = FocusBridgePolicy.evaluate(
            messageName: message.name,
            isMainFrame: frame.isMainFrame,
            originProtocol: frame.securityOrigin.protocol,
            frameURL: frame.request.url,
            expectedPage: expectedPage,
            body: message.body
        )
        switch decision {
        case .reject(let reason):
            onEvent(.snapshotRejected(reason))
        case .accept(let data):
            switch store() {
            case .failure:
                onEvent(.storeUnavailable)
            case .success(let target):
                do {
                    try target.writeValidated(data)
                    onEvent(.snapshotStored)
                } catch let error as AppGroupStoreError {
                    onEvent(.snapshotNotStored("\(error)"))
                } catch {
                    onEvent(.snapshotNotStored("unknown"))
                }
            }
        }
    }
}

// Навигация: только файлы каталога Web, focus-app://today — нативно, остальное отклоняется.
final class FocusNavigationDelegate: NSObject, WKNavigationDelegate {
    private let webRoot: URL?
    private let onEvent: (FocusBridgeEvent) -> Void
    // Необязательный хук наблюдения (тесты/диагностика): вызывается для КАЖДОГО решения, в т.ч. «разрешить».
    // На решения не влияет.
    var onDecision: ((URL, FocusNavigationPolicy.Decision) -> Void)?

    init(webRoot: URL?, onEvent: @escaping (FocusBridgeEvent) -> Void) {
        self.webRoot = webRoot
        self.onEvent = onEvent
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            onEvent(.navigationBlocked("nil"))
            return
        }
        let decision = FocusNavigationPolicy.decide(url, webRoot: webRoot)
        onDecision?(url, decision)
        switch decision {
        case .allow:
            decisionHandler(.allow)
        case .deepLinkToday:
            decisionHandler(.cancel)
            onEvent(.deepLinkToday)
        case .cancel:
            decisionHandler(.cancel)
            onEvent(.navigationBlocked(url.scheme ?? "none"))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onEvent(.pageLoaded)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        report(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        report(error)
    }

    // Отмена навигации политикой (-999 / WebKit 102) — не ошибка загрузки.
    private func report(_ error: Error) {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
        if ns.domain == "WebKitErrorDomain" && ns.code == 102 { return }
        onEvent(.loadFailed("\(ns.domain) \(ns.code)"))
    }
}
