import Foundation

// B3: политика моста JS → Swift, белый список ссылок, правила навигации и хранилище App Group.
// Здесь нет WebKit: код компилируется и в приложение, и в виджет, и проверяется модульными тестами.

// MARK: - Мост JS → Swift

enum FocusBridgePolicy {
    static let messageName = "focusSnapshot"

    enum Reason: String, Equatable {
        case unknownMessage = "unknown-message"
        case notMainFrame = "not-main-frame"
        case blockedOrigin = "blocked-origin"
        case badStructure = "bad-structure"
        case tooLarge = "too-large"
        case invalidSnapshot = "invalid-snapshot"
    }

    enum Decision: Equatable {
        case accept(Data)
        case reject(Reason)
    }

    // Единственная разрешённая операция — передача снимка: {"snapshot": {...}} без других ключей.
    // originProtocol — схема security origin отправителя; frameURL — адрес его документа;
    // expectedPage — адрес встроенного index.html (если задан, документ отправителя должен совпасть).
    static func evaluate(messageName: String, isMainFrame: Bool, originProtocol: String,
                         frameURL: URL?, expectedPage: URL?, body: Any) -> Decision {
        guard messageName == Self.messageName else {
            return .reject(.unknownMessage)
        }
        guard isMainFrame else {
            return .reject(.notMainFrame)
        }
        guard originProtocol == "file" else {
            return .reject(.blockedOrigin)
        }
        if let expected = expectedPage {
            guard let url = frameURL, url.isFileURL,
                  url.resolvingSymlinksInPath().path == expected.resolvingSymlinksInPath().path else {
                return .reject(.blockedOrigin)
            }
        }
        guard let dict = body as? [String: Any], dict.count == 1,
              let payload = dict["snapshot"] as? [String: Any],
              JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
            return .reject(.badStructure)
        }
        if data.count > SnapshotConstants.maxBytes {
            return .reject(.tooLarge)
        }
        guard (try? SnapshotParser.parse(data)) != nil else {
            return .reject(.invalidSnapshot)
        }
        return .accept(data)
    }
}

// MARK: - Ссылки focus-app://

// Единственная разрешённая ссылка: focus-app://today (допустим только завершающий «/»).
enum FocusDeepLinkPolicy {
    static func allows(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "focus-app",
              url.host?.lowercased() == "today",
              url.path.isEmpty || url.path == "/",
              url.query == nil, url.fragment == nil,
              url.user == nil, url.password == nil, url.port == nil else {
            return false
        }
        return true
    }
}

// MARK: - Навигация внутри WebView

enum FocusNavigationPolicy {
    enum Decision: Equatable {
        case allow
        case cancel
        case deepLinkToday
    }

    // Разрешены только файлы внутри каталога Web встроенного пакета (с учётом «..» и символических ссылок),
    // ссылка focus-app://today обрабатывается нативно. Всё остальное отклоняется.
    static func decide(_ url: URL, webRoot: URL?) -> Decision {
        if url.absoluteString == "about:blank" {
            return .allow
        }
        if url.isFileURL {
            guard let root = webRoot?.resolvingSymlinksInPath().path else {
                return .cancel
            }
            let path = url.resolvingSymlinksInPath().path
            return path.hasPrefix(root + "/") ? .allow : .cancel
        }
        return FocusDeepLinkPolicy.allows(url) ? .deepLinkToday : .cancel
    }
}

// MARK: - Хранилище в App Group

enum AppGroupStoreError: Error, Equatable {
    case containerUnavailable
    case invalidSnapshot
    case stale
    case writeFailed
}

// Обёртка над хранилищем B2 (SnapshotStore: атомарная запись и .prev) с правилами B3:
// размер, разбор парсером B2, допустимое время снимка, защита файлов.
final class AppGroupSnapshotStore {
    static let defaultGroupIdentifier = "group.com.focusproto.app"
    static let maxFutureSkew: TimeInterval = 5 * 60

    let directory: URL
    private let store: SnapshotStore

    // Поставщик контейнера App Group. По умолчанию — системный; в тестах можно передать closure, возвращающий nil.
    typealias ContainerProvider = (String) -> URL?
    static let systemContainerProvider: ContainerProvider = { identifier in
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    // Реальный App Group. Бросает containerUnavailable, если контейнер недоступен (нет entitlement/подписи).
    init(groupIdentifier: String = AppGroupSnapshotStore.defaultGroupIdentifier,
         containerProvider: ContainerProvider = AppGroupSnapshotStore.systemContainerProvider) throws {
        guard let container = containerProvider(groupIdentifier) else {
            throw AppGroupStoreError.containerUnavailable
        }
        let dir = container.appendingPathComponent("widget", isDirectory: true)
        self.directory = dir
        self.store = SnapshotStore(directory: dir)
    }

    // Произвольный каталог (тесты).
    init(directory: URL) {
        self.directory = directory
        self.store = SnapshotStore(directory: directory)
    }

    var primaryURL: URL { return store.primaryURL }
    var previousURL: URL { return store.previousURL }

    func writeValidated(_ data: Data, now: Date = Date()) throws {
        guard data.count <= SnapshotConstants.maxBytes,
              let snapshot = try? SnapshotParser.parse(data) else {
            throw AppGroupStoreError.invalidSnapshot
        }
        if snapshot.generatedAt > now.addingTimeInterval(AppGroupSnapshotStore.maxFutureSkew) {
            throw AppGroupStoreError.invalidSnapshot
        }
        if now.timeIntervalSince(snapshot.generatedAt) > SnapshotConstants.staleAfterHours * 3600 {
            throw AppGroupStoreError.stale
        }
        // Повторная отправка того же снимка безопасна: идентичные байты не перезаписываются
        // (чтобы запасная копия .prev не заменялась самой собой).
        if let current = try? Data(contentsOf: primaryURL), current == data {
            return
        }
        do {
            try store.write(data)
        } catch SnapshotStoreError.invalid {
            throw AppGroupStoreError.invalidSnapshot
        } catch {
            throw AppGroupStoreError.writeFailed
        }
        protectFiles()
    }

    // Чтение для виджета: основной файл → .prev → «нет данных» (правила B2).
    // Устаревание определяет Staleness.state по полям снимка.
    func load() -> SnapshotLoadResult {
        return store.load()
    }

    private func protectFiles() {
        for url in [primaryURL, previousURL] {
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path
            )
        }
    }
}
