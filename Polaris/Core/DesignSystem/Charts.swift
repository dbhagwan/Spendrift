import Charts
import SwiftUI

/// Stable, calm chart palette — one hue family per category so the donut and
/// bars read consistently everywhere. (UI concern, so it lives here and not
/// on the model.)
extension SpendingCategory {
    var chartColor: Color {
        switch self {
        case .income: Color(red: 0.18, green: 0.65, blue: 0.45)
        case .housing: Color(red: 0.35, green: 0.62, blue: 0.98)
        case .utilities: Color(red: 0.30, green: 0.48, blue: 0.85)
        case .groceries: Color(red: 0.22, green: 0.72, blue: 0.60)
        case .dining: Color(red: 0.95, green: 0.58, blue: 0.30)
        case .travel: Color(red: 0.55, green: 0.45, blue: 0.95)
        case .transportation: Color(red: 0.40, green: 0.70, blue: 0.90)
        case .shopping: Color(red: 0.92, green: 0.45, blue: 0.55)
        case .entertainment: Color(red: 0.80, green: 0.40, blue: 0.85)
        case .health: Color(red: 0.90, green: 0.35, blue: 0.40)
        case .insurance: Color(red: 0.45, green: 0.55, blue: 0.70)
        case .debtPayments: Color(red: 0.75, green: 0.55, blue: 0.35)
        case .transfers: Color(red: 0.55, green: 0.60, blue: 0.65)
        case .investments: Color(red: 0.30, green: 0.75, blue: 0.75)
        case .fees: Color(red: 0.70, green: 0.45, blue: 0.45)
        case .subscriptions: Color(red: 0.50, green: 0.50, blue: 0.95)
        case .taxes: Color(red: 0.60, green: 0.50, blue: 0.40)
        case .miscellaneous: Color(red: 0.55, green: 0.55, blue: 0.60)
        }
    }
}

/// Account-kind palette + icons for the net-worth allocation donut.
extension AccountKind {
    var chartColor: Color {
        switch self {
        case .checking: Color(red: 0.35, green: 0.62, blue: 0.98)
        case .savings: Color(red: 0.22, green: 0.72, blue: 0.60)
        case .creditCard: Color(red: 0.92, green: 0.45, blue: 0.55)
        case .loan: Color(red: 0.75, green: 0.55, blue: 0.35)
        case .investment: Color(red: 0.55, green: 0.45, blue: 0.95)
        case .other: Color(red: 0.55, green: 0.55, blue: 0.60)
        }
    }

    var chartSystemImage: String {
        switch self {
        case .checking: "banknote"
        case .savings: "building.columns"
        case .creditCard: "creditcard"
        case .loan: "percent"
        case .investment: "chart.line.uptrend.xyaxis"
        case .other: "tray"
        }
    }
}

/// One ring segment — generic so the same donut renders category splits and
/// account allocations.
struct DonutSlice: Identifiable, Equatable, Sendable {
    var id: String
    var label: String
    var amount: Decimal
    var color: Color
    var systemImage: String?

    init(id: String, label: String, amount: Decimal, color: Color, systemImage: String? = nil) {
        self.id = id
        self.label = label
        self.amount = amount
        self.color = color
        self.systemImage = systemImage
    }

    init(category: SpendingCategory, amount: Decimal) {
        self.init(
            id: category.rawValue,
            label: category.displayName,
            amount: amount,
            color: category.chartColor,
            systemImage: category.systemImage
        )
    }
}

/// Interactive donut: tap (or drag) a sector to see its share in the center —
/// every selection change clicks via haptics. Optional Robinhood-style
/// percent labels on the ring band.
struct DonutChart: View {
    var slices: [DonutSlice]
    var centerCaption: String = "this period"
    var showsPercentLabels = false

    @State private var selectedAngle: Double?

    private var total: Decimal { slices.reduce(0) { $0 + $1.amount } }

    private var selectedSlice: DonutSlice? {
        guard let selectedAngle else { return nil }
        var running = 0.0
        for slice in slices {
            running += slice.amount.doubleValue
            if selectedAngle <= running { return slice }
        }
        return nil
    }

