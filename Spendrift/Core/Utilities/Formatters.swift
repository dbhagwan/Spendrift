import Foundation

extension Decimal {
    func currency(_ code: String = "USD", showCents: Bool = true) -> String {
        formatted(
            .currency(code: code)
            .precision(.fractionLength(showCents ? 2 : 0))
        )
    }

    /// Compact form for dense surfaces: $1.2K, $38, -$420.
    func currencyCompact(_ code: String = "USD") -> String {
        let magnitude = abs((self as NSDecimalNumber).doubleValue)
        if magnitude >= 1_000_000 {
            return formatted(.currency(code: code).notation(.compactName).precision(.fractionLength(1)))
        }
        if magnitude >= 10_000 {
            return formatted(.currency(code: code).notation(.compactName).precision(.fractionLength(1)))
        }
        return formatted(.currency(code: code).precision(.fractionLength(0)))
    }

    var doubleValue: Double { (self as NSDecimalNumber).doubleValue }
}

extension Double {
    var percentString: String {
        formatted(.percent.precision(.fractionLength(0)))
    }

    var signedPercentString: String {
        let sign = self >= 0 ? "+" : ""
        return sign + formatted(.percent.precision(.fractionLength(0)))
    }
}

extension Date {
    var shortDay: String { formatted(.dateTime.month(.abbreviated).day()) }
    var weekdayName: String { formatted(.dateTime.weekday(.wide)) }

    func daysUntil(_ other: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: self), to: calendar.startOfDay(for: other)).day ?? 0
    }

    var startOfDay: Date { Calendar.current.startOfDay(for: self) }
}
