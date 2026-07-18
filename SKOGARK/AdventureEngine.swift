import Foundation
import Observation

// MARK: - World Model

/// The compass and vertical directions the player can travel, plus
/// "inside"/"outside" for entering and leaving enclosed spaces.
enum Direction: String, CaseIterable, Codable {
    case north, south, east, west, up, down, inside, outside

    /// Maps typed shorthand (n, s, e, w, u, d, in, out) to a direction.
    static func from(_ word: String) -> Direction? {
        switch word {
        case "n", "north": return .north
        case "s", "south": return .south
        case "e", "east": return .east
        case "w", "west": return .west
        case "u", "up": return .up
        case "d", "down": return .down
        case "in", "inside", "enter": return .inside
        case "out", "outside", "exit", "leave": return .outside
        // "forward"/"back" read as north/south, for walking a linear trail.
        case "forward", "ahead", "fwd": return .north
        case "back", "backward", "backwards": return .south
        default: return Direction(rawValue: word)
        }
    }
}

/// A physical object in the world. Items can be carried, read, opened,
/// act as light sources, serve as containers, be creatures you talk to,
/// or be goods for sale in a shop.
struct Item: Identifiable, Codable {
    let id: String
    var name: String
    /// Words the parser accepts as referring to this item.
    var nouns: [String]
    var description: String
    var isTakeable: Bool = false
    var isLightSource: Bool = false
    var isLit: Bool = false
    var isOpenable: Bool = false
    var isOpen: Bool = false
    var isContainer: Bool = false
    /// IDs of items currently held inside this container.
    var contents: [String] = []
    var readText: String? = nil
    /// A fixture is woven into the room's prose rather than listed as
    /// "There is a … here."
    var isFixture: Bool = false
    /// A creature can be talked to and given things.
    var isCreature: Bool = false
    /// What the creature says by default when talked to.
    var dialogue: String? = nil
    /// Goods for sale must be bought, not simply taken.
    var forSale: Bool = false
    var price: Int = 0
    /// Groups interchangeable goods (e.g. every fish shares kind "fish"), so
    /// bought copies can be matched by type rather than by unique id.
    var kind: String? = nil

    func matches(_ word: String) -> Bool {
        nouns.contains(word)
    }

    /// A fresh, carried copy of a for-sale ware: a new id, takeable, and no
    /// longer for sale. The stall keeps its original so it can restock.
    func copied(withID newID: String) -> Item {
        Item(id: newID, name: name, nouns: nouns, description: description,
             isTakeable: true, isLightSource: isLightSource, isLit: isLit,
             isOpenable: isOpenable, isOpen: isOpen, isContainer: isContainer,
             contents: contents, readText: readText, isFixture: false,
             isCreature: isCreature, dialogue: dialogue, forSale: false,
             price: price, kind: kind)
    }
}

/// A location in the world with named exits and the items resting there.
struct Room: Identifiable, Codable {
    let id: String
    var title: String
    var description: String
    var exits: [Direction: String] = [:]
    var items: [String] = []
    /// A dark room needs a lit light source before anything can be seen.
    var isDark: Bool = false
    var visited: Bool = false
}

// MARK: - Scenario

/// A self-contained adventure: its world data plus a small set of optional
/// rule hooks. The engine (`Game`) is generic and drives whichever scenario
/// it's handed, so multiple games share one engine, one UI, and one deploy.
///
/// Every hook receives the `Game` as a parameter (no capture), and the hook
/// closures are defined inside `Game`'s scenario factories so they can reach
/// the engine's private helpers.
struct Scenario: Identifiable {
    let id: String
    let title: String
    let blurb: String
    let banner: String
    let startRoomID: String
    let maxScore: Int
    let startingCoins: Int
    /// Builds a fresh world (called on new game and RESTART).
    let build: () -> (rooms: [String: Room], items: [String: Item])

    /// Returns a blocking message if a move in `direction` is gated here.
    var portalGate: ((Game, Direction) -> String?)? = nil
    /// Maps a portal item ("go through the window") to a travel direction.
    var portalDirection: ((Game, String) -> Direction?)? = nil
    /// Hides a discovered-later exit from the "obvious exits" listing.
    var exitHidden: ((Game, Direction) -> Bool)? = nil
    /// A custom room-description line for a fixture (state, price, …).
    var fixtureLine: ((Game, String) -> String?)? = nil
    /// Reacts to a successful TAKE.
    var onTake: ((Game, String) -> Void)? = nil
    /// Handles MOVE/PUSH of an object; return true if handled.
    var onMoveObject: ((Game, String) -> Bool)? = nil
    /// Handles GIVE of a carried item to a creature; return true if handled.
    var onGive: ((Game, _ gift: String, _ recipient: String) -> Bool)? = nil
    /// Reacts to a successful PUT of an item into a container.
    var onPut: ((Game, _ object: String, _ target: String) -> Void)? = nil
    /// Handles TALK to a creature; return true if handled.
    var onTalk: ((Game, String) -> Bool)? = nil
    /// Reacts to the player arriving in a room, after its description prints.
    var onEnterRoom: ((Game, _ roomID: String) -> Void)? = nil
    /// Progressive, context-aware hints: returns the current puzzle-stage key
    /// and its escalating clues (gentle → explicit) for the HINT command.
    var hintStage: ((Game) -> (key: String, clues: [String]))? = nil
}

// MARK: - Transcript

/// One line of output in the scrolling transcript. Commands the player
/// typed are flagged so the UI can style them differently.
struct TranscriptEntry: Identifiable, Codable {
    let id: Int
    let text: String
    let isCommand: Bool
}

// MARK: - Game Engine

/// A small, fully deterministic text-adventure engine in the spirit of
/// SkoGarK. All state lives here; `process(_:)` is the single entry point
/// that turns a line of typed input into transcript output. The world it
/// runs is supplied as a `Scenario`.
@Observable
final class Game {
    private(set) var transcript: [TranscriptEntry] = []
    private(set) var moves = 0
    private(set) var score = 0
    private(set) var isWon = false

    let scenario: Scenario

    private var rooms: [String: Room] = [:]
    private var items: [String: Item] = [:]
    private var inventory: [String] = []
    private var currentRoomID: String = ""
    /// Generic on/off world state (rug moved, cat fed, goods delivered, …).
    private var flags: Set<String> = []
    private var coins = 0
    private var nextEntryID = 0
    private var nextPurchaseID = 0
    private var hintLevel = 0
    private var hintStageKey = ""

    /// All playable scenarios, for the selection menu.
    static let scenarios: [Scenario] = [houseScenario(), townScenario(), riverboatScenario(), fortPulaskiScenario()]

    convenience init() { self.init(scenario: Game.houseScenario()) }

    init(scenario: Scenario) {
        self.scenario = scenario
        startFresh(clearTranscript: false)
    }

    /// (Re)builds the world from the scenario and prints the opening.
    private func startFresh(clearTranscript: Bool) {
        if clearTranscript { transcript = [] }
        moves = 0
        score = 0
        isWon = false
        inventory = []
        flags = []
        coins = scenario.startingCoins
        nextPurchaseID = 0
        hintLevel = 0
        hintStageKey = ""
        let world = scenario.build()
        rooms = world.rooms
        items = world.items
        currentRoomID = scenario.startRoomID
        emit(scenario.banner, asCommand: false)
        describeCurrentRoom(force: true)
    }

    // MARK: Scenario-facing helpers (used by rule hooks)

    func item(_ id: String) -> Item? { items[id] }
    var roomID: String { currentRoomID }
    /// The display title of the room the player is currently in.
    var roomTitle: String { rooms[currentRoomID]?.title ?? "" }
    /// Whether the player can currently see here (a dark room needs a lit light
    /// source). Drives the cellar's dark → lit background reveal.
    var canSeeRoom: Bool { canSee }
    func has(flag: String) -> Bool { flags.contains(flag) }
    func set(flag: String) { flags.insert(flag) }
    func inventoryKinds() -> Set<String> { Set(inventory.compactMap { items[$0]?.kind }) }
    var purse: Int { coins }
    func isCarrying(_ id: String) -> Bool { inventory.contains(id) }

    // MARK: Input Handling

    /// The single public entry point: process one line of player input.
    func process(_ rawInput: String) {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        emit("> \(input)", asCommand: true)

        let tokens = tokenize(input)
        guard let verb = tokens.first else {
            emit("I don't understand that.")
            return
        }

        // After winning, only meta commands remain available.
        if isWon, !["restart", "restore", "load", "score", "save"].contains(verb) {
            emit("You've already won. Type RESTART to play again.")
            return
        }

        // A bare direction word means "go that way".
        if tokens.count == 1, let dir = Direction.from(verb) {
            move(dir)
            return
        }

        let rest = Array(tokens.dropFirst())
        switch verb {
        case "look", "l":
            if rest.first == "at", rest.count > 1 {
                examine(Array(rest.dropFirst()))
            } else if rest.contains("around") || rest.contains("here") {
                lookAround()
            } else {
                describeCurrentRoom(force: true)
            }
        case "what", "survey":
            lookAround()
        case "go", "walk", "run", "climb", "enter", "crawl", "cross",
             "board", "sail", "depart", "choose", "select", "ride", "catch", "join":
            handleGo(rest)
        case "examine", "x", "inspect", "read":
            if verb == "read" { readItem(rest) } else { examine(rest) }
        case "take", "get", "grab", "pick":
            take(rest.filter { $0 != "up" })
        case "drop":
            drop(rest)
        case "open":
            setOpen(rest, open: true)
        case "close", "shut":
            setOpen(rest, open: false)
        case "move", "push", "pull", "slide":
            moveObject(rest)
        case "turn":
            turn(rest)
        case "light", "activate":
            turnLantern(on: true)
        case "extinguish":
            turnLantern(on: false)
        case "put", "place", "insert":
            put(rest)
        case "give", "offer", "feed":
            give(rest)
        case "talk", "ask", "speak", "greet":
            talkTo(rest)
        case "buy", "purchase":
            buyItem(rest)
        case "coins", "money", "wealth":
            emit(coins > 0 ? "You have \(coins) coins." : "You don't have any money.")
        case "inventory", "i", "inv":
            showInventory()
        case "score":
            emit("Your score is \(score) of a possible \(scenario.maxScore), in \(moves) moves.")
        case "hint", "hints":
            showHint()
        case "why":
            emit("Why not? Adventure rarely waits for a reason. Type HELP if you're stuck.")
        case "help", "?":
            emit(helpText)
        case "save":
            save()
        case "restore", "load":
            restore()
        case "restart":
            restart()
        default:
            // Naming a portal with no verb (e.g. a cruise by time or name at
            // the dock) is taken as "go through it".
            if let id = resolveItem(tokens), let dir = scenario.portalDirection?(self, id) {
                move(dir)
            } else {
                emit("I don't know how to \"\(verb)\".")
            }
        }
    }

