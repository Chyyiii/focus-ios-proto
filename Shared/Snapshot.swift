import Foundation

// Снимок для виджетов (схема 1). Производная проекция, не источник данных.
// Разбор снисходительный: необязательные блоки с неверным содержимым отбрасываются,
// обязательные поля (schema, generatedAt, forDate) — нет.

enum SnapshotConstants {
    static let supportedSchemaMin = 1
    static let supportedSchemaMax = 1
    static let maxBytes = 64 * 1024
    static let staleAfterHours = 48.0
}

enum Palette: String, CaseIterable {
    case ember, ocean, graphite
}

enum ThemeMode: String, CaseIterable {
    case auto, light, dark
}

enum LimitState: String {
    case ok, over, short
}

struct WidgetSnapshot: Equatable {
    struct Theme: Equatable {
        var palette: Palette
        var mode: ThemeMode
    }

    struct Privacy: Equatable {
        var hideAmounts: Bool
        var locked: Bool
    }

    struct Day: Equatable {
        var done: Int
        var total: Int
        var nextTime: String?
        var nextText: String?
    }

    struct Habits: Equatable {
        var done: Int
        var total: Int
    }

    struct Limit: Equatable {
        var enabled: Bool
        var state: LimitState?
        var value: Double?
    }

    var schema: Int
    var source: String?
    var generatedAt: Date
    var forDate: String
    var tz: String?
    var theme: Theme
    var privacy: Privacy
    var day: Day?
    var habits: Habits?
    var limit: Limit?
    var streakBest: Int?
}

enum SnapshotParseError: Error, Equatable {
    case tooLarge
    case notJSON
    case notObject
    case missingSchema
    case unsupportedSchema(Int)
    case missingGeneratedAt
    case badGeneratedAt
    case missingForDate
    case badForDate
}

enum SnapshotParser {
    static func parse(_ data: Data) throws -> WidgetSnapshot {
        if data.count > SnapshotConstants.maxBytes {
            throw SnapshotParseError.tooLarge
        }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw SnapshotParseError.notJSON
        }

        guard let root = object as? [String: Any] else {
            throw SnapshotParseError.notObject
        }
        guard let schema = root["schema"] as? Int else {
            throw SnapshotParseError.missingSchema
        }
        if schema < SnapshotConstants.supportedSchemaMin || schema > SnapshotConstants.supportedSchemaMax {
            throw SnapshotParseError.unsupportedSchema(schema)
        }
        guard let generatedString = root["generatedAt"] as? String else {
            throw SnapshotParseError.missingGeneratedAt
        }
        guard let generatedAt = parseDate(generatedString) else {
            throw SnapshotParseError.badGeneratedAt
        }
        guard let forDate = root["forDate"] as? String else {
            throw SnapshotParseError.missingForDate
        }
        if !isValidDay(forDate) {
            throw SnapshotParseError.badForDate
        }

        return WidgetSnapshot(
            schema: schema,
            source: root["source"] as? String,
            generatedAt: generatedAt,
            forDate: forDate,
            tz: root["tz"] as? String,
            theme: parseTheme(root["theme"]),
            privacy: parsePrivacy(root["privacy"]),
            day: parseDayBlock(root["day"]),
            habits: parseHabits(root["habits"]),
            limit: parseLimit(root["limit"]),
            streakBest: parseStreak(root["streak"])
        )
    }

    // MARK: даты

    static func parseDate(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: text) {
            return date
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }

    static func isValidDay(_ text: String) -> Bool {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
            return false
        }
        return year >= 2000 && year <= 2100 && month >= 1 && month <= 12 && day >= 1 && day <= 31
    }

    static func isValidTime(_ text: String) -> Bool {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 2, parts[1].count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]) else {
            return false
        }
        return hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59
    }

    // MARK: блоки (неверное содержимое → блок отсутствует)

    private static func parseTheme(_ any: Any?) -> WidgetSnapshot.Theme {
        let block = any as? [String: Any]
        let paletteName = (block?["palette"] as? String) ?? ""
        let modeName = (block?["mode"] as? String) ?? ""
        return WidgetSnapshot.Theme(
            palette: Palette(rawValue: paletteName) ?? .ember,
            mode: ThemeMode(rawValue: modeName) ?? .auto
        )
    }

    private static func parsePrivacy(_ any: Any?) -> WidgetSnapshot.Privacy {
        let block = any as? [String: Any]
        return WidgetSnapshot.Privacy(
            hideAmounts: (block?["hideAmounts"] as? Bool) ?? false,
            locked: (block?["locked"] as? Bool) ?? false
        )
    }

    private static func parseDayBlock(_ any: Any?) -> WidgetSnapshot.Day? {
        guard let block = any as? [String: Any],
              let done = block["done"] as? Int,
              let total = block["total"] as? Int,
              done >= 0, total >= 0, total <= 1000, done <= total else {
            return nil
        }
        var time: String? = nil
        var text: String? = nil
        if let next = block["next"] as? [String: Any] {
            if let value = next["time"] as? String, isValidTime(value) {
                time = value
            }
            if let value = next["text"] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    text = String(trimmed.prefix(120))
                }
            }
        }
        return WidgetSnapshot.Day(done: done, total: total, nextTime: time, nextText: text)
    }

    private static func parseHabits(_ any: Any?) -> WidgetSnapshot.Habits? {
        guard let block = any as? [String: Any],
              let done = block["done"] as? Int,
              let total = block["total"] as? Int,
              done >= 0, total >= 0, total <= 1000, done <= total else {
            return nil
        }
        return WidgetSnapshot.Habits(done: done, total: total)
    }

    private static func parseLimit(_ any: Any?) -> WidgetSnapshot.Limit? {
        guard let block = any as? [String: Any],
              let enabled = block["enabled"] as? Bool else {
            return nil
        }
        if !enabled {
            return WidgetSnapshot.Limit(enabled: false, state: nil, value: nil)
        }
        guard let stateName = block["state"] as? String,
              let state = LimitState(rawValue: stateName),
              let number = block["value"] as? NSNumber else {
            return nil
        }
        let value = number.doubleValue
        guard value.isFinite, abs(value) < 1e12 else {
            return nil
        }
        return WidgetSnapshot.Limit(enabled: true, state: state, value: value)
    }

    private static func parseStreak(_ any: Any?) -> Int? {
        guard let block = any as? [String: Any],
              let best = block["best"] as? Int,
              best >= 0, best <= 100000 else {
            return nil
        }
        return best
    }
}
