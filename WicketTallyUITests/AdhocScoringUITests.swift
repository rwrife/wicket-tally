import XCTest

/// Issue #16 acceptance evidence: an impromptu game must be scoreable from
/// two names with zero setup. The app launches with
/// `--ui-testing-adhoc`, which resets the store to a genuinely empty
/// database (no leagues, teams, players, or grounds), then:
///
/// 1. the Quick game row opens the quick-game sheet;
/// 2. two names + an overs choice start the game, landing directly in the
///    outdoor scorer;
/// 3. the toss/innings/ball path works exactly like a scheduled fixture;
/// 4. relaunching with `--ui-testing-adhoc-relaunch` (same database file,
///    no reset) finds the impromptu game still listed and scoreable, with
///    the recorded ledger replayed.
///
/// Screenshots attach to the xcresult as visual evidence. Method names are
/// testA/testB so XCTest runs the start before the relaunch.
final class AdhocScoringUITests: XCTestCase {
    @MainActor
    func testAQuickGameFromTwoNamesReachesTheScorer() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-adhoc"]
        app.launch()

        let quick = app.buttons["fixtures.quickGame"]
        XCTAssertTrue(quick.waitForExistence(timeout: 15), "Quick game row missing")
        XCTAssertGreaterThanOrEqual(quick.frame.height, 60, "Quick game row below 60 pt")
        quick.tap()

        let start = app.buttons["adhoc.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        attach(app, name: "20-adhoc-sheet")

        // Type the two sides. Submit moves focus to the next field and the
        // final submit releases the keyboard deterministically.
        let home = app.textFields["adhoc.homeName"]
        XCTAssertTrue(home.waitForExistence(timeout: 5))
        home.tap()
        home.typeText("Street Kings")
        let next = app.buttons["Next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5), "Keyboard Next key missing")
        next.tap()

        let away = app.textFields["adhoc.awayName"]
        XCTAssertTrue(away.waitForExistence(timeout: 5))
        away.tap()
        away.typeText("Gully XI")
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "Keyboard Done key missing")
        done.tap()

        // Bound the keyboard-dismiss animation before tapping start.
        var remaining = 10
        while !start.isHittable && remaining > 0 {
            usleep(500_000)
            remaining -= 1
        }
        XCTAssertTrue(start.isHittable, "Start game never became hittable")
        start.tap()

        let toss = app.buttons["scorer.recordToss"]
        XCTAssertTrue(toss.waitForExistence(timeout: 10), "Scorer did not open for the ad-hoc game")
        attach(app, name: "21-adhoc-scorer-toss")
        toss.tap()

        let startInnings = app.buttons["scorer.startInnings"]
        XCTAssertTrue(startInnings.waitForExistence(timeout: 5))
        startInnings.tap()

        app.buttons["scorer.ball.4"].tap()
        // The scoreboard merges into one accessibility element; assert on
        // the scoreline label the same way the scheduled-flow tests do.
        let score = app.staticTexts.matching(NSPredicate(format: "label == '4/0'")).firstMatch
        XCTAssertTrue(score.waitForExistence(timeout: 5))
        attach(app, name: "22-adhoc-score")
    }

    @MainActor
    func testBQuickGameSurvivesRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-adhoc-relaunch"]
        app.launch()

        // The impromptu fixture persists across relaunch with its derived
        // side names rendered from the hidden quick-games records.
        let row = app.staticTexts.matching(NSPredicate(format: "CONTAINS[c] 'gully xi'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "Ad-hoc game did not persist")
        attach(app, name: "23-adhoc-relaunch-list")

        let scoreMatch = app.buttons["Score match"]
        XCTAssertTrue(scoreMatch.waitForExistence(timeout: 5))
        scoreMatch.tap()

        // The recorded toss and ball survive too: replay still shows 4/0.
        let score = app.staticTexts.matching(NSPredicate(format: "label == '4/0'")).firstMatch
        XCTAssertTrue(score.waitForExistence(timeout: 10), "Ledger did not replay after relaunch")
        attach(app, name: "24-adhoc-relaunch-score")
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