    private func tokenize(_ input: String) -> [String] {
        let filler: Set<String> = ["the", "a", "an", "to", "at", "my", "some"]
        return input.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !filler.contains($0) }
    }

    // MARK: Movement

    private func move(_ direction: Direction) {
        moves += 1
        guard let room = rooms[currentRoomID] else { return }

        // Scenario-specific gating (locked/closed portals).
        if let blocked = scenario.portalGate?(self, direction) {
            emit(blocked)
            return
        }

        guard let destination = room.exits[direction] else {
            emit("You can't go that way.")
            return
        }

        currentRoomID = destination
        describeCurrentRoom()
        scenario.onEnterRoom?(self, destination)
    }

    /// Handles a movement verb whose object may be a direction word, a
    /// portal you pass through ("go through the window"), or the name of
    /// an adjacent room ("go to the kitchen").
    private func handleGo(_ words: [String]) {
        if let dir = words.compactMap({ Direction.from($0) }).first {
            move(dir)
            return
        }
        if let id = resolveItem(words), let dir = scenario.portalDirection?(self, id) {
            move(dir)
            return
        }
        if let room = rooms[currentRoomID] {
            for (dir, destinationID) in room.exits {
                guard let destination = rooms[destinationID] else { continue }
                let titleWords = Set(destination.title.lowercased()
                    .split(whereSeparator: { !$0.isLetter })
                    .map(String.init))
                if words.contains(where: { titleWords.contains($0) }) {
                    move(dir)
                    return
                }
            }
        }
        emit("Go where?")
    }

    // MARK: Description & Visibility

    /// True when the current room is lit — either not dark, or a lit
    /// light source is present in the room or the player's inventory.
    private var canSee: Bool {
        guard let room = rooms[currentRoomID] else { return false }
        if !room.isDark { return true }
        let candidates = inventory + room.items
        return candidates.contains { items[$0]?.isLit == true }
    }

    private func describeCurrentRoom(force: Bool = false) {
        guard var room = rooms[currentRoomID] else { return }

        if !canSee {
            emit("Pitch black.\nIt is so dark you can't see a thing. You are likely to be eaten by a grue.")
            room.visited = true
            rooms[currentRoomID] = room
            return
        }

        let firstVisit = !room.visited
        room.visited = true
        rooms[currentRoomID] = room

        var lines = [room.title]
        if firstVisit || force {
            lines.append(room.description)
        }
        for itemID in room.items {
            guard let item = items[itemID] else { continue }
            if item.isFixture {
                // Fixtures are woven into the prose; some get a state line.
                if let line = scenario.fixtureLine?(self, itemID) { lines.append(line) }
                continue
            }
            lines.append("There is a \(item.name) here.")
        }
        emit(lines.joined(separator: "\n"))
    }

    /// A low-spoiler perception command ("what can I see" / "look around").
    private func lookAround() {
        guard canSee else { emit("It's too dark to see anything."); return }
        guard let room = rooms[currentRoomID] else { return }

        var lines: [String] = []
        var names: [String] = []
        for itemID in room.items {
            guard let item = items[itemID] else { continue }
            if item.isContainer, item.isOpen, !item.contents.isEmpty {
                let inside = item.contents.compactMap { items[$0]?.name }
                names.append("\(item.name) (holding \(inside.joined(separator: ", ")))")
            } else {
                names.append(item.name)
            }
        }
        if names.isEmpty {
            lines.append("You see nothing here worth remarking on.")
        } else {
            lines.append("You can see: \(names.joined(separator: ", ")).")
        }

        let exits = obviousExits()
        if !exits.isEmpty {
            lines.append("Obvious exits: \(exits.map { $0.rawValue }.joined(separator: ", ")).")
        }
        emit(lines.joined(separator: "\n"))
    }

    /// The directions the player could reasonably know they can travel.
    private func obviousExits() -> [Direction] {
        guard let room = rooms[currentRoomID] else { return [] }
        return Direction.allCases.filter { direction in
            guard room.exits[direction] != nil else { return false }
            if scenario.exitHidden?(self, direction) == true { return false }
            return true
        }
    }

    // MARK: Item Resolution

    private func resolveItem(_ words: [String]) -> String? {
        let candidateIDs = visibleItemIDs()
        for word in words {
            if let id = candidateIDs.first(where: { items[$0]?.matches(word) == true }) {
                return id
            }
        }
        return nil
    }

    private func visibleItemIDs() -> [String] {
        var ids = inventory
        if let room = rooms[currentRoomID] {
            ids += room.items
            for itemID in room.items {
                if let item = items[itemID], item.isContainer, item.isOpen {
                    ids += item.contents
                }
            }
        }
        for itemID in inventory {
            if let item = items[itemID], item.isContainer, item.isOpen {
                ids += item.contents
            }
        }
        return ids
    }

    // MARK: Verbs

    private func examine(_ words: [String]) {
        guard canSee else { emit("It's too dark to see anything."); return }
        guard let id = resolveItem(words), let item = items[id] else {
            emit("You don't see that here.")
            return
        }
        var text = item.description
        if item.isContainer {
            if item.isOpen {
                let contents = item.contents.compactMap { items[$0]?.name }
                text += contents.isEmpty ? " It is open and empty."
                    : " It contains: \(contents.joined(separator: ", "))."
            } else {
                text += " It is closed."
            }
        }
        if item.isLightSource {
            text += item.isLit ? " It is currently lit." : " It is not lit."
        }
        if item.forSale {
            text += " It's for sale for \(item.price) coins."
        }
        emit(text)
    }

    private func readItem(_ words: [String]) {
        guard canSee else { emit("It's too dark to read."); return }
        guard let id = resolveItem(words), let item = items[id] else {
            emit("You don't see that here.")
            return
        }
        if let text = item.readText {
            emit(text)
        } else {
            emit("There's nothing to read on the \(item.name).")
        }
    }

    private func take(_ words: [String]) {
        moves += 1
        guard canSee else { emit("It's too dark to see what you're grabbing."); return }
        guard let id = resolveItem(words), let item = items[id] else {
            emit("You don't see that here.")
            return
        }
        if inventory.contains(id) {
            emit("You're already carrying the \(item.name).")
            return
        }
        if item.forSale {
            emit("That's for sale — you'll have to BUY it.")
            return
        }
        guard item.isTakeable else {
            // "Take the 1pm cruise" reads as boarding it, not pocketing it.
            if let dir = scenario.portalDirection?(self, id) { move(dir); return }
            emit("You can't take the \(item.name).")
            return
        }
        removeItemFromWorld(id)
        inventory.append(id)
        scenario.onTake?(self, id)
        emit("Taken.")
    }

    private func drop(_ words: [String]) {
        moves += 1
        guard let id = resolveItem(words.filter { $0 != "down" }),
              inventory.contains(id), let item = items[id] else {
            emit("You're not carrying that.")
            return
        }
        inventory.removeAll { $0 == id }
        rooms[currentRoomID]?.items.append(id)
        emit("You drop the \(item.name).")
    }

    private func setOpen(_ words: [String], open: Bool) {
        moves += 1
        guard let id = resolveItem(words), var item = items[id] else {
            emit("You don't see that here.")
            return
        }
        guard item.isOpenable else {
            emit("You can't \(open ? "open" : "close") the \(item.name).")
            return
        }
        if item.isOpen == open {
            emit("It's already \(open ? "open" : "closed").")
            return
        }
        item.isOpen = open
        items[id] = item
        if item.isContainer && open && !item.contents.isEmpty {
            let contents = item.contents.compactMap { items[$0]?.name }
            emit("Opening the \(item.name) reveals: \(contents.joined(separator: ", ")).")
        } else {
            emit("\(open ? "Opened" : "Closed").")
        }
    }

    private func moveObject(_ words: [String]) {
        moves += 1
        guard let id = resolveItem(words) else {
            emit("You don't see that here.")
            return
        }
        if scenario.onMoveObject?(self, id) == true { return }
        emit("Moving the \(items[id]?.name ?? "that") accomplishes nothing.")
    }

    private func turn(_ words: [String]) {
        if words.contains("on") { turnLantern(on: true) }
        else if words.contains("off") { turnLantern(on: false) }
        else { emit("Turn it on or off?") }
    }

    private func turnLantern(on: Bool) {
        moves += 1
        guard let id = resolveItem(["lantern"]), var item = items[id] else {
            emit("You don't have a light source.")
            return
        }
        if item.isLit == on {
            emit("The lantern is already \(on ? "on" : "off").")
            return
        }
        item.isLit = on
        items[id] = item
        emit("The brass lantern is now \(on ? "on" : "off").")
        // Re-describe if turning it on suddenly reveals a dark room.
        if on { describeCurrentRoom(force: true) }
    }

    private func put(_ words: [String]) {
        moves += 1
        let separators: Set<String> = ["in", "into", "inside", "on"]
        guard let sepIndex = words.firstIndex(where: { separators.contains($0) }) else {
            emit("Put what where? Try \"put egg in case\".")
            return
        }
        let objectWords = Array(words[..<sepIndex])
        let targetWords = Array(words[(sepIndex + 1)...])

        guard let objectID = resolveItem(objectWords), inventory.contains(objectID),
              let object = items[objectID] else {
            emit("You need to be holding that first.")
            return
        }
        guard let targetID = resolveItem(targetWords), var target = items[targetID],
              target.isContainer else {
            emit("You can't put anything in that.")
            return
        }
        guard target.isOpen else {
            emit("The \(target.name) is closed.")
            return
        }

        inventory.removeAll { $0 == objectID }
        target.contents.append(objectID)
        items[targetID] = target
        emit("You place the \(object.name) in the \(target.name).")

        scenario.onPut?(self, objectID, targetID)
    }

    /// Give a carried item to a creature. Word order is free ("give fish to
    /// cat" or "feed cat fish"); roles are resolved by matching a visible
    /// creature and a carried item.
    private func give(_ words: [String]) {
        moves += 1
        let visible = visibleItemIDs()
        let recipientID = words.lazy.compactMap { word in
            visible.first { self.items[$0]?.matches(word) == true && self.items[$0]?.isCreature == true }
        }.first
        let giftID = words.lazy.compactMap { word in
            self.inventory.first { self.items[$0]?.matches(word) == true }
        }.first

        guard let recipientID, let recipient = items[recipientID] else {
            emit("There's no one here to give anything to.")
            return
        }
        guard let giftID, let gift = items[giftID] else {
            emit("You need to be holding something to give the \(recipient.name).")
            return
        }

        if scenario.onGive?(self, giftID, recipientID) == true { return }
        emit("The \(recipient.name) has no interest in the \(gift.name).")
    }

    /// Talk to a creature in the room. Scenarios can supply dynamic dialogue
    /// via `onTalk`; otherwise the creature's default `dialogue` is used.
    private func talkTo(_ words: [String]) {
        guard canSee else { emit("It's too dark to see who you'd talk to."); return }
        let visible = visibleItemIDs()
        let id = words.lazy.compactMap { word in
            visible.first { self.items[$0]?.matches(word) == true && self.items[$0]?.isCreature == true }
        }.first
        guard let id, let npc = items[id] else {
            emit("There's no one here to talk to.")
            return
        }
        if scenario.onTalk?(self, id) == true { return }
        if let line = npc.dialogue {
            emit(line)
        } else {
            emit("The \(npc.name) has nothing to say.")
        }
    }

    /// Buy a for-sale item in the current shop, spending coins.
    private func buyItem(_ words: [String]) {
        moves += 1
        guard canSee else { emit("It's too dark to shop."); return }
        // Resolve specifically to a for-sale ware (so a copy already in the
        // player's bag doesn't shadow the restocking stall item).
        let visible = visibleItemIDs()
        let wareID = words.lazy.compactMap { word in
            visible.first { self.items[$0]?.matches(word) == true && self.items[$0]?.forSale == true }
        }.first
        guard let wareID, let ware = items[wareID] else {
            if let otherID = resolveItem(words), let other = items[otherID] {
                emit("The \(other.name) isn't for sale.")
            } else {
                emit("You don't see that here.")
            }
            return
        }
        guard coins >= ware.price else {
            emit("You can't afford the \(ware.name) — it costs \(ware.price) coins and you have \(coins).")
            return
        }
        coins -= ware.price
        // Mint a fresh carried copy; the stall keeps its ware and restocks.
        let boughtID = "\(wareID)#\(nextPurchaseID)"
        nextPurchaseID += 1
        items[boughtID] = ware.copied(withID: boughtID)
        inventory.append(boughtID)
        emit("You buy the \(ware.name) for \(ware.price) coins. You have \(coins) left.")
    }

    /// Progressive, opt-in hint. Each call escalates from a gentle nudge to
    /// an explicit instruction; the level resets automatically whenever the
    /// player advances to a new puzzle stage.
    private func showHint() {
        guard let stage = scenario.hintStage?(self) else {
            emit("No hints are available here — you're on your own!")
            return
        }
        if stage.key != hintStageKey {
            hintStageKey = stage.key
            hintLevel = 0
        }
        let clues = stage.clues
        guard !clues.isEmpty else { emit("No hint right now."); return }
        let index = min(hintLevel, clues.count - 1)
        var output = clues[index]
        if hintLevel < clues.count - 1 {
            output += "\n(Type HINT again for a bigger hint.)"
            hintLevel += 1
        }
        emit(output)
    }

    private func showInventory() {
        var lines: [String] = []
        if inventory.isEmpty {
            lines.append("You are empty-handed.")
        } else {
            lines = ["You are carrying:"] + inventory.compactMap { items[$0].map { "  a \($0.name)" } }
        }
        if scenario.startingCoins > 0 {
            lines.append("You have \(coins) coins.")
        }
        emit(lines.joined(separator: "\n"))
    }

    // MARK: Helpers

    private func removeItemFromWorld(_ id: String) {
        rooms[currentRoomID]?.items.removeAll { $0 == id }
        for (key, var item) in items where item.contents.contains(id) {
            item.contents.removeAll { $0 == id }
            items[key] = item
        }
    }

    func award(_ points: Int, _ note: String?) {
        score += points
        if let note { emit(note) }
    }

    /// Ends the game as a win, printing the scenario's closing message
    /// followed by the standard score footer.
    func win(_ message: String) {
        isWon = true
        emit("""

        \(message)

        *** You have won! ***

        Your score is \(score) of a possible \(scenario.maxScore), in \(moves) moves.
        Type RESTART to play again.
        """)
    }

    func emit(_ text: String, asCommand: Bool = false) {
        transcript.append(TranscriptEntry(id: nextEntryID, text: text, isCommand: asCommand))
        nextEntryID += 1
    }

    // MARK: Save & Restore

    private var saveKey: String { "skogark.\(scenario.id).savegame" }

    /// True when a saved game exists for this scenario.
    var hasSavedGame: Bool {
        UserDefaults.standard.data(forKey: saveKey) != nil
    }

    /// A serializable capture of every piece of mutable game state.
    private struct Snapshot: Codable {
        var rooms: [String: Room]
        var items: [String: Item]
        var inventory: [String]
        var currentRoomID: String
        var flags: [String]
        var coins: Int
        var nextPurchaseID: Int?
        var score: Int
        var moves: Int
        var isWon: Bool
        var transcript: [TranscriptEntry]
        var nextEntryID: Int
    }

    private func save() {
        let snapshot = Snapshot(
            rooms: rooms, items: items, inventory: inventory,
            currentRoomID: currentRoomID, flags: Array(flags), coins: coins,
            nextPurchaseID: nextPurchaseID,
            score: score, moves: moves, isWon: isWon,
            transcript: transcript, nextEntryID: nextEntryID
        )
        do {
            let data = try JSONEncoder().encode(snapshot)
            UserDefaults.standard.set(data, forKey: saveKey)
            emit("Game saved.")
        } catch {
            emit("Something went wrong and the game could not be saved.")
        }
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: saveKey) else {
            emit("There is no saved game to restore.")
            return
        }
        do {
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
            rooms = snapshot.rooms
            items = snapshot.items
            inventory = snapshot.inventory
            currentRoomID = snapshot.currentRoomID
            flags = Set(snapshot.flags)
            coins = snapshot.coins
            nextPurchaseID = snapshot.nextPurchaseID ?? 0
            score = snapshot.score
            moves = snapshot.moves
            isWon = snapshot.isWon
            transcript = snapshot.transcript
            nextEntryID = snapshot.nextEntryID
            emit("Game restored.")
            describeCurrentRoom(force: true)
        } catch {
            emit("The saved game could not be read.")
        }
    }

    private func restart() {
        startFresh(clearTranscript: true)
    }

    // MARK: Static Text

    private var helpText: String {
        var lines = [
            "Some things you can type:",
            "  Directions: NORTH/N, SOUTH/S, EAST/E, WEST/W, UP/U, DOWN/D, IN, OUT",
            "  LOOK (L)              — describe your surroundings",
            "  LOOK AROUND           — list what you can see here, and the exits",
            "  EXAMINE <thing> (X)   — inspect something",
            "  READ <thing>          — read something",
            "  TALK TO <someone>     — speak with a person",
            "  TAKE / DROP <thing>   — pick up or set down an item",
            "  OPEN / CLOSE <thing>  — for doors, windows, containers",
            "  MOVE <thing>          — shift a heavy object",
            "  TURN ON / OFF LAMP    — control a light source",
            "  PUT <thing> IN <thing>— place an item in a container",
            "  GIVE <thing> TO <someone> — offer an item",
        ]
        if scenario.startingCoins > 0 {
            lines.append("  BUY <thing>           — purchase goods in a shop")
            lines.append("  COINS                 — check your money")
        }
        lines += [
            "  INVENTORY (I)         — list what you're carrying",
            "  SCORE                 — check your progress",
            "  HINT                  — a nudge toward your next step",
            "  SAVE / RESTORE        — save or reload your game",
            "  RESTART               — start over",
        ]
        return lines.joined(separator: "\n")
    }
}

