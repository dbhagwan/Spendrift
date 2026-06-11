import SwiftUI

/// Full-screen donut tilted into 3D that you spin with a drag. Whatever
/// sector faces you is selected — each new selection clicks via haptics and
/// the sector lifts out of the ring — with its breakdown beneath. Pure
/// SwiftUI (custom annular sectors + `rotation3DEffect`), no SceneKit.
struct DonutSpinView: View {
    var title: String
    var slices: [DonutSlice]

    @Environment(\.dismiss) private var dismiss
    @State private var rotation: Double = 0          // committed, degrees
    @GestureState private var dragDelta: Double = 0  // in-flight, degrees

    private var total: Decimal { slices.reduce(0) { $0 + $1.amount } }
    private var currentRotation: Double { rotation + dragDelta }

    /// Cumulative [start, end) fraction of the ring per slice.
    private var segments: [(slice: DonutSlice, start: Double, end: Double)] {
        let totalValue = total.doubleValue
        guard totalValue > 0 else { return [] }
        var running = 0.0
        return slices.map { slice in
            let fraction = slice.amount.doubleValue / totalValue
            defer { running += fraction }
            return (slice, running, running + fraction)
        }
    }

    /// The slice whose middle currently faces the viewer (6 o'clock). The
    /// ring is drawn from 12 o'clock, so after rotating by r degrees the
    /// front holds the fraction ((180 − r) mod 360) / 360.
    private var selected: DonutSlice? {
        guard !segments.isEmpty else { return nil }
        let front = (((180 - currentRotation).truncatingRemainder(dividingBy: 360)) + 360)
            .truncatingRemainder(dividingBy: 360) / 360
        return segments.first { front >= $0.start && front < $0.end }?.slice
            ?? segments.last?.slice
    }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 24) {
                header
                Spacer(minLength: 0)
                spinningDonut
                breakdown
                Text("Drag to spin — the front slice opens up")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
            .padding()
        }
        .sensoryFeedback(.selection, trigger: selected?.id)
    }

    private var header: some View {
        HStack {
            Text(title)
                .font(.title3.weight(.semibold))
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .padding(10)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Close")
        }
    }

    private var spinningDonut: some View {
        ZStack {
            ForEach(segments, id: \.slice.id) { segment in
                let isFront = selected?.id == segment.slice.id
                AnnularSector(
                    startFraction: segment.start,
                    endFraction: segment.end,
                    innerRatio: 0.62
                )
                .fill(segment.slice.color.gradient)
                .opacity(isFront ? 1 : 0.78)
                .scaleEffect(isFront ? 1.07 : 1)
                .animation(.snappy(duration: 0.25), value: selected?.id)
            }
        }
        .frame(width: 300, height: 300)
        .rotationEffect(.degrees(currentRotation))
        .rotation3DEffect(.degrees(48), axis: (x: 1, y: 0, z: 0), perspective: 0.55)
        .frame(height: 230)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .updating($dragDelta) { value, state, _ in
                    state = value.translation.width * 0.6
                }
                .onEnded { value in
                    rotation += value.translation.width * 0.6
                        + (value.predictedEndTranslation.width - value.translation.width) * 0.2
                    snapToNearest()
                }
        )
    }

    private var breakdown: some View {
        Group {
            if let selected {
                VStack(spacing: 6) {
                    if let icon = selected.systemImage {
                        Image(systemName: icon)
                            .font(.title3)
                            .foregroundStyle(selected.color)
                    }
                    Text(selected.label)
                        .font(.headline)
                    AmountText(
                        amount: selected.amount,
                        font: .system(size: 40, weight: .bold),
                        showCents: false,
                        style: AnyShapeStyle(selected.color.gradient)
                    )
                    if total > 0 {
                        Text("\((selected.amount / total).doubleValue.percentString) of \(total.currency(showCents: false))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .id(selected.id)
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
                .padding(.horizontal, 32)
                .padding(.vertical, 18)
                .glassEffect(
                    .regular,
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                )
            }
        }
        .animation(.snappy(duration: 0.25), value: selected?.id)
    }

    /// Settle so the nearest sector's middle sits exactly at the front.
    private func snapToNearest() {
        guard !segments.isEmpty else { return }
        let front = (((180 - rotation).truncatingRemainder(dividingBy: 360)) + 360)
            .truncatingRemainder(dividingBy: 360) / 360
        let segment = segments.first { front >= $0.start && front < $0.end } ?? segments[segments.count - 1]
        let mid = (segment.start + segment.end) / 2
        var delta = (180 - mid * 360 - rotation).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        withAnimation(.spring(duration: 0.45, bounce: 0.3)) {
            rotation += delta
        }
    }
}

/// One donut segment as a fillable path. Fractions run clockwise from
/// 12 o'clock; a small fixed gap keeps segments visually separate.
private struct AnnularSector: Shape {
    var startFraction: Double
    var endFraction: Double
    var innerRatio: CGFloat

    func path(in rect: CGRect) -> Path {
        let gapDegrees = 1.2
        let start = Angle.degrees(startFraction * 360 - 90 + gapDegrees / 2)
        let end = Angle.degrees(max(startFraction * 360 + gapDegrees, endFraction * 360) - 90 - gapDegrees / 2)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * innerRatio

        var path = Path()
        path.addArc(center: center, radius: outer, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: center, radius: inner, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }
}

#Preview {
    DonutSpinView(
        title: "Where It's Going",
        slices: [
            DonutSlice(category: .dining, amount: 420),
            DonutSlice(category: .groceries, amount: 380),
            DonutSlice(category: .shopping, amount: 300),
            DonutSlice(category: .transportation, amount: 180),
            DonutSlice(category: .entertainment, amount: 90),
        ]
    )
    .environment(AppEnvironment.mock())
}
