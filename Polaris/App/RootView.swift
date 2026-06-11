import SwiftData
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case home, transactions, receipts, analytics, netWorth, budget, accounts, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .transactions: "Transactions"
        case .receipts: "Receipts"
        case .analytics: "Spending Profile"
        case .netWorth: "Net Worth"
        case .budget: "Budget"
        case .accounts: "Accounts"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "sparkles.rectangle.stack"
        case .transactions: "list.bullet.rectangle"
        case .receipts: "doc.text.viewfinder"
        case .analytics: "chart.xyaxis.line"
        case .netWorth: "chart.line.uptrend.xyaxis"
        case .budget: "chart.pie"
        case .accounts: "building.columns"
        case .settings: "gearshape"
        }
    }

    /// iPhone tab bar — iOS shows at most 5 items before collapsing into
    /// "More". Net Worth earned a tab; Receipts is one tap away via the Home
    /// card (and Accounts lives in Settings). The iPad sidebar shows everything.
    static let phoneTabs: [AppSection] = [.home, .transactions, .netWorth, .analytics, .budget]
    static let padSidebar: [AppSection] = allCases
}

struct RootView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query private var profiles: [UserProfile]

    @State private var selection: AppSection = .home

    private var needsOnboarding: Bool {
        !(profiles.first?.onboardingCompleted ?? false)
    }

    var body: some View {
        Group {
            if needsOnboarding {
                OnboardingFlowView()
            } else if sizeClass == .regular {
                sidebarLayout
            } else {
                tabLayout
            }
        }
        .task {
            guard !needsOnboarding else { return }
            await appEnvironment.sync(context: modelContext)
        }
    }

    /// iPhone: tab bar.
    private var tabLayout: some View {
        TabView(selection: $selection) {
            ForEach(AppSection.phoneTabs) { section in
                NavigationStack { destination(for: section) }
                    .tabItem { Label(section.title, systemImage: section.systemImage) }
                    .tag(section)
            }
        }
        // Liquid Glass tab bar tucks away while scrolling content, floating
        // back on the lightest upward gesture.
        .tabBarMinimizeBehavior(.onScrollDown)
    }

    /// iPad: sidebar + detail with richer section list.
    /// iOS List selection requires an optional binding (the non-optional
    /// overload is macOS-only); ignore deselection so a row is always active.
    private var sidebarSelection: Binding<AppSection?> {
        Binding(
            get: { selection },
            set: { if let newValue = $0 { selection = newValue } }
        )
    }

    private var sidebarLayout: some View {
        NavigationSplitView {
            List(AppSection.padSidebar, selection: sidebarSelection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle("Polaris")
        } detail: {
            NavigationStack { destination(for: selection) }
        }
    }

    @ViewBuilder
    private func destination(for section: AppSection) -> some View {
        switch section {
        case .home: HomeView()
        case .transactions: TransactionsView()
        case .receipts: ReceiptsView()
        case .analytics: SpendingProfileView()
        case .netWorth: NetWorthView(showsTitle: false)
        case .budget: BudgetView()
        case .accounts: AccountsView()
        case .settings: SettingsView()
        }
    }
}

#Preview {
    RootView()
        .environment(AppEnvironment.mock())
        .modelContainer(ModelContainerFactory.preview())
}
