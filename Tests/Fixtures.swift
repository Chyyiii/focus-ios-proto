import Foundation

// Синтетические снимки. Реальных данных пользователя здесь нет.
enum Fixtures {
    static let valid = """
    {"schema":1,"source":"demo","generatedAt":"2026-11-18T05:12:00Z","forDate":"2026-11-18","tz":"Asia/Yekaterinburg","theme":{"palette":"ember","mode":"auto"},"privacy":{"hideAmounts":false,"locked":false},"day":{"done":3,"total":7,"next":{"time":"15:30","text":"Записаться к врачу"}},"habits":{"done":3,"total":4},"limit":{"enabled":true,"state":"ok","value":1306},"streak":{"best":11}}
    """

    static let minimal = """
    {"schema":1,"generatedAt":"2026-11-18T05:12:00Z","forDate":"2026-11-18","day":{"done":0,"total":0}}
    """

    static let noDay = """
    {"schema":1,"generatedAt":"2026-11-18T05:12:00Z","forDate":"2026-11-18"}
    """

    static let unknownFields = """
    {"schema":1,"generatedAt":"2026-11-18T05:12:00Z","forDate":"2026-11-18","future":{"x":1},"day":{"done":1,"total":2,"extra":true}}
    """

    static let unknownPalette = """
    {"schema":1,"generatedAt":"2026-11-18T05:12:00Z","forDate":"2026-11-18","theme":{"palette":"emerald","mode":"sepia"},"day":{"done":1,"total":2}}
    """

    static let doneGreaterThanTotal = """
    {"schema":1,"generatedAt":"2026-11-18T05:12:00Z","forDate":"2026-11-18","day":{"done":9,"total":3}}
    """

    static let negativeTotal = """
    {"schema":1,"generatedAt":"2026-11-18T05:12:00Z","forDate":"2026-11-18","day":{"done":0,"total":-1}}
    """

    static let habitsWrongType = """
    {"schema":1,"generatedAt":"2026-11-18T05:12:00Z","forDate":"2026-11-18","day":{"done":1,"total":2},"habits":{"done":"3","total":4}}
    """

    static let limitBadState = """
    {"schema":1,"generatedAt":"2026-11-18T05:12:00Z","forDate":"2026-11-18","day":{"done":1,"total":2},"limit":{"enabled":true,"state":"meh","value":10}}
    """

    static let limitDisabled = """
    {"schema":1,"generatedAt":"2026-11-18T05:12:00Z","forDate":"2026-11-18","day":{"done":1,"total":2},"limit":{"enabled":false}}
    """

    static let badNextTime = """
    {"schema":1,"generatedAt":"2026-11-18T05:12:00Z","forDate":"2026-11-18","day":{"done":1,"total":2,"next":{"time":"25:99","text":"   "}}}
    """

    static let missingGeneratedAt = """
    {"schema":1,"forDate":"2026-11-18","day":{"done":1,"total":2}}
    """

    static let badGeneratedAt = """
    {"schema":1,"generatedAt":"вчера","forDate":"2026-11-18","day":{"done":1,"total":2}}
    """

    static let missingForDate = """
    {"schema":1,"generatedAt":"2026-11-18T05:12:00Z","day":{"done":1,"total":2}}
    """

    static let badForDate = """
    {"schema":1,"generatedAt":"2026-11-18T05:12:00Z","forDate":"18.11.2026","day":{"done":1,"total":2}}
    """

    static let missingSchema = """
    {"generatedAt":"2026-11-18T05:12:00Z","forDate":"2026-11-18","day":{"done":1,"total":2}}
    """

    static let schemaZero = """
    {"schema":0,"generatedAt":"2026-11-18T05:12:00Z","forDate":"2026-11-18","day":{"done":1,"total":2}}
    """

    static let schemaTwo = """
    {"schema":2,"generatedAt":"2026-11-18T05:12:00Z","forDate":"2026-11-18","day":{"done":1,"total":2}}
    """

    static let notJSON = "{not json"
    static let arrayRoot = "[1,2,3]"

    static func data(_ text: String) -> Data {
        return Data(text.utf8)
    }
}