    var body: some View {
        Chart(slices) { slice in
            SectorMark(
                angle: .value("Amount", slice.amount.doubleValue),
                innerRadius: .ratio(0.64),
                angularInset: 1.5
            )
            .cornerRadius(4)
            .foregroundStyle(slice.color)
            .opacity(selectedSlice == nil || selectedSlice?.id == slice.id ? 1 : 0.35)
        }
        .chartAngleSelection(value: $selectedAngle)
        .chartBackground { proxy in
            GeometryReader { geometry in
                if let frame = proxy.plotFrame.map({ geometry[$0] }) {
                    VStack(spacing: 2) {
                        Text(selectedSlice?.label ?? "Total")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        AmountText(
                            amount: selectedSlice?.amount ?? total,
                            font: .title3.bold(),
                            showCents: false
                        )
                        Text(selectedSlice == nil ? centerCaption : (total > 0
                            ? (selectedSlice!.amount / total).doubleValue.percentString + " of total"
                            : ""))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                // Percent labels sit on the ring band itself (between inner
                // and outer radius) so they never clip the card.
                if showsPercentLabels, total > 0,
                   let frame = proxy.plotFrame.map({ geometry[$0] }) {
                    let center = CGPoint(x: frame.midX, y: frame.midY)
                    let bandRadius = min(frame.width, frame.height) / 2 * 0.82
                    let fractions = labelFractions
                    ForEach(fractions, id: \.id) { item in
                        let theta = item.midFraction * 2 * .pi
                        Text(item.percent)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .position(
                                x: center.x + bandRadius * sin(theta),
                                y: center.y - bandRadius * cos(theta)
                            )
                    }
                }
            }
        }
        .animation(.snappy, value: selectedAngle == nil)
        .sensoryFeedback(.selection, trigger: selectedSlice?.id)
    }

    /// Mid-angle fraction + percent text per slice, skipping slivers that
    /// can't fit a label.
    private var labelFractions: [(id: String, midFraction: Double, percent: String)] {
        let totalValue = total.doubleValue
        guard totalValue > 0 else { return [] }
        var running = 0.0
        return slices.compactMap { slice in
            let fraction = slice.amount.doubleValue / totalValue
            defer { running += fraction }
            guard fraction >= 0.07 else { return nil }
            return (slice.id, running + fraction / 2, "\(Int((fraction * 100).rounded()))%")
        }
    }
}

/// Last-two-weeks daily spend: rounded gradient bars, dashed average line,
/// scrub to inspect a day. Lives on Home under the hero.
struct DailySpendChart: View {
    struct Day: Identifiable {
        var date: Date
        var total: Decimal
        var id: Date { date }
    }

    var days: [Day]

    @State private var selectedDate: Date?

    private var average: Double {
        guard !days.isEmpty else { return 0 }
        return days.reduce(0.0) { $0 + $1.total.doubleValue } / Double(days.count)
    }

    private var selectedDay: Day? {
        guard let selectedDate else { return nil }
        return days.first { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
    }

    var body: some View {
        Chart(days) { day in
            BarMark(
                x: .value("Day", day.date, unit: .day),
                y: .value("Spent", day.total.doubleValue)
            )
            .cornerRadius(3)
            .foregroundStyle(
                Calendar.current.isDateInToday(day.date)
                    ? AnyShapeStyle(Theme.heroGradient)
                    : AnyShapeStyle(Theme.accent.opacity(
                        selectedDay == nil || selectedDay?.id == day.id ? 0.55 : 0.25
                    ))
            )

            RuleMark(y: .value("Average", average))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(.secondary.opacity(0.5))
        }
        .chartXSelection(value: $selectedDate)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                AxisValueLabel(format: .dateTime.day(), centered: true)
            }
        }
        .chartYAxis(.hidden)
        .overlay(alignment: .topLeading) {
            if let selectedDay {
                HStack(spacing: 6) {
                    Text(selectedDay.date.shortDay)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    AmountText(amount: selectedDay.total, font: .caption.bold())
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .glassEffect(.regular, in: Capsule())
            }
        }
        .sensoryFeedback(.selection, trigger: selectedDay?.id)
    }
}