// MARK: - Scenarios

extension Game {

    /// The original adventure: explore the white house and its caverns,
    /// get the jeweled egg into the trophy case, and visit the village.
    static func houseScenario() -> Scenario {
        Scenario(
            id: "house",
            title: "Explore a House",
            blurb: "Explore a house and the caverns beneath it in search of treasure. Beware the grue.",
            banner: """
            SKOGARK
            A tiny text adventure. (c) 2026
            Type HELP for a list of commands.
            ─────────────────────────────
            """,
            startRoomID: "westOfHouse",
            maxScore: 25,
            startingCoins: 0,
            build: buildHouseWorld,
            portalGate: { game, direction in
                if direction == .inside, game.roomID == "behindHouse",
                   game.item("window")?.isOpen != true {
                    return "The window is closed. You'll need to open it first."
                }
                if direction == .down, game.roomID == "livingRoom" {
                    if !game.has(flag: "rugMoved") { return "You can't go that way." }
                    if game.item("trapdoor")?.isOpen != true { return "The trap door is closed." }
                }
                return nil
            },
            portalDirection: { game, id in
                if id == "window" {
                    if game.roomID == "behindHouse" { return .inside }
                    if game.roomID == "kitchen" { return .outside }
                    return nil
                }
                if id == "trapdoor" { return .down }
                return nil
            },
            exitHidden: { game, direction in
                game.roomID == "livingRoom" && direction == .down && !game.has(flag: "rugMoved")
            },
            fixtureLine: { game, id in
                guard let item = game.item(id) else { return nil }
                switch id {
                case "trapdoor":
                    return "A trap door is set into the floor. It is \(item.isOpen ? "open" : "closed")."
                case "case":
                    let contents = item.contents.compactMap { game.item($0)?.name }
                    return contents.isEmpty
                        ? "The trophy case is \(item.isOpen ? "open and empty" : "closed")."
                        : "The trophy case contains: \(contents.joined(separator: ", "))."
                default:
                    return nil // mailbox, window, rug — woven into prose
                }
            },
            onTake: { game, id in
                if id == "egg" { game.award(5, "You've found a treasure!") }
            },
            onMoveObject: { game, id in
                guard id == "rug" else { return false }
                if game.has(flag: "rugMoved") {
                    game.emit("You've already moved the rug aside.")
                    return true
                }
                game.set(flag: "rugMoved")
                game.revealItem("trapdoor", inRoom: "livingRoom")
                game.award(2, nil)
                game.emit("With a great heave you drag the rug aside, revealing a dusty trap door set into the floor.")
                return true
            },
            onGive: { game, gift, recipient in
                guard recipient == "cat", gift == "fish" else { return false }
                if game.has(flag: "catFed") {
                    game.emit("The cat has already had its fill and just blinks at you contentedly.")
                    return true
                }
                game.set(flag: "catFed")
                game.consumeFromInventory(gift)
                game.award(3, nil)
                game.emit("You offer the fish to the stray cat. It gulps the treat down, then winds around your ankles with a rumbling purr. You've made a friend.")
                return true
            },
            onPut: { game, object, target in
                if target == "case", object == "egg" {
                    game.award(10, nil)
                    game.win("The jeweled egg settles into the trophy case with a soft, satisfying click. Light dances through the glass.")
                }
            },
            hintStage: { game in
                if game.item("case")?.contents.contains("egg") == true {
                    return (key: "done", clues: ["The egg is in the case — you've done it!"])
                }
                if game.item("window")?.isOpen != true {
                    return (key: "enter", clues: [
                        "The house looks sealed from the front — try looking around the back.",
                        "Behind the house a window is ajar: OPEN WINDOW, then go IN.",
                    ])
                }
                if game.item("lantern")?.isLit != true {
                    return (key: "light", clues: [
                        "It's pitch dark underground, and a grue lurks there. You'll want a light before you descend.",
                        "There's a brass lantern in the kitchen — TAKE LANTERN, then TURN ON LANTERN.",
                    ])
                }
                if !game.has(flag: "rugMoved") {
                    return (key: "rug", clues: [
                        "The living room hides a way down; something on the floor is in the way.",
                        "MOVE the RUG to uncover a trap door.",
                    ])
                }
                if game.item("trapdoor")?.isOpen != true {
                    return (key: "trap", clues: [
                        "You've found the trap door — but it's no use to you closed.",
                        "OPEN the TRAP DOOR, then go DOWN.",
                    ])
                }
                if !game.isCarrying("egg") {
                    return (key: "egg", clues: [
                        "The treasure lies in the darkness below.",
                        "Go DOWN into the cellar (lantern lit!) and TAKE the EGG.",
                    ])
                }
                return (key: "deliver", clues: [
                    "You have the treasure — now it needs a home.",
                    "Return to the living room, OPEN CASE, and PUT EGG IN CASE.",
                ])
            }
        )
    }

