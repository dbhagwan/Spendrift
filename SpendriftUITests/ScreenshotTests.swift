import XCTest

/// Drives the full app — onboarding through every tab — capturing a named
/// screenshot at each step. CI exports the attachments as the
/// `simulator-screenshots` artifact.
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
        // ── Onboarding ──────────────────────────────────────────────
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
        let startUsing = app.buttons["Start using Spendrift"]
        XCTAssertTrue(startUsing.waitForExistence(timeout: 60), "Budget setup should appear after initial sync")
        snap("06-onboarding-budget")
        startUsing.tap()

        // ── Home ────────────────────────────────────────────────────
        let safeToSpend = app.staticTexts["SAFE TO SPEND TODAY"]
        XCTAssertTrue(safeToSpend.waitForExistence(timeout: 60), "Home should show the safe-to-spend hero card")
        sleep(2) // let remaining cards settle
        snap("07-home")

        // Safe-to-spend explanation drawer.
        let why = app.buttons["Why this number?"]
        if why.exists {
            why.tap()
            if app.staticTexts["How this is computed"].waitForExistence(timeout: 10) {
                sleep(1)
                snap("08-safe-to-spend-explanation")
                app.buttons["Done"].tap()
            }
        }

        // ── Tabs ────────────────────────────────────────────────────
        captureTab("Transactions", screenshot: "09-transactions")
        captureTab("Receipts", screenshot: "10-receipts")
        captureTab("Spending Profile", screenshot: "11-spending-profile")
        captureTab("Budget", screenshot: "12-budget")
        captureTab("Accounts", screenshot: "13-accounts")
    }

    private func captureTab(_ tab: String, screenshot name: String) {
        let button = app.tabBars.buttons[tab]
        guard button.waitForExistence(timeout: 10) else {
            XCTFail("Tab \(tab) not found")
            return
        }
        button.tap()
        sleep(2) // allow content + charts to render
        snap(name)
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
