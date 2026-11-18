import XCTest

final class ThemeTests: XCTestCase {
    private func allTokens() -> [(String, ThemeTokens)] {
        var result: [(String, ThemeTokens)] = []
        for palette in Palette.allCases {
            for dark in [false, true] {
                result.append(("\(palette.rawValue)/\(dark ? "dark" : "light")",
                               ThemeTable.tokens(palette: palette, dark: dark)))
            }
        }
        return result
    }

    func testSixDistinctThemes() {
        let backgrounds = Set(allTokens().map { $0.1.bg })
        XCTAssertEqual(allTokens().count, 6)
        XCTAssertEqual(backgrounds.count, 6)
    }

    func testAllColorsAreValidHex() {
        for (name, t) in allTokens() {
            for value in [t.bg, t.surface, t.text, t.muted, t.accent, t.accentInk, t.line, t.tint] {
                XCTAssertNotNil(ThemeTable.rgb(value), "\(name): неверный цвет \(value)")
            }
        }
    }

    func testTextContrast() {
        for (name, t) in allTokens() {
            XCTAssertGreaterThanOrEqual(ThemeTable.contrast(t.text, t.bg) ?? 0, 7.0, "\(name): text/bg")
            XCTAssertGreaterThanOrEqual(ThemeTable.contrast(t.text, t.surface) ?? 0, 7.0, "\(name): text/surface")
        }
    }

    func testMutedTextContrast() {
        for (name, t) in allTokens() {
            XCTAssertGreaterThanOrEqual(ThemeTable.contrast(t.muted, t.bg) ?? 0, 4.5, "\(name): muted/bg")
        }
    }

    func testAccentContrast() {
        for (name, t) in allTokens() {
            // акцент — крупный элемент (кольцо, значок): порог 3:1
            XCTAssertGreaterThanOrEqual(ThemeTable.contrast(t.accent, t.bg) ?? 0, 3.0, "\(name): accent/bg")
            // текст на акценте
            XCTAssertGreaterThanOrEqual(ThemeTable.contrast(t.accentInk, t.accent) ?? 0, 4.5, "\(name): ink/accent")
        }
    }

    func testContrastFormulaKnownValues() {
        XCTAssertEqual(ThemeTable.contrast("000000", "FFFFFF") ?? 0, 21.0, accuracy: 0.01)
        XCTAssertEqual(ThemeTable.contrast("FFFFFF", "FFFFFF") ?? 0, 1.0, accuracy: 0.001)
        XCTAssertNil(ThemeTable.contrast("zzzzzz", "FFFFFF"))
    }

    func testAutoModeFollowsSystem() {
        let theme = WidgetSnapshot.Theme(palette: .ocean, mode: .auto)
        XCTAssertEqual(ThemeTable.tokens(theme: theme, systemIsDark: true),
                       ThemeTable.tokens(palette: .ocean, dark: true))
        XCTAssertEqual(ThemeTable.tokens(theme: theme, systemIsDark: false),
                       ThemeTable.tokens(palette: .ocean, dark: false))
    }

    func testExplicitModeIgnoresSystem() {
        let light = WidgetSnapshot.Theme(palette: .graphite, mode: .light)
        let dark = WidgetSnapshot.Theme(palette: .graphite, mode: .dark)
        XCTAssertEqual(ThemeTable.tokens(theme: light, systemIsDark: true),
                       ThemeTable.tokens(palette: .graphite, dark: false))
        XCTAssertEqual(ThemeTable.tokens(theme: dark, systemIsDark: false),
                       ThemeTable.tokens(palette: .graphite, dark: true))
    }

    func testEmberIsDefaultAccentOrange() {
        XCTAssertEqual(ThemeTable.tokens(palette: .ember, dark: true).accent, "FF8A1F")
    }
}