    /// The town errand: the inn's cook sends you out with a purse to buy a
    /// cut of meat, a loaf of bread, and a fresh fish, then bring them back.
    static func townScenario() -> Scenario {
        Scenario(
            id: "town",
            title: "Explore the Town",
            blurb: "The cook needs supplies for a feast. Shop the village with a purse of coins and deliver the goods.",
            banner: """
            MARKET ERRAND
            A tiny SkoGarK tale. (c) 2026
            Type HELP for commands, and READ LIST for your task.
            ─────────────────────────────
            """,
            startRoomID: "innKitchen",
            maxScore: 20,
            startingCoins: 25,
            build: buildTownWorld,
            fixtureLine: { game, id in
                guard let item = game.item(id) else { return nil }
                if item.forSale {
                    let name = item.name.prefix(1).uppercased() + item.name.dropFirst()
                    return "\(name) is on offer here — \(item.price) coins."
                }
                if item.isCreature {
                    switch id {
                    case "cook": return "The cook waits by the hearth for her supplies."
                    case "butcherman": return "A burly butcher stands behind the counter."
                    case "baker": return "A cheerful baker dusts flour from her hands."
                    case "fishwife": return "A brisk fishwife tends her glistening stall."
                    case "cat": return "A skinny stray cat loiters by the stall, eyeing the fish hopefully."
                    default: return nil
                    }
                }
                return nil
            },
            onGive: { game, gift, recipient in
                // Optional side-quest: the stray cat by the fishmonger wants a fish.
                if recipient == "cat" {
                    if game.has(flag: "catFed") {
                        game.emit("The cat has already had its fill and just blinks at you contentedly.")
                        return true
                    }
                    guard game.item(gift)?.kind == "fish" else {
                        game.emit("The cat sniffs the \(game.item(gift)?.name ?? "offering") and turns away — it only wants fish.")
                        return true
                    }
                    game.set(flag: "catFed")
                    game.consumeFromInventory(gift)
                    game.award(5, nil)
                    game.emit("You set the fish down for the stray cat. It pounces, devours the treat, and rubs against your leg with a rumbling purr.")
                    return true
                }
                guard recipient == "cook" else { return false }
                let goods = ["meat", "bread", "fish"]
                guard let kind = game.item(gift)?.kind, goods.contains(kind) else {
                    game.emit("The cook chuckles. \"That's not on my list, friend.\"")
                    return true
                }
                game.consumeFromInventory(gift)
                game.set(flag: "delivered_\(kind)")
                game.award(5, nil)
                let deliveredCount = goods.filter { game.has(flag: "delivered_\($0)") }.count
                if deliveredCount == goods.count {
                    game.win("The cook beams as you hand over the last of the shopping. \"A feast fit for the whole village — thank you, and keep the change!\"")
                } else {
                    let name = game.item(gift)?.name ?? "goods"
                    game.emit("The cook takes the \(name) with a grateful nod. (\(deliveredCount) of \(goods.count) delivered.)")
                }
                return true
            },
            onTalk: { game, id in
                guard id == "cook" else { return false }
                let goods = ["meat", "bread", "fish"]
                let remaining = goods
                    .filter { !game.has(flag: "delivered_\($0)") }
                    .compactMap { game.item($0)?.name }
                if remaining.isEmpty {
                    game.emit("\"You've brought everything — bless you!\" the cook says.")
                } else {
                    game.emit("\"I still need: \(remaining.joined(separator: ", ")). Buy them from the shops around the square and bring them back to me. Mind your coins!\" the cook says.")
                }
                return true
            },
            hintStage: { game in
                let goods = [
                    (kind: "meat", name: "cut of meat", shop: "the butcher (east of the square)"),
                    (kind: "bread", name: "loaf of bread", shop: "the bakery (west of the square)"),
                    (kind: "fish", name: "fresh fish", shop: "the fishmonger (north of the square)"),
                ]
                let needed = goods.filter { !game.has(flag: "delivered_\($0.kind)") }
                if needed.isEmpty {
                    return (key: "done", clues: ["You've delivered everything the cook wanted!"])
                }
                let carried = game.inventoryKinds()
                let toBuy = needed.filter { !carried.contains($0.kind) }
                let key = "left:" + needed.map { $0.kind }.joined(separator: ",")
                    + "|buy:" + toBuy.map { $0.kind }.joined(separator: ",")

                var clues: [String] = []
                clues.append("The cook still needs: \(needed.map { $0.name }.joined(separator: ", ")). (Try READ LIST or TALK TO COOK.)")
                if toBuy.isEmpty {
                    clues.append("You've bought what's left — head back to the inn (south of the square) and GIVE each item TO COOK.")
                } else {
                    clues.append("Where to shop: \(toBuy.map { "\($0.name) at \($0.shop)" }.joined(separator: "; ")).")
                }
                var finalClue = "BUY each item (mind your 25 coins), then return to the inn and GIVE <item> TO COOK."
                if !game.has(flag: "catFed") {
                    finalClue += " Bonus: a spare fish pleases the stray cat by the fishmonger (+5)."
                }
                clues.append(finalClue)
                return (key: key, clues: clues)
            }
        )
    }

