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

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: 480)
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .animation(.snappy, value: step)
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

    private var welcome: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Theme.accent)
            Text("Spendrift").font(.largeTitle.bold())
            Text("An AI copilot for your money. Link your accounts once — Spendrift learns your spending, predicts what's ahead, and tells you exactly what's safe to spend today.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            primaryButton("Get Started") { step = .signIn }
        }
    }

    private var signIn: some View {
        VStack(spacing: 16) {
            Spacer()
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
            privacyRow("lock.shield", "Read-only connection", "Spendrift can see balances and transactions — it can never move money.")
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
            header("Receipts make it smarter", "Snap a receipt and Spendrift reads the merchant, total, tip, and line items — then matches it to the card charge automatically.")
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
            header("Set a monthly budget", "Spendrift recommends a starting point from your history. You can change it anytime.")
            Text(Decimal(monthlyBudget).currency(showCents: false))
                .font(.system(size: 44, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Slider(value: $monthlyBudget, in: 1000...10000, step: 100)
            Spacer()
            primaryButton("Start using Spendrift") { finish(withBudget: true) }
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
