import XCTest

/// Issue #9 acceptance evidence: layout tests for the scorer and glance mode
/// in the Direct Sunlight theme, on the smallest available iPhone simulator.
///
/// The app is launched with `--indica-theme sunlight`, which seeds the
/// persisted skin selection before the first view reads it (see
/// `WicketTallyApp.init`), so the whole app — not just glance mode — renders
/// with the Sunlight tokens. Screenshots are attached to the xcresult as
/// visual evidence (`10-sunlight-scorer`, `11-sunlight-glance`).
///
/// These tests prove token wiring and layout geometry in the simulator.
/// Real-sun legibility on a physical device stays a pending human field
/// check per repo convention.
final class ScorerSunlightUITests: XCTestCase {
    @MainActor
    func testScorerAndGlanceLayoutUnderSunlightTheme() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-scorer", "--indica-theme", "sunlight"]
        app.launch()

        let scoreMatch = app.buttons["Score match"]
        XCTAssertTrue(scoreMatch.waitForExistence(timeout: 15))
        scoreMatch.tap()

        let toss = app.buttons["scorer.recordToss"]
        XCTAssertTrue(toss.waitForExistence(timeout: 5))
        toss.tap()
        let start = app.buttons["scorer.startInnings"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        // Outdoor promise holds in the Sunlight skin: every primary scorer
        // action stays a >= 60 pt one-thumb target on the smallest iPhone.
        let ids = [
            "scorer.ball.0", "scorer.ball.1", "scorer.ball.2",
            "scorer.ball.3", "scorer.ball.4", "scorer.ball.6",
            "scorer.extra.wide", "scorer.extra.noBall",
            "scorer.extra.bye", "scorer.extra.legBye", "scorer.wicket",
        ]
        for id in ids {
            let control = app.buttons[id]
            XCTAssertTrue(control.waitForExistence(timeout: 5), "Missing \(id)")
            XCTAssertTrue(control.isHittable, "Unhittable \(id)")
            XCTAssertGreaterThanOrEqual(control.frame.height, 60, "Short target \(id)")
            XCTAssertGreaterThanOrEqual(control.frame.width, 60, "Narrow target \(id)")
        }
        attach(app, name: "10-sunlight-scorer")

        app.buttons["scorer.ball.4"].tap()
        // The scoreboard merges into one accessibility element; match the
        // scoreline by label everywhere (identifier queries never resolve on
        // merged children — see issue #15 CI history).
        let score = app.staticTexts.matching(NSPredicate(format: "label == '4/0'")).firstMatch
        XCTAssertTrue(score.waitForExistence(timeout: 5))

        app.buttons["scorer.glanceToggle"].tap()

        // Glance mode renders the score at arm's-length scale under the
        // Sunlight tokens: assert the numerals keep a glance-legible frame.
        let glanceScore = app.staticTexts.matching(NSPredicate(format: "label == '4/0'")).firstMatch
        XCTAssertTrue(glanceScore.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(glanceScore.frame.height, 55, "Glance score not glance-legible")

        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Overs '")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'RRR '")).firstMatch.exists)
        let lastOver = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Last over '")).firstMatch
        XCTAssertTrue(lastOver.waitForExistence(timeout: 5))
        XCTAssertTrue(lastOver.label.contains("4"))

        // The return control is itself an outdoor target, not a hairline link.
        let back = app.buttons["scorer.return"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(back.frame.height, 60, "Return control below outdoor minimum")
        attach(app, name: "11-sunlight-glance")
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
