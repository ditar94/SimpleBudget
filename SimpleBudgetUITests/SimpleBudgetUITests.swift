//
//  SimpleBudgetUITests.swift
//  SimpleBudgetUITests
//
//  Created by Dionicy Tarantino on 12/2/25.
//

import XCTest

// UI test scaffold generated for SimpleBudget interactions
final class SimpleBudgetUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testDialRangeIsCappedWhenTransactionsCreateSurplus() throws {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: ["UI-Testing", "UITestSeedRefund"])
        app.launchEnvironment["UITEST_BUDGET"] = "500"
        app.launch()

        let dial = app.otherElements["BudgetDial"]
        XCTAssertTrue(dial.waitForExistence(timeout: 2))
        XCTAssertEqual(dial.value as? String, "range:500")
    }

    @MainActor
    func testDialRangeTracksBudgetWithoutOverage() throws {
        let app = XCUIApplication()
        app.launchArguments.append("UI-Testing")
        app.launchEnvironment["UITEST_BUDGET"] = "300"
        app.launch()

        let dial = app.otherElements["BudgetDial"]
        XCTAssertTrue(dial.waitForExistence(timeout: 2))
        XCTAssertEqual(dial.value as? String, "range:300")
    }
}
