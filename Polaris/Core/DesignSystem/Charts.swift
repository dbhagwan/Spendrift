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

/// Interactive donut: tap (or drag) a sector to see its share in the center.
/// Used for "where the money goes" on Budget and Spending Profile.
struct CategoryDonutChart: View {
    struct Slice: Identifiable {
        var category: SpendingCategory
        var amount: Decimal
        var id: String { category.rawValue }
    }

    var slices: [Slice]
    var centerCaption: String = "this period"

    @State private var selectedAngle: Double?

    private var total: Decimal { slices.reduce(0) { $0 + $1.amount } }

    private var selectedSlice: Slice? {
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
            .foregroundStyle(slice.category.chartColor)
            .opacity(selectedSlice == nil || selectedSlice?.id == slice.id ? 1 : 0.35)
        }
        .chartAngleSelection(value: $selectedAngle)
        .chartBackground { proxy in
            GeometryReader { geometry in
                if let frame = proxy.plotFrame.map({ geometry[$0] }) {
                    VStack(spacing: 2) {
                        Text(selectedSlice?.category.displayName ?? "Total")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        AmountText(
                            amount: selectedSlice?.amount ?? total,
                            font: .title3.bold(),
                            showCents: false
                        )
                        Text(selectedSlice == nil ? centerCaption : (total > 0
                            ? (selectedSlice!.amount / total).doubleValue.percentString + " of spend"
                            : ""))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .animation(.snappy, value: selectedAngle == nil)
        .sensoryFeedback(.selection, trigger: selectedSlice?.id)
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
