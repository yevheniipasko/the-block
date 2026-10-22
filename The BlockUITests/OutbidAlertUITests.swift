import XCTest

/// Outbid banner on the real app with a fast market (spec ALERT-1, ALERT-3).
///
/// The fast market targets the buyer's lots every second, so a bid on lot D-0010 (no bids,
/// live for about an hour after launch) is outbid within seconds.
@MainActor
final class OutbidAlertUITests: XCTestCase {

    /// ALERT-1, ALERT-3: after bidding, being outbid shows the banner once the bid sheet closes,
    /// and "Bid again" opens that lot's bid sheet.
    func testOutbidBannerOpensBidSheet() {
        let app = launch(market: "fast")
        openLot(app)
        element(app, "detail.placeBidButton").tap()
        tapWhenReady(app, "bid.reviewButton")
        tapWhenReady(app, "bid.confirmButton")

        let banner = element(app, "alert.banner")
        XCTAssertTrue(banner.waitForExistence(timeout: Constants.alertTimeout))

        tapWhenReady(app, "alert.bidAgainButton")
        XCTAssertTrue(element(app, "bid.reviewButton").waitForExistence(timeout: Constants.stepTimeout))
        XCTAssertFalse(banner.exists)
    }

    // MARK: - Helpers

    private func launch(market: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-market", market]
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func openLot(_ app: XCUIApplication) {
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: Constants.loadTimeout))
        field.tap()
        field.typeText(Constants.lot)
        let lotRow = element(app, "list.row.\(Constants.lot)")
        XCTAssertTrue(lotRow.waitForExistence(timeout: Constants.stepTimeout))
        lotRow.tap()
        XCTAssertTrue(element(app, "detail.placeBidButton").waitForExistence(timeout: Constants.stepTimeout))
    }

    private func tapWhenReady(_ app: XCUIApplication, _ identifier: String) {
        let target = element(app, identifier)
        XCTAssertTrue(target.waitForExistence(timeout: Constants.stepTimeout), "\(identifier) not found")
        target.tap()
    }

}

private enum Constants {
    static let lot = "D-0010"
    static let loadTimeout: TimeInterval = 20
    static let alertTimeout: TimeInterval = 30
    static let stepTimeout: TimeInterval = 10
}
