//
//  MyBidsUITests.swift
//  The Block
//
//  XCUITest journey for My bids with the market off: open it from the toolbar, see the
//  seeded groups, open a lot (MYBIDS-1…MYBIDS-3, MYBIDS-6, MYBIDS-7).
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import XCTest

/// "My bids" journey on the real app with the market off, so the two demo positions seeded at
/// launch (spec MYBIDS-7) stay put: one lot you lead on, one you're outbid on.
@MainActor
final class MyBidsUITests: XCTestCase {

    /// MYBIDS-1, MYBIDS-2, MYBIDS-3, MYBIDS-6, MYBIDS-7: the toolbar entry opens My bids, the
    /// seeded Winning and Outbid groups are listed, and tapping a row opens its detail.
    func testOpenMyBidsAndSelectLot() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-market", "off"]
        app.launch()

        XCTAssertTrue(element(app, "list.resultCount").waitForExistence(timeout: Constants.loadTimeout))
        let myBidsButton = element(app, "list.myBidsButton")
        XCTAssertTrue(myBidsButton.waitForExistence(timeout: Constants.stepTimeout))
        XCTAssertEqual(myBidsButton.value as? String, Constants.seededOutbidValue)
        myBidsButton.tap()

        XCTAssertTrue(element(app, "mybids.group.winning").waitForExistence(timeout: Constants.stepTimeout))
        XCTAssertTrue(element(app, "mybids.group.outbid").exists)

        let firstRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "mybids.row."))
            .firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: Constants.stepTimeout))
        firstRow.tap()

        XCTAssertTrue(element(app, "detail.title").waitForExistence(timeout: Constants.stepTimeout))
    }

    // MARK: - Helpers

    /// First element of any type with `identifier`.
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

}

/// Timeouts and expected values for the My bids journey.
private enum Constants {
    static let loadTimeout: TimeInterval = 20
    static let stepTimeout: TimeInterval = 10
    /// The demo seed leaves you outbid on exactly one lot.
    static let seededOutbidValue = "Outbid on 1"
}
