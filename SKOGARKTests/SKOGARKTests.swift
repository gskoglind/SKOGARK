//
//  SKOGARKTests.swift
//  SKOGARKTests
//
//  Exercises the deterministic adventure engine through its single public
//  entry point, `Game.process(_:)`, asserting on the resulting game state.
//  Covers both scenarios' win paths, darkness/grue visibility, scoring,
//  puzzle gates, and the parser.
//

import Testing
@testable import SKOGARK

struct SKOGARKTests {

    /// Feeds a sequence of typed commands to a game, in order.
    private func play(_ game: Game, _ commands: [String]) {
        for command in commands { game.process(command) }
    }

    // MARK: - House scenario: win path

    @Test func houseScenarioCanBeWon() {
        let game = Game(scenario: Game.houseScenario())
        play(game, [
            "east", "open window", "in",   // slip in through the kitchen window
            "take lantern", "light lantern",
            "west", "move rug", "open trapdoor", "down",
            "take egg", "up",
            "open case", "put egg in case",
        ])
        #expect(game.isWon)
        #expect(game.item("case")?.contents.contains("egg") == true)
    }

    // MARK: - House scenario: darkness / the grue

    @Test func cellarIsDarkUntilLanternIsLit() {
        let game = Game(scenario: Game.houseScenario())
        // Descend into the cellar carrying, but not lighting, the lantern.
        play(game, ["east", "open window", "in", "take lantern",
                    "west", "move rug", "open trapdoor", "down"])
        #expect(game.roomID == "cellar")
        #expect(game.canSeeRoom == false)

        game.process("take egg")
        #expect(game.isCarrying("egg") == false)   // too dark to grab it

        game.process("light lantern")
        #expect(game.canSeeRoom == true)
        game.process("take egg")
        #expect(game.isCarrying("egg") == true)
    }

    // MARK: - House scenario: scoring milestones

    @Test func houseScoringMilestones() {
        let game = Game(scenario: Game.houseScenario())
        play(game, ["east", "open window", "in", "take lantern", "light lantern", "west"])

        game.process("move rug")            // +2
        #expect(game.score == 2)

        play(game, ["open trapdoor", "down"])
        game.process("take egg")            // +5
        #expect(game.score == 7)

        play(game, ["up", "open case", "put egg in case"])   // +10
        #expect(game.score == 17)
        #expect(game.isWon)
    }

    // MARK: - House scenario: puzzle gates

    @Test func cannotDescendBeforeRugMovedAndTrapdoorOpen() {
        let game = Game(scenario: Game.houseScenario())
        play(game, ["east", "open window", "in", "take lantern", "light lantern", "west"])

        game.process("down")               // rug still covers the trap door
        #expect(game.roomID == "livingRoom")

        game.process("move rug")
        game.process("down")               // trap door revealed but closed
        #expect(game.roomID == "livingRoom")

        game.process("open trapdoor")
        game.process("down")
        #expect(game.roomID == "cellar")
    }

    @Test func closedWindowGatesEntryToHouse() {
        let game = Game(scenario: Game.houseScenario())
        play(game, ["east", "in"])         // window closed — no entry
        #expect(game.roomID == "behindHouse")

        play(game, ["open window", "in"])
        #expect(game.roomID == "kitchen")
    }

    // MARK: - Town scenario: win path

    @Test func townScenarioCanBeWon() {
        let game = Game(scenario: Game.townScenario())
        play(game, [
            "north", "east", "buy meat", "west",     // butcher
            "west", "buy bread", "east",             // bakery
            "north", "buy fish", "south",            // fishmonger
            "south",                                 // back to the inn
            "give meat to cook", "give bread to cook", "give fish to cook",
        ])
        #expect(game.isWon)
    }

    // MARK: - Town scenario: shop economy

    @Test func forSaleGoodsMustBeBoughtNotTaken() {
        let game = Game(scenario: Game.townScenario())
        play(game, ["north", "east"])      // the butcher's shop

        game.process("take meat")
        #expect(game.inventoryKinds().contains("meat") == false)   // can't just take it

        game.process("buy meat")
        #expect(game.inventoryKinds().contains("meat") == true)
        #expect(game.purse == 17)          // started with 25, meat costs 8
    }

    // MARK: - Town scenario: optional cat side-quest

    @Test func feedingTheCatAwardsBonus() {
        let game = Game(scenario: Game.townScenario())
        play(game, ["north", "north", "buy fish"])   // fishmonger, holding a fish
        #expect(game.has(flag: "catFed") == false)

        game.process("give fish to cat")
        #expect(game.has(flag: "catFed") == true)
        #expect(game.score == 5)
    }

    // MARK: - Parser

    @Test func parserHandlesShorthandAndFillerWords() {
        let game = Game(scenario: Game.townScenario())
        game.process("n")                  // shorthand direction
        #expect(game.roomID == "square")

        game.process("go to the south")    // verb + stripped filler + direction
        #expect(game.roomID == "innKitchen")
    }

    @Test func unknownVerbIsReported() {
        let game = Game(scenario: Game.townScenario())
        game.process("frobnicate")
        #expect(game.transcript.last?.text.contains("I don't know how to") == true)
    }
}
