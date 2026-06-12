import XCTest

/// Drives the full app — onboarding, every tab, every pushed feature screen —
/// capturing a named screenshot at each step, then flips to dark mode via the
/// in-app appearance picker and captures the core screens again. CI exports
/// the attachments as the `simulator-screenshots` artifact.
@MainActor
final class ScreenshotTests: XCTestCase {

    var app: XCUIApplication!

    // Async so it hops onto the MainActor (XCUIApplication is MainActor-isolated).
    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testCaptureAllScreens() {
        runOnboarding()
        captureAllScreens(suffix: "", capturesOnboardingFollowups: true)

        // ── Dark mode: flip the in-app appearance picker and re-capture ──
        setAppearance("Dark")
        captureAllScreens(suffix: "-dark", capturesOnboardingFollowups: false)
        setAppearance("Light")
        captureTab("Home", screenshot: "32-home-light")
    }

    // MARK: - Onboarding

    private func runOnboarding() {
        let getStarted = app.buttons["Get Started"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 15), "Welcome screen should appear")
        snap("01-onboarding-welcome")
        getStarted.tap()

        let devSignIn = app.buttons["Continue without signing in (development)"]
        XCTAssertTrue(devSignIn.waitForExistence(timeout: 10), "Sign-in screen should appear")
        snap("02-onboarding-signin")
        devSignIn.tap()

        let privacyContinue = app.buttons["Continue"]
        XCTAssertTrue(privacyContinue.waitForExistence(timeout: 10), "Privacy screen should appear")
        snap("03-onboarding-privacy")
        privacyContinue.tap()

        let skipPlaid = app.buttons["Skip for now"]
        XCTAssertTrue(skipPlaid.waitForExistence(timeout: 10), "Connect screen should appear")
        snap("04-onboarding-connect")
        skipPlaid.tap()

        let receiptsOK = app.buttons["Sounds good"]
        XCTAssertTrue(receiptsOK.waitForExistence(timeout: 10), "Receipts screen should appear")
        snap("05-onboarding-receipts")
        receiptsOK.tap()

