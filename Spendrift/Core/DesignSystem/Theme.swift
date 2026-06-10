import SwiftUI

/// Design tokens. One accent (mint) plus a semantic palette — no gradients,
/// no decoration. Financial data should read calm.
enum Theme {
    static let accent = Color("AccentColor")
    static let positive = Color(red: 0.18, green: 0.65, blue: 0.45)
    static let negative = Color(red: 0.85, green: 0.32, blue: 0.30)
    static let warning = Color(red: 0.88, green: 0.62, blue: 0.18)

    static let cardCornerRadius: CGFloat = 16
    static let cardPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 14

    static func severityColor(_ severity: InsightSeverity) -> Color {
        switch severity {
        case .positive: positive
        case .neutral: .secondary
        case .warning: warning
        case .critical: negative
        }
    }
}

/// The standard breathable card every dashboard surface uses.
struct Card<Content: View>: View {
    var title: String?
    var systemImage: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                HStack(spacing: 6) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .kerning(0.6)
                    Spacer(minLength: 0)
                }
            }
            content
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
    }
}

/// Currency text that respects privacy mode (blurs when hidden).
struct AmountText: View {
    var amount: Decimal
    var currencyCode: String = "USD"
    var font: Font = .body
    var showCents = true
    var colorBySign = false

    @Environment(AppEnvironment.self) private var appEnvironment

    var body: some View {
        Text(amount.currency(currencyCode, showCents: showCents))
            .font(font.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(color)
            .privacyBlur(appEnvironment.privacyModeEnabled)
            .contentTransition(.numericText())
    }

    private var color: Color {
        guard colorBySign else { return .primary }
        return amount >= 0 ? Theme.positive : Theme.negative
    }
}

extension View {
    @ViewBuilder
    func privacyBlur(_ enabled: Bool) -> some View {
        if enabled {
            self.blur(radius: 8).accessibilityLabel("Hidden amount")
        } else {
            self
        }
    }
}

/// Circular progress used for budget rings.
struct ProgressRing: View {
    var progress: Double // 0...1+, overage drawn in negative color
    var lineWidth: CGFloat = 6
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.tertiarySystemFill), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, progress))
                .stroke(
                    progress > 1 ? Theme.negative : Theme.accent,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.snappy, value: progress)
        }
        .frame(width: size, height: size)
    }
}

/// Small pill showing AI confidence on categorized data.
struct ConfidenceBadge: View {
    var confidence: Double
    var source: CategorySource = .ai

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: source == .user ? "person.fill" : "sparkles")
            Text(source == .user ? "You" : confidence.percentString)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.12), in: Capsule())
    }

    private var color: Color {
        if source == .user { return Theme.accent }
        return confidence >= 0.8 ? Theme.positive : confidence >= 0.5 ? Theme.warning : Theme.negative
    }
}

/// Skeleton placeholder block for loading states.
struct SkeletonBlock: View {
    var height: CGFloat = 80

    @State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
            .fill(Color(.tertiarySystemFill))
            .frame(height: height)
            .opacity(pulse ? 0.5 : 1)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}

struct EmptyStateView: View {
    var systemImage: String
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}
