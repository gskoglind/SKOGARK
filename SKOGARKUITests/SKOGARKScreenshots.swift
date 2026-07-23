//
//  SKOGARKScreenshots.swift
//  SKOGARKUITests
//
//  Drives the app to its five best scenes and captures the App Store
//  screenshots via fastlane snapshot (`fastlane snapshot`). One test per
//  screenshot, each with a fresh launch, so a flaky simulator moment can
//  only cost one shot.
//

import XCTest

final class SKOGARKScreenshots: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments += ["-unlockAll"]   // screenshots show the full atlas
        app.launch()
        XCTAssertTrue(app.buttons["destination:Sydney"].waitForExistence(timeout: 20),
                      "Menu never appeared")
        return app
    }

    @MainActor
    private func tap(_ id: String, in app: XCUIApplication) {
        let element = app.buttons[id]
        XCTAssertTrue(element.waitForExistence(timeout: 20), "Missing element: \(id)")
        let bar = app.scrollViews["actionBar"].firstMatch
        var swipes = 0
        while !element.isHittable && swipes < 8 {
            (bar.exists ? bar : app).swipeLeft(velocity: .fast)
            swipes += 1
        }
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    /// Opens a scenario from the menu and waits for the game to be ready.
    @MainActor
    private func open(_ destination: String, _ scenario: String, in app: XCUIApplication) {
        tap("destination:\(destination)", in: app)
        tap("scenario:\(scenario)", in: app)
        XCTAssertTrue(app.buttons["chip:look"].waitForExistence(timeout: 20),
                      "Game never became ready")
    }

    @MainActor
    func testShot1Menu() throws {
        _ = launch()
        snapshot("01-Menu")
    }

    @MainActor
    func testShot2Roppongi() throws {
        let app = launch()
        open("Japan", "roppongi", in: app)
        tap("chip:up", in: app)                                   // the crossing
        _ = app.buttons["chip:up"].waitForExistence(timeout: 10)  // Geronimo's stairs = settled
        snapshot("02-Roppongi")
    }

    @MainActor
    func testShot3Fuji() throws {
        let app = launch()
        open("Japan", "fuji", in: app)
        snapshot("03-Fuji")
    }

    @MainActor
    func testShot4Sydney() throws {
        let app = launch()
        open("Sydney", "sydney", in: app)
        snapshot("04-Sydney")
    }

    @MainActor
    func testShot5Greenwich() throws {
        let app = launch()
        open("London", "greenwich", in: app)
        for cmd in ["up", "south", "south", "south", "south", "east"] {
            tap("chip:\(cmd)", in: app)
        }
        _ = app.buttons["chip:sit"].waitForExistence(timeout: 10)
        snapshot("05-Greenwich")
    }
}