    /// The riverboat: a narrated sightseeing cruise on the Savannah River.
    /// Pick a sailing at the River Street dock, board the paddle steamer
    /// *Savannah Cruise*, and ride upriver past the busy port to the Talmadge
    /// Bridge, then down to Old Fort Jackson. The 1 o'clock "Cannon Cruise"
    /// adds a cannon salute at the fort.
    static func riverboatScenario() -> Scenario {
        // True once the guest has picked one of the three sailings.
        func choseCruise(_ game: Game) -> Bool {
            game.has(flag: "cruise_cannon") || game.has(flag: "cruise_afternoon")
                || game.has(flag: "cruise_sunset")
        }
        return Scenario(
            id: "riverboat",
            title: "Savannah Riverboat",
            blurb: "Take a paddle-steamer sightseeing tour on the Savannah River: pick a sailing, board at River Street, and ride past the busy port to Old Fort Jackson as Captain Mike narrates.",
            banner: """
            SAVANNAH RIVERBOAT
            A narrated cruise on the Savannah River. (c) 2026
            Type HELP for commands, and READ SCHEDULE for today's sailings.
            ─────────────────────────────
            """,
            startRoomID: "riverStreet",
            maxScore: 25,
            startingCoins: 0,
            build: buildRiverboatWorld,
            portalGate: { game, direction in
                if game.roomID == "riverStreet", direction == .north, !choseCruise(game) {
                    return "\"Which sailing?\" Captain Mike calls down from the deck. \"Board the CANNON, the AFTERNOON, or the SUNSET cruise.\""
                }
                return nil
            },
            portalDirection: { game, id in
                // Choosing a sailing and stepping aboard are one action: each
                // cruise placard boards the boat and records the choice.
                guard game.roomID == "riverStreet" else { return nil }
                switch id {
                case "cannonCruise": game.set(flag: "cruise_cannon"); return .north
                case "afternoonCruise": game.set(flag: "cruise_afternoon"); return .north
                case "sunsetCruise": game.set(flag: "cruise_sunset"); return .north
                default: return nil
                }
            },
            fixtureLine: { game, id in
                switch id {
                case "captain":
                    return "Captain Mike stands at the wheel, narrating the tour."
                case "guests":
                    return "Fellow sightseers wait on the wharf, tickets in hand."
                default:
                    return nil // schedule, gangway, ships, bridge, fort — woven into the prose
                }
            },
            onTalk: { game, id in
                switch id {
                case "guests":
                    game.emit("\"First time on the boat?\" a fellow passenger asks. \"They say Captain Mike tells the best stories on the river.\"")
                    return true
                case "captain":
                    game.emit("\"Welcome aboard the Savannah Cruise!\" the captain says. \"Four decks to enjoy — two dining rooms below, the air-conditioned sightseeing lounge on the third, and this open deck up top for the best views. We'll steam upriver past the port to the Talmadge Bridge, come about, and call on Old Fort Jackson. Head WEST from the top deck when you're ready.\"")
                    return true
                default:
                    return false
                }
            },
            onEnterRoom: { game, roomID in
                // Each new leg is announced once, no matter which of the four
                // decks the passenger is on. The cannon and afternoon cruises get
                // Captain Mike's narrated history; the 7 o'clock sunset cruise has
                // no tour — a DJ works the open-air top deck instead, so the legs
                // get party lines and the top deck plays dance music (see
                // GameView.updateDanceMusic).
                let sunset = game.has(flag: "cruise_sunset")
                if roomID == "fortJackson" {
                    guard !game.isWon else { return }
                    if sunset {
                        game.emit("The DJ eases into a mellow sunset anthem as Old Fort Jackson's brick ramparts drift past, glowing in the last of the light.")
                    } else {
                        game.emit("Captain Mike: \"Old Fort Jackson ahead is one of the oldest standing brick forts in the nation, guarding this bend of the river since the War of 1812 and held by Confederate defenders through the Civil War.\"")
                    }
                    if game.has(flag: "cruise_cannon") {
                        game.emit("At Old Fort Jackson a cannon crew in period dress touches off the great gun — BOOOM! — a plume of white smoke and a salute that rolls across the water and thumps in your chest.")
                    }
                    let closing: String
                    if sunset {
                        closing = "Old Fort Jackson's brick ramparts glow in the last of the sunset as the boat turns for the lamplit run home to River Street."
                    } else if game.has(flag: "cruise_cannon") {
                        closing = "With the cannon's echo still fading over the marsh, Captain Mike brings the boat about for the run home to River Street."
                    } else {
                        closing = "The boat eases past Old Fort Jackson's weathered ramparts, then comes about for the easy run home to River Street."
                    }
                    game.award(15, nil)
                    game.win(closing)
                } else if roomID.hasPrefix("port"), !game.has(flag: "sawPort") {
                    game.set(flag: "sawPort")
                    game.award(5, sunset
                        ? "The DJ on the top deck kicks off the night — a thumping bassline rolls out over the water and the dance floor fills as the lit-up Port of Savannah slides past in the dusk."
                        : "Captain Mike: \"Off to starboard lies the Port of Savannah, one of the busiest in the nation. Towering container ships ride the channel while stout tugboats shoulder them to their berths.\"")
                } else if roomID.hasPrefix("bridge"), !game.has(flag: "sawBridge") {
                    game.set(flag: "sawBridge")
                    game.award(5, sunset
                        ? "The boat swings around beneath the Talmadge Bridge, its lights flickering on against the purple sky, and the DJ drops the beat — the whole top deck throws their hands up. (Head EAST to continue to Old Fort Jackson.)"
                        : "Captain Mike: \"Overhead soars the Talmadge Memorial Bridge, its cables strung like a harp above the river. Here we come about for the slow run downriver.\" (Head EAST to continue to Old Fort Jackson.)")
                } else if roomID.hasPrefix("city"), !game.has(flag: "sawCity") {
                    game.set(flag: "sawCity")
                    game.emit(sunset
                        ? "Downtown Savannah glitters past as the DJ mixes into a deep, rolling groove and glow sticks trace the rail."
                        : "Captain Mike: \"Savannah was founded in 1733 by General James Oglethorpe — the last of the thirteen colonies, laid out in that famous grid of leafy squares you can still walk today. That gold dome is City Hall; beside it stands the old Cotton Exchange, from the days when Savannah set the world's price for cotton. And from this very river, in 1819, the SS Savannah steamed off to become the first steamship to cross the Atlantic.\"")
                } else if roomID.hasPrefix("waving"), !game.has(flag: "sawWaving") {
                    game.set(flag: "sawWaving")
                    if sunset {
                        game.emit("The DJ cues a floor-filler and the whole boat sings along, waving at a passing freighter — an old Savannah tradition, remixed.")
                    } else {
                        game.emit("Captain Mike: \"That little white figure on the point is the Waving Girl — Florence Martus, who for forty-four years greeted every ship entering the port, waving a handkerchief by day and a lantern by night. These marshes carried Savannah's cotton and naval stores out to the world.\"")
                        game.emit("Captain Mike: \"Now, those refineries coming up on the bank — that's my favorite. See those big piles? That's the cereal. And those three tall silos yonder? Whole milk, oat milk, and skim. Biggest bowl of breakfast on the Georgia coast — all we're missing is a spoon the size of the Talmadge Bridge!\"")
                    }
                }
            },
            hintStage: { game in
                if !choseCruise(game) {
                    return (key: "board", clues: [
                        "Today's sailings are chalked on the schedule board at the dock — READ the SCHEDULE.",
                        "Pick one and step aboard: BOARD THE CANNON CRUISE (or the AFTERNOON, or the SUNSET cruise).",
                    ])
                }
                // Only the open-air top deck (D4) drives the boat onward;
                // every leg's other decks are yours to explore with UP/DOWN.
                let room = game.roomID
                let onTopDeck = room.hasSuffix("D4")
                if room.hasPrefix("city") || room.hasPrefix("waving") {
                    return onTopDeck
                        ? (key: "east4", clues: [
                            "Captain Mike is telling the city's story — no rush.",
                            "Continue EAST; Old Fort Jackson is downriver.",
                        ])
                        : (key: "eastUp", clues: [
                            "You can roam all four decks here with UP and DOWN.",
                            "To carry on, climb UP to the open-air deck and keep heading EAST to Old Fort Jackson.",
                        ])
                }
                if room.hasPrefix("bridge") {
                    return onTopDeck
                        ? (key: "bridge4", clues: [
                            "The boat comes about beneath the bridge to head downriver.",
                            "Go EAST to run down to Old Fort Jackson.",
                        ])
                        : (key: "bridgeUp", clues: [
                            "You can wander all four decks here with UP and DOWN.",
                            "To carry on, climb UP to the open-air deck; the boat turns here, so head EAST toward Old Fort Jackson.",
                        ])
                }
                if room.hasPrefix("port") {
                    return onTopDeck
                        ? (key: "port4", clues: [
                            "The Talmadge Bridge lies just ahead upriver.",
                            "Continue WEST to reach the bridge.",
                        ])
                        : (key: "portUp", clues: [
                            "Explore the decks with UP and DOWN.",
                            "To carry on, climb UP to the open-air deck and head WEST toward the bridge.",
                        ])
                }
                // River Street leg (riverD1…riverD4).
                return onTopDeck
                    ? (key: "river4", clues: [
                        "You're up on the open-air deck — time to get underway.",
                        "Head WEST to steam upriver toward the Talmadge Bridge.",
                    ])
                    : (key: "riverUp", clues: [
                        "You can visit all four decks with UP and DOWN — two dining rooms, the sightseeing lounge, and the open-air deck up top.",
                        "To get underway, climb UP to the open-air deck and head WEST.",
                    ])
            }
        )
    }

    /// Fort Pulaski: a self-guided visit to the National Monument on Cockspur
    /// Island. Drive in through the gates, check in at the visitor center, then
    /// walk out past Battery Hambright to the historic North Pier, and follow
    /// the Lighthouse Overlook Trail through the marsh to the Cockspur Island
    /// Lighthouse. (The fort itself — inside and out, with its cannon-lined
    /// upstairs — is left as a placeholder for a future update.)
    static func fortPulaskiScenario() -> Scenario {
        // The four points of interest the visitor is here to see.
        let stops = ["checkedIn", "sawBattery", "sawPier", "sawLighthouse"]
        return Scenario(
            id: "fortPulaski",
            title: "Explore Fort Pulaski",
            blurb: "Drive onto Cockspur Island to visit Fort Pulaski National Monument: check in at the visitor center, walk out past Battery Hambright to the historic North Pier, and follow the Lighthouse Overlook Trail through the marsh to spy the Cockspur Island Lighthouse.",
            banner: """
            FORT PULASKI
            A visit to the National Monument on Cockspur Island. (c) 2026
            Type HELP for commands. Drive NORTH to the visitor center to check in.
            ─────────────────────────────
            """,
            startRoomID: "gate",
            maxScore: 25,
            startingCoins: 0,
            build: buildFortPulaskiWorld,
            onTalk: { game, id in
                guard id == "ranger" else { return false }
                game.emit("Ranger Max leans on the desk. \"Fort Pulaski is named for Casimir Pulaski — a Polish nobleman and cavalry commander, the 'father of the American cavalry,' who fell leading a charge at the Siege of Savannah in 1779. The fort took eighteen years to build, and a young Lieutenant Robert E. Lee helped lay out its dikes. Everyone believed these seven-and-a-half-foot brick walls were invincible — until April 1862, when Union rifled cannon on Tybee Island breached them in about thirty hours and made every masonry fort in the world obsolete overnight. Take the walking path out to Battery Hambright and the North Pier, and don't miss the Lighthouse Overlook Trail.\"")
                return true
            },
            onEnterRoom: { game, roomID in
                // Reaching each of the four points of interest is announced and
                // scored once; seeing all four ends the visit.
                func award(_ flag: String, _ points: Int, _ note: String) {
                    guard !game.has(flag: flag) else { return }
                    game.set(flag: flag)
                    game.award(points, note)
                    if stops.allSatisfy({ game.has(flag: $0) }) {
                        game.win("You've driven in through the gates, checked in at the visitor center, walked out to Battery Hambright and the North Pier, and followed the marsh trail to the Cockspur Island Lighthouse. The old fort itself — its drawbridge, casemates, and the cannon-lined terreplein upstairs — waits for another day. (More of Fort Pulaski is coming soon.)")
                    }
                }
                switch roomID {
                case "visitorCenter":
                    award("checkedIn", 5, "Ranger Max welcomes you to Fort Pulaski National Monument from behind the desk and checks you in. \"Cockspur Island has guarded the mouth of the Savannah River for a very long time — TALK TO MAX or READ the EXHIBIT to hear the story.\"")
                case "batteryHambright":
                    award("sawBattery", 5, "You come to Battery Hambright, a squat concrete gun emplacement half-swallowed by the marsh grass, its gun wells empty and open to the sky. It's named for Lieutenant Horace G. Hambright, a young West Point officer who died out west in 1896 and was honored here in 1904. Poured about 1900 over a foundation of 30,000 bricks salvaged from the original fort village, it was built to guard the river mouth in the Spanish-American War era — yet it never received its guns and never fired a shot.")
                case "northPier":
                    award("sawPier", 5, "Out at the end of the Historic North Pier, you settle in to watch the traffic where the Savannah River meets the sea: a towering container ship slides seaward stacked with steel boxes, a Coast Guard boat throttles past on patrol, and a fast river pilot boat darts out to put a harbor pilot aboard an inbound freighter.")
                case "trail4":
                    award("sawLighthouse", 10, "The trail ends at a small observation deck. You lean into the mounted binoculars and there it is across the marsh: the Cockspur Island Lighthouse — the smallest lighthouse in Georgia — standing on its oyster-shell bar, its base shaped like a ship's prow to cut the waves. It survived the 1862 bombardment of Fort Pulaski with over five thousand shots screaming directly overhead, and stands quiet now, relit for history.")
                default:
                    break
                }
            },
            hintStage: { game in
                if !game.has(flag: "checkedIn") {
                    return (key: "checkin", clues: [
                        "Start by driving up to the visitor center to check in.",
                        "Go NORTH from the gates to the visitor center.",
                    ])
                }
                var todo: [String] = []
                if !game.has(flag: "sawBattery") { todo.append("Battery Hambright") }
                if !game.has(flag: "sawPier") { todo.append("the North Pier") }
                if !game.has(flag: "sawLighthouse") { todo.append("the Lighthouse Overlook") }
                if todo.isEmpty {
                    return (key: "done", clues: ["You've seen every stop — enjoy the view!"])
                }
                return (key: "todo:" + todo.joined(separator: "|"), clues: [
                    "Still to explore: \(todo.joined(separator: ", ")).",
                    "From the visitor center, NORTH walks you past Battery Hambright to the North Pier; EAST starts the Lighthouse Overlook Trail — go FORWARD four stops to the deck and its binoculars, then head BACK.",
                ])
            }
        )
    }

