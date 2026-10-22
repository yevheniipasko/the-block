import XCTest

/// End-to-end smoke flows on the real app (spec UX-4). The simulated market is switched off
/// (`-market off`) so other bidders can't change a lot mid-test, except in the live test.
///
/// Lot D-0010 (2016 Mazda Mazda3 Turbo) is used throughout: no bids, no Buy Now price, and its
/// auction is live for about an hour after every launch because timing is anchored at launch.
@MainActor
final class SmokeUITests: XCTestCase {

    // MARK: - Flows

    /// LIST-1, LIST-2, LIST-5, LIST-6: the list loads, search narrows it, and a miss shows the empty state.
    func testBrowseAndSearch() {
        let app = launch(market: "off")

        XCTAssertTrue(element(app, "list.resultCount").waitForExistence(timeout: Constants.loadTimeout))
        search(app, for: Constants.lot)
        XCTAssertTrue(row(app, Constants.lot).waitForExistence(timeout: Constants.stepTimeout))

        search(app, for: Constants.noMatch, replacing: Constants.lot)
        XCTAssertTrue(element(app, "list.emptyState").waitForExistence(timeout: Constants.stepTimeout))
    }

    /// DETAIL-2, DETAIL-6: opening a lot shows its header and the pinned bid action.
    func testOpenDetail() {
        let app = launch(market: "off")
        openLot(app)

        XCTAssertTrue(element(app, "detail.title").waitForExistence(timeout: Constants.stepTimeout))
        XCTAssertTrue(element(app, "detail.placeBidButton").exists)
    }

    /// BID-1, BID-5, BID-6, UX-5: review → confirm places the bid and the detail shows you lead.
    func testPlaceValidBid() {
        let app = launch(market: "off")
        openLot(app)

        element(app, "detail.placeBidButton").tap()
        tapWhenReady(app, "bid.reviewButton")
        tapWhenReady(app, "bid.confirmButton")

        XCTAssertTrue(element(app, "detail.buyerMarker").waitForExistence(timeout: Constants.stepTimeout))
    }

    /// BID-3: a bid below the minimum shows the reason and cannot be reviewed.
    func testRejectBelowMinimum() {
        let app = launch(market: "off")
        openLot(app)
        element(app, "detail.placeBidButton").tap()

        let amount = element(app, "bid.amountField")
        XCTAssertTrue(amount.waitForExistence(timeout: Constants.stepTimeout))
        amount.tap()
        amount.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: Constants.clearCount))
        amount.typeText(Constants.tooLowAmount)

        XCTAssertTrue(element(app, "bid.validationMessage").waitForExistence(timeout: Constants.stepTimeout))
        XCTAssertFalse(element(app, "bid.reviewButton").isEnabled)
    }

    /// LIVE-2, LIVE-3: with a fast market, another bidder outbids you while you watch the lot.
    func testOutbidWhileWatching() {
        let app = launch(market: "fast")
        openLot(app)

        element(app, "detail.placeBidButton").tap()
        tapWhenReady(app, "bid.reviewButton")
        tapWhenReady(app, "bid.confirmButton")

        XCTAssertTrue(element(app, "detail.outbidMarker").waitForExistence(timeout: Constants.outbidTimeout))
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

    private func row(_ app: XCUIApplication, _ lot: String) -> XCUIElement {
        element(app, "list.row.\(lot)")
    }

    private func search(_ app: XCUIApplication, for text: String, replacing previous: String = "") {
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: Constants.loadTimeout))
        field.tap()
        if !previous.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count))
        }
        field.typeText(text)
    }

    private func openLot(_ app: XCUIApplication) {
        search(app, for: Constants.lot)
        let lotRow = row(app, Constants.lot)
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
    static let noMatch = "zzzz"
    static let tooLowAmount = "100"
    static let clearCount = 12
    static let loadTimeout: TimeInterval = 20
    static let stepTimeout: TimeInterval = 10
    static let outbidTimeout: TimeInterval = 30
}
