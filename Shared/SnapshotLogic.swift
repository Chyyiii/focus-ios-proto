import Foundation

// Загрузка (с запасной копией), устаревание и безопасная запись снимка.

enum SnapshotLoadResult: Equatable {
    case snapshot(WidgetSnapshot, fromPrevious: Bool)
    case unsupportedSchema(Int)
    case noData
}

enum SnapshotLoader {
    // Основной файл → запасной (.prev) → «нет данных».
    // Схема новее/старее поддерживаемой не маскируется запасной копией.
    static func load(primary: Data?, previous: Data?) -> SnapshotLoadResult {
        if let data = primary {
            do {
                return .snapshot(try SnapshotParser.parse(data), fromPrevious: false)
            } catch SnapshotParseError.unsupportedSchema(let version) {
                return .unsupportedSchema(version)
            } catch {
                // повреждён — пробуем запасной
            }
        }
        if let data = previous {
            do {
                return .snapshot(try SnapshotParser.parse(data), fromPrevious: true)
            } catch SnapshotParseError.unsupportedSchema(let version) {
                return .unsupportedSchema(version)
            } catch {
                // и этот повреждён
            }
        }
        return .noData
    }
}

enum SnapshotState: Equatable {
    case fresh
    case dayOld(forDate: String)
    case stale
    case locked

    // Дневные числа (день, привычки, лимит) можно показывать как актуальные только в этом состоянии.
    var showsDailyNumbers: Bool {
        return self == .fresh
    }
}

enum Staleness {
    static func dayString(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    // Порядок: скрыто/заблокировано → старше 48 ч → другой день → актуально.
    static func state(of snapshot: WidgetSnapshot, now: Date, calendar: Calendar) -> SnapshotState {
        if snapshot.privacy.locked {
            return .locked
        }
        let age = now.timeIntervalSince(snapshot.generatedAt)
        if age > SnapshotConstants.staleAfterHours * 3600 {
            return .stale
        }
        if snapshot.forDate != dayString(for: now, calendar: calendar) {
            return .dayOld(forDate: snapshot.forDate)
        }
        return .fresh
    }
}

enum SnapshotValidator {
    // Снимок можно записывать, если он разбирается и содержит блок дня.
    static func isWritable(_ data: Data) -> Bool {
        guard let snapshot = try? SnapshotParser.parse(data) else {
            return false
        }
        return snapshot.day != nil
    }
}

enum SnapshotStoreError: Error, Equatable {
    case invalid
}

// Хранилище в каталоге (в B3 каталогом станет контейнер App Group).
struct SnapshotStore {
    let directory: URL

    var primaryURL: URL {
        return directory.appendingPathComponent("widget-snapshot.json")
    }

    var previousURL: URL {
        return directory.appendingPathComponent("widget-snapshot.prev.json")
    }

    func write(_ data: Data) throws {
        guard SnapshotValidator.isWritable(data) else {
            throw SnapshotStoreError.invalid
        }
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        if let old = try? Data(contentsOf: primaryURL), SnapshotValidator.isWritable(old) {
            try? old.write(to: previousURL, options: .atomic)
        }
        try data.write(to: primaryURL, options: .atomic)
    }

    func load() -> SnapshotLoadResult {
        let primary = try? Data(contentsOf: primaryURL)
        let previous = try? Data(contentsOf: previousURL)
        return SnapshotLoader.load(primary: primary, previous: previous)
    }
}
