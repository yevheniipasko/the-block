import Foundation

/// Display formatting shared by every screen. Money is whole CAD, distances in km.
enum Formatting {

    /// Formats whole dollars as Canadian currency without cents, e.g. `$24,500`.
    static func currency(_ amount: Int) -> String {
        amount.formatted(.currency(code: "CAD").precision(.fractionLength(0)).locale(Locale(identifier: "en_CA")))
    }

    /// Formats an odometer reading, e.g. `47,731 km`.
    static func kilometres(_ value: Int) -> String {
        "\(value.formatted(.number.locale(Locale(identifier: "en_CA")))) km"
    }

    /// Compact time remaining until `date` (spec TIME-3).
    ///
    /// More than a day shows days and hours (`2d 4h`), more than an hour shows hours and
    /// minutes (`4h 12m`), under an hour shows minutes and seconds (`12m 05s`).
    /// A date in the past returns `0m 00s`.
    static func countdown(from now: Date, to date: Date) -> String {
        let total = max(0, Int(date.timeIntervalSince(now)))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        if days > 0 {
            return "\(days)d \(hours)h"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m " + String(format: "%02ds", seconds)
    }

}
