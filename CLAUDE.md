# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Polaris is an AI-first personal finance copilot for iOS 26+/iPadOS 26+ (Swift 6, SwiftUI, SwiftData, WidgetKit, Swift Charts, VisionKit) with a TypeScript backend scaffold for Plaid integration and AI orchestration. The hero feature is **Safe to Spend Today** — everything else feeds or explains that number.

## Build & Run

The Xcode project is generated, not checked in:

```bash
xcodegen generate        # requires: brew install xcodegen
open Polaris.xcodeproj
```

Targets: `Polaris` (app) and `PolarisWidgets` (widget extension, shares `Core/Models`, `Core/Utilities`, and `SharedSnapshotStore.swift` via project.yml source entries). When adding a model or utility the widgets need, no project change is required; for other shared files, update the `PolarisWidgets.sources` list in `project.yml`.

The app defaults to **mock mode** (`AppEnvironment(useMocks: true)` in `App/PolarisApp.swift`) — `MockSyncService` seeds `PreviewContent/SampleData.swift` and everything runs without a backend.

Backend:

```bash
cd Backend && npm install && npm run dev   # needs .env (copy .env.example) + Postgres schema in src/db/schema.sql
npm run typecheck
```

Icons: `python3 scripts/generate_icons.py` (Pillow).

## Architecture — the part that matters

**All derived state flows through `Core/AI/AIPipeline.swift` (`recompute`).** It runs the full pipeline: pending/posted dedupe → transfer detection → recurring detection → receipt-to-transaction matching → `SpendingProfileEngine` → `ForecastEngine` (forecast + budget risk) → `SafeToSpendEngine` → AI narratives → net-worth snapshot → widget snapshot (`SharedSnapshotStore` in the App Group, then `WidgetCenter.reloadAllTimelines()`). Any mutation that affects money (category correction, budget edit, account hidden, receipt matched) must end with a `pipeline.recompute(in:)` call — views already do this via `AppEnvironment`.

**Structured AI only.** Model-backed inference goes through the `AIInferenceService` protocol and returns validated value types defined in `Core/Models/AIOutputs.swift` (`SpendingProfile`, `SpendForecast`, `BudgetRiskAssessment`, `SafeToSpendDecision`, `SpendingInsight`, `Recommendation`, `WidgetSnapshot`). Never render raw model text; insights/recommendations must carry `evidence` and `confidence`.

**On-device AI.** `FoundationModelsAIService` (Apple Foundation Models / Apple Intelligence, iOS 26) is the production `AIInferenceService` — classification, receipt extraction, and narratives all run on device via `@Generable` guided generation. Every method checks `SystemLanguageModel.default.availability` and falls back to `MockAIService` heuristics (ineligible devices, AI disabled, simulators/CI). Keep prompts terse — the on-device model has a small context window; `compactSummary` exists for that reason.

