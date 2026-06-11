import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @Query private var budgets: [Budget]
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage(NotificationScheduler.digestEnabledKey) private var weeklyDigestEnabled = false

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        @Bindable var appEnvironment = appEnvironment
        Form {
            // On iPhone, Accounts isn't a tab (5-tab limit).
            Section {
                NavigationLink("Accounts") { AccountsView() }
            }

            Section {
                Label {
                    LabeledContent("iCloud Sync", value: "On")
                } icon: {
                    Image(systemName: "icloud").foregroundStyle(Theme.accent)
                }
            } footer: {
                Text("Budgets, settings, transactions, and bank connections follow your Apple ID. Sign in on a new device and everything is already set up.")
            }

            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
            }

            Section("Privacy") {
                Toggle("Privacy mode (blur amounts)", isOn: $appEnvironment.privacyModeEnabled)
                if let profile {
                    Toggle("Require Face ID / passcode", isOn: bind(profile, \.appLockEnabled))
                }
            }

            Section("Budget period") {
                if let budget = budgets.first {
                    Picker("Starts on day", selection: startDayBinding(budget)) {
                        ForEach(1...28, id: \.self) { day in
                            Text("\(day)").tag(day)
                        }
                    }
                } else {
                    Text("Set up a budget first.").foregroundStyle(.secondary)
                }
            }

            Section {
                ForEach(SpendingCategory.allCases.filter(\.isDiscretionaryByDefault)) { category in
                    Toggle(category.displayName, isOn: excludedCategoryBinding(category))
                }
            } header: {
                Text("Safe-to-spend categories")
            } footer: {
                Text("Toggled-off categories are excluded from the safe-to-spend calculation.")
            }

            Section {
                Toggle(isOn: $weeklyDigestEnabled) {
                    Label("Weekly digest", systemImage: "bell.badge")
                }
                // Re-run the pipeline so the digest is scheduled or cleared
                // immediately rather than on the next sync.
                .onChange(of: weeklyDigestEnabled) {
                    Task { await appEnvironment.pipeline.recompute(in: modelContext) }
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text("A Sunday-evening summary of your week in money, written on device from your own numbers.")
            }

            Section("AI") {
                LabeledContent("Engine", value: "Apple Intelligence (on-device)")
                NavigationLink("How decisions are made") {
                    aiExplainer
                }
            }

            Section("Account") {
                Button("Sign out", role: .destructive) {
                    appEnvironment.auth.signOut()
                }
            }

            Section {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
            }
        }
        .glassListRow()
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("Settings")
    }

    private var aiExplainer: some View {
        List {
            Section {
                Text("Every number Polaris shows traces back to your transactions, receipts, and budget — never to a model's imagination.")
            }
            Section("Pipeline") {
                Label("Categorization: your corrections → rules → provider hint → AI fallback", systemImage: "1.circle")
                Label("Receipts: on-device OCR → structured extraction → transaction matching", systemImage: "2.circle")
                Label("Profile & forecast: deterministic statistics over your history", systemImage: "3.circle")
                Label("Safe-to-spend: deterministic base × bounded behavioral adjustment, always explained", systemImage: "4.circle")
            }
            .font(.subheadline)
        }
        .navigationTitle("How AI is used")
    }

    // MARK: - Bindings

    private func bind(_ profile: UserProfile, _ keyPath: ReferenceWritableKeyPath<UserProfile, Bool>) -> Binding<Bool> {
        Binding(
            get: { profile[keyPath: keyPath] },
            set: {
                profile[keyPath: keyPath] = $0
                try? modelContext.save()
            }
        )
    }

    private func startDayBinding(_ budget: Budget) -> Binding<Int> {
        Binding(
            get: { budget.periodStartDay },
            set: {
                budget.periodStartDay = $0
                try? modelContext.save()
                Task { await appEnvironment.pipeline.recompute(in: modelContext) }
            }
        )
    }

    private func excludedCategoryBinding(_ category: SpendingCategory) -> Binding<Bool> {
        Binding(
            get: { !(profile?.excludedSafeToSpendCategories.contains(category.rawValue) ?? false) },
            set: { included in
                guard let profile else { return }
                if included {
                    profile.excludedSafeToSpendCategories.removeAll { $0 == category.rawValue }
                } else {
                    profile.excludedSafeToSpendCategories.append(category.rawValue)
                }
                try? modelContext.save()
                Task { await appEnvironment.pipeline.recompute(in: modelContext) }
            }
        )
    }
}

#Preview {
    NavigationStack { SettingsView() }
        .environment(AppEnvironment.mock())
        .modelContainer(ModelContainerFactory.preview())
}
