import SwiftUI

enum Fmt {
    static var imperial: Bool { UserDefaults.standard.string(forKey: "units") == "imperial" }

    static func speed(_ ms: Double) -> Double { ms * (imperial ? 2.236936 : 3.6) }
    static var speedUnit: String { imperial ? "mph" : "km/h" }

    static func dist(_ m: Double) -> Double { m / (imperial ? 1609.344 : 1000) }
    static var distUnit: String { imperial ? "mi" : "km" }

    static func alt(_ m: Double) -> Double { imperial ? m * 3.28084 : m }
    static var altUnit: String { imperial ? "ft" : "m" }

    static func speedText(_ ms: Double) -> String { String(format: "%.0f", speed(ms)) }
    static func distText(_ m: Double) -> String {
        let v = dist(m)
        return String(format: v < 10 ? "%.2f" : (v < 100 ? "%.1f" : "%.0f"), v)
    }
    static func altText(_ m: Double) -> String { String(format: "%.0f", alt(m)) }

    static func duration(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }

    static func durationLong(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        let h = s / 3600, m = (s % 3600) / 60
        if h == 0 && m == 0 { return "\(s)s" }
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    /// Verde → rosso in base alla velocità (km/h equivalenti).
    static func speedColor(_ ms: Double) -> Color {
        let kmh = ms * 3.6
        let t = min(max(kmh / 160, 0), 1)
        return Color(hue: 0.36 - 0.36 * t, saturation: 0.85, brightness: 0.95)
    }
}

extension Date {
    static let itLocale = Locale(identifier: "it_IT")
    var shortDate: String { formatted(Date.FormatStyle(locale: Date.itLocale).day().month(.abbreviated).year()) }
    var dayMonth: String { formatted(Date.FormatStyle(locale: Date.itLocale).day().month(.abbreviated)) }
    var monthYear: String { formatted(Date.FormatStyle(locale: Date.itLocale).month(.wide).year()) }
    var shortTime: String { formatted(Date.FormatStyle(locale: Date.itLocale).hour().minute()) }
}