    // Small mutators the scenario hooks lean on.
    fileprivate func revealItem(_ id: String, inRoom roomID: String) {
        rooms[roomID]?.items.append(id)
    }
    fileprivate func consumeFromInventory(_ id: String) {
        inventory.removeAll { $0 == id }
    }
}

// MARK: - World Builders

private func buildHouseWorld() -> (rooms: [String: Room], items: [String: Item]) {
    var items: [String: Item] = [:]
    func add(_ item: Item) { items[item.id] = item }

    add(Item(id: "leaflet", name: "leaflet", nouns: ["leaflet", "paper", "mail"],
             description: "A small paper leaflet.", isTakeable: true,
             readText: "\"WELCOME TO SKOGARK!\n\nSkoGarK is a game of adventure and low cunning. In it you will explore a house and the caverns beneath it in search of treasure. Beware the grue — it lurks in darkness. Type HELP if you get stuck.\""))
    add(Item(id: "mailbox", name: "small mailbox", nouns: ["mailbox", "box"],
             description: "It's a small mailbox.", isOpenable: true, isContainer: true,
             contents: ["leaflet"], isFixture: true))
    add(Item(id: "window", name: "window", nouns: ["window"],
             description: "The kitchen window is slightly ajar.", isOpenable: true, isFixture: true))
    add(Item(id: "lantern", name: "brass lantern", nouns: ["lantern", "lamp", "light"],
             description: "A battered brass lantern.", isTakeable: true, isLightSource: true))
    add(Item(id: "bottle", name: "glass bottle", nouns: ["bottle", "water"],
             description: "A glass bottle containing a little water.", isTakeable: true))
    add(Item(id: "rug", name: "oriental rug", nouns: ["rug", "carpet"],
             description: "A large oriental rug in the center of the room.", isFixture: true))
    add(Item(id: "trapdoor", name: "trap door", nouns: ["trapdoor", "trap", "door", "hatch"],
             description: "A closed wooden trap door in the floor.", isOpenable: true, isFixture: true))
    add(Item(id: "case", name: "trophy case", nouns: ["case", "trophy"],
             description: "A handsome glass trophy case, waiting to be filled.",
             isOpenable: true, isContainer: true, isFixture: true))
    add(Item(id: "egg", name: "jeweled egg", nouns: ["egg", "jewel", "treasure"],
             description: "A stunning jeweled egg that glitters even in faint light.",
             isTakeable: true))
    add(Item(id: "fish", name: "fresh fish", nouns: ["fish", "herring", "catch"],
             description: "A fat, silver fish fresh from the stall, still glistening.",
             isTakeable: true))
    add(Item(id: "cat", name: "stray cat", nouns: ["cat", "kitten", "stray"],
             description: "A scruffy stray cat with matted fur, watching the fishmonger's stall with hungry, hopeful eyes.",
             isCreature: true, dialogue: "The stray cat regards you with lofty indifference."))

    var rooms: [String: Room] = [:]
    func add(_ room: Room) { rooms[room.id] = room }

    add(Room(id: "westOfHouse", title: "West of House",
             description: "You are standing in an open field west of a white house, with a boarded front door. A small mailbox stands here.",
             exits: [.east: "behindHouse", .north: "behindHouse"],
             items: ["mailbox"]))
    add(Room(id: "behindHouse", title: "Behind House",
             description: "You are behind the white house. A path leads into the forest to the east. One window into the kitchen is slightly ajar.",
             exits: [.west: "westOfHouse", .inside: "kitchen", .east: "forestPath"],
             items: ["window"]))
    add(Room(id: "kitchen", title: "Kitchen",
             description: "You are in the kitchen of the white house. A table sits in the middle of the room. A passage leads west, and a dark staircase leads up. To the east, a window opens onto the yard.",
             exits: [.west: "livingRoom", .outside: "behindHouse", .east: "behindHouse"],
             items: ["lantern", "bottle"]))
    add(Room(id: "livingRoom", title: "Living Room",
             description: "You are in the living room. There is a trophy case here, and a large oriental rug lies in the center of the floor. A doorway leads east to the kitchen.",
             exits: [.east: "kitchen", .down: "cellar"],
             items: ["case", "rug"]))
    add(Room(id: "cellar", title: "Cellar",
             description: "You are in a damp, cramped cellar carved from the rock. A rickety staircase leads up toward the living room.",
             exits: [.up: "livingRoom"],
             items: ["egg"], isDark: true))

    // The village, reached along the forest path east of the house.
    add(Room(id: "forestPath", title: "Forest Path",
             description: "A narrow dirt path winds through cool, whispering pines. The white house lies back to the west, while ahead to the east the trees thin toward the rooftops of a village.",
             exits: [.west: "behindHouse", .east: "villageSquare"]))
    add(Room(id: "villageSquare", title: "Village Square",
             description: "You stand on the cobbles at the heart of a small village. Shops crowd the edges: a butcher to the north and a bakery to the south. A lane leads east toward the market, and the forest path returns west toward the house.",
             exits: [.west: "forestPath", .north: "butcher", .south: "bakery", .east: "marketRow"]))
    add(Room(id: "marketRow", title: "Market Row",
             description: "A bustling market row, hemmed in by timber-framed storefronts. A fishmonger's stall stands to the north and a blacksmith's forge glows to the south. The village square lies back to the west.",
             exits: [.west: "villageSquare", .north: "fishmonger", .south: "blacksmith"],
             items: ["cat"]))
    add(Room(id: "butcher", title: "The Butcher",
             description: "The butcher's shop smells of sawdust and cold iron. Cuts of meat hang from steel hooks while a broad-shouldered butcher wipes his hands on a striped apron. The square is back to the south.",
             exits: [.south: "villageSquare"]))
    add(Room(id: "bakery", title: "The Bakery",
             description: "Warm air and the scent of fresh bread fill the bakery. Loaves and pastries are stacked on wooden shelves, and a flour-dusted baker nods you a greeting. The square lies north.",
             exits: [.north: "villageSquare"]))
    add(Room(id: "fishmonger", title: "The Fishmonger",
             description: "The fishmonger's stall glistens with the day's catch laid out on crushed ice. A brisk woman in oilskins calls her prices to no one in particular. Market row is back to the south.",
             exits: [.south: "marketRow"],
             items: ["fish"]))
    add(Room(id: "blacksmith", title: "The Blacksmith",
             description: "Heat rolls off the blacksmith's forge, and the ring of hammer on anvil fills the air. A soot-streaked smith pauses, tongs in hand, to size you up. Market row lies north.",
             exits: [.north: "marketRow"]))

    return (rooms, items)
}