        // Initial sync seeds mock data, then lands on budget setup.
        let startUsing = app.buttons["Start using Polaris"]
        XCTAssertTrue(startUsing.waitForExistence(timeout: 60), "Budget setup should appear after initial sync")
        snap("06-onboarding-budget")
        startUsing.tap()
    }

    // MARK: - Full sweep

    private func captureAllScreens(suffix: String, capturesOnboardingFollowups: Bool) {
        // ── Home ────────────────────────────────────────────────────
        captureTab("Home", screenshot: nil)
        let safeToSpend = app.staticTexts["SAFE TO SPEND TODAY"]
        XCTAssertTrue(safeToSpend.waitForExistence(timeout: 60), "Home should show the safe-to-spend hero card")
        sleep(2) // let remaining cards settle
        snap("07-home\(suffix)")

        // Safe-to-spend explanation drawer.
        let why = app.buttons["Why this number?"]
        if why.exists {
            why.tap()
            if app.staticTexts["How this is computed"].waitForExistence(timeout: 10) {
                sleep(1)
                snap("08-safe-to-spend-explanation\(suffix)")
                app.buttons["Done"].tap()
                sleep(2) // let the dismissal settle before the next query
            }
        }

        // Receipts now lives behind the Home card (Net Worth took its tab).
        // Card titles render uppercased, so match either form.
        if let receiptsCard = firstExisting(["RECEIPTS", "Receipts"], timeout: 10) {
            receiptsCard.tap()
            sleep(2)
            snap("09-receipts\(suffix)")
            // Receipt detail: basket split + return window.
            let target = app.staticTexts["Target"].firstMatch
            if target.waitForExistence(timeout: 5) {
                target.tap()
                sleep(2)
                snap("10-receipt-detail-basket-split\(suffix)")
                app.navigationBars.buttons.firstMatch.tap()
                sleep(1)
            }
            app.navigationBars.buttons.firstMatch.tap() // back Home
            sleep(1)
        }

        // ── Feature screens reached from Home cards ─────────────────
        openHomeCard(["GOALS", "Goals"], snapshot: "08b-goals\(suffix)")
        openHomeCard(["CASH FLOW", "Cash Flow"], snapshot: "08c-cash-flow\(suffix)")
        openMonthlyStory(suffix: suffix)

        // ── Transactions: list + AI natural-language search ─────────
        captureTab("Transactions", screenshot: "11-transactions\(suffix)")
        let searchField = app.searchFields.firstMatch
        if searchField.waitForExistence(timeout: 5) {
            searchField.tap()
            searchField.typeText("dining over $20\n") // \n submits → AI parse
            sleep(2)
            snap("12-transactions-ai-search\(suffix)")
            let clear = app.buttons["Clear AI filter"]
            if clear.exists { clear.tap() }
            let cancel = app.buttons["Cancel"].firstMatch
            if cancel.exists { cancel.tap() }
            sleep(1)
        }

        // ── Net Worth (now a first-class tab) ───────────────────────
        captureTab("Net Worth", screenshot: "13-net-worth\(suffix)")
        // Allocation ring swaps in via the top-right toggle.
        let allocationToggle = app.buttons["Allocation"].firstMatch
        if allocationToggle.waitForExistence(timeout: 5) {
            allocationToggle.tap()
            sleep(1)
            snap("13b-net-worth-allocation\(suffix)")
            let allocationSpin = app.buttons["Spin in 3D"].firstMatch
            if allocationSpin.exists && allocationSpin.isHittable {
                allocationSpin.tap()
                sleep(2)
                snap("13c-allocation-spin-3d\(suffix)")
                app.swipeLeft()
                sleep(1)
                snap("13d-allocation-spin-rotated\(suffix)")
                app.buttons["Close"].firstMatch.tap()
                sleep(1)
            }
            app.buttons["Trend"].firstMatch.tap()
            sleep(1)
        }
        // Breakdown rows sit below the hero card; the brokerage pushes
        // its holdings (allocation ring + positions).
        app.swipeUp()
        sleep(1)
        let brokerageRow = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS 'Brokerage'"))
            .firstMatch
        if brokerageRow.exists && brokerageRow.isHittable {
            brokerageRow.tap()
            sleep(2)
            snap("13e-holdings\(suffix)")
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }
        app.swipeDown() // restore the minimized tab bar
        sleep(1)

        // ── Spending Profile: donut, momentum, audit insights ───────
        captureTab("Spending Profile", screenshot: "14-spending-profile\(suffix)")

        // ── Budget: ring, donut, 3D spin, what-if ───────────────────
        captureTab("Budget", screenshot: "15-budget\(suffix)")
        let categorySpin = app.buttons["Spin in 3D"].firstMatch
        if categorySpin.waitForExistence(timeout: 5) && categorySpin.isHittable {
            categorySpin.tap()
            sleep(2)
            snap("15b-category-spin-3d\(suffix)")
            app.swipeLeft()
            sleep(1)
            snap("15c-category-spin-rotated\(suffix)")
            app.buttons["Close"].firstMatch.tap()
            sleep(1)
        }
        if let whatIf = firstExisting(["WHAT IF…", "What If…"], timeout: 5) {
            whatIf.tap()
            sleep(2)
            // Drag the first lever so the result card shows real numbers.
            let slider = app.sliders.firstMatch
            if slider.waitForExistence(timeout: 5) {
                slider.adjust(toNormalizedSliderPosition: 0.5)
                sleep(1)
            }
            snap("16-what-if\(suffix)")
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }

        guard capturesOnboardingFollowups else { return }

        // ── Settings + Accounts (Settings-only screens, light only) ─
        captureTab("Home", screenshot: nil)
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "Settings gear should be in the Home toolbar")
        settings.tap()
        sleep(1)
        snap("17-settings")

        let accounts = app.buttons["Accounts"].firstMatch
        XCTAssertTrue(accounts.waitForExistence(timeout: 10), "Accounts link should be in Settings")
        accounts.tap()
        sleep(2)
        snap("18-accounts")
        app.navigationBars.buttons.firstMatch.tap() // back to Settings
        sleep(1)

        // Rules editor lives in the AI section, below the fold.
        app.swipeUp()
        sleep(1)
        let rules = app.buttons["Categorization rules"].firstMatch
        if rules.exists && rules.isHittable {
            rules.tap()
            sleep(1)
            snap("19-rules")
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }
        app.navigationBars.buttons.firstMatch.tap() // back to Home
        sleep(1)
    }

    /// Scrolls Home until the named card is hittable, taps it, snaps the
    /// pushed screen, and restores Home's scroll position.
    private func openHomeCard(_ labels: [String], snapshot: String) {
        captureTab("Home", screenshot: nil)
        for _ in 0..<6 {
            if let card = firstExisting(labels, timeout: 1), card.isHittable {
                card.tap()
                sleep(2)
                snap(snapshot)
                app.navigationBars.buttons.firstMatch.tap()
                sleep(1)
                break
            }
            app.swipeUp()
        }
        for _ in 0..<3 { app.swipeDown() }
        sleep(1)
    }

    /// The story card opens a full-screen pager; capture two pages.
    private func openMonthlyStory(suffix: String) {
        captureTab("Home", screenshot: nil)
        let storyCard = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS[c] 'story'"))
            .firstMatch
        for _ in 0..<6 {
            if storyCard.exists && storyCard.isHittable {
                storyCard.tap()
                sleep(2)
                snap("08d-monthly-story\(suffix)")
                app.swipeLeft()
                sleep(1)
                snap("08e-monthly-story-2\(suffix)")
                app.buttons["Close"].firstMatch.tap()
                sleep(1)
                break
            }
            app.swipeUp()
        }
        for _ in 0..<3 { app.swipeDown() }
        sleep(1)
    }

    // MARK: - Appearance

    /// Flips the in-app appearance picker (Settings → Appearance → segment).
    private func setAppearance(_ mode: String) {
        captureTab("Home", screenshot: nil)
        let settings = app.buttons["Settings"]
        guard settings.waitForExistence(timeout: 10) else { return }
        settings.tap()
        sleep(1)
        let segment = app.buttons[mode].firstMatch
        if segment.waitForExistence(timeout: 5) {
            segment.tap()
            sleep(1)
        }
        app.navigationBars.buttons.firstMatch.tap() // back to Home
        sleep(1)
    }

    /// First static text matching any of the given labels (Card titles render
    /// uppercased, so callers pass both forms). Uses expectation-based
    /// waiting — polling `.exists` can blow the snapshot deadline when the
    /// runner is busy encoding the walkthrough video.
    private func firstExisting(_ labels: [String], timeout: TimeInterval) -> XCUIElement? {
        for (index, label) in labels.enumerated() {
            let element = app.staticTexts[label].firstMatch
            if element.waitForExistence(timeout: index == 0 ? timeout : 3) {
                return element
            }
        }
        return nil
    }

    private func captureTab(_ tab: String, screenshot name: String?) {
        let button = app.tabBars.buttons[tab]
        guard button.waitForExistence(timeout: 10) else {
            XCTFail("Tab \(tab) not found")
            return
        }
        button.tap()
        sleep(2) // allow content + charts to render
        if let name {
            snap(name)
        }
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
