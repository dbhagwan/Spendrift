import SwiftData
import SwiftUI

struct AccountsView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.modelContext) private var modelContext
    @Query private var institutions: [LinkedInstitution]
    @Query private var accounts: [Account]

    @State private var isLinking = false

    var body: some View {
        List {
            ForEach(institutions) { institution in
                Section {
                    institutionHeader(institution)
                    ForEach(accounts.filter { $0.institution?.id == institution.id || $0.institutionName == institution.name }) { account in
                        AccountRow(account: account)
                    }
                } header: {
                    Text(institution.name)
                }
            }

            // Accounts not tied to a tracked institution (e.g. seeded data).
            let orphans = accounts.filter { account in
                !institutions.contains { $0.name == account.institutionName || $0.id == account.institution?.id }
            }
            if !orphans.isEmpty {
                Section("Other") {
                    ForEach(orphans) { account in
                        AccountRow(account: account)
                    }
                }
            }

            Section {
                Button {
                    linkInstitution()
                } label: {
                    Label(isLinking ? "Connecting…" : "Connect another institution", systemImage: "plus.circle")
                }
                .disabled(isLinking)
            }

            if institutions.isEmpty && accounts.isEmpty {
                EmptyStateView(
                    systemImage: "building.columns",
                    title: "No institutions linked",
                    message: "Connect your bank, cards, loans, and investments through Plaid.",
                    actionTitle: "Connect with Plaid",
                    action: { linkInstitution() }
                )
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Accounts")
        .refreshable { await appEnvironment.sync(context: modelContext) }
    }

    @ViewBuilder
    private func institutionHeader(_ institution: LinkedInstitution) -> some View {
        HStack {
            Image(systemName: institution.requiresRelink ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(institution.requiresRelink ? Theme.warning : Theme.positive)
            VStack(alignment: .leading, spacing: 2) {
                Text(institution.requiresRelink ? "Reconnection required" : "Sync healthy")
                    .font(.subheadline.weight(.medium))
                if let lastSyncedAt = institution.lastSyncedAt {
                    Text("Updated \(lastSyncedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let error = institution.lastSyncError {
                    Text(error).font(.caption).foregroundStyle(Theme.negative)
                }
            }
            Spacer()
            if institution.requiresRelink {
                Button("Relink") {
                    Task { try? await appEnvironment.plaidLink.relink(itemID: institution.providerItemID) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                modelContext.delete(institution)
                try? modelContext.save()
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    private func linkInstitution() {
        Task {
            isLinking = true
            defer { isLinking = false }
            if let result = try? await appEnvironment.plaidLink.linkNewInstitution() {
                modelContext.insert(LinkedInstitution(
                    providerItemID: result.providerItemID,
                    name: result.institutionName,
                    lastSyncedAt: .now
                ))
                try? modelContext.save()
                await appEnvironment.sync(context: modelContext)
            }
        }
    }
}

struct AccountRow: View {
    @Bindable var account: Account
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationLink {
            AccountDetailView(account: account)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(account.isHidden ? .secondary : .primary)
                    Text("\(account.kind.displayName) ••\(account.mask)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    AmountText(
                        amount: account.kind.isLiability ? -account.currentBalance : account.currentBalance,
                        font: .subheadline,
                        colorBySign: account.kind.isLiability
                    )
                    if account.isHidden {
                        Text("Hidden").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .swipeActions(edge: .trailing) {
            Button {
                account.isHidden.toggle()
                Task { await appEnvironment.pipeline.recompute(in: modelContext) }
            } label: {
                Label(account.isHidden ? "Show" : "Hide", systemImage: account.isHidden ? "eye" : "eye.slash")
            }
            .tint(.gray)
        }
    }
}

struct AccountDetailView: View {
    @Bindable var account: Account
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Form {
            Section("Balance") {
                LabeledContent("Current") { AmountText(amount: account.currentBalance, font: .body) }
                if let available = account.availableBalance {
                    LabeledContent("Available") { AmountText(amount: available, font: .body) }
                }
                if let limit = account.creditLimit {
                    LabeledContent("Credit limit") { AmountText(amount: limit, font: .body) }
                }
            }
            Section("Participation") {
                Toggle("Hidden everywhere", isOn: recomputeBinding(\.isHidden))
                Picker("Role", selection: roleBinding) {
                    Text("Full").tag(AccountRole.full)
                    Text("Spending only").tag(AccountRole.spendingOnly)
                    Text("Asset only").tag(AccountRole.assetOnly)
                    Text("Liability only").tag(AccountRole.liabilityOnly)
                }
                Text("Controls whether this account counts toward net worth, budgets, or both.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Details") {
                LabeledContent("Institution", value: account.institutionName)
                LabeledContent("Type", value: "\(account.kind.displayName) · \(account.subtype)")
                LabeledContent("Currency", value: account.currencyCode)
            }
        }
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func recomputeBinding(_ keyPath: ReferenceWritableKeyPath<Account, Bool>) -> Binding<Bool> {
        Binding(
            get: { account[keyPath: keyPath] },
            set: {
                account[keyPath: keyPath] = $0
                Task { await appEnvironment.pipeline.recompute(in: modelContext) }
            }
        )
    }

    private var roleBinding: Binding<AccountRole> {
        Binding(
            get: { account.role },
            set: {
                account.role = $0
                Task { await appEnvironment.pipeline.recompute(in: modelContext) }
            }
        )
    }
}

#Preview {
    NavigationStack { AccountsView() }
        .environment(AppEnvironment.mock())
        .modelContainer(ModelContainerFactory.preview())
}