private func buildTownWorld() -> (rooms: [String: Room], items: [String: Item]) {
    var items: [String: Item] = [:]
    func add(_ item: Item) { items[item.id] = item }

    add(Item(id: "list", name: "shopping list", nouns: ["list", "note", "paper"],
             description: "The cook's shopping list, in a hurried scrawl.", isTakeable: true,
             readText: "\"FEAST SHOPPING\n  • a cut of meat — from the butcher\n  • a loaf of bread — from the bakery\n  • a fresh fish — from the fishmonger\nBring them all back to me. Here's your purse. — Cook\""))
    add(Item(id: "cook", name: "cook", nouns: ["cook", "innkeeper", "woman"],
             description: "The inn's cook, rosy-cheeked and flour-dusted, waiting for her supplies.",
             isFixture: true, isCreature: true))
    add(Item(id: "meat", name: "cut of meat", nouns: ["meat", "beef", "cut"],
             description: "A good red cut, trimmed and ready.",
             isTakeable: true, isFixture: true, forSale: true, price: 8, kind: "meat"))
    add(Item(id: "bread", name: "loaf of bread", nouns: ["bread", "loaf"],
             description: "A crusty loaf, still warm from the oven.",
             isTakeable: true, isFixture: true, forSale: true, price: 5, kind: "bread"))
    add(Item(id: "fish", name: "fresh fish", nouns: ["fish", "herring", "catch"],
             description: "A silvery fish laid out on crushed ice.",
             isTakeable: true, isFixture: true, forSale: true, price: 6, kind: "fish"))
    add(Item(id: "butcherman", name: "butcher", nouns: ["butcher", "man"],
             description: "A burly butcher in a striped apron.",
             isFixture: true, isCreature: true,
             dialogue: "\"Finest cuts in the village,\" the butcher grunts. \"Eight coins and that one's yours — just say BUY MEAT.\""))
    add(Item(id: "baker", name: "baker", nouns: ["baker"],
             description: "A cheerful baker, sleeves rolled and dusted with flour.",
             isFixture: true, isCreature: true,
             dialogue: "\"Fresh from the oven!\" the baker beams. \"Five coins a loaf — BUY BREAD whenever you like.\""))
    add(Item(id: "fishwife", name: "fishwife", nouns: ["fishwife", "fishmonger", "woman"],
             description: "A brisk fishwife in oilskins.",
             isFixture: true, isCreature: true,
             dialogue: "\"Caught this very morning,\" says the fishwife. \"Six coins — BUY FISH and it's yours.\""))
    add(Item(id: "cat", name: "stray cat", nouns: ["cat", "kitten", "stray"],
             description: "A skinny stray cat loiters by the fishmonger's stall, watching the catch with hungry, hopeful eyes.",
             isFixture: true, isCreature: true,
             dialogue: "The stray cat mews at you and glances pointedly at the fish."))

    var rooms: [String: Room] = [:]
    func add(_ room: Room) { rooms[room.id] = room }

    add(Room(id: "innKitchen", title: "The Inn Kitchen",
             description: "You're in the warm kitchen of the village inn. The cook has sent you out for tonight's feast — a shopping list lies on the table, and a purse of coins is already in your pocket. The square is just outside to the north. (Word is a stray cat haunts the fishmonger's stall and would adore a spare fish, if your coins stretch that far.)",
             exits: [.north: "square"],
             items: ["list", "cook"]))
    add(Room(id: "square", title: "Village Square",
             description: "The cobbled square, ringed with shops. The butcher is to the east, the bakery to the west, and the fishmonger to the north. The inn's kitchen is back to the south.",
             exits: [.south: "innKitchen", .east: "townButcher", .west: "townBakery", .north: "townFish"]))
    add(Room(id: "townButcher", title: "The Butcher",
             description: "Cuts of meat hang from steel hooks, and a broad-shouldered butcher stands ready behind the counter. The square is back to the west.",
             exits: [.west: "square"],
             items: ["meat", "butcherman"]))
    add(Room(id: "townBakery", title: "The Bakery",
             description: "Shelves of loaves and pastries fill the warm little bakery. The square lies east.",
             exits: [.east: "square"],
             items: ["bread", "baker"]))
    add(Room(id: "townFish", title: "The Fishmonger",
             description: "The day's catch glistens on crushed ice while the fishwife calls her prices. The square is back to the south.",
             exits: [.south: "square"],
             items: ["fish", "fishwife", "cat"]))

    return (rooms, items)
}
private func buildRiverboatWorld() -> (rooms: [String: Room], items: [String: Item]) {
    var items: [String: Item] = [:]
    func add(_ item: Item) { items[item.id] = item }

    // Dockside fixtures at River Street.
    add(Item(id: "schedule", name: "schedule board", nouns: ["schedule", "board", "sign", "chalkboard"],
             description: "A chalkboard easel by the gangway listing today's sailings.",
             readText: "\"SAVANNAH BELLE — TODAY'S SAILINGS\n  • 1:00  The CANNON Cruise — includes a cannon salute at Fort Jackson\n  • 3:30  The AFTERNOON Cruise\n  • 7:00  The SUNSET Cruise\nEvery cruise runs west to the Talmadge Bridge, then down to Old Fort Jackson.\nBOARD the cruise you'd like.\"",
             isFixture: true))
    add(Item(id: "gangway", name: "gangway", nouns: ["gangway", "gangplank", "ramp"],
             description: "A broad wooden gangway sloping up to the boat's main deck.", isFixture: true))
    add(Item(id: "guests", name: "guests", nouns: ["guests", "guest", "passengers", "tourists", "crowd"],
             description: "Cheerful guests in sun hats and windbreakers, waiting to board.",
             isFixture: true, isCreature: true))
    add(Item(id: "cannonCruise", name: "Cannon Cruise", nouns: ["cannon", "one", "noon", "first", "1", "1pm"],
             description: "The 1:00 sailing — it includes a cannon salute at Old Fort Jackson.", isFixture: true))
    add(Item(id: "afternoonCruise", name: "Afternoon Cruise", nouns: ["afternoon", "half", "three", "matinee", "3", "3pm", "330", "30"],
             description: "The 3:30 sailing, an easy afternoon run to the fort and back.", isFixture: true))
    add(Item(id: "sunsetCruise", name: "Sunset Cruise", nouns: ["sunset", "evening", "seven", "dusk", "7", "7pm"],
             description: "The 7:00 sailing, timed to catch the sunset over the marshes.", isFixture: true))

    // Aboard and along the river.
    add(Item(id: "captain", name: "Captain Mike", nouns: ["captain", "mike", "skipper", "pilot"],
             description: "Captain Mike, the boat's weathered and genial skipper, one hand on the wheel and a microphone in the other.",
             isFixture: true, isCreature: true))
    add(Item(id: "tugboat", name: "tugboat", nouns: ["tug", "tugboat", "tugs"],
             description: "A squat, powerful tugboat churning past, its wake rocking the boat.", isFixture: true))
    add(Item(id: "containership", name: "container ship", nouns: ["container", "ship", "freighter", "cargo"],
             description: "A colossal container ship stacked with steel boxes from every corner of the world, riding low with cargo.", isFixture: true))
    add(Item(id: "bridge", name: "Talmadge Bridge", nouns: ["bridge", "talmadge", "cables", "span"],
             description: "The Talmadge Memorial Bridge, a soaring cable-stayed span high above the river.", isFixture: true))
    add(Item(id: "fort", name: "Old Fort Jackson", nouns: ["fort", "jackson", "ramparts", "walls"],
             description: "Old Fort Jackson, a squat brick fortress guarding a bend in the river.", isFixture: true))
    add(Item(id: "cannon", name: "cannon", nouns: ["cannon", "gun"],
             description: "A black iron cannon on the fort's rampart, manned by a crew in period dress.", isFixture: true))

    var rooms: [String: Room] = [:]
    func add(_ room: Room) { rooms[room.id] = room }

    add(Room(id: "riverStreet", title: "River Street Dock",
             description: "You're on the cobblestones of River Street, just east of the Hyatt, where the paddle steamer Savannah Cruise is moored. A gangway leads aboard, and a chalk schedule board lists today's sailings. Fellow sightseers line up around you, tickets in hand. (READ the SCHEDULE, then BOARD a cruise.)",
             exits: [.north: "riverD1"],
             items: ["schedule", "gangway", "guests", "cannonCruise", "afternoonCruise", "sunsetCruise"]))

    // The boat is a four-deck boat; each cruise leg has all four decks, so
    // passengers can roam UP/DOWN at every stage. The tour advances from the
    // open-air top deck (D4): WEST to the bridge, then EAST to the fort.

    // Leg 1 — moored at River Street, downtown Savannah in view.
    add(Room(id: "riverD1", title: "First Deck — Dining Room",
             description: "The first-deck dining room, white-clothed tables and a Lowcountry buffet, windows framing the cobblestones of River Street. A stairway leads UP.",
             exits: [.up: "riverD2"]))
    add(Room(id: "riverD2", title: "Second Deck — Dining Room",
             description: "A second, airier dining room, its tall windows looking out on the historic River Street storefronts. Stairs lead UP and DOWN.",
             exits: [.up: "riverD3", .down: "riverD1"]))
    add(Room(id: "riverD3", title: "Third Deck — Sightseeing Lounge",
             description: "The air-conditioned sightseeing lounge, wrapped in panoramic glass, cool and quiet above the waterfront bustle. Stairs lead UP and DOWN.",
             exits: [.up: "riverD4", .down: "riverD2"]))
    add(Room(id: "riverD4", title: "Fourth Deck — Open-Air Deck",
             description: "The breezy open-air top deck. Captain Mike is at the wheel, and off the rail stand the golden dome of City Hall, the old Cotton Exchange, and the Waving Girl statue on her lonely watch. Head WEST to get underway upriver; stairs lead DOWN.",
             exits: [.west: "portD4", .down: "riverD3"],
             items: ["captain"]))

    // Leg 2 — the working river, amid the Port of Savannah.
    add(Room(id: "portD1", title: "First Deck — Dining Room",
             description: "The first-deck dining room; through the windows the steel hulls of container ships slide past, close enough to read their names. A stairway leads UP.",
             exits: [.up: "portD2"],
             items: ["containership", "tugboat"]))
    add(Room(id: "portD2", title: "Second Deck — Dining Room",
             description: "The second-deck dining room, dessert plates rattling as a tugboat's wake rolls under the boat. Stairs lead UP and DOWN.",
             exits: [.up: "portD3", .down: "portD1"],
             items: ["containership", "tugboat"]))
    add(Room(id: "portD3", title: "Third Deck — Sightseeing Lounge",
             description: "The cool sightseeing lounge; behind the glass, towering cranes work the busy terminals of the Port of Savannah. Stairs lead UP and DOWN.",
             exits: [.up: "portD4", .down: "portD2"],
             items: ["containership", "tugboat"]))
    add(Room(id: "portD4", title: "Fourth Deck — Open-Air Deck",
             description: "The open-air deck amid the working river — container ships and tugboats on every side, the Talmadge Bridge climbing into the sky ahead. Continue WEST toward the bridge; stairs lead DOWN.",
             exits: [.west: "bridgeD4", .down: "portD3"],
             items: ["captain", "containership", "tugboat"]))

    // Leg 3 — beneath the Talmadge Bridge, where the boat comes about.
    add(Room(id: "bridgeD1", title: "First Deck — Dining Room",
             description: "The first-deck dining room; the light dims for a moment as the great bridge passes overhead. A stairway leads UP.",
             exits: [.up: "bridgeD2"],
             items: ["bridge"]))
    add(Room(id: "bridgeD2", title: "Second Deck — Dining Room",
             description: "The second-deck dining room, passengers pressing to the windows to crane up at the span. Stairs lead UP and DOWN.",
             exits: [.up: "bridgeD3", .down: "bridgeD1"],
             items: ["bridge"]))
    add(Room(id: "bridgeD3", title: "Third Deck — Sightseeing Lounge",
             description: "The sightseeing lounge; through the glass the Talmadge's pale cables fan out far above. Stairs lead UP and DOWN.",
             exits: [.up: "bridgeD4", .down: "bridgeD2"],
             items: ["bridge"]))
    add(Room(id: "bridgeD4", title: "Fourth Deck — Open-Air Deck",
             description: "The open-air deck beneath the Talmadge Memorial Bridge, its pale cables soaring overhead. Captain Mike brings the boat about here for the slow run downriver — head EAST and he'll walk you through Savannah's history all the way to Old Fort Jackson; stairs lead DOWN.",
             exits: [.east: "cityD4", .down: "bridgeD3"],
             items: ["captain", "bridge"]))

    // Eastbound history legs — the slow downriver run, narrated by Captain Mike.
    // Leg 4 — the historic downtown riverfront.
    add(Room(id: "cityD1", title: "First Deck — Dining Room",
             description: "The first-deck dining room; out the windows the historic riverfront slides slowly by — cobblestone River Street and the tall façades of the old cotton warehouses. A stairway leads UP.",
             exits: [.up: "cityD2"]))
    add(Room(id: "cityD2", title: "Second Deck — Dining Room",
             description: "The second-deck dining room; above the rooftops rises the gold dome of City Hall. Stairs lead UP and DOWN.",
             exits: [.up: "cityD3", .down: "cityD1"]))
    add(Room(id: "cityD3", title: "Third Deck — Sightseeing Lounge",
             description: "The sightseeing lounge; through the glass, the restored Cotton Exchange and the ballast-stone ramps of the old wharves. Stairs lead UP and DOWN.",
             exits: [.up: "cityD4", .down: "cityD2"]))
    add(Room(id: "cityD4", title: "Fourth Deck — Open-Air Deck",
             description: "The open-air deck off historic downtown Savannah, the old city drifting slowly past. Continue EAST toward Old Fort Jackson; stairs lead DOWN.",
             exits: [.east: "wavingD4", .down: "cityD3"],
             items: ["captain"]))

    // Leg 5 — the eastern riverfront and the Waving Girl.
    add(Room(id: "wavingD1", title: "First Deck — Dining Room",
             description: "The first-deck dining room; the banks open to marsh grass and the long view downriver. A stairway leads UP.",
             exits: [.up: "wavingD2"]))
    add(Room(id: "wavingD2", title: "Second Deck — Dining Room",
             description: "The second-deck dining room; passengers wave at a passing freighter, keeping up an old Savannah tradition. Stairs lead UP and DOWN.",
             exits: [.up: "wavingD3", .down: "wavingD1"]))
    add(Room(id: "wavingD3", title: "Third Deck — Sightseeing Lounge",
             description: "The sightseeing lounge; the little white statue of the Waving Girl slips by on the point. Stairs lead UP and DOWN.",
             exits: [.up: "wavingD4", .down: "wavingD2"]))
    add(Room(id: "wavingD4", title: "Fourth Deck — Open-Air Deck",
             description: "The open-air deck along the eastern riverfront; riverside refineries — great heaped piles and three tall silos — slide past as Old Fort Jackson comes into view downriver. Continue EAST; stairs lead DOWN.",
             exits: [.east: "fortJackson", .down: "wavingD3"],
             items: ["captain"]))

    add(Room(id: "fortJackson", title: "Old Fort Jackson",
             description: "The boat rounds a marshy bend to Old Fort Jackson, its brick ramparts standing guard where the river narrows.",
             exits: [.west: "wavingD4"],
             items: ["fort", "cannon"]))

    return (rooms, items)
}

