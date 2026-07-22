//
//  SKOGARKUITests.swift
//  SKOGARKUITests
//
//  Drives the real app with XCUIAutomation: the destination menu, and a
//  complete tap-only win of the town errand using nothing but action chips.
//  Chips, destination cards, and scenario cards carry accessibility
//  identifiers ("chip:<command>", "destination:<name>", "scenario:<id>").
//

import XCTest

final class SKOGARKUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Taps the action chip that emits `cmd`, swiping the chip row as needed
    /// to bring it on screen.
    @MainActor
    private func tapChip(_ cmd: String, in app: XCUIApplication) {
        let chip = app.buttons["chip:\(cmd)"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "Missing chip for '\(cmd)'")
        var swipes = 0
        while !chip.isHittable && swipes < 6 {
            app.swipeLeft(velocity: .fast)
            swipes += 1
        }
        chip.tap()
    }

    // MARK: - The destination menu

    @MainActor
    func testMenuListsAllDestinationsAndTheirAdventures() throws {
        let app = XCUIApplication()
        app.launch()

        for name in ["Explore", "Savannah", "Japan", "London", "Sydney"] {
            XCTAssertTrue(app.buttons["destination:\(name)"].waitForExistence(timeout: 5),
                          "Missing destination card: \(name)")
        }

        app.buttons["destination:Japan"].tap()
        XCTAssertTrue(app.buttons["scenario:roppongi"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["scenario:fuji"].exists)

        app.buttons["All destinations"].tap()
        XCTAssertTrue(app.buttons["destination:Sydney"].waitForExistence(timeout: 5))
    }

    // MARK: - Tap-only play, end to end

    /// Wins the town market errand in the running app using only tapped
    /// chips — no keyboard at any point. If this passes, the chip layer is
    /// generating real, working commands against the live engine and UI.
    @MainActor
    func testTownErrandCanBeWonByTapAlone() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["destination:Explore"].waitForExistence(timeout: 5))
        app.buttons["destination:Explore"].tap()
        XCTAssertTrue(app.buttons["scenario:town"].waitForExistence(timeout: 5))
        app.buttons["scenario:town"].tap()

        // The action bar is up and the utility chips exist.
        XCTAssertTrue(app.buttons["chip:look"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["chip:inventory"].exists)

        // The whole errand, by thumb: shop the square, feed the cook.
        tapChip("north", in: app)                    // village square
        tapChip("east", in: app)                     // the butcher
        tapChip("buy meat", in: app)
        tapChip("west", in: app)                     // square
        tapChip("west", in: app)                     // the bakery
        tapChip("buy bread", in: app)
        tapChip("east", in: app)                     // square
        tapChip("north", in: app)                    // the fishmonger
        tapChip("buy fish", in: app)
        tapChip("south", in: app)                    // square
        tapChip("south", in: app)                    // the inn kitchen
        tapChip("give meat to cook", in: app)
        tapChip("give bread to cook", in: app)
        tapChip("give fish to cook", in: app)

        // The win banner lands in the transcript, and the chips collapse to
        // the single Play Again chip.
        let won = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "You have won")).firstMatch
        XCTAssertTrue(won.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["chip:restart"].waitForExistence(timeout: 5))
    }

}
