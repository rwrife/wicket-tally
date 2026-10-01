import XCTest

final class ScorerUITests: XCTestCase {
    @MainActor
    func testSmallestIPhoneScoringFlowAndTargets() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-scorer"]
        app.launch()

        let scoreMatch = app.buttons["Score match"]
        XCTAssertTrue(scoreMatch.waitForExistence(timeout: 15))
        scoreMatch.tap()
        attach(app, name: "01-toss")

        let toss = app.buttons["scorer.recordToss"]
        XCTAssertTrue(toss.waitForExistence(timeout: 5))
        toss.tap()
        let start = app.buttons["scorer.startInnings"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        attach(app, name: "02-innings")
        start.tap()

        let ids = ["scorer.ball.0", "scorer.ball.1", "scorer.ball.2",
                   "scorer.ball.3", "scorer.ball.4", "scorer.ball.6",
                   "scorer.extra.wide", "scorer.extra.noBall",
                   "scorer.extra.bye", "scorer.extra.legBye", "scorer.wicket"]
        for id in ids {
            let control = app.buttons[id]
            XCTAssertTrue(control.waitForExistence(timeout: 5), "Missing \(id)")
            XCTAssertTrue(control.isHittable, "Unhittable \(id)")
            XCTAssertGreaterThanOrEqual(control.frame.height, 60, "Short target \(id)")
            XCTAssertGreaterThanOrEqual(control.frame.width, 60, "Narrow target \(id)")
        }
        attach(app, name: "03-ball-entry")
        app.buttons["scorer.ball.4"].tap()
        // The scoreboard merges into one accessibility element; children
        // surface under the scoreboard identifier with their own labels.
        // The last-over header text now carries the dot sequence itself
        // ("Last over 4, –"), so match by label everywhere.
        let score = app.staticTexts.matching(NSPredicate(format: "label == '4/0'")).firstMatch
        XCTAssertTrue(score.waitForExistence(timeout: 5))
        app.buttons["scorer.glanceToggle"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == '4/0'")).firstMatch
            .waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Overs '")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'RRR '")).firstMatch.exists)
        let lastOver = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Last over '")).firstMatch
        XCTAssertTrue(lastOver.waitForExistence(timeout: 5))
        XCTAssertTrue(lastOver.label.contains("4"))
        attach(app, name: "04-glance")
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
