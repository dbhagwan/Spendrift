import AuthenticationServices
import SwiftData
import SwiftUI

/// Welcome → Sign in with Apple → privacy → Plaid Link → receipts opt-in →
/// initial AI analysis → optional budget → dashboard.
struct OnboardingFlowView: View {
    private enum Step: Int, CaseIterable {
        case welcome, signIn, privacy, connectAccounts, receipts, initialSync, budget
    }

    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.modelContext) private var modelContext

    @State private var step: Step = .welcome
    @State private var linkedInstitutionName: String?
    @State private var isLinking = false
    @State private var syncProgressText = "Connecting…"
    @State private var monthlyBudget: Double = 3500

    // Welcome choreography: line draws → star ignites → copy fades in.
    @State private var lineProgress: CGFloat = 0
    @State private var showStar = false
    @State private var showWelcomeContent = false
    @Namespace private var starNamespace

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: 480)
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppBackground())
        .animation(.spring(duration: 0.65, bounce: 0.18), value: step)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcome
        case .signIn: signIn
        case .privacy: privacy
        case .connectAccounts: connectAccounts
        case .receipts: receipts
        case .initialSync: initialSync
        case .budget: budgetSetup
        }
    }

    /// The opening scene: a market line climbs out of the lower-left and
    /// ignites the North Star where it lands; the name and copy follow.
    private var welcome: some View {
        VStack(spacing: 16) {
            GeometryReader { geometry in
                let size = geometry.size
                let end = CGPoint(
                    x: TrendToStarShape.endPoint.x * size.width,
                    y: TrendToStarShape.endPoint.y * size.height
                )
                ZStack(alignment: .topLeading) {
                    TrendToStarShape()
                        .trim(from: 0, to: lineProgress)
                        .stroke(
                            Theme.heroGradient,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                        )
                        .shadow(color: Theme.accent.opacity(0.55), radius: 10)

                    // Placed by layout (not .position) so the matched frame
                    // is the 96pt star itself, making the morph to the
                    // sign-in emblem track the real shape.
                    NorthStarShape()
                        .fill(Theme.heroGradient)
                        .frame(width: 96, height: 96)
                        .shadow(color: Theme.accent.opacity(0.75), radius: showStar ? 26 : 0)
                        .scaleEffect(showStar ? 1 : 0.1)
                        .opacity(showStar ? 1 : 0)
                        .matchedGeometryEffect(id: "northStar", in: starNamespace)
                        .padding(.leading, max(0, end.x - 48))
                        .padding(.top, max(0, end.y - 48))
                }
            }
            .frame(maxHeight: .infinity)
            .accessibilityHidden(true)

            Group {
                Text("Polaris").font(.largeTitle.bold())
                Text("An AI copilot for your money. Link your accounts once — Polaris learns your spending, predicts what's ahead, and tells you exactly what's safe to spend today.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                primaryButton("Get Started") { step = .signIn }
                    .padding(.top, 8)
            }
            .opacity(showWelcomeContent ? 1 : 0)
            .offset(y: showWelcomeContent ? 0 : 18)
        }
        .task {
            guard lineProgress == 0 else { return }
            withAnimation(.easeInOut(duration: 1.6)) { lineProgress = 1 }
            try? await Task.sleep(for: .milliseconds(1_400))
            withAnimation(.spring(duration: 0.55, bounce: 0.45)) { showStar = true }
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.easeOut(duration: 0.5)) { showWelcomeContent = true }
        }
    }

    private var signIn: some View {
        VStack(spacing: 16) {
            Spacer()
            // The welcome star sails here — one continuous object across
            // the transition (matched geometry), now a quiet emblem.
            NorthStarShape()
                .fill(Theme.heroGradient)
                .frame(width: 44, height: 44)
                .shadow(color: Theme.accent.opacity(0.5), radius: 12)
                .matchedGeometryEffect(id: "northStar", in: starNamespace)
                .padding(.bottom, 4)
            header("Sign in", "Your data syncs securely across iPhone and iPad.")
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName]
            } onCompletion: { result in
                Task {
                    if await appEnvironment.auth.handleAuthorization(result) {
                        step = .privacy
                    }
                }
            }
            .frame(height: 50)
            .signInWithAppleButtonStyle(.black)

            Button("Continue without signing in (development)") {
                appEnvironment.auth.signInForDevelopment()
                step = .privacy
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            header("Private by design", nil)
            privacyRow("lock.shield", "Read-only connection", "Polaris can see balances and transactions — it can never move money.")
            privacyRow("key.horizontal", "Credentials never touch the app", "Bank login happens inside Plaid. Access tokens stay on our servers, never on your device.")
            privacyRow("eye.slash", "You stay in control", "Hide accounts, exclude categories, and blur balances any time.")
            Spacer()
            primaryButton("Continue") { step = .connectAccounts }
        }
    }

    private var connectAccounts: some View {
        VStack(spacing: 16) {
            Spacer()
            header("Connect your accounts", "Checking, credit cards, loans, and investments — all in one place.")
            if let linkedInstitutionName {
                Label("\(linkedInstitutionName) connected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.positive)
            }
            Spacer()
            primaryButton(isLinking ? "Connecting…" : "Connect with Plaid") {
                Task {
                    isLinking = true
                    defer { isLinking = false }
                    if let result = try? await appEnvironment.plaidLink.linkNewInstitution() {
                        linkedInstitutionName = result.institutionName
                        modelContext.insert(LinkedInstitution(
                            providerItemID: result.providerItemID,
                            name: result.institutionName,
                            lastSyncedAt: .now
                        ))
                        step = .receipts
                    }
                }
            }
            .disabled(isLinking)
            Button("Skip for now") { step = .receipts }
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var receipts: some View {
        VStack(spacing: 16) {
            Spacer()
            header("Receipts make it smarter", "Snap a receipt and Polaris reads the merchant, total, tip, and line items — then matches it to the card charge automatically.")
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Theme.accent)
            Spacer()
            primaryButton("Sounds good") { startInitialSync() }
        }
    }

    private var initialSync: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView().controlSize(.large)
            Text(syncProgressText)
                .font(.headline)
            Text("Analyzing your spending patterns…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var budgetSetup: some View {
        VStack(spacing: 20) {
            Spacer()
            header("Set a monthly budget", "Polaris recommends a starting point from your history. You can change it anytime.")
            Text(Decimal(monthlyBudget).currency(showCents: false))
                .font(.system(size: 44, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Slider(value: $monthlyBudget, in: 1000...10000, step: 100)
            Spacer()
            primaryButton("Start using Polaris") { finish(withBudget: true) }
            Button("Skip — recommend one for me later") { finish(withBudget: false) }
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func startInitialSync() {
        step = .initialSync
        Task {
            syncProgressText = "Syncing accounts…"
            await appEnvironment.sync(context: modelContext)
            syncProgressText = "Building your spending profile…"
            // Recommend a budget from history: average monthly spend, rounded.
            if let average = appEnvironment.pipeline.profile?.averageMonthlySpend, average > 0 {
                monthlyBudget = (average.doubleValue / 100).rounded() * 100
            }
            step = .budget
        }
    }

    private func finish(withBudget: Bool) {
        if withBudget {
            let budget = Budget(monthlyTotal: Decimal(monthlyBudget))
            // Seed AI-recommended category budgets from the spending profile.
            if let profile = appEnvironment.pipeline.profile {
                for categorySpend in profile.topCategories where !categorySpend.category.isExcludedFromSpend {
                    budget.categories.append(BudgetCategory(
                        category: categorySpend.category,
                        monthlyLimit: categorySpend.monthlyAverage,
                        isAIRecommended: true
                    ))
                }
            }
            modelContext.insert(budget)
        }
        let profile = UserProfile(onboardingCompleted: true)
        modelContext.insert(profile)
        try? modelContext.save()
        Task { await appEnvironment.pipeline.recompute(in: modelContext) }
    }

    // MARK: - Pieces

    private func header(_ title: String, _ subtitle: String?) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.title.bold())
            if let subtitle {
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func privacyRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
    }
}

#Preview {
    OnboardingFlowView()
        .environment(AppEnvironment.mock())
        .modelContainer(ModelContainerFactory.make(inMemory: true))
}