private func buildFortPulaskiWorld() -> (rooms: [String: Room], items: [String: Item]) {
    var items: [String: Item] = [:]
    func add(_ item: Item) { items[item.id] = item }

    // Entrance.
    add(Item(id: "gates", name: "park gates", nouns: ["gate", "gates"],
             description: "The park entrance gates, open onto the causeway that runs across the marsh to Cockspur Island.", isFixture: true))
    add(Item(id: "entrancesign", name: "entrance sign", nouns: ["sign", "entrance"],
             description: "A brown National Park Service sign: FORT PULASKI NATIONAL MONUMENT.",
             readText: "\"FORT PULASKI NATIONAL MONUMENT — Cockspur Island, Georgia. Established 1924. Drive ahead to the visitor center to begin your visit.\"",
             isFixture: true))

    // Visitor center.
    add(Item(id: "ranger", name: "Ranger Max", nouns: ["ranger", "max", "guide", "attendant"],
             description: "Ranger Max, a National Park Service ranger in a flat-brimmed hat, glad to share the fort's story.",
             isFixture: true, isCreature: true))
    add(Item(id: "exhibit", name: "history exhibit", nouns: ["exhibit", "display", "history", "panel", "panels"],
             description: "A wall of exhibit panels tracing the fort from its brick-by-brick construction to the day its walls were breached.",
             readText: "\"THE STORY OF FORT PULASKI\nNamed for Casimir Pulaski, the Polish-born 'father of the American cavalry,' who fell at the 1779 Siege of Savannah. Begun in 1829 and eighteen years in the building — a young Robert E. Lee helped survey its dikes. Its walls were thought impregnable until April 11–12, 1862, when Union rifled cannon on Tybee Island breached them in about thirty hours, ending the age of masonry forts.\"",
             isFixture: true))

    // Battery Hambright.
    add(Item(id: "battery", name: "Battery Hambright", nouns: ["battery", "hambright", "emplacement", "concrete"],
             description: "A squat, poured-concrete gun battery from around 1900, its gun wells empty and open to the sky. It is named for Lieutenant Horace G. Hambright, a West Point officer who died young in 1896; the battery never received its guns and never fired a shot.",
             isFixture: true))
    add(Item(id: "marker", name: "historical marker", nouns: ["marker", "plaque", "tablet"],
             description: "A cast historical marker beside the battery.",
             readText: "\"BATTERY HORACE HAMBRIGHT — Built 1899–1900 to guard the mouth of the Savannah River, and named in 1904 for Lt. Horace G. Hambright, U.S.A. Poured over 30,000 bricks salvaged from the original fort construction village. Designed for two rapid-fire 3-inch guns on disappearing mounts; the guns were never installed.\"",
             isFixture: true))

    // North Pier and the river traffic.
    add(Item(id: "pier", name: "North Pier", nouns: ["pier", "dock", "wharf"],
             description: "The historic North Pier, reaching out into the channel where the Savannah River opens to the Atlantic.", isFixture: true))
    add(Item(id: "containership", name: "container ship", nouns: ["container", "ship", "freighter", "cargo"],
             description: "A colossal container ship riding the channel, stacked with steel boxes bound to or from the busy Port of Savannah.", isFixture: true))
    add(Item(id: "coastguard", name: "Coast Guard boat", nouns: ["coast", "guard", "cutter", "patrol"],
             description: "A bright, orange-striped Coast Guard boat throttling past on patrol.", isFixture: true))
    add(Item(id: "pilotboat", name: "river pilot boat", nouns: ["pilot", "pilotboat"],
             description: "A fast river pilot boat, out to put a harbor pilot aboard an inbound freighter for the run up to Savannah.", isFixture: true))

    // Lighthouse Overlook Trail.
    add(Item(id: "crabs", name: "fiddler crabs", nouns: ["crab", "crabs", "fiddler", "fiddlers"],
             description: "Mud fiddler crabs — the males waving one oversized claw — scattering sideways into their burrows as you pass.", isFixture: true))
    add(Item(id: "binoculars", name: "binoculars", nouns: ["binoculars", "scope"],
             description: "A pair of mounted binoculars fixed on the channel, trained across the marsh toward the lighthouse.", isFixture: true))
    add(Item(id: "lighthouse", name: "Cockspur Island Lighthouse", nouns: ["lighthouse", "cockspur", "light", "beacon"],
             description: "The Cockspur Island Lighthouse — the smallest in Georgia — on its oyster-shell bar, its base shaped like a ship's prow to cut the waves. It stood through the 1862 bombardment with thousands of shots passing overhead; it's closed to the public but plain to see from here.", isFixture: true))
    add(Item(id: "deck", name: "observation deck", nouns: ["deck", "overlook", "platform"],
             description: "A small wooden observation deck at the marsh's edge.", isFixture: true))

    // The fort itself (placeholder for a future update).
    add(Item(id: "fortwalls", name: "fort", nouns: ["fort", "pulaski", "walls", "drawbridge", "moat"],
             description: "Fort Pulaski itself — a massive brick fortress ringed by a moat, its far wall still scarred where Union rifled cannon breached it in 1862. Exploring the parade ground, the casemates, and the cannon-lined terreplein upstairs is coming in a future update.", isFixture: true))

    var rooms: [String: Room] = [:]
    func add(_ room: Room) { rooms[room.id] = room }

    add(Room(id: "gate", title: "Fort Pulaski Gates",
             description: "You drive in through the park gates and along the causeway across the marsh onto Cockspur Island. Ahead, the brick ramparts of Fort Pulaski rise behind their moat. The visitor center is just NORTH.",
             exits: [.north: "visitorCenter"],
             items: ["gates", "entrancesign"]))
    add(Room(id: "visitorCenter", title: "Visitor Center",
             description: "The Fort Pulaski visitor center: a cool room of exhibits and a bookstore, where Ranger Max waits at the desk to check you in. The fort's drawbridge is just INSIDE. A walking path leads NORTH toward the river, past Battery Hambright to the North Pier; the Lighthouse Overlook trailhead is EAST; and your car is parked back SOUTH.",
             exits: [.south: "gate", .inside: "fort", .north: "batteryHambright", .east: "trail1"],
             items: ["ranger", "exhibit"]))
    add(Room(id: "fort", title: "Fort Pulaski",
             description: "You cross the drawbridge into Fort Pulaski. The parade ground opens before you, casemates ringing the walls and a stone stair climbing to the terreplein — the upper level where the cannons stand watch over the river. (Exploring the fort inside and out, including the cannon-lined upstairs, is coming soon.) The visitor center is back OUTSIDE.",
             exits: [.outside: "visitorCenter"],
             items: ["fortwalls"]))
    add(Room(id: "batteryHambright", title: "Battery Hambright",
             description: "The path from the visitor center brings you to Battery Hambright, a low concrete gun battery set among the marsh grass, its gun wells empty and open to the sky. The North Pier lies ahead to the NORTH; the visitor center is back SOUTH.",
             exits: [.south: "visitorCenter", .north: "northPier"],
             items: ["battery", "marker"]))
    add(Room(id: "northPier", title: "Historic North Pier",
             description: "The Historic North Pier reaches out into the channel at the mouth of the Savannah River, where it opens to the Atlantic — a fine spot to watch the river traffic pass. Battery Hambright and the visitor center are back SOUTH.",
             exits: [.south: "batteryHambright"],
             items: ["pier", "containership", "coastguard", "pilotboat"]))

    // The Lighthouse Overlook Trail — four stops through marshy maritime woods,
    // walked FORWARD (deeper) and BACK (toward the fort).
    add(Room(id: "trail1", title: "Lighthouse Overlook — Trailhead",
             description: "A flat, sandy path slips into the maritime woods northeast of the fort, live oaks draped in Spanish moss overhead. Fiddler crabs scatter from the path ahead, big claws waving. The trail leads FORWARD into the marsh; the fort is BACK the way you came.",
             exits: [.north: "trail2", .south: "visitorCenter"],
             items: ["crabs"]))
    add(Room(id: "trail2", title: "Lighthouse Overlook — Into the Marsh",
             description: "The woods open onto broad stands of green cordgrass running to the horizon. Hundreds of fiddler crabs pour sideways into their burrows as your shadow falls across the mud. The path runs FORWARD and BACK.",
             exits: [.north: "trail3", .south: "trail1"],
             items: ["crabs"]))
    add(Room(id: "trail3", title: "Lighthouse Overlook — The Dike",
             description: "The path climbs onto an old earthen dike, oyster shells crunching underfoot and the salt smell strong on the breeze. More fiddler crabs scurry clear ahead. Continue FORWARD toward the overlook, or head BACK.",
             exits: [.north: "trail4", .south: "trail2"],
             items: ["crabs"]))
    add(Room(id: "trail4", title: "Lighthouse Overlook — The Deck",
             description: "A small wooden observation deck at the marsh's edge, a pair of mounted binoculars fixed on the channel. Out across the water stands the Cockspur Island Lighthouse. The trail runs BACK the way you came.",
             exits: [.south: "trail3"],
             items: ["deck", "binoculars", "lighthouse"]))

    return (rooms, items)
}

