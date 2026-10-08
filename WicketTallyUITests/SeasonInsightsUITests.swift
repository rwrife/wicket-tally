import XCTest

final class SeasonInsightsUITests: XCTestCase {
    @MainActor
    func testSeasonLinksBackToScorecard() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-season", "--indica-theme", "sunlight"]
        app.launch()
        app.tabBars.buttons["Stats"].tap()
        let player = app.buttons["Season Batter"].firstMatch
        for _ in 0..<6 where !player.isHittable { app.swipeUp() }
        XCTAssertTrue(player.waitForExistence(timeout: 15))
        player.tap()
        XCTAssertTrue(app.staticTexts["Best match runs: 4"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Cumulative runs 4 • wickets 0"].exists)
        XCTAssertTrue(app.buttons["season.share"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "season-insights-sunlight"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let scorecard = app.buttons["Open match scorecard"].firstMatch
        for _ in 0..<6 where !scorecard.isHittable { app.swipeUp() }
        XCTAssertTrue(scorecard.isHittable)
        scorecard.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Season Batter: 4")).firstMatch.waitForExistence(timeout: 5))
    }
}