**Categorization is layered** (`Core/AI/CategorizationEngine.swift`): user correction memory → rules → *specific* provider hint → on-device AI (generic hints like GENERAL_MERCHANDISE only steer the prompt, they don't decide). The AI prompt carries direction/date/recurring context plus the user's own corrections as few-shot examples (`relevantExamples`) so one correction generalizes to similar merchants. Low-confidence results are flagged `needsAIReview` and re-classified by a bounded sweep in `AIPipeline.recompute` after recurring detection. User corrections always win (`categorySource == .user`, confidence 1.0), are learned via `learn(merchant:category:)`, and apply retroactively to same-merchant transactions. Don't overwrite user-sourced categories anywhere.

**Safe-to-spend** (`Core/AI/SafeToSpendEngine.swift`) = deterministic base (remaining discretionary budget − upcoming recurring discretionary − unreserved essential, ÷ days left) × behavioral adjustment clamped to [0.7, 1.2], with every adjustment pushed into `adjustmentReasons` for the explanation drawer. Keep the clamp and the reasons — explainability is a product requirement. Forecast/risk math counts anomalies and recurring charges once (no daily extrapolation — only variable spend paces out), and upcoming charges in categories excluded from spend (transfers, investments) appear in the bills list and cash-flow calendar but never reduce spend forecasts or safe-to-spend.

**Dependency injection:** `App/AppEnvironment.swift` is the composition root, injected via SwiftUI `.environment()`. Previews use `AppEnvironment.mock()` + `ModelContainerFactory.preview()` (in-memory, seeded).

**Plaid:** the Link iOS SDK (LinkKit, SPM package in `project.yml`) is presented by `PlaidLinkService`; mock mode (`simulated: true`) bypasses the SDK entirely. **Secrets:** Plaid access tokens and model API keys exist only in `Backend/`. The device stores only a session token / Apple user ID in the Keychain (`KeychainStore`). Don't add provider API calls to the iOS app.

**iCloud sync (three channels):** (1) SwiftData→CloudKit private database (`ModelContainerFactory` — falls back to local-only when iCloud is unavailable, e.g. simulators/CI); because of CloudKit rules, `@Model` classes must have **no `@Attribute(.unique)`** and **every stored property needs a default value** — keep this invariant when adding models. (2) iCloud Keychain (`KeychainStore` items are `kSecAttrSynchronizable`) carries credentials so a new device is pre-authenticated and the backend returns the same Plaid-linked institutions. (3) `NSUbiquitousKeyValueStore` syncs the categorization correction memory. Entitlements live in `project.yml`.

**Money convention:** `Transaction.amount` is positive for money out, negative for money in (Plaid convention). Spend totals must filter via `countsAsSpend` (excludes transfers, reimbursements, hidden, superseded pending, and excluded categories).

## Backend notes

`Backend/src/ai.ts` calls the Anthropic API (model `claude-opus-4-8`) with structured outputs (`output_config.format` + zod validation). `Backend/src/index.ts` contains an inline job runner explicitly marked TODO for replacement with a real queue. Plaid webhook → enqueue sync → `/transactions/sync` cursor-based upsert.

## Design system

**Adaptive glass** (Robinhood/Apple Stocks direction): iOS 26 real Liquid Glass (`.glassEffect`) over `AppBackground` — an aurora backdrop that adapts to light/dark via `colorScheme` (appearance preference in `@AppStorage("appearance")`, picker in Settings). `Card` renders `.glassEffect(.regular.interactive(), in:)`; List screens use `.scrollContentBackground(.hidden)` + `.glassListRow()`. One accent color (mint, `Assets.xcassets/AccentColor`). Liquid Glass lives only in `Card`/`glassListRow` in `Core/DesignSystem/Theme.swift`. Building requires Xcode 26 (CI selects it explicitly).

**Interaction conventions:** tab-root pages have **no `navigationTitle`** (the tab bar already says where you are; pushed detail pages keep titles — `NetWorthView(showsTitle:)` handles being both). Rows support hold-to-preview `contextMenu` (transaction preview card, full receipt image). Key actions give haptics via `.sensoryFeedback`. iPhone tabs: Home, Transactions, **Net Worth**, Spending Profile, Budget — Receipts is reached via the Home card (NavigationLink), Accounts via Settings. Gradients are reserved for data (hero numbers, chart marks — `Theme.heroGradient`/`chartAreaGradient`); shared interactive charts (`DonutChart` — generic slices for categories *and* account allocation, optional on-ring percent labels — `DailySpendChart`, per-category/account-kind `chartColor`) live in `Core/DesignSystem/Charts.swift`; `DonutSpinView` is the full-screen 3D drag-to-spin breakdown (pure SwiftUI `rotation3DEffect`, haptic per sector) opened from the donut cards on Budget, Spending Profile, and Net Worth.

**AI surfaces beyond the pipeline:** natural-language transaction search (`parseTransactionQuery` → `TransactionSearchQuery`, a structured filter — never free text); anomaly detection (`AnomalyDetector`, deterministic, narrated by the model via `profile.recentAnomalies`); subscription audit (`SubscriptionAuditor`, deterministic insights); what-if coach (`WhatIfView`, deterministic math over the profile); per-line receipt categories (basket split) + return-window extraction; Siri via App Intents (`PolarisAppIntents.swift`, answers from the widget snapshot — instant, offline); weekly digest + return reminders (`NotificationScheduler`, local notifications only, gated on the Settings toggle).

**Platform surfaces:** Live Activity / Dynamic Island (`SafeToSpendActivityAttributes` in Core/Models — shared with PolarisWidgets, `#if canImport(ActivityKit)` so the watch target skips it — driven by `LiveActivityController` after each recompute, Settings-gated). Watch app (`PolarisWatch` target, embedded in the iOS app; `WatchSync` pushes the widget snapshot over WatchConnectivity `applicationContext` — App Groups don't span devices). FinanceKit Wallet import (`FinanceKitImporter`, runtime-gated; needs Apple's com.apple.developer.financekit entitlement, NOT in project.yml — request it before adding). Household budget sharing (`HouseholdSharing`: CKShare around a CloudKit mirror record of the budget — SwiftData's CloudKit mirror can't share; acceptance flow is TODO(production)). Goals and rollover feed `SafeToSpendEngine.decide(goalDailyReservation:rolloverCredit:)` — both must appear in `adjustmentReasons`/decision fields for the explanation drawer. `generateNarratives` takes `monthlyCategoryHistory` so the on-device model can tool-call real per-category trends (`CategoryHistoryTool`).

Shared components in `Core/DesignSystem/Theme.swift`: `Card`, `AmountText` (respects privacy mode — always use it for currency), `ProgressRing`, `ConfidenceBadge`, `SkeletonBlock`, `EmptyStateView`. Widget financial values must be `privacySensitive()`.
