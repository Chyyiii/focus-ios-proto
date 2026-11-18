import Foundation

// Цвета тем взяты из токенов приложения FOCUS (index.html, палитры «Жар», «Океан», «Графит»).
// Строки — hex без «#», чтобы код не зависел от SwiftUI и проверялся тестами.

struct ThemeTokens: Equatable {
    let bg: String
    let surface: String
    let text: String
    let muted: String
    let accent: String
    let accentInk: String
    let line: String
    let tint: String
}

enum ThemeTable {
    static func tokens(palette: Palette, dark: Bool) -> ThemeTokens {
        switch (palette, dark) {
        case (.ember, false):
            return ThemeTokens(bg: "FBF4EC", surface: "FFFFFF", text: "26160B", muted: "6B5646",
                               accent: "C44A05", accentInk: "FFFFFF", line: "EBDAC8", tint: "F5EADD")
        case (.ember, true):
            return ThemeTokens(bg: "0A0705", surface: "140E0A", text: "F8EDE3", muted: "C2AC9B",
                               accent: "FF8A1F", accentInk: "1A0C02", line: "3A2518", tint: "1E140E")
        case (.ocean, false):
            return ThemeTokens(bg: "EEF3F9", surface: "FFFFFF", text: "0C1A2B", muted: "445970",
                               accent: "1D5FB8", accentInk: "FFFFFF", line: "D3DFEC", tint: "E5EDF6")
        case (.ocean, true):
            return ThemeTokens(bg: "04070C", surface: "0B121B", text: "EAF2FB", muted: "9FB3C8",
                               accent: "3D9BFF", accentInk: "031020", line: "1B2D44", tint: "111C29")
        case (.graphite, false):
            return ThemeTokens(bg: "F1F2F4", surface: "FFFFFF", text: "161B20", muted: "4C545C",
                               accent: "2B3640", accentInk: "FFFFFF", line: "DCDFE3", tint: "EBEDF0")
        case (.graphite, true):
            return ThemeTokens(bg: "060708", surface: "101214", text: "EEF0F3", muted: "A9B0B8",
                               accent: "DDE3EA", accentInk: "0E1114", line: "272B30", tint: "181B1E")
        }
    }

    // Режим «auto» определяется системой на стороне виджета: dark = текущая цветовая схема.
    static func tokens(theme: WidgetSnapshot.Theme, systemIsDark: Bool) -> ThemeTokens {
        let dark: Bool
        switch theme.mode {
        case .light: dark = false
        case .dark: dark = true
        case .auto: dark = systemIsDark
        }
        return tokens(palette: theme.palette, dark: dark)
    }

    // MARK: контраст (WCAG)

    static func rgb(_ hex: String) -> (Double, Double, Double)? {
        guard hex.count == 6, let value = Int(hex, radix: 16) else {
            return nil
        }
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        return (red, green, blue)
    }

    private static func linear(_ channel: Double) -> Double {
        if channel <= 0.03928 {
            return channel / 12.92
        }
        return pow((channel + 0.055) / 1.055, 2.4)
    }

    static func luminance(_ hex: String) -> Double? {
        guard let color = rgb(hex) else {
            return nil
        }
        return 0.2126 * linear(color.0) + 0.7152 * linear(color.1) + 0.0722 * linear(color.2)
    }

    static func contrast(_ first: String, _ second: String) -> Double? {
        guard let a = luminance(first), let b = luminance(second) else {
            return nil
        }
        let lighter = max(a, b)
        let darker = min(a, b)
        return (lighter + 0.05) / (darker + 0.05)
    }
}
