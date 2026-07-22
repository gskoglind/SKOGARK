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

    @Test func lookAtExaminesThings() {
        let game = Game(scenario: Game.townScenario())
        game.process("north")
        game.process("look at the butcher")   // "at"/"the" are filler; LOOK+words examines
        #expect(game.roomID == "square")      // did not re-describe or move
    }

    // MARK: - Tap-only completability
    //
    // Every command below is exactly a string the action-chip layer emits
    // (directions, BOARD/OPEN/TAKE/BUY/GIVE/PUT/EAT/DRINK/PLAY, "turn on").
    // If any of these stop winning, tap-only players are stranded.

    @Test func houseIsTapOnlyCompletable() {
        let game = Game(scenario: Game.houseScenario())
        play(game, ["east", "open window", "inside", "take lantern", "turn on",
                    "west", "move rug", "open trapdoor", "down", "take egg", "up",
                    "open case", "put egg in case"])
        #expect(game.isWon)
    }

    @Test func riverboatIsTapOnlyCompletable() {
        let game = Game(scenario: Game.riverboatScenario())
        play(game, ["board cannon", "up", "up", "up", "west", "west", "east", "east", "east"])
        #expect(game.isWon)
        #expect(game.score == 25)
    }

    @Test func fortPulaskiIsTapOnlyCompletable() {
        let game = Game(scenario: Game.fortPulaskiScenario())
        play(game, ["north", "inside", "inside", "north", "south", "west", "east",
                    "south", "north", "up", "down", "outside", "south", "east",
                    "west", "north", "outside", "north", "north", "south", "south",
                    "east", "north", "north", "north"])
        #expect(game.isWon)
        #expect(game.score == game.scenario.maxScore)
    }

    @Test func roppongiIsTapOnlyCompletable() {
        let game = Game(scenario: Game.roppongiScenario())
        play(game, ["take napkin", "up", "up", "ring bell", "down", "east",
                    "north", "buy margarita", "give margarita to roy",
                    "south", "east", "throw darts",
                    "west", "south",                        // ramen at dawn
                    "north", "west", "down",                // back to the station
                    "inside", "buy ticket", "inside",       // ticket, board the 05:12
                    "north", "down"])                       // transfer, home
        #expect(game.isWon)
        #expect(game.score == game.scenario.maxScore)
    }

    @Test func fujiIsTapOnlyCompletableInAnyWeather() {
        // The storm jacket covers every weather roll; UP is the primary verb.
        for _ in 0..<6 {
            let game = Game(scenario: Game.fujiScenario())
            play(game, ["buy stick", "buy headlamp", "buy jacket", "buy letter",
                        "up", "give stick to guide",
                        "up", "give stick to keeper",
                        "up", "give stick to keeper",
                        "up", "turn on", "up",
                        "give stick to priest",
                        "east", "up", "down", "west",
                        "inside", "put letter in postbox"])
            #expect(game.isWon)
            #expect(game.score == game.scenario.maxScore)
        }
    }

    @Test func greenwichIsTapOnlyCompletable() {
        let game = Game(scenario: Game.greenwichScenario())
        play(game, ["up", "south", "south", "take map", "buy nuts", "buy beer",
                    "up", "up", "straddle line", "east",
                    "examine canary", "examine o2", "examine eye",
                    "give nuts to squirrel", "drink beer", "south"])
        #expect(game.isWon)
        #expect(game.score == game.scenario.maxScore)
    }

    @Test func sydneyIsTapOnlyCompletableWhateverTheDice() {
        for _ in 0..<8 {
            let game = Game(scenario: Game.sydneyScenario())
            play(game, ["take card", "board manly",
                        "examine opera", "examine bridge", "examine fort",
                        "north", "north",
                        "east", "buy chips", "east", "eat chips",
                        "west", "west", "board return", "north",
                        "board casino", "north", "play craps", "north",
                        "board balmoral", "east",
                        "board neutral", "north", "board bus",
                        "buy schooner", "drink schooner"])
            #expect(game.isWon)
            #expect(game.score == game.scenario.maxScore)
            #expect(game.purse >= 0)
        }
    }

    // MARK: - Gates in the newer scenarios

    @Test func sydneyOpalAndFullDayGatesHold() {
        let game = Game(scenario: Game.sydneyScenario())
        game.process("board manly")
        #expect(game.roomID == "circularQuay")          // no Opal card yet

        play(game, ["take card", "board neutral"])
        #expect(game.roomID == "circularQuay")          // day not done — refused

        game.process("board manly")
        #expect(game.roomID == "manlyDeck")
    }

    @Test func fujiWeatherGateAndShelter() {
        // Roll games until a foul-weather night, then confirm the gate blocks
        // the summit push and the keeper's shelter reopens it.
        for _ in 0..<40 {
            let game = Game(scenario: Game.fujiScenario())
            play(game, ["buy stick", "buy headlamp", "up", "up", "up"])
            guard game.has(flag: "weatherRain") || game.has(flag: "weatherCold") else { continue }
            game.process("up")
            #expect(game.roomID == "eighthHut")         // weather blocks the trail
            play(game, ["talk to keeper", "up"])
            #expect(game.roomID == "ninthStation")      // shelter reopens it
            return
        }
        Issue.record("No foul-weather night in 40 rolls — check the weather odds")
    }

    @Test func roppongiGatesUntilRamen() {
        let game = Game(scenario: Game.roppongiScenario())
        game.process("inside")
        #expect(game.roomID == "roppongiStation")       // shutters down pre-crawl

        let g2 = Game(scenario: Game.greenwichScenario())
        play(g2, ["up", "south", "south", "buy beer", "drink beer"])
        #expect(g2.has(flag: "hadBeer") == false)       // beer only on the bench
    }
}
