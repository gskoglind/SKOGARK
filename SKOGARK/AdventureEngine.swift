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
        // "forward"/"back" read as north/south, for walking a linear trail,
        // and "next (stage)"/"onward" advance the same way.
        case "forward", "ahead", "fwd", "next", "onward": return .north
        case "back", "backward", "backwards": return .south
        case "ascend": return .up
        case "descend": return .down
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
    /// The destination the opening menu groups this adventure under
    /// ("Explore", "Savannah", "Japan", …).
    let destination: String
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
    /// Handles EXAMINE/LOOK AT of an item; return true if handled. Lets a
    /// scenario make looking at something matter (sights, spotting).
    var onExamine: ((Game, String) -> Bool)? = nil
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
    static let scenarios: [Scenario] = [houseScenario(), townScenario(), riverboatScenario(), fortPulaskiScenario(), roppongiScenario(), fujiScenario(), greenwichScenario()]

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
    func isCarrying(kind: String) -> Bool { inventory.contains { items[$0]?.kind == kind } }

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
            // "at" is stripped as filler, so any words after LOOK name a
            // thing to examine ("look at the bell" arrives as "look bell").
            if rest.isEmpty {
                describeCurrentRoom(force: true)
            } else if rest.contains("around") || rest.contains("here") {
                lookAround()
            } else {
                examine(rest)
            }
        case "what", "survey":
            lookAround()
        case "go", "walk", "run", "climb", "enter", "crawl", "cross",
             "board", "sail", "depart", "choose", "select", "ride", "catch", "join":
            // A bare CLIMB means climb UP (stairs, decks, the mountain).
            if verb == "climb", rest.isEmpty { move(.up) } else { handleGo(rest) }
        case "examine", "x", "inspect", "read", "watch", "view":
            if verb == "read" { readItem(rest) } else { examine(rest) }
        case "take", "get", "grab", "pick":
            take(rest.filter { $0 != "up" })
        case "drop":
            drop(rest)
        case "open":
            setOpen(rest, open: true)
        case "close", "shut":
            setOpen(rest, open: false)
        case "move", "push", "pull", "slide", "ring", "throw", "play", "stand", "straddle", "drink", "sip":
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
        case "sit", "rest":
            sitDown()
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
        // "stage" is filler so "NEXT STAGE" reads as the direction NEXT.
        let filler: Set<String> = ["the", "a", "an", "to", "at", "my", "some", "stage"]
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
        // Place names win over direction words embedded in them, so
        // "go to north pier" heads for the pier rather than reading "north".
        let nonDirectional = words.filter { Direction.from($0) == nil }
        if !nonDirectional.isEmpty {
            if let room = rooms[currentRoomID] {
                for (dir, destinationID) in room.exits
                where titleMatches(rooms[destinationID], nonDirectional) {
                    move(dir)
                    return
                }
            }
            if walkToward(nonDirectional) { return }
        }
        if let dir = words.compactMap({ Direction.from($0) }).first {
            move(dir)
            return
        }
        if let id = resolveItem(words), let dir = scenario.portalDirection?(self, id) {
            move(dir)
            return
        }
        emit("Go where?")
    }

    /// True when any of the player's words appears in the room's title.
    private func titleMatches(_ room: Room?, _ words: [String]) -> Bool {
        guard let room else { return false }
        let titleWords = Set(room.title.lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init))
        return words.contains { titleWords.contains($0) }
    }

    /// Walks toward a previously visited room the player names from anywhere
    /// ("go to the visitor center" from deep in the fort), following the
    /// shortest chain of exits one step at a time — every step is a real move,
    /// so gates still gate and each room announces itself. Returns false when
    /// no visited room matches the words.
    private func walkToward(_ words: [String]) -> Bool {
        guard rooms.values.contains(where: {
            $0.visited && $0.id != currentRoomID && titleMatches($0, words)
        }) else { return false }

        // Breadth-first search over exits to the nearest matching visited room.
        var queue: [String] = [currentRoomID]
        var cameFrom: [String: (room: String, dir: Direction)] = [:]
        var seen: Set<String> = [currentRoomID]
        var target: String? = nil
        while !queue.isEmpty {
            let id = queue.removeFirst()
            if id != currentRoomID, let room = rooms[id], room.visited, titleMatches(room, words) {
                target = id
                break
            }
            guard let room = rooms[id] else { continue }
            for (dir, dest) in room.exits where !seen.contains(dest) {
                seen.insert(dest)
                cameFrom[dest] = (id, dir)
                queue.append(dest)
            }
        }
        guard let target else { return false }

        var path: [Direction] = []
        var cursor = target
        while cursor != currentRoomID, let step = cameFrom[cursor] {
            path.append(step.dir)
            cursor = step.room
        }
        path.reverse()
        guard !path.isEmpty, path.count <= 10 else { return false }

        for direction in path {
            let before = currentRoomID
            move(direction)
            if currentRoomID == before { break }   // a gate blocked the way
        }
        return true
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
        // Always list the ways out — especially on revisits, when the full
        // description (and its woven-in directions) doesn't reprint.
        let exits = obviousExits()
        if !exits.isEmpty {
            lines.append("Obvious exits: \(exits.map { $0.rawValue }.joined(separator: ", ")).")
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
        if scenario.onExamine?(self, id) == true { return }
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
        emit("The \(item.name) is now \(on ? "on" : "off").")
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

    /// Sit on a bench or other seat in the room (any item of kind "seat").
    /// The seat's readText is the view from it; a plain line otherwise.
    private func sitDown() {
        moves += 1
        guard canSee else { emit("It's too dark to find a seat."); return }
        let visible = visibleItemIDs()
        guard let id = visible.first(where: { items[$0]?.kind == "seat" }),
              let seat = items[id] else {
            emit("There's nowhere comfortable to sit here.")
            return
        }
        emit(seat.readText ?? "You rest for a spell on the \(seat.name).")
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
            "  GO TO <place>         — walk back to somewhere you've visited",
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
            "  SIT                   — rest on a bench, where there is one",
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
            destination: "Explore",
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
            destination: "Explore",
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
            destination: "Savannah",
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
    /// Island. Drive in through the gates, check in at the visitor center,
    /// explore the fort inside and out — the parade ground, the gun casemates,
    /// the prison casemates of the Immortal 600, the cannon-lined terreplein
    /// upstairs with its river view, and the shell-scarred southeast angle on
    /// the moat walk — then head out past Battery Hambright to the North Pier
    /// and follow the Lighthouse Overlook Trail to the Cockspur Lighthouse.
    static func fortPulaskiScenario() -> Scenario {
        // The nine points of interest the visitor is here to see.
        let stops = ["checkedIn", "sawFort", "sawTerreplein", "sawPrison",
                     "sawSurrender", "sawBreach", "sawBattery", "sawPier", "sawLighthouse"]
        return Scenario(
            id: "fortPulaski",
            title: "Explore Fort Pulaski",
            destination: "Savannah",
            blurb: "Drive onto Cockspur Island to visit Fort Pulaski National Monument: check in at the visitor center, explore the fort from the parade ground to the cannon-lined terreplein, circle the moat to the shell-scarred walls, watch the ships from the North Pier, and follow the marsh trail to the Cockspur Lighthouse.",
            banner: """
            FORT PULASKI
            A visit to the National Monument on Cockspur Island. (c) 2026
            Type HELP for commands. Drive NORTH to the visitor center to check in.
            ─────────────────────────────
            """,
            startRoomID: "gate",
            maxScore: 60,
            startingCoins: 0,
            build: buildFortPulaskiWorld,
            fixtureLine: { _, id in
                // Wayfinding signs print on every visit, not just the first,
                // so the fort never leaves you guessing which way is which.
                switch id {
                case "paradeSign":
                    return "A wooden signpost points the way: gun casemates NORTH · prison casemates WEST · Colonel Olmstead's quarters SOUTH · terreplein cannons UP · sally port OUT."
                case "bridgeSign":
                    return "A small sign by the drawbridge: parade ground IN · moat walk SOUTH · visitor center OUT."
                case "ballplayers":
                    return "Across the grass, reenactors in Union blue are deep in a vintage game of base ball — bats cracking, cheers rolling off the casemate walls."
                default:
                    return nil
                }
            },
            onTalk: { game, id in
                guard id == "ranger" else { return false }
                let beenInside = game.has(flag: "sawFort")
                let beenNorth = game.has(flag: "sawBattery") || game.has(flag: "sawPier")
                let beenTrail = game.has(flag: "sawLighthouse")
                // Until the guest has explored somewhere, Max tells the fort's story.
                if !beenInside && !beenNorth && !beenTrail {
                    game.emit("Ranger Max leans on the desk. \"Fort Pulaski is named for Casimir Pulaski — a Polish nobleman and cavalry commander, the 'father of the American cavalry,' who fell leading a charge at the Siege of Savannah in 1779. The fort took eighteen years to build, and a young Lieutenant Robert E. Lee helped lay out its dikes. Everyone believed these seven-and-a-half-foot brick walls were invincible — until April 1862, when Union rifled cannon on Tybee Island breached them in about thirty hours and made every masonry fort in the world obsolete overnight. The fort itself is just INSIDE across the drawbridge — climb up top for the view, and walk the moat around to see what the cannon fire did. The path NORTH leads to Battery Hambright and the North Pier, and the Lighthouse Overlook Trail heads EAST.\"")
                    return true
                }
                // On return visits Max asks how the guest enjoyed wherever
                // they've been, then points toward what they haven't seen yet.
                // Remember what he's asked about so the visitor-center nudge
                // only fires when there's fresh news.
                if beenInside { game.set(flag: "toldMaxFort") }
                if game.has(flag: "sawPier") {
                    game.set(flag: "toldMaxPier")
                } else if game.has(flag: "sawBattery") {
                    game.set(flag: "toldMaxBattery")
                }
                if beenTrail { game.set(flag: "toldMaxTrail") }
                var talk = "Ranger Max looks up from the desk. \"Back again! "
                if beenInside {
                    if game.has(flag: "sawBreach") {
                        talk += "Did you enjoy the fort? I see you found the southeast angle — lay a hand on those shell scars and you're touching the exact spot where every masonry fort on earth went out of date. "
                    } else {
                        talk += "Did you enjoy the fort? Before you leave, walk the moat around to the southeast angle — you can still see where the shells came through in 1862. "
                    }
                }
                if game.has(flag: "sawPier") {
                    talk += "How was the North Pier — best ship-watching on the island, isn't it? Poor Lieutenant Hambright, though: last in his class at West Point, and his battery never fired a shot. "
                } else if game.has(flag: "sawBattery") {
                    talk += "Did you enjoy Battery Hambright? Named for the West Point 'Goat' of 1893, dead last in his class. Keep on up the path to the North Pier and watch the ships come in. "
                }
                if beenTrail {
                    talk += "And how was the lighthouse trail? Smallest lighthouse in Georgia — over five thousand shells passed right over her in 1862 and she never lost a brick. "
                }
                var left: [String] = []
                if !beenInside { left.append("the fort itself is just INSIDE across the drawbridge") }
                if !beenNorth { left.append("the path NORTH leads to Battery Hambright and the North Pier") }
                if !beenTrail { left.append("the Lighthouse Overlook Trail heads EAST") }
                if left.isEmpty {
                    talk += "You've made the full circuit — not much left I could tell you that you haven't seen with your own eyes.\""
                } else {
                    talk += "Still to see: " + left.joined(separator: ", and ") + ".\""
                }
                game.emit(talk)
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
                        game.win("You've seen it all: checked in with Ranger Max, crossed the drawbridge to the parade ground, stood among the cannons on the terreplein with the whole river spread below, paid your respects in the prison casemates, stood in the room where Colonel Olmstead gave up his sword, run your fingers over the shell-scarred southeast angle, watched the ships from the North Pier, and spied the Cockspur Lighthouse from the marsh trail. Fort Pulaski thanks you for visiting — come back any time.")
                    }
                }
                switch roomID {
                case "visitorCenter":
                    if !game.has(flag: "checkedIn") {
                        award("checkedIn", 5, "Ranger Max welcomes you to Fort Pulaski National Monument from behind the desk and checks you in. \"Cockspur Island has guarded the mouth of the Savannah River for a very long time — TALK TO MAX or READ the EXHIBIT to hear the story. The fort is just INSIDE, the riverside path to Battery Hambright and the North Pier is NORTH, and the Lighthouse Overlook Trail heads EAST. Take a PARK MAP from the desk — READ MAP any time for the lay of the land.\"")
                    } else if !game.isWon {
                        // Max waves the guest over when they come back with
                        // somewhere new to chat about since the last talk.
                        let news = (game.has(flag: "sawFort") && !game.has(flag: "toldMaxFort"))
                            || (game.has(flag: "sawPier") && !game.has(flag: "toldMaxPier"))
                            || (!game.has(flag: "sawPier") && game.has(flag: "sawBattery") && !game.has(flag: "toldMaxBattery"))
                            || (game.has(flag: "sawLighthouse") && !game.has(flag: "toldMaxTrail"))
                        if news {
                            game.emit("Ranger Max looks up from the desk and waves. \"Back from exploring? Come TALK to me when you have a minute — I'd love to hear how it went.\"")
                        }
                    }
                case "fort":
                    award("sawFort", 5, "You step through the sally port onto the parade ground — a broad green field ringed by brick casemate arches under the garrison flag. Eighteen years and some twenty-five million bricks went into these walls, finished in 1847, and a young Robert E. Lee helped engineer the site. The gun galleries are NORTH, the prison casemates WEST, and a stone stair climbs UP to the cannons on the terreplein.")
                    // The vintage base ball match is in full swing right here
                    // on the parade ground. Optional bonus.
                    if !game.has(flag: "sawBallgame") {
                        game.set(flag: "sawBallgame")
                        game.award(5, "Across the grass, a vintage base ball match is in full swing — bearded men in Union blue swatting a lemon-peel ball and legging it between the sacks, to whoops and hollers off the casemate walls. In 1862 the soldiers of the 48th New York played base ball on this very field, and a photographer caught them at it: one of the earliest photographs of the game ever taken. (WATCH the PLAYERS, or TALK to them.)")
                    }
                case "terreplein":
                    award("sawTerreplein", 10, "You come up onto the terreplein, the fort's open upper level, and the view stops you flat: the Savannah River spreading to the sea, container ships riding the channel, the little Cockspur Lighthouse on its shell bar below, and the low green line of Tybee Island across the water — where the Union gunners set their batteries in 1862. Great black cannons stand watch along the ramparts, muzzles out over the river they were built to close.")
                case "prison":
                    award("sawPrison", 5, "These dim casemates served as a prison. In the winter of 1864–65 they held the \"Immortal 600\" — Confederate officers confined here in the cold on scant rations; thirteen of them never left the island. Rough wooden bunks and names scratched into the brick remember them.")
                case "quarters":
                    award("sawSurrender", 5, "You step into Colonel Olmstead's quarters, kept much as they looked on April 11, 1862. Framed pictures on the wall show the scene: at 2:30 that afternoon, with the southeast wall breached and Union shells reaching for the twenty tons of powder in the magazine, the 25-year-old colonel — who had answered the surrender demand a day earlier with \"I am here to defend the fort, not to surrender it\" — handed his sword across this table to the Union officers. Days later, General David Hunter sent the sword back: the defense had been honorable. In the whole thirty-hour battle, only two men died — one from each side. The sword itself rests in the visitor center museum.")
                case "scarredWall":
                    award("sawBreach", 5, "Here it is — the reason this fort changed history. The southeast angle is pocked and cratered with shell strikes, and the smoother, darker patch of brick marks where the wall was breached and rebuilt. On April 10–11, 1862, Union rifled cannon on Tybee Island — a mile away, farther than any smoothbore could reach — chewed through these seven-and-a-half-foot walls in thirty hours. When shells began threatening the powder magazine, Colonel Olmstead surrendered, and every masonry fort on earth was obsolete by lunchtime.")
                case "batteryHambright":
                    award("sawBattery", 5, "You come to Battery Hambright, a squat concrete gun emplacement half-swallowed by the marsh grass, its gun wells empty and open to the sky. It's named for Lieutenant Horace G. Hambright — the West Point \"Goat\" of 1893, the cadet who graduates dead last in his class — a well-liked young officer who died out west in 1896 and was honored here in 1904. Poured about 1900 over a foundation of 30,000 bricks salvaged from the original fort village, it was built to guard the river mouth in the Spanish-American War era — yet it never received its guns and never fired a shot. Last in his class, and his battery never fired a shot: somehow it fits.")
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
                if !game.has(flag: "sawFort") { todo.append("the parade ground") }
                if !game.has(flag: "sawTerreplein") { todo.append("the cannons up on the terreplein") }
                if !game.has(flag: "sawPrison") { todo.append("the prison casemates") }
                if !game.has(flag: "sawSurrender") { todo.append("Colonel Olmstead's quarters") }
                if !game.has(flag: "sawBreach") { todo.append("the shell-scarred southeast angle") }
                if !game.has(flag: "sawBattery") { todo.append("Battery Hambright") }
                if !game.has(flag: "sawPier") { todo.append("the North Pier") }
                if !game.has(flag: "sawLighthouse") { todo.append("the Lighthouse Overlook") }
                if todo.isEmpty {
                    return (key: "done", clues: ["You've seen every stop — enjoy the view!"])
                }
                return (key: "todo:" + todo.joined(separator: "|"), clues: [
                    "Still to explore: \(todo.joined(separator: ", ")).",
                    "The fort is INSIDE from the visitor center: cross the drawbridge to the parade ground, with the gun casemates NORTH, the prison casemates WEST, Colonel Olmstead's quarters SOUTH, and stairs UP to the terreplein. From the drawbridge, SOUTH follows the moat around to the battered southeast wall.",
                    "Outside the fort: NORTH from the visitor center passes Battery Hambright to the North Pier, and the Lighthouse Overlook Trail heads EAST — go FORWARD four stops to the deck and its binoculars.",
                ])
            }
        )
    }

    /// Roppongi Pub Crawl: one loud, neon night out in Tokyo's most famous
    /// bar district. Ride the escalator up from the Hibiya Line into Roppongi
    /// Crossing, then work the classic gaijin circuit — ring the bell at
    /// Geronimo's shot bar, treat homesick Roy at tiny Mogambo's, and throw
    /// darts with the expat league at Bar Quest — before landing the night at
    /// the ramen stand as the sky goes pale. Every bar hangs a bell over the
    /// counter: RING it and you buy the whole bar a round, ringer's choice —
    /// and now and then another guest rings it, and you're included.
    static func roppongiScenario() -> Scenario {
        return Scenario(
            id: "roppongi",
            title: "Roppongi Pub Crawl",
            destination: "Japan",
            blurb: "One neon night in Tokyo's famous bar district: ring the bell at Geronimo's, treat a homesick regular at Mogambo's, throw darts at Bar Quest, then dawn ramen and the 05:12 first train home.",
            banner: """
            ROPPONGI PUB CRAWL
            One night out in Tokyo. (c) 2026
            Type HELP for commands. Ride the escalator UP to the crossing.
            ─────────────────────────────
            """,
            startRoomID: "roppongiStation",
            maxScore: 60,
            startingCoins: 50,
            build: buildRoppongiWorld,
            portalGate: { game, direction in
                // The first train only runs at dawn: the gates are shuttered
                // until the crawl is done and the ramen eaten.
                if game.roomID == "roppongiStation", direction == .inside,
                   !game.has(flag: "ateRamen") {
                    return "The ticket gates are shuttered and the platform is dark — the last train left at 00:24, and nothing runs until the 05:12 first train. (Finish the crawl and eat your ramen first.)"
                }
                return nil
            },
            fixtureLine: { game, id in
                guard let item = game.item(id) else { return nil }
                if item.forSale {
                    let name = item.name.prefix(1).uppercased() + item.name.dropFirst()
                    return "\(name) is on the menu — \(item.price) coins."
                }
                switch id {
                case "bellGeronimos":
                    return game.has(flag: "rangBell")
                        ? "The famous bell hangs quiet over the bar — you've already had your CLANG tonight."
                        : "Over the bar hangs THE bell. House rule: RING it and you buy the whole bar a round, ringer's choice."
                case "bellMogambos":
                    return game.has(flag: "rangBellMogambos")
                        ? "Mogambo's little bell hangs quiet, still swinging faintly from your round."
                        : "A little brass bell hangs over the counter. Same rule as everywhere in Roppongi: RING it, and the round's on you — ringer's choice."
                case "bellQuest":
                    return game.has(flag: "rangBellQuest")
                        ? "Quest's bell hangs quiet over the taps, its rope still warm from your big moment."
                        : "A ship's bell hangs over the taps. The plaque under it reads: RING FOR GLORY — ROUND FOR THE HOUSE, RINGER'S CHOICE."
                case "dartboard":
                    return game.has(flag: "threwDarts")
                        ? "The dartboard on the far wall still shows your lucky triple-20."
                        : "A battered dartboard waits on the far wall, the expat league eyeing fresh blood. (THROW DARTS to chalk in.)"
                case "ryan": return "Ryan works the rail of shot glasses behind the bar like a church organ."
                case "martin": return "Martin presides over the tiny bar, remembering everyone's name."
                case "roy": return "Roy, a big homesick Texan, nurses an empty glass at the end of the bar."
                case "matt": return "Matt pulls pints behind the long counter, keeping half an eye on the darts."
                case "cook": return "The cook tends his steaming pots behind the counter, towel knotted around his head."
                case "tout": return "A fast-talking tout works the corner, promising the best deals in Roppongi."
                case "salarymen": return "A knot of cheerful salarymen sways past, neckties knotted around their heads."
                default: return nil
                }
            },
            onMoveObject: { game, id in
                switch id {
                case "bellGeronimos":
                    if game.has(flag: "rangBell") {
                        game.emit("Ryan shakes his head, grinning. \"Once a night, champ. Legends pace themselves.\"")
                        return true
                    }
                    guard game.spend(15) else {
                        game.emit("Ringing the bell means buying the whole bar a round — 15 coins, and you have \(game.purse). Ryan gives you a look of genuine sympathy.")
                        return true
                    }
                    game.set(flag: "rangBell")
                    game.award(10, "You reach up and give the bell a mighty CLANG. The bar erupts. \"Ringer's choice!\" Ryan shouts, and you call it — tequila! — and a rank of shots goes rattling down the counter. Strangers pound your back; somebody asks how to spell your name for a plaque. Fifteen coins well spent: for one golden moment you are the most popular person in Roppongi. (You have \(game.purse) coins left.)")
                    return true
                case "bellMogambos":
                    if game.has(flag: "rangBellMogambos") {
                        game.emit("Martin catches your hand halfway to the rope. \"Pace yourself, friend. The night is long and the blender needs a rest.\"")
                        return true
                    }
                    guard game.spend(15) else {
                        game.emit("Mogambo's bell plays by Roppongi rules — a round for the house is 15 coins, and you have \(game.purse). Martin pretends not to have noticed you reaching.")
                        return true
                    }
                    game.set(flag: "rangBellMogambos")
                    game.emit("CLANG! \"Ringer's choice!\" Martin calls. \"Margaritas,\" you declare, and the blender roars like a jet on takeoff. Eight frozen margaritas for eight stools, and the whole bar toasts you by name — Martin's already learned it. (You have \(game.purse) coins left.)")
                    return true
                case "bellQuest":
                    if game.has(flag: "rangBellQuest") {
                        game.emit("Matt raises an eyebrow at the bell rope. \"Encore's extra, and your public can wait.\"")
                        return true
                    }
                    guard game.spend(15) else {
                        game.emit("Quest's bell means a round for the whole pub — 15 coins, and you have \(game.purse). Matt polishes a glass and lets the moment pass kindly.")
                        return true
                    }
                    game.set(flag: "rangBellQuest")
                    game.emit("CLANG! The whole pub turns. \"Ringer's choice!\" calls Matt. \"Pints all round!\" you announce, and the taps run bright while the darts corner drums the tables. Somebody starts the jukebox in your honor. (You have \(game.purse) coins left.)")
                    return true
                case "dartboard":
                    if game.has(flag: "threwDarts") {
                        game.emit("\"Another leg?\" the oil trader offers. You bow out while you're ahead — retire undefeated, that's the secret.")
                        return true
                    }
                    game.set(flag: "threwDarts")
                    game.award(10, "You chalk in with the expat league — an oil trader, two English teachers, and a bassist between gigs. Your first two darts wander wide. The third thuds home in the triple-20 and the corner erupts; Matt rings last orders off the back of it. You retire one leg up, a legend of exactly one leg.")
                    return true
                case "jukebox":
                    game.emit("You punch in your pick and 'Take Me Home, Country Roads' rolls out for the ninth time tonight. The entire pub sings the chorus. It is impossible not to.")
                    return true
                case "fareMachine":
                    if game.has(flag: "fareSettled") {
                        game.emit("The attendant already waved you through — the gate is open. Step back OUT.")
                        return true
                    }
                    game.set(flag: "fareSettled")
                    game.emit("You start jabbing at the 精算 machine — wrong buttons, no ticket, and a queue of exactly nobody behind you. The night-shift attendant watches the jet-lagged foreigner struggle for about four seconds, then just slides the gate open by hand with a small, tired bow. Far too much to explain at this hour; far easier to let you go. You bow back, twice, and step through. The gate is open — go OUT.")
                    return true
                default:
                    return false
                }
            },
            onGive: { game, gift, recipient in
                guard recipient == "roy" else { return false }
                if game.has(flag: "treatedRoy") {
                    game.emit("Roy raises what's left of the margarita to you. \"One's my limit, partner. Two and I start singin'.\"")
                    return true
                }
                guard game.item(gift)?.kind == "margarita" else {
                    game.emit("Roy eyes the \(game.item(gift)?.name ?? "offering") and shakes his head kindly. \"Mighty generous — but round here I only drink Martin's frozen margarita.\"")
                    return true
                }
                game.consumeFromInventory(gift)
                game.set(flag: "treatedRoy")
                game.award(10, "Roy takes the frozen margarita in both hands like it's the last helicopter out of somewhere. \"From Kenji? Well I'll be.\" One long pull and he's telling Galveston stories; by the second he's promised you a bed on the Gulf Coast any time you're passing. Martin gives you a quiet nod — you've done a good thing tonight.")
                return true
            },
            onTalk: { game, id in
                switch id {
                case "roy":
                    if game.has(flag: "treatedRoy") {
                        game.emit("\"You're alright, partner,\" Roy says, raising the frosty glass. \"Anybody gives you trouble tonight, you tell 'em Roy sent you.\"")
                    } else {
                        game.emit("\"Galveston,\" Roy sighs into his empty glass. \"You know what they don't got in this whole shining city? A decent frozen margarita.\" Behind the bar, Martin polishes a glass and nods meaningfully at the blender.")
                    }
                    return true
                case "cook":
                    var left: [String] = []
                    if !game.has(flag: "rangBell") { left.append("the bell at Geronimo's") }
                    if !game.has(flag: "treatedRoy") { left.append("Roy's margarita at Mogambo's") }
                    if !game.has(flag: "threwDarts") { left.append("darts at Quest") }
                    if left.isEmpty {
                        game.emit(game.has(flag: "ateRamen")
                            ? "\"05:12,\" the cook says, jerking his chin toward the crossing. \"First train. You'll make it.\""
                            : "\"Sit,\" the cook says, already reaching for a bowl.")
                    } else {
                        game.emit("The cook taps his ladle on the pot. \"Ramen is the period at the end of the sentence — not the middle. Still on your list: \(left.joined(separator: ", ")). Come back when the crawl is done.\"")
                    }
                    return true
                default:
                    return false
                }
            },
            onEnterRoom: { game, roomID in
                func award(_ flag: String, _ points: Int, _ note: String) {
                    guard !game.has(flag: flag) else { return }
                    game.set(flag: flag)
                    game.award(points, note)
                }
                // On a return visit to each bar, another guest rings the bell —
                // round for the house, ringer's choice, and you're included.
                // Once per bar, and never after the night has been won.
                func guestRingsBell(_ flag: String, _ note: String) {
                    guard !game.has(flag: flag), !game.isWon else { return }
                    game.set(flag: flag)
                    game.emit(note)
                }
                switch roomID {
                case "crossing":
                    award("hitTheTown", 5, "You ride the escalator up out of the station and Roppongi hits you all at once — neon stacked ten stories high, the Shuto Expressway thundering overhead on its great green legs, touts calling, taxis sweeping past, a hundred bars leaking a hundred songs. The night is officially on. (Kenji's NAPKIN has the plan, if you grabbed it.)")
                case "geronimos":
                    if !game.has(flag: "sawGeronimos") {
                        award("sawGeronimos", 5, "Up the narrow stairs and into Geronimo Shot Bar — small, loud, and famous on five continents. Brass plaques of honored drinkers plate every wall (READ them), Ryan holds court behind the bar, and everyone who walks in glances up at the bell. You did too.")
                    } else {
                        guestRingsBell("guestRangGeronimos", "CLANG! Before the door even shuts behind you, a just-promoted banker down the bar rings the bell. \"Ringer's choice — tequila!\" Shots for the whole house, and Ryan slides one your way without asking. House rules are house rules.")
                    }
                case "mogambos":
                    if !game.has(flag: "sawMogambos") {
                        award("sawMogambos", 5, "You duck into Mogambo's — a bar the size of a generous closet and warmer than most living rooms. Martin greets you from behind the counter like he's been expecting you for years. At the end of the bar, a big man in a pearl-snap shirt stares into an empty glass.")
                    } else {
                        guestRingsBell("guestRangMogambos", "As you settle back in, one of the eight stools stands up and rings the little bell — CLANG! \"Ringer's choice: margaritas, all around!\" Martin's blender roars like a jet engine, and yours arrives with extra salt. You didn't even have to ask.")
                    }
                case "quest":
                    if !game.has(flag: "sawQuest") {
                        award("sawQuest", 5, "Bar Quest: a proper pub transplanted whole into Tokyo — long oak counter, taps polished bright, a jukebox mid-singalong, and a darts corner where the expat league holds court. Matt nods you in. Nobody stays a stranger here longer than one pint.")
                    } else {
                        guestRingsBell("guestRangQuest", "CLANG! The night's darts winner rings the bell at the end of the bar. \"Ringer's choice — whisky, the good one!\" Matt walks the bottle down the line, you included. Rules are rules.")
                    }
                case "roppongiStation":
                    // The classic all-nighter bookends: come down too early
                    // and the last train is long gone; come down after the
                    // ramen and the 05:12 first train carries you home — the
                    // win.
                    if game.has(flag: "ateRamen"), !game.isWon {
                        if !game.has(flag: "boardedFirstTrain") {
                            game.set(flag: "boardedFirstTrain")
                            game.emit("Down the long escalator one last time. The platform is cool and near-empty, and at 05:12 the first Hibiya Line train of the morning slides in with its lights on. But there is no riding home for free — the TICKET MACHINES are INSIDE by the gates. BUY a TICKET, then step IN to board.")
                        }
                    } else if game.has(flag: "hitTheTown"), !game.has(flag: "sawShutters"), !game.isWon {
                        game.set(flag: "sawShutters")
                        game.emit("Down on the platform the shutters are half-drawn and the departure board is blank — the last train left at 00:24. No way home now but through the night. First train: 05:12. Better make it a night worth staying up for.")
                    }
                case "ramenya":
                    let done = game.has(flag: "rangBell") && game.has(flag: "treatedRoy") && game.has(flag: "threwDarts")
                    if done, !game.has(flag: "ateRamen") {
                        game.set(flag: "ateRamen")
                        game.award(10, "The cook takes one look at you and doesn't ask — a bowl of shoyu ramen lands on the counter, and it is the best thing anyone has ever eaten anywhere. You rang the bell at Geronimo's, fixed Roy's homesickness at Mogambo's, went one leg up on the darts league at Quest — and now the sky over the expressway is going pale. One thing left, and every Tokyo all-nighter ends the same way: the 05:12 first train. GO TO STATION when the bowl is empty — it's DOWN from the crossing.")
                    } else if !game.isWon {
                        game.emit("The cook looks up from his pots and reads you like a menu. \"Not yet,\" he says, not unkindly. \"Ramen is for AFTER the crawl. TALK to me if you've lost the thread.\"")
                    }
                case "trainCar":
                    game.emit("The doors chime shut and Roppongi slides away behind you. One stop — Kamiyachō — and the train eases in at your transfer. This is where you change: get OFF, go FORWARD onto the platform.")
                case "wrongTerminus":
                    if !game.has(flag: "wentWrong") {
                        game.set(flag: "wentWrong")
                        game.emit("Somewhere around the third unfamiliar station name it dawns on you — you never changed trains. By the time you surface it is two hours and a small fortune later, blinking at a terminus you have never heard of. Nothing for it but the long ride BACK to the transfer — and DOWN to your home line this time.")
                    }
                case "homeStation":
                    if !game.isWon {
                        if game.isCarrying(kind: "ticket") || game.has(flag: "fareSettled") {
                            game.win("You feed the ticket into the gate and the little flaps snap open — home. The street outside is going pink over the rooftops, the birds are up, and somewhere a train chimes off toward the day everyone else is starting. You made the 05:12, rode it home, and the perfect crawl is complete: the bell, the margarita, the darts, the ramen, and the last quiet leg through a waking city. Oyasumi.")
                        } else {
                            game.emit("You reach the gate and pat your pockets — no ticket. The flap stays shut with a soft beep of reproach. The 精算 fare-adjustment machine is right beside you: go IN, PUSH it to settle up, then come back OUT to the gate.")
                        }
                    }
                default:
                    break
                }
            },
            hintStage: { game in
                if !game.has(flag: "hitTheTown") {
                    return (key: "surface", clues: [
                        "The night is waiting at street level.",
                        "TAKE the NAPKIN and a MAP from the rack, then ride the escalator UP to Roppongi Crossing.",
                    ])
                }
                var todo: [String] = []
                if !game.has(flag: "rangBell") { todo.append(game.has(flag: "sawGeronimos") ? "ring the bell at Geronimo's" : "find Geronimo's shot bar") }
                if !game.has(flag: "treatedRoy") { todo.append(game.has(flag: "sawMogambos") ? "treat Roy at Mogambo's" : "find Mogambo's") }
                if !game.has(flag: "threwDarts") { todo.append(game.has(flag: "sawQuest") ? "throw darts at Bar Quest" : "find Bar Quest") }
                if todo.isEmpty {
                    if game.has(flag: "ateRamen") {
                        switch game.roomID {
                        case "ticketMachine":
                            return (key: "board", clues: [
                                "The gate at the far end is hungry — you'll want a ticket.",
                                "BUY TICKET, then step IN to board the 05:12.",
                            ])
                        case "trainCar":
                            return (key: "ride", clues: [
                                "One stop to the transfer — don't get comfortable.",
                                "Go FORWARD (off the train) when it slides into the transfer.",
                            ])
                        case "transferStation":
                            return (key: "change", clues: [
                                "Your home line leaves from Platform 2.",
                                "Go DOWN to Platform 2 — the train waiting at THIS platform runs the wrong way.",
                            ])
                        case "wrongTerminus":
                            return (key: "wrong", clues: [
                                "Everyone does this exactly once.",
                                "Ride BACK to the transfer, then DOWN to your home line.",
                            ])
                        case "homeStation", "fareAdjust":
                            return game.isCarrying(kind: "ticket") || game.has(flag: "fareSettled")
                                ? (key: "tapout", clues: [
                                    "You're one gate from a hot shower.",
                                    "Go OUT through the gate — you're home.",
                                ])
                                : (key: "fare", clues: [
                                    "No ticket — and the gate knows.",
                                    "Go IN to the fare-adjustment machines, PUSH the MACHINE to settle up, then back OUT through the gate.",
                                ])
                        default:
                            return (key: "train", clues: [
                                "One thing left — the 05:12 first train home.",
                                "GO TO STATION (DOWN from Roppongi Crossing), BUY a TICKET at the gates INSIDE, then board the train IN.",
                            ])
                        }
                    }
                    return (key: "ramen", clues: [
                        "The crawl is done — and every good Tokyo night ends the same way.",
                        "Follow the red lantern: the ramen stand is SOUTH off the side street.",
                    ])
                }
                return (key: "todo:" + todo.joined(separator: "|"), clues: [
                    "Still on the crawl: \(todo.joined(separator: ", ")). (Kenji's napkin has the plan.)",
                    "Geronimo's is UP the stairs right at the crossing. The side street EAST of the crossing leads to Mogambo's (NORTH) and Bar Quest (EAST), with the ramen stand SOUTH.",
                    "At Geronimo's: RING BELL (15 coins — a round for the house, ringer's choice). At Mogambo's: BUY MARGARITA, then GIVE MARGARITA TO ROY. At Quest: THROW DARTS.",
                ])
            }
        )
    }

    /// Mount Fuji: a night climb of the Yoshida Trail from the Fuji Subaru
    /// Line Fifth Station to the summit. Gear up at the fifth-station shop —
    /// the traditional kongō-zue walking stick and a headlamp — then climb
    /// station by station, earning each hut's brand burned into the stick.
    /// The weather is rolled fresh each game at the sixth station: on a rain
    /// or cold-wind night the stretch above the Eighth is impassable without
    /// a storm jacket or a paid rest by the hut stove. Reach the goraiko
    /// sunrise at the summit torii, linger over the crater rim, Ken-ga-mine,
    /// and the highest post office in Japan — then seal the climb (and win)
    /// by earning the summit brand at Kusushi Shrine.
    static func fujiScenario() -> Scenario {
        return Scenario(
            id: "fuji",
            title: "Climb Mount Fuji",
            destination: "Japan",
            blurb: "A night climb of the Yoshida Trail from the Fifth Station: earn every hut's brand on a kongō-zue walking stick, weather whatever the mountain throws at you, greet the goraiko sunrise, and seal the climb with the summit brand at the very top of Japan.",
            banner: """
            MOUNT FUJI
            A night climb of the Yoshida Trail. (c) 2026
            Type HELP for commands. Gear up at the lodge, then climb UP, stage by stage.
            ─────────────────────────────
            """,
            startRoomID: "fifthStation",
            maxScore: 60,
            startingCoins: 50,
            build: buildFujiWorld,
            portalGate: { game, direction in
                guard game.roomID == "eighthHut", direction == .north || direction == .up else { return nil }
                if !game.inventoryKinds().contains("headlamp") {
                    return "The hut keeper steps into the trail, kind but immovable. \"Nobody goes above the Eighth at night without a light. The lodge shop sells HEADLAMPS — GO TO LODGE and gear up; the mountain will wait.\""
                }
                // Weather rolled at the sixth station: rain or bitter wind
                // closes the exposed final stretch until the climber shelters
                // with the keeper or carries a storm jacket.
                let sheltered = game.has(flag: "weatherReady") || game.inventoryKinds().contains("jacket")
                if game.has(flag: "weatherRain"), !sheltered {
                    return "Above the Eighth the squall owns the trail — rain flying sideways, headlamps turning back. The keeper shakes his head: \"Not into that without a shell. TALK to me and wait it out warm — or a STORM JACKET from the fifth station would see you through.\""
                }
                if game.has(flag: "weatherCold"), !sheltered {
                    return "The north wind comes over the ridge like a wall — stinging cold, climbers hunching back into the hut. The keeper catches your sleeve: \"Not into that unprotected. TALK to me and warm up first — or a STORM JACKET would cut it.\""
                }
                return nil
            },
            exitHidden: { _, direction in
                // The mountain speaks in UP and DOWN. North/south still work
                // (FORWARD, NEXT STAGE) but shadow the canonical climb exits,
                // so they stay out of the listings.
                direction == .north || direction == .south
            },
            fixtureLine: { game, id in
                guard let item = game.item(id) else { return nil }
                if item.forSale {
                    let name = item.name.prefix(1).uppercased() + item.name.dropFirst()
                    return "\(name) is for sale here — \(item.price) coins."
                }
                switch id {
                case "keeper7":
                    return game.has(flag: "brand7")
                        ? "Tomoekan's keeper tends the branding iron in the fire, your stick's fresh brand still fragrant."
                        : "Tomoekan's keeper tends a branding iron glowing in the fire. (GIVE your STICK to the KEEPER for the hut's brand — 3 coins.)"
                case "keeper8":
                    return game.has(flag: "brand8")
                        ? "Taishikan's keeper nods at the twin brands on your stick with professional approval."
                        : "Taishikan's keeper stands ready at the fire with the hut's iron. (GIVE your STICK to the KEEPER for the brand — 3 coins.)"
                case "shopkeeper": return "The shopkeeper arranges walking sticks, headlamps, and storm jackets with equal ceremony."
                case "guide":
                    return game.has(flag: "brand6")
                        ? "The mountain guide waves climbers through, your stick's trailhead brand already vouching for you."
                        : "A mountain guide checks climbers through beside a small brazier. (GIVE your STICK to the GUIDE for the trailhead brand — 3 coins.)"
                case "priest":
                    return "A shrine priest tends Kusushi Shrine's branding fire. (Once your stick carries every hut's mark, GIVE it to the PRIEST for the summit brand — 5 coins — and the climb is sealed.)"
                case "clerk": return "The postal clerk waits behind the little counter, stamps at the ready."
                case "horses": return "Pack horses doze by the trailhead, unimpressed by the altitude."
                default: return nil
                }
            },
            onGive: { game, gift, recipient in
                guard ["guide", "keeper7", "keeper8", "priest"].contains(recipient) else { return false }
                guard game.item(gift)?.kind == "stick" else {
                    game.emit("A smile, a wave of the hand — the branding iron is for walking sticks. (The fifth-station shop sells the traditional kongō-zue.)")
                    return true
                }
                // The summit brand at Kusushi Shrine crowns a finished stick
                // and seals the climb — this is the win.
                if recipient == "priest" {
                    var missing: [String] = []
                    if !game.has(flag: "brand6") { missing.append("the trailhead brand (6th station)") }
                    if !game.has(flag: "brand7") { missing.append("Tomoekan's brand (7th station)") }
                    if !game.has(flag: "brand8") { missing.append("Taishikan's brand (8th station)") }
                    if !missing.isEmpty {
                        game.emit("The priest turns your stick gently, reading its marks, and shakes his head. \"The summit brand crowns a finished stick. You are missing: \(missing.joined(separator: ", ")). The huts below will gladly mend that — the mountain is patient.\"")
                        return true
                    }
                    if game.has(flag: "summitBrand") {
                        game.emit("Your kongō-zue already carries the summit brand — there is no higher mark to give it.")
                        return true
                    }
                    guard game.spend(5) else {
                        game.emit("The summit brand is 5 coins, and you have \(game.purse). The priest bows — the shrine can wait, but it cannot haggle.")
                        return true
                    }
                    game.set(flag: "summitBrand")
                    var note = "The priest draws the iron from the shrine's fire, and with a hiss the summit brand crowns your kongō-zue — the final mark above the three earned below. The stick tells the entire story now: fifth station to the sky."
                    if game.has(flag: "weatherRain") {
                        note += " It tells the rain, too — anyone who reads it will know the night the mountain tested you."
                    } else if game.has(flag: "weatherCold") {
                        note += " It remembers the wind, too — anyone who reads it will know the night the mountain tested you."
                    }
                    note += " One thing remains, and the priest says it for you: \"Someone at home is waiting to hear. The post office is just inside the torii.\""
                    game.award(10, note)
                    return true
                }
                // The station brands on the way up.
                let hut: (flag: String, name: String, note: String) =
                    recipient == "guide" ? ("brand6", "the trailhead",
                        "The guide grins, pulls the trailhead iron from the little brazier beside the safety center, and burns the first mark into your kongō-zue. \"There. Now the stick is honest.\" One brand down, the mountain to go.")
                    : recipient == "keeper7" ? ("brand7", "Tomoekan",
                        "The keeper takes your kongō-zue, lays the glowing iron against it, and Tomoekan's brand chars crisply into the wood — smoke, cedar, ceremony. He hands it back with both hands and a small bow.")
                    : ("brand8", "Taishikan",
                        "Taishikan's iron hisses against the wood beside the marks already earned — station by station, the stick is becoming a story. The keeper studies his work, nods once, and returns it like a sword being sheathed.")
                if game.has(flag: hut.flag) {
                    game.emit("Your stick already carries \(hut.name)'s brand — one per station, that's the tradition.")
                    return true
                }
                guard game.spend(3) else {
                    game.emit("The brand is 3 coins, and you have \(game.purse). The iron goes back in the fire apologetically.")
                    return true
                }
                game.set(flag: hut.flag)
                game.award(5, hut.note + " (You have \(game.purse) coins left.)")
                return true
            },
            onPut: { game, object, target in
                // The finale: at the tenth station, the letter home to Mom
                // goes into the red postbox — and that wins the climb.
                guard target == "postbox", game.item(object)?.kind == "letter" else { return }
                game.award(10, nil)
                var closing = "The clerk cancels the stamp with a soft, official thump — MOUNT FUJI SUMMIT POST OFFICE — and the letter home to Mom begins its journey down the mountain in a mail sack, carrying the whole night inside it: the stations, the stove smoke, the sea of clouds catching fire at dawn."
                let fullStick = game.has(flag: "brand6") && game.has(flag: "brand7")
                    && game.has(flag: "brand8") && game.has(flag: "summitBrand")
                if fullStick {
                    closing += " Beside you leans a kongō-zue burned with every brand from the trailhead to the sky — but Mom gets the news first. That's the rule, and it's a good one."
                }
                if game.has(flag: "weatherRain") {
                    closing += " Outside, the last of the rain is drying off the rocks, already turning into a better story."
                } else if game.has(flag: "weatherCold") {
                    closing += " Outside, the north wind has given up, which is more than it can say for you."
                }
                game.win(closing)
            },
            onTalk: { game, id in
                switch id {
                case "shopkeeper":
                    game.emit("\"Climbing tonight?\" The shopkeeper sizes you up and taps the counter. \"Then you'll want the kongō-zue — the walking stick. Every station on the trail burns its brand into it, and the shrine at the summit burns the last; come down with a full stick and you'll never need to tell the story, it tells itself. A HEADLAMP too — it's dark above the Eighth. A STORM JACKET, if the mountain turns rough. And a POSTCARD-sized LETTER, if you know anyone at home waiting to hear from the top of Japan.\"")
                    return true
                case "guide":
                    var talk: String
                    if game.has(flag: "weatherRain") {
                        talk = "\"Rain on the way,\" the guide says, sniffing the wind. \"You'll feel it above the Eighth — a STORM JACKET sheds it, or shelter at Taishikan until it passes. The huts have food and fire; use them."
                    } else if game.has(flag: "weatherCold") {
                        talk = "\"North wind tonight,\" the guide says, zipping his collar to the chin. \"Bitter cold on the final stretch. A STORM JACKET blunts it, or warm up at Taishikan before the push. The huts have food and fire; use them."
                    } else {
                        talk = "\"Clear and calm,\" the guide says, patting the air with both hands. \"The mountain is in a good mood — it isn't always. Slowly, slowly: climbed with the legs, summited with the lungs."
                    }
                    talk += game.has(flag: "brand6")
                        ? " And sit a while at every stage — the views climb with you.\""
                        : " And GIVE me that STICK before you go up — the trailhead brand starts the collection.\""
                    game.emit(talk)
                    return true
                case "clerk":
                    game.emit("\"Welcome to the top of Japan,\" the clerk says, entirely serious. \"Highest post office in the country, and the best mail we handle is the kind that goes home. PUT your LETTER IN the POSTBOX and we'll do the rest — the postmark says Mount Fuji, and mothers frame that sort of thing.\"")
                    return true
                case "priest":
                    game.emit("\"You made the sunrise,\" the priest says, as if confirming a fact about the weather. \"When your stick carries every station's mark, GIVE it here and the shrine will burn the summit brand — the climb, sealed. But the top rewards lingering: the crater rim is EAST, and the post office is just INSIDE the torii. The mountain does not hurry, and neither should you.\"")
                    return true
                case "keeper7", "keeper8":
                    // On a foul-weather night, Taishikan's keeper offers the
                    // shelter that reopens the trail above — and never leaves
                    // a broke climber out in it.
                    if id == "keeper8",
                       game.has(flag: "weatherRain") || game.has(flag: "weatherCold"),
                       !game.has(flag: "weatherReady") {
                        game.set(flag: "weatherReady")
                        if game.spend(4) {
                            game.emit(game.has(flag: "weatherRain")
                                ? "The keeper pulls you in by the stove. Hot noodles, steam on the windows, rain drumming the roof like applause — and then, gradually, not. The squall rattles off down the valley and the stars come back out. (4 coins well spent — the trail above is yours.)"
                                : "The keeper sits you by the stove with hot cocoa until the feeling returns to your fingers. Outside, the wind drops from a howl to a mutter. \"Now,\" he says, \"now you're ready.\" (4 coins well spent — the trail above is yours.)")
                        } else {
                            game.emit("You turn out your pockets — not enough. The keeper waves it off and pulls you in anyway. \"Mountain code. Pay me on the way down.\" Noodles, stove, and by the time you're warm again, the weather has moved on. The trail above is yours.")
                        }
                        return true
                    }
                    let flag = id == "keeper7" ? "brand7" : "brand8"
                    if game.has(flag: flag) {
                        game.emit("\"Good brand, good climb,\" the keeper says, glancing at your stick. \"The summit is waiting — slowly, slowly. And the bench out front has the best view on the mountain, if you ask me. SIT a while.\"")
                    } else {
                        game.emit("\"Rest a moment,\" the keeper says, nodding at the fire where the branding iron glows. \"There's food at the counter and a bench with a view. And if you carry the kongō-zue, GIVE it here — every station burns its own mark, and this one is ours. Three coins, and it lasts a lifetime.\"")
                    }
                    return true
                default:
                    return false
                }
            },
            onEnterRoom: { game, roomID in
                func award(_ flag: String, _ points: Int, _ note: String) {
                    guard !game.has(flag: flag) else { return }
                    game.set(flag: flag)
                    game.award(points, note)
                }
                switch roomID {
                case "sixthStation":
                    // The mountain rolls its weather once per game, announced
                    // by the guide at the safety center. The roll is stored in
                    // flags, so SAVE/RESTORE keeps the same night.
                    guard !game.has(flag: "weatherRolled") else { break }
                    game.set(flag: "weatherRolled")
                    switch Int.random(in: 0..<3) {
                    case 0:
                        game.set(flag: "weatherClear")
                        game.emit("At the safety center the guide reads the sky like a menu. \"Clear and calm tonight — the mountain is in a good mood. It isn't always. Go gently, and enjoy the view from every stage.\"")
                    case 1:
                        game.set(flag: "weatherRain")
                        game.emit("The guide sniffs the wind and frowns. \"Smell that? Rain, coming up the valley. It'll catch the trail above the Eighth before you do. A STORM JACKET sheds it — or shelter at Taishikan until it blows through. The huts have food and fire; use them.\"")
                    default:
                        game.set(flag: "weatherCold")
                        game.emit("The guide zips his collar to the chin. \"North wind tonight — bitter cold on the final stretch, the kind that argues. A STORM JACKET blunts it, or warm up at Taishikan before the push. The huts have food and fire; use them.\"")
                    }
                case "summit":
                    award("sawSummit", 15, "You haul yourself up the last worn steps, under the summit torii — and stop. The east is turning. Below you lies a sea of clouds to the edge of the world, and as you watch, the sun breaks over it — the goraiko, the honored arrival of light — spilling gold across the cloud tops while every climber on the rim raises their arms and shouts \"Banzai!\" three times into the dawn. You came up a mountain in the dark, and this is what was waiting.")
                case "kengamine":
                    award("sawKengamine", 10, "One last rise — and there is nothing above you. Ken-ga-mine, 3,776 meters: the highest point of Mount Fuji, and of Japan, marked by a worn stone pillar every climber touches. The old weather-radar dome kept watch here for forty years; now it's just you, the thin bright air, and the entire country arranged politely below.")
                default:
                    break
                }
            },
            hintStage: { game in
                let kinds = game.inventoryKinds()
                if !(kinds.contains("stick") && kinds.contains("headlamp")) {
                    return (key: "gear", clues: [
                        "A proper climb starts with proper gear — TALK to the SHOPKEEPER, and TAKE a trail MAP from the counter.",
                        "BUY the STICK and the HEADLAMP — and mind the forecast: a STORM JACKET and a LETTER home round out the kit. Then climb UP, stage by stage.",
                    ])
                }
                if game.roomID == "ninthStation", !game.canSeeRoom {
                    return (key: "dark", clues: [
                        "It's pitch black on the upper trail.",
                        "TURN ON your HEADLAMP.",
                    ])
                }
                if game.roomID == "eighthHut",
                   game.has(flag: "weatherRain") || game.has(flag: "weatherCold"),
                   !game.has(flag: "weatherReady"), !kinds.contains("jacket") {
                    return (key: "weather", clues: [
                        "The weather owns the trail above the Eighth tonight.",
                        "TALK to the KEEPER to shelter with hot food until it passes (4 coins) — or a STORM JACKET from the fifth station gets you through it.",
                    ])
                }
                var todo: [String] = []
                if !game.has(flag: "brand6") { todo.append("the trailhead brand (6th station — the GUIDE)") }
                if !game.has(flag: "brand7") { todo.append("Tomoekan's brand (7th station)") }
                if !game.has(flag: "brand8") { todo.append("Taishikan's brand (8th station)") }
                if !todo.isEmpty {
                    return (key: "brands:" + todo.joined(separator: "|"), clues: [
                        "Still to burn into your stick: \(todo.joined(separator: ", ")).",
                        "At each station, GIVE STICK TO the brander — 3 coins a mark. The trail climbs UP (or NEXT STAGE), with food, benches, and views at every stage. GO TO LODGE any time you need the shop.",
                    ])
                }
                if !game.has(flag: "sawSummit") {
                    return (key: "climb", clues: [
                        "Every station brand is burned — now it's just you and the mountain.",
                        "Keep climbing UP. Above the Eighth it gets dark — TURN ON your HEADLAMP — and the goraiko waits at the top.",
                    ])
                }
                if !game.has(flag: "summitBrand") {
                    return (key: "seal", clues: [
                        "The shrine at the tenth station crowns a finished stick.",
                        "GIVE your STICK TO the PRIEST at Kusushi Shrine — 5 coins — for the summit brand.",
                    ])
                }
                if !game.has(flag: "sawKengamine") {
                    return (key: "kengamine", clues: [
                        "The torii isn't quite the top — the true summit is across the crater.",
                        "Head EAST to the crater rim, then UP to Ken-ga-mine. (And SIT anywhere along the way — the views are the point.)",
                    ])
                }
                return (key: "mom", clues: [
                    "One thing remains, and it isn't for you — someone at home is waiting to hear.",
                    kinds.contains("letter")
                        ? "The post office is just INSIDE the torii — PUT the LETTER IN the POSTBOX, and the climb is complete."
                        : "The post office INSIDE the torii sells letters — BUY one, then PUT the LETTER IN the POSTBOX, and the climb is complete.",
                ])
            }
        )
    }

    /// Greenwich Park: a London afternoon by the meridian. Step off the
    /// Thames Clipper at Greenwich Pier, walk beneath the Cutty Sark, meet
    /// Nelson's coat at the National Maritime Museum, climb the chestnut
    /// avenue to the Royal Observatory and straddle the Prime Meridian —
    /// then take the bench by the Wolfe statue, where the game turns from
    /// going to looking: spot Canary Wharf, the O2, and the London Eye from
    /// your seat, and share your hazelnuts with a squirrel.
    static func greenwichScenario() -> Scenario {
        // The eight marks of a perfect Greenwich afternoon; the walk home to
        // Blackheath, with all of them done, is the win.
        let stops = ["sawCutty", "sawMuseum", "straddled",
                     "spotCanary", "spotO2", "spotEye", "fedSquirrel", "hadBeer"]
        let finishIfDone: (Game) -> Void = { game in
            guard stops.allSatisfy({ game.has(flag: $0) }), !game.has(flag: "readyHome") else { return }
            game.set(flag: "readyHome")
            game.emit("And that's the whole afternoon, done properly. Nothing left but the best part: the amble home — Blackheath is SOUTH, out across the heath.")
        }
        return Scenario(
            id: "greenwich",
            title: "Greenwich Park",
            destination: "London",
            blurb: "The commute-home detour: off the DLR from Canary Wharf at Cutty Sark station, under the tea clipper, past Nelson's coat, up to the Prime Meridian — then the bench above London, spotting the skyline you just left, with hazelnuts for the squirrels.",
            banner: """
            GREENWICH PARK
            A London afternoon by the meridian. (c) 2026
            Type HELP for commands. The Cutty Sark is just UP the station steps.
            ─────────────────────────────
            """,
            startRoomID: "dlrStation",
            maxScore: 60,
            startingCoins: 12,
            build: buildGreenwichWorld,
            exitHidden: { game, direction in
                // On the hill legs, UP/DOWN are synonyms of the compass exits;
                // keep those listings to one of each. (At the DLR station and
                // the ship, UP/DOWN are the real exits and stay visible.)
                (direction == .up || direction == .down)
                    && ["parkLawn", "chestnutAvenue", "observatory"].contains(game.roomID)
            },
            fixtureLine: { game, id in
                guard let item = game.item(id) else { return nil }
                if item.forSale {
                    let name = item.name.prefix(1).uppercased() + item.name.dropFirst()
                    return "\(name) — \(item.price) coins at the kiosk."
                }
                switch id {
                case "meridian":
                    return game.has(flag: "straddled")
                        ? "The brass meridian line runs across the courtyard, already conquered — one foot per hemisphere."
                        : "A brass line runs across the courtyard: the Prime Meridian of the world. (STRADDLE THE LINE — one foot in each hemisphere.)"
                case "kioskLady":
                    return "The kiosk lady keeps the teas coming and the hazelnut supply steady."
                case "squirrel":
                    return "A grey squirrel loiters at polite arm's length, monitoring developments."
                default:
                    return nil
                }
            },
            onMoveObject: { game, id in
                // DRINK BEER — but only where it belongs: on the bench.
                if game.item(id)?.kind == "beer" {
                    if game.roomID != "wolfeViewpoint" {
                        game.emit("Not yet. This beer has exactly one correct location — the bench at the top of the park. It's the law of the hill.")
                        return true
                    }
                    if game.has(flag: "hadBeer") {
                        game.emit("The empty can is already crackling contentedly beside you on the bench.")
                        return true
                    }
                    game.consumeFromInventory(id)
                    game.set(flag: "hadBeer")
                    game.award(10, "You crack the can — that first pssht doing exactly what it always does — and settle back on the bench with the whole city arranged below. Cold beer, warm light, squirrels auditing the area, London politely getting on without you. Whoever invented this routine deserves a statue next to Wolfe's.")
                    finishIfDone(game)
                    return true
                }
                guard id == "meridian" else { return false }
                if game.has(flag: "straddled") {
                    game.emit("You've already had your moment astride the world — though nobody would blame you for a second one. The queue behind you might.")
                    return true
                }
                game.set(flag: "straddled")
                game.award(15, "You plant one foot on each side of the brass strip — east in one hemisphere, west in the other, longitude zero running exactly between your shoes. And as if the Observatory approves, the red Time Ball on Flamsteed House climbs its mast and, at 13:00 precisely — Greenwich Mean Time, measured from the very line between your feet — drops. Since 1833, ships on the Thames have set their clocks by that fall. Today it might as well be saluting you.")
                finishIfDone(game)
                return true
            },
            onGive: { game, gift, recipient in
                guard recipient == "squirrel" else { return false }
                if game.has(flag: "fedSquirrel") {
                    game.emit("The squirrel pats its cheeks — full — and performs a slow cartwheel of gratitude along the railing instead.")
                    return true
                }
                guard game.item(gift)?.kind == "nut" else {
                    game.emit("The squirrel inspects the offering from a safe distance, decides you can do better, and returns to the branch. (The park kiosk sells hazelnuts.)")
                    return true
                }
                game.consumeFromInventory(gift)
                game.set(flag: "fedSquirrel")
                game.award(10, "You hold a hazelnut out on your palm and keep very still. The grey squirrel flows down the oak in three quick spirals, pauses, judges you thoroughly — and takes it from your fingers, sitting up to eat it right there on the bench arm, tail curled like a question mark. Two of its colleagues immediately begin a formal audit of your pockets. You have been accepted.")
                finishIfDone(game)
                return true
            },
            onTalk: { game, id in
                switch id {
                case "squirrel":
                    game.emit(game.has(flag: "fedSquirrel")
                        ? "The squirrel chirrs at you in a companionable way and stays within arm's reach — you're one of the good ones now."
                        : "The squirrel fixes you with one bright eye and chitters something that is unmistakably a question about snacks. (The kiosk down the hill sells hazelnuts.)")
                    return true
                case "kioskLady":
                    game.emit("\"Lovely afternoon for it,\" the kiosk lady says, restocking the hazelnuts. \"Nuts are for the squirrels up by the statue — they'll take them right off your hand if you keep still. Ice cream's for you. And if you haven't stood on the line yet, do — everyone pretends they're too grown-up for it, and nobody is.\"")
                    return true
                default:
                    return false
                }
            },
            onExamine: { game, id in
                // The bench view: looking IS the sightseeing. Each landmark
                // spotted from the Wolfe viewpoint is scored once.
                func spot(_ flag: String, _ points: Int, _ text: String) -> Bool {
                    if game.has(flag: flag) {
                        game.emit(text)
                    } else {
                        game.set(flag: flag)
                        game.award(points, text)
                        finishIfDone(game)
                    }
                    return true
                }
                switch id {
                case "canaryWharf":
                    return spot("spotCanary", 5, "Canary Wharf, straight ahead across the river bend — the cluster of glass towers you rode out of an hour ago, One Canada Square's pyramid roof winking in the light, the DLR threading between the buildings like a toy. From up here the whole money-machine looks quiet, like a model of itself, and the day's work seems a very long way below. The squirrels are unimpressed, which feels correct.")
                case "o2":
                    return spot("spotO2", 5, "Off to the right on its peninsula sits the O2 — the old Millennium Dome — a great white tent pinned down by twelve yellow masts, one for each month, looking exactly like a spaceship that decided to stay. You can just make out the little figures of people walking over its roof.")
                case "londonEye":
                    return spot("spotEye", 5, "Far off to the left, past the towers of the City, the London Eye turns so slowly you have to trust it rather than see it — a pale wheel standing over the river, with St Paul's dome holding its ground among the glass nearby. All of London, in one patient look.")
                default:
                    return false
                }
            },
            onEnterRoom: { game, roomID in
                func award(_ flag: String, _ points: Int, _ note: String) {
                    guard !game.has(flag: flag) else { return }
                    game.set(flag: flag)
                    game.award(points, note)
                    finishIfDone(game)
                }
                switch roomID {
                case "cuttySark":
                    award("sawCutty", 5, "There she is — the Cutty Sark, the fastest tea clipper of her age, raised on glass above her dry dock so you can walk clean underneath a hull that once did Shanghai to London with the year's first tea. Her name is pure Robert Burns: the witch Nannie in her 'cutty sark' — her short shirt — who tore the tail from Tam o' Shanter's horse, and the gilded figurehead still brandishes that horsehair. Under the copper-sheathed hull, the whole ship balances above you like held breath.")
                case "maritimeMuseum":
                    award("sawMuseum", 5, "The National Maritime Museum — the largest of its kind in the world, and free as the wind. In a quiet case hangs the exhibit that stops everyone: Nelson's own Trafalgar coat, the bullet hole from the fatal musket ball still in the left shoulder, the stain never cleaned. Around it, a navy's worth of figureheads, ship models, and gilded barges. (READ the EXHIBIT for the story.)")
                case "wolfeViewpoint":
                    if !game.has(flag: "sawViewpoint") {
                        game.set(flag: "sawViewpoint")
                        game.emit("You come out at the statue of General Wolfe and the ground simply stops — all of London opens below the hill. This is a place for sitting, not walking: take the BENCH, and LOOK at things — CANARY WHARF, the O2, the LONDON EYE. The squirrels will find you, and the walk home to Blackheath waits SOUTH across the heath.")
                    }
                case "blackheath":
                    if stops.allSatisfy({ game.has(flag: $0) }), !game.isWon {
                        game.win("You finish the last of the light on the long diagonal across the park, give the squirrel sentry at the gate a nod of colleagues parting, and come out onto the heath — wide, flat, and gold, a kite or two up, the village lights coming on across the grass. Home to Blackheath, the long way round: the ship, the coat, the line, the view, the squirrel, the beer on the bench. The perfect commute, door to door. Kettle on.")
                    } else if !game.isWon {
                        game.emit("The heath opens ahead and home is just across it — but the afternoon isn't finished with you yet. The park, the bench, and the rest of the ritual are back NORTH. (HINT knows what's left.)")
                    }
                default:
                    break
                }
            },
            hintStage: { game in
                if !game.has(flag: "sawCutty") {
                    return (key: "cutty", clues: [
                        "The whole point of getting off at this stop is waiting at the top of the steps.",
                        "Go UP from the DLR station — the Cutty Sark is right outside.",
                    ])
                }
                if !game.has(flag: "sawMuseum") {
                    return (key: "museum", clues: [
                        "The museum is on the way to the park — and it's free.",
                        "Go SOUTH from the Cutty Sark to the National Maritime Museum.",
                    ])
                }
                if !game.has(flag: "straddled") {
                    return (key: "line", clues: [
                        "The hill is worth the climb — the whole world is measured from the top.",
                        "Go SOUTH through the park and UP the chestnut avenue to the Royal Observatory, then STRADDLE THE LINE — one foot in each hemisphere.",
                    ])
                }
                var left: [String] = []
                if !game.has(flag: "spotCanary") { left.append("CANARY WHARF") }
                if !game.has(flag: "spotO2") { left.append("the O2") }
                if !game.has(flag: "spotEye") { left.append("the LONDON EYE") }
                if !left.isEmpty {
                    return (key: "view:" + left.joined(separator: "|"), clues: [
                        "The best part of Greenwich is done sitting down.",
                        "The viewpoint is EAST of the Observatory. SIT on the bench and LOOK AT \(left.joined(separator: ", then ")).",
                    ])
                }
                if !game.has(flag: "fedSquirrel") {
                    return (key: "squirrel", clues: [
                        "You have company on that bench, and it has expectations.",
                        game.inventoryKinds().contains("nut")
                            ? "GIVE a NUT TO the SQUIRREL — hold still and it will take it from your hand."
                            : "BUY NUTS at the park kiosk (back down the hill), then GIVE a NUT TO the SQUIRREL at the bench.",
                    ])
                }
                if !game.has(flag: "hadBeer") {
                    return (key: "beer", clues: [
                        "One bench tradition remains to be honoured.",
                        game.inventoryKinds().contains("beer")
                            ? "DRINK the BEER — you're in exactly the right place."
                            : "BUY a BEER at the park kiosk, carry it up the hill, and DRINK it on the bench.",
                    ])
                }
                return (key: "home", clues: [
                    "The heath is calling, and the kettle is at the far end of it.",
                    "Go SOUTH from the viewpoint, out across the heath, home to Blackheath.",
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
    /// Spends coins if the purse covers it; returns whether it did.
    fileprivate func spend(_ amount: Int) -> Bool {
        guard coins >= amount else { return false }
        coins -= amount
        return true
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
    add(Item(id: "map", name: "park map", nouns: ["map", "brochure", "guide", "pamphlet"],
             description: "A folding park map of Fort Pulaski National Monument, free from the stack on the desk.",
             isTakeable: true,
             readText: """
             "FORT PULASKI — PARK MAP
               • The fort: INSIDE across the drawbridge. On the parade ground, the gun casemates are NORTH, the prison casemates WEST, Colonel Olmstead's quarters (the surrender room) SOUTH, and stairs lead UP to the cannons on the terreplein.
               • Moat walk: SOUTH from the drawbridge, then EAST to the shell-scarred southeast angle.
               • Battery Hambright & the North Pier: NORTH along the riverside path.
               • Lighthouse Overlook Trail: EAST of the visitor center — FORWARD four stops to the observation deck.
             Benches throughout — SIT and stay awhile.
             Lost? GO TO VISITOR CENTER walks you back from anywhere you've been."
             """))
    add(Item(id: "ranger", name: "Ranger Max", nouns: ["ranger", "max", "guide", "attendant"],
             description: "Ranger Max, a National Park Service ranger in a flat-brimmed hat, glad to share the fort's story.",
             isFixture: true, isCreature: true))
    add(Item(id: "exhibit", name: "history exhibit", nouns: ["exhibit", "display", "history", "panel", "panels"],
             description: "A wall of exhibit panels tracing the fort from its brick-by-brick construction to the day its walls were breached.",
             readText: "\"THE STORY OF FORT PULASKI\nNamed for Casimir Pulaski, the Polish-born 'father of the American cavalry,' who fell at the 1779 Siege of Savannah. Begun in 1829 and eighteen years in the building — a young Robert E. Lee helped survey its dikes. Its walls were thought impregnable until April 11–12, 1862, when Union rifled cannon on Tybee Island breached them in about thirty hours, ending the age of masonry forts.\"",
             isFixture: true))

    // Battery Hambright.
    add(Item(id: "battery", name: "Battery Hambright", nouns: ["battery", "hambright", "emplacement", "concrete"],
             description: "A squat, poured-concrete gun battery from around 1900, its gun wells empty and open to the sky. It is named for Lieutenant Horace G. Hambright, who graduated dead last in the West Point class of 1893 — the class \"Goat\" — and died young in 1896; the battery never received its guns and never fired a shot.",
             isFixture: true))
    add(Item(id: "marker", name: "historical marker", nouns: ["marker", "plaque", "tablet"],
             description: "A cast historical marker beside the battery.",
             readText: "\"BATTERY HORACE HAMBRIGHT — Built 1899–1900 to guard the mouth of the Savannah River, and named in 1904 for Lt. Horace G. Hambright, U.S.A. — last-ranked graduate (the 'Goat') of the West Point class of 1893, remembered fondly by his fellow officers. Poured over 30,000 bricks salvaged from the original fort construction village. Designed for two rapid-fire 3-inch guns on disappearing mounts; the guns were never installed.\"",
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

    // The fort — drawbridge and moat.
    add(Item(id: "fortwalls", name: "fort", nouns: ["fort", "pulaski", "walls"],
             description: "Fort Pulaski itself — a massive five-sided brick fortress ringed by a moat, its walls seven and a half feet thick. They were thought invincible until the rifled cannon on Tybee Island proved otherwise in 1862.", isFixture: true))
    add(Item(id: "drawbridgeItem", name: "drawbridge", nouns: ["drawbridge", "bridge"],
             description: "A stout wooden drawbridge on chains, spanning the moat to the fort's arched sally port.", isFixture: true))
    add(Item(id: "moat", name: "moat", nouns: ["moat", "water"],
             description: "The moat rings the fort, seven feet deep and fed by the tide. Dragonflies stitch the surface — and is that a small alligator gliding along the far bank? It is.", isFixture: true))

    // The vintage base ball match, in full swing on the parade ground.
    // WATCH PLAYERS is the main event.
    add(Item(id: "ballplayers", name: "ballplayers", nouns: ["players", "ballplayers", "player", "game", "match", "baseball", "ball", "reenactors", "soldiers"],
             description: "You watch an inning. The striker squares up, the pitcher lobs the lemon-peel ball underhand, and — CRACK — it sails over the shortscout's head. The runner tears around the sacks in his wool uniform while the fielders give chase bare-handed, and the whole garrison seems to cheer. Behind them, a fellow with a box camera on a tripod is fussing with his plates, recreating the famous photograph: the 48th New York at play on this parade ground in 1862 — one of the earliest photographs of baseball ever taken.",
             isFixture: true, isCreature: true,
             dialogue: "\"Straight out of the 1862 photograph!\" a player calls, tapping his bat. \"The Forty-Eighth New York played ball right here between drills — earliest picture of the game anyone knows of. Rules of the day: underhand pitching, no gloves, and a ball caught on one bounce is an out. Stay for an inning!\""))

    // Wayfinding signs inside the fort.
    add(Item(id: "paradeSign", name: "signpost", nouns: ["signpost", "sign", "signs"],
             description: "A weathered wooden signpost with arms pointing every which way: gun casemates NORTH, prison casemates WEST, Colonel Olmstead's quarters SOUTH, the terreplein UP, and the sally port OUT.", isFixture: true))
    add(Item(id: "bridgeSign", name: "sign", nouns: ["sign", "signs", "signpost"],
             description: "A small park sign: parade ground IN across the drawbridge, moat walk SOUTH along the bank, visitor center back OUT.", isFixture: true))

    // Parade ground.
    add(Item(id: "flag", name: "garrison flag", nouns: ["flag", "colors", "flagpole"],
             description: "The garrison flag riding the sea breeze above the ramparts, just as it did over the 1862 siege.", isFixture: true))
    add(Item(id: "paradeBench", name: "wooden bench", nouns: ["bench", "benches", "seat"],
             description: "A simple wooden park bench in the shade at the edge of the parade ground.",
             readText: "You settle onto the bench at the edge of the parade ground. The flag snaps overhead, swallows loop between the casemate arches, and for a moment the fort is yours alone.",
             isFixture: true, kind: "seat"))

    // Colonel Olmstead's quarters — the surrender room.
    add(Item(id: "surrenderTable", name: "writing table", nouns: ["table", "desk"],
             description: "The plain writing table where, on April 11, 1862, Colonel Olmstead handed over his sword and signed away the fort.", isFixture: true))
    add(Item(id: "pictures", name: "framed pictures", nouns: ["pictures", "picture", "photos", "photographs", "frames"],
             description: "Framed period pictures of the surrender that took place in this room.",
             readText: "You study the framed pictures: Union officers crowd the small room, hats in hand, while Colonel Olmstead stands at the table, sword reversed, hilt offered. The caption reads: \"Surrender of Fort Pulaski — April 11, 1862, 2:30 p.m.\"",
             isFixture: true))

    // Olmstead's sword, displayed in the visitor center museum.
    add(Item(id: "sword", name: "Olmstead's sword", nouns: ["sword", "olmstead", "saber", "sabre"],
             description: "Colonel Charles Olmstead's own sword, resting in a museum case — the one he handed over when the fort fell in April 1862, and which General David Hunter sent back to him days later because the surrender had been honorable.", isFixture: true))

    // Gun casemates.
    add(Item(id: "casemateGun", name: "casemate cannon", nouns: ["cannon", "gun", "smoothbore"],
             description: "A big black smoothbore on its wooden carriage, aimed out through the embrasure at the river channel — exactly the kind of gun the rifled cannon across the water made obsolete.", isFixture: true))

    // Prison casemates.
    add(Item(id: "bunks", name: "wooden bunks", nouns: ["bunks", "bunk", "beds"],
             description: "Rows of rough wooden bunks, stacked close in the cold brick chamber where the Immortal 600 were held.", isFixture: true))
    add(Item(id: "graffiti", name: "carved names", nouns: ["graffiti", "names", "carvings"],
             description: "Names and dates scratched into the soft brick by prisoners' hands.",
             readText: "You lean close to the brick and pick out the shallow scratches: initials, a date — 1864 — and a name half-worn away. Men counting days.", isFixture: true))

    // Terreplein.
    add(Item(id: "cannons", name: "rampart cannons", nouns: ["cannon", "cannons", "gun", "guns"],
             description: "A rank of great black cannons along the terreplein's ramparts, muzzles trained over the river channel they once commanded.", isFixture: true))
    add(Item(id: "terrepleinBench", name: "bench", nouns: ["bench", "benches", "seat"],
             description: "A bench set between two cannons, facing out over the river.",
             readText: "You sit between the cannons with the wind off the Atlantic in your face, watching a container ship the size of a city block glide past the little lighthouse below. Hard to beat this seat anywhere in Georgia.",
             isFixture: true, kind: "seat"))

    // Moat walk and the battered southeast angle.
    add(Item(id: "moatBench", name: "bench", nouns: ["bench", "benches", "seat"],
             description: "A bench on the grassy bank, facing the fort across the moat.",
             readText: "You take the bench by the moat. The brick walls rise mirror-doubled in the still water, a heron stalks the reeds, and the dragonflies mind their own business.",
             isFixture: true, kind: "seat"))
    add(Item(id: "shells", name: "embedded shells", nouns: ["shell", "shells", "shot", "iron"],
             description: "Union shot and shell from 1862, still lodged in the brickwork where they struck — round dimples from smoothbores, deep gouges from the rifled guns.", isFixture: true))
    add(Item(id: "breach", name: "repaired breach", nouns: ["breach", "wall", "scars", "brick", "patch"],
             description: "The patch of smoother, darker brick marks where the wall was shot through in April 1862 and rebuilt afterward. Around it the original face is cratered like the moon.", isFixture: true))

    var rooms: [String: Room] = [:]
    func add(_ room: Room) { rooms[room.id] = room }

    add(Room(id: "gate", title: "Fort Pulaski Gates",
             description: "You drive in through the park gates and along the causeway across the marsh onto Cockspur Island. Ahead, the brick ramparts of Fort Pulaski rise behind their moat. The visitor center is just NORTH.",
             exits: [.north: "visitorCenter"],
             items: ["gates", "entrancesign"]))
    add(Room(id: "visitorCenter", title: "Visitor Center",
             description: "The Fort Pulaski visitor center: a cool room of exhibits and a bookstore, where Ranger Max waits at the desk to check you in. The fort's drawbridge is just INSIDE. A walking path leads NORTH toward the river, past Battery Hambright to the North Pier; the Lighthouse Overlook trailhead is EAST; and your car is parked back SOUTH.",
             exits: [.south: "gate", .inside: "drawbridge", .north: "batteryHambright", .east: "trail1"],
             items: ["ranger", "exhibit", "map", "sword"]))

    // The fort — cross the moat, explore inside and up top, and circle the
    // walls outside to see what the 1862 cannon fire left behind.
    add(Room(id: "drawbridge", title: "The Drawbridge",
             description: "A wooden drawbridge crosses the tidal moat to the fort's arched sally port, brick walls rising sheer from the water. Go INSIDE to the parade ground, follow the grassy bank SOUTH along the moat, or head back OUTSIDE to the visitor center.",
             exits: [.outside: "visitorCenter", .inside: "fort", .south: "moatWalk"],
             items: ["fortwalls", "drawbridgeItem", "moat", "bridgeSign"]))
    add(Room(id: "fort", title: "Parade Ground",
             description: "The broad green parade ground inside Fort Pulaski, ringed by brick casemate arches, with the garrison flag overhead. The gun casemates are NORTH, the prison casemates WEST, Colonel Olmstead's quarters SOUTH, and a stone stair climbs UP to the terreplein and its cannons. A wooden bench sits in the shade — SIT a while if you like. The sally port leads back OUTSIDE.",
             exits: [.outside: "drawbridge", .north: "casemates", .west: "prison", .south: "quarters", .up: "terreplein"],
             items: ["flag", "paradeBench", "paradeSign", "ballplayers"]))
    add(Room(id: "quarters", title: "Colonel Olmstead's Quarters",
             description: "The colonel's quarters off the parade ground, kept as they were in 1862 — a narrow bed, a plain writing table, and framed pictures on the wall of the surrender that happened in this very room (READ the PICTURES). The parade ground is back NORTH.",
             exits: [.north: "fort"],
             items: ["surrenderTable", "pictures"]))
    add(Room(id: "casemates", title: "Gun Casemates",
             description: "A long gallery of arched brick casemates, cool and echoing, each with a great black cannon aimed out through its embrasure at the river channel. The parade ground is back SOUTH.",
             exits: [.south: "fort"],
             items: ["casemateGun"]))
    add(Room(id: "prison", title: "Prison Casemates",
             description: "Dim casemates fitted with rows of rough wooden bunks — the prison of the Immortal 600. Names are scratched into the brick (READ them if you dare the chill). The parade ground is back EAST.",
             exits: [.east: "fort"],
             items: ["bunks", "graffiti"]))
    add(Room(id: "terreplein", title: "The Terreplein",
             description: "The fort's open upper level, high above the parade ground, cannons ranked along the ramparts. The whole mouth of the Savannah River spreads below — ships in the channel, the Cockspur Lighthouse on its bar, Tybee Island on the horizon. A bench faces the water between two guns. The stair leads back DOWN.",
             exits: [.down: "fort"],
             items: ["cannons", "terrepleinBench", "lighthouse", "containership"]))
    add(Room(id: "moatWalk", title: "Along the Moat",
             description: "A grassy bank between the moat and the marsh, the fort's brick walls doubled in the still water. A bench faces the reflection. The path curls EAST around the walls toward the southeast angle; the drawbridge is back NORTH.",
             exits: [.north: "drawbridge", .east: "scarredWall"],
             items: ["moatBench", "moat"]))
    add(Room(id: "scarredWall", title: "The Battered Southeast Angle",
             description: "The fort's southeast corner, the face that took the Union bombardment of 1862. The brick is pocked and cratered with shell strikes, iron shot still lodged in the wall, and a broad patch of darker brick marks the repaired breach. Across the water lies Tybee Island, where the batteries fired from. The moat walk leads back WEST.",
             exits: [.west: "moatWalk"],
             items: ["shells", "breach"]))
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

private func buildRoppongiWorld() -> (rooms: [String: Room], items: [String: Item]) {
    var items: [String: Item] = [:]
    func add(_ item: Item) { items[item.id] = item }

    // The station, and Kenji's marching orders.
    add(Item(id: "napkin", name: "bar napkin", nouns: ["napkin", "note", "plan", "list"],
             description: "A bar napkin covered in Kenji's confident scrawl — tonight's marching orders.",
             isTakeable: true,
             readText: """
             "THE CLASSIC ROPPONGI CRAWL — do it right:
               1. GERONIMO'S — up the stairs at the crossing. Ring the bell. Yes, really.
               2. MOGAMBO'S — tiny place off the side street. Buy Roy a frozen margarita and tell him it's from me.
               3. BAR QUEST — down the side street. Throw darts with the league.
               Finish: ramen under the red lantern, SOUTH off the side street.
             Text me when you're home. — Kenji"
             """))
    add(Item(id: "roppongiMap", name: "Roppongi map", nouns: ["map", "guide", "pamphlet"],
             description: "A free fold-out night map of Roppongi from the rack by the ticket gates, creased along well-worn lines.",
             isTakeable: true,
             readText: """
             "ROPPONGI NIGHT MAP
               • Roppongi Crossing: UP the escalator from the station — Almond's pink awning marks the corner.
               • Geronimo Shot Bar: UP the narrow stairs right at the crossing, second floor.
               • The side street: EAST of the crossing. Mogambo's is NORTH, Bar Quest is EAST.
               • Ramen stand: SOUTH off the side street — follow the red lantern.
             Lost? GO TO <place> walks you back from anywhere you've been."
             """))
    add(Item(id: "stationSign", name: "station sign", nouns: ["sign", "board"],
             description: "The backlit station sign, gray and steady amid the rush.",
             readText: "\"ROPPONGI — Hibiya Line. Exit 3: Roppongi Crossing / Gaien-Higashi-dori. Last train 00:24. First train 05:12.\" You intend to see both.",
             isFixture: true))
    add(Item(id: "vendingMachine", name: "vending machine", nouns: ["vending", "machine"],
             description: "A vending machine glowing like a small shrine, offering hot corn soup, cold coffee, and eleven kinds of tea. Tokyo in one appliance.", isFixture: true))
    add(Item(id: "salarymen", name: "salarymen", nouns: ["salarymen", "salaryman", "crowd", "commuters"],
             description: "A knot of cheerful salarymen fresh from an office party, one necktie already promoted to headband.",
             isFixture: true, isCreature: true,
             dialogue: "\"Konbanwa!\" the salarymen chorus, bowing in ragged unison. The one with the necktie around his head gives you a double thumbs-up: \"Roppongi! Best night! Ganbatte!\""))

    // Roppongi Crossing.
    add(Item(id: "almond", name: "Almond café", nouns: ["almond", "cafe", "awning"],
             description: "Almond — the coffee shop with the famous pink awning that has anchored Roppongi Crossing since 1964. Half the meetups in Tokyo begin with the words \"in front of Almond.\"", isFixture: true))
    add(Item(id: "expressway", name: "Shuto Expressway", nouns: ["expressway", "overpass", "highway"],
             description: "The Shuto Expressway runs directly over the crossing on massive green legs, traffic drumming overhead like weather.", isFixture: true))
    add(Item(id: "tout", name: "tout", nouns: ["tout", "hawker", "barker"],
             description: "A fast-talking tout in a shiny jacket, scanning the crowd for the undecided.",
             isFixture: true, isCreature: true,
             dialogue: "\"My friend! Best bars, best prices!\" The tout drops the pitch the moment he sees your napkin. \"Ah — the classic crawl. Respect. Geronimo's is UP right here at the crossing; the side street EAST has the rest. And skip anywhere with a menu in four currencies.\""))

    // Geronimo Shot Bar.
    add(Item(id: "bellGeronimos", name: "bell", nouns: ["bell"],
             description: "A polished ship's bell on a short rope, hung dead center over the bar. The hand-lettered card beneath reads: RING FOR GLORY — ROUND FOR THE HOUSE, RINGER'S CHOICE, 15 COINS.", isFixture: true))
    add(Item(id: "plaques", name: "brass plaques", nouns: ["plaques", "plaque", "brass", "wall", "names"],
             description: "Hundreds of brass plaques, floor to ceiling — the honor roll of Geronimo's regulars from every corner of the earth.",
             readText: "You scan the plaques: a bush pilot from Anchorage, an entire rugby team from Auckland, a violinist from Vienna. The newest one is still shiny; the oldest is worn smooth by thirty years of thumbs. There's space left on the wall.",
             isFixture: true))
    add(Item(id: "shot", name: "tequila shot", nouns: ["shot", "tequila", "shots"],
             description: "The house tequila shot, poured generous.",
             isTakeable: true, isFixture: true, forSale: true, price: 8, kind: "shot"))
    add(Item(id: "ryan", name: "Ryan", nouns: ["ryan", "bartender", "barkeep"],
             description: "Ryan, Geronimo's bartender — fast hands, faster grin, and total command of the room.",
             isFixture: true, isCreature: true,
             dialogue: "\"Welcome to Geronimo's!\" Ryan calls over the noise, not missing a pour. \"Rules are on the wall and the bell speaks for itself. RING it and everyone in here is your friend for life — or at least until closing.\""))

    // Mogambo's.
    add(Item(id: "bellMogambos", name: "bell", nouns: ["bell"],
             description: "A little brass bell over Mogambo's counter, polished by years of celebrations. Same rule as everywhere: ring it, and the round's on you — ringer's choice.", isFixture: true))
    add(Item(id: "margarita", name: "frozen margarita", nouns: ["margarita", "marg", "cocktail"],
             description: "Martin's frozen margarita — Mogambo's pride, blended to a snowdrift and salted like the Gulf of Mexico.",
             isTakeable: true, isFixture: true, forSale: true, price: 9, kind: "margarita"))
    add(Item(id: "martin", name: "Martin", nouns: ["martin", "bartender", "master"],
             description: "Martin, Mogambo's bartender and mayor of its eight stools, who remembers every name he's ever been told.",
             isFixture: true, isCreature: true,
             dialogue: "\"First time? Then it isn't,\" Martin says warmly, wiping the counter. \"This is Mogambo's — everyone's local. The margarita is frozen, famous, and nine coins. And if you're feeling generous—\" he tilts his head toward the end of the bar, \"—somebody down there needs one more than you do.\""))
    add(Item(id: "roy", name: "Roy", nouns: ["roy", "texan", "regular"],
             description: "Roy: big, sunburned, pearl-snap shirt, and about as far from Galveston, Texas as a man can get. His glass has been empty a while.",
             isFixture: true, isCreature: true))

    // Bar Quest.
    add(Item(id: "bellQuest", name: "bell", nouns: ["bell"],
             description: "A ship's bell over the taps, its rope frayed by celebration. The plaque reads: RING FOR GLORY — ROUND FOR THE HOUSE, RINGER'S CHOICE.", isFixture: true))
    add(Item(id: "pint", name: "pint of lager", nouns: ["pint", "beer", "lager", "ale"],
             description: "A proper pint of lager, pulled slow, with an inch of head.",
             isTakeable: true, isFixture: true, forSale: true, price: 7, kind: "pint"))
    add(Item(id: "matt", name: "Matt", nouns: ["matt", "bartender", "barman"],
             description: "Matt, Bar Quest's bartender — unflappable, generous with coasters, and the final word in all darts disputes.",
             isFixture: true, isCreature: true,
             dialogue: "\"Evenin',\" says Matt, setting a coaster in front of you out of pure reflex. \"Pint's seven coins, darts are free, and the league—\" he nods at the corner \"—is always short a player. THROW some DARTS if you fancy your chances.\""))
    add(Item(id: "dartboard", name: "dartboard", nouns: ["darts", "dart", "dartboard", "board"],
             description: "A bristle dartboard that has absorbed a decade of expat ambition. The chalk scoreboard beside it reads like a UN roll call.", isFixture: true))
    add(Item(id: "jukebox", name: "jukebox", nouns: ["jukebox", "music"],
             description: "A jukebox loaded with three decades of singalongs. Somebody has queued 'Country Roads' again. Somebody always has.", isFixture: true))

    // The side street.
    add(Item(id: "tower", name: "Tokyo Tower", nouns: ["tower", "tokyo"],
             description: "Tokyo Tower, orange and white and lit like a carnival, rises over the low rooftops at the end of the street — close enough to feel like scenery hung there just for you.", isFixture: true))

    // The ramen stand.
    add(Item(id: "cook", name: "ramen cook", nouns: ["cook", "chef", "master", "ojisan"],
             description: "The ramen cook, towel knotted around his head, working his pots with the calm of a man who has seen every kind of 4 a.m.",
             isFixture: true, isCreature: true))
    add(Item(id: "stool", name: "counter stool", nouns: ["stool", "seat"],
             description: "A worn wooden stool at the ramen counter, shaped by ten thousand late nights.",
             readText: "You settle onto the stool. Steam rises, the cook works in unhurried silence, and Roppongi's last stragglers drift past the curtain. The best seat in Tokyo at this hour.",
             isFixture: true, kind: "seat"))
    add(Item(id: "noren", name: "noren curtain", nouns: ["noren", "curtain", "banner"],
             description: "The short noren curtain across the stall's front, dyed deep red and breathing steam — the single kanji on it promises RAMEN, and it does not lie.", isFixture: true))

    add(Item(id: "ticketMachines", name: "ticket machines", nouns: ["machine", "machines", "kensyoki", "vending"],
             description: "A row of blue ticket machines under a big fare map. BUY a TICKET to your home station — you will need it to get out at the far end.",
             isFixture: true))
    add(Item(id: "ticket", name: "train ticket", nouns: ["ticket", "kippu", "fare"],
             description: "A little magnetic-stripe ticket home. Hang onto it — the gate eats it on the way out, and no ticket means a trip to the fare-adjustment machine.",
             isTakeable: true, isFixture: true, forSale: true, price: 3, kind: "ticket"))
    add(Item(id: "fareMachine", name: "fare adjustment machine", nouns: ["machine", "farebox", "seisan", "adjustment"],
             description: "The orange 精算 fare-adjustment machine beside the gate. PUSH it to settle up and the gate will open.",
             isFixture: true))

    var rooms: [String: Room] = [:]
    func add(_ room: Room) { rooms[room.id] = room }

    add(Room(id: "roppongiStation", title: "Roppongi Station",
             description: "The Hibiya Line platform at Roppongi, deep enough underground that the escalator ride feels like a pilgrimage. Kenji couldn't come tonight, but his marching orders — scrawled on a bar napkin — lie folded on the bench beside you (TAKE it, READ it), and a rack by the ticket gates offers free Roppongi maps. The escalator leads UP to the crossing.",
             exits: [.up: "crossing", .inside: "ticketMachine"],
             items: ["napkin", "roppongiMap", "stationSign", "vendingMachine", "salarymen"]))
    add(Room(id: "crossing", title: "Roppongi Crossing",
             description: "The heart of Roppongi at full night volume: the Shuto Expressway roaring overhead, Almond's pink awning glowing on the corner, taxis, touts, and ten thousand watts of stacked neon. A narrow stairway climbs UP to Geronimo Shot Bar; the side street EAST leads deeper into bar country; the station is back DOWN.",
             exits: [.down: "roppongiStation", .up: "geronimos", .east: "sideStreet"],
             items: ["almond", "expressway", "tout"]))
    add(Room(id: "geronimos", title: "Geronimo Shot Bar",
             description: "Geronimo's, second floor: a shot bar the size of a train car with the volume of a stadium. Brass plaques plate the walls (READ them), Ryan holds court behind the bar, and the famous bell hangs over everything. The stairs lead back DOWN to the crossing.",
             exits: [.down: "crossing"],
             items: ["bellGeronimos", "plaques", "ryan", "shot"]))
    add(Room(id: "sideStreet", title: "The Side Street",
             description: "A narrow street of stacked bar signs — six glowing floors of them on every building, each promising a different tiny world. Tokyo Tower burns orange at the end of the block like a lucky charm. Mogambo's doorway is NORTH; Bar Quest's brass-lettered door is EAST; a red lantern and the smell of broth wait SOUTH; the crossing is back WEST.",
             exits: [.west: "crossing", .north: "mogambos", .east: "quest", .south: "ramenya"],
             items: ["tower"]))
    add(Room(id: "mogambos", title: "Mogambo's",
             description: "Inside Mogambo's: eight stools, one Martin, and a thousand stories. The blender sits ready for margarita duty, a little bell hangs over the counter, and Roy holds down the end stool. The side street is back SOUTH.",
             exits: [.south: "sideStreet"],
             items: ["bellMogambos", "martin", "roy", "margarita"]))
    add(Room(id: "quest", title: "Bar Quest",
             description: "Bar Quest, open until the first train and honest about it: long oak counter, taps polished bright, a bell over the bar, a jukebox mid-singalong, and the darts corner where the expat league holds court. Matt keeps the pints coming. The side street is back WEST.",
             exits: [.west: "sideStreet"],
             items: ["bellQuest", "matt", "pint", "dartboard", "jukebox"]))
    add(Room(id: "ramenya", title: "The Ramen Stand",
             description: "A tiny late-night ramen stand under a glowing red lantern, steam rolling out beneath the noren curtain. A worn counter stool waits (SIT, if the night has caught up with you) while the cook tends his pots. The side street is back NORTH.",
             exits: [.north: "sideStreet"],
             items: ["cook", "stool", "noren"]))

    add(Room(id: "ticketMachine", title: "The Ticket Gates",
             description: "The ticket gates at Roppongi, quiet at dawn. A row of blue TICKET MACHINES glows under a big fare map. BUY a TICKET here, then step IN to the platform and board the first train. The station hall is back OUT.",
             exits: [.outside: "roppongiStation", .inside: "trainCar"],
             items: ["ticketMachines", "ticket"]))
    add(Room(id: "trainCar", title: "The First Train",
             description: "Inside the 05:12 Hibiya Line car: warm, half-empty, a few nodding heads and a route map glowing over the doors. It is just ONE STOP to your transfer — get OFF (go FORWARD) when it slides in.",
             exits: [.north: "transferStation", .outside: "transferStation"],
             items: []))
    add(Room(id: "transferStation", title: "The Transfer",
             description: "A cavernous transfer station, one stop from Roppongi. Your home line is DOWN the stairs to Platform 2 — three stops and you are home. The train still waiting at THIS platform runs the other way, out to the end of the line; do NOT stay aboard it. (Go DOWN for home.)",
             exits: [.down: "homeStation", .north: "wrongTerminus"],
             items: []))
    add(Room(id: "wrongTerminus", title: "The End of the Line",
             description: "You stayed on the wrong train and rode it all the way to a sleepy terminus somewhere out in the suburbs, hours from home, the platform empty and the sun already up. Nothing for it but to ride all the way BACK to the transfer.",
             exits: [.south: "transferStation", .outside: "transferStation"],
             items: []))
    add(Room(id: "homeStation", title: "Your Station",
             description: "Your own little station at last, the morning gone pink over the rooftops. The exit gates stand between you and a hot shower — TAP OUT (go OUT) with your ticket. No ticket? The 精算 fare-adjustment machine is just IN from the gate.",
             exits: [.outside: "homeStation", .inside: "fareAdjust"],
             items: []))
    add(Room(id: "fareAdjust", title: "Fare Adjustment",
             description: "The little bank of fare-adjustment machines beside the blocked gate. No ticket, no exit — but the orange 精算 machine will sort you out. PUSH it to settle the fare, then step back OUT to the gate.",
             exits: [.outside: "homeStation"],
             items: ["fareMachine"]))

    return (rooms, items)
}

private func buildGreenwichWorld() -> (rooms: [String: Room], items: [String: Item]) {
    var items: [String: Item] = [:]
    func add(_ item: Item) { items[item.id] = item }

    // The DLR from Canary Wharf.
    add(Item(id: "dlrTrain", name: "DLR train", nouns: ["dlr", "train", "carriage"],
             description: "The driverless DLR train that carried you from Canary Wharf, resting at the platform. No driver's cab — which means the front seat is the best seat in London transport, and everyone aboard quietly knows it.", isFixture: true))
    add(Item(id: "dlrSign", name: "station sign", nouns: ["sign", "board"],
             description: "The station roundel, patient as ever.",
             readText: "\"CUTTY SARK — for Maritime Greenwich. Way out for: Cutty Sark · Greenwich Market · National Maritime Museum · Royal Observatory & Greenwich Park.\" The whole afternoon, listed in order.",
             isFixture: true))

    // The Cutty Sark.
    add(Item(id: "clipper", name: "Cutty Sark", nouns: ["ship", "clipper", "sark", "cutty", "hull"],
             description: "The Cutty Sark, launched 1869 — the fastest tea clipper ever built, raised on a ring of glass above her dry dock. Her copper-sheathed hull hangs overhead close enough to touch, still shaped like the sea is missing.", isFixture: true))
    add(Item(id: "nannie", name: "Nannie figurehead", nouns: ["figurehead", "nannie", "witch"],
             description: "Nannie herself at the bow — the witch from Burns' Tam o' Shanter, in her short 'cutty sark', arm outstretched with the grey horsehair she tore from Tam's mare as he escaped. A ship named after a punchline, and the fastest of her age at that.",
             readText: "The plaque gives you the Burns: Tam o' Shanter, fleeing the witches at midnight, is saved because a witch can't cross running water — but the young witch Nannie, in her 'cutty sark' (her short shift), snatches the tail from his horse at the bridge. Ship, name, and figurehead: one good story, sailing since 1869.",
             isFixture: true))

    // The National Maritime Museum.
    add(Item(id: "nelsonCoat", name: "Nelson's coat", nouns: ["coat", "nelson", "exhibit", "uniform"],
             description: "Vice-Admiral Nelson's undress coat, worn at Trafalgar, in a quiet case with the light kept low. The musket-ball hole is in the left shoulder. Nobody talks loudly in front of it.",
             readText: "\"UNDRESS COAT, VICE-ADMIRAL HORATIO NELSON — worn at the Battle of Trafalgar, 21 October 1805. The hole of the fatal musket ball is visible in the left shoulder; the medals are the replicas he wore at sea. He asked that his family be looked after. The nation kept the coat instead.\"",
             isFixture: true))
    add(Item(id: "shipModels", name: "ship models", nouns: ["models", "model", "ships", "cases"],
             description: "Case after case of ship models rigged with thread finer than hair — three centuries of the sea, at 1:48 scale, each one somebody's ten thousand patient hours.", isFixture: true))
    add(Item(id: "figureheads", name: "figureheads", nouns: ["figureheads", "figures", "carvings"],
             description: "A wall of retired figureheads gazing over your head toward horizons that stopped existing a century ago — lions, ladies, admirals, and one alarmingly cheerful unicorn.", isFixture: true))

    // The park lawn and kiosk.
    add(Item(id: "greenwichMap", name: "park map", nouns: ["map", "guide", "leaflet"],
             description: "A free folding map of Greenwich Park from the kiosk rack, soft at the creases.",
             isTakeable: true,
             readText: """
             "GREENWICH PARK — oldest of the Royal Parks, enclosed 1433.
               • The Royal Observatory & Prime Meridian: UP the chestnut avenue, at the top of the hill.
               • The Wolfe statue viewpoint: EAST of the Observatory — the famous view, and the famous benches.
               • Kiosk: hazelnuts (the squirrels take them from your hand), ice cream, cold drinks.
               • Blackheath & the village: SOUTH across the heath from the top of the park.
             Lost? GO TO <place> retraces your steps. The deer live in the Wilderness — look, don't chase."
             """))
    add(Item(id: "nuts", name: "bag of hazelnuts", nouns: ["nuts", "nut", "hazelnuts", "hazelnut", "bag"],
             description: "A paper bag of hazelnuts, sold for one purpose only, and the squirrels know the sound it makes.",
             isTakeable: true, isFixture: true, forSale: true, price: 4, kind: "nut"))
    add(Item(id: "iceCream", name: "99 with a Flake", nouns: ["ice", "cream", "99", "flake", "cone"],
             description: "A whippy 99 with a Flake at a jaunty angle — the official ice cream of British childhood, and of anyone sensible since.",
             isTakeable: true, isFixture: true, forSale: true, price: 3, kind: "icecream"))
    add(Item(id: "beer", name: "cold beer", nouns: ["beer", "can", "lager"],
             description: "A properly cold can of lager, beaded with condensation. It has an appointment with a bench at the top of the hill.",
             isTakeable: true, isFixture: true, forSale: true, price: 4, kind: "beer"))
    add(Item(id: "kioskLady", name: "kiosk lady", nouns: ["lady", "keeper", "vendor", "kiosk"],
             description: "The kiosk lady, who has watched twenty years of afternoons head up that hill and knows exactly what each of them needs.",
             isFixture: true, isCreature: true))

    // The avenue and the hilltop.
    add(Item(id: "chestnuts", name: "sweet chestnuts", nouns: ["chestnuts", "chestnut", "trees", "avenue"],
             description: "Ancient sweet chestnuts line the climb, planted in the 1660s and grown into vast twisted characters, each with a personality and most with a squirrel in residence.", isFixture: true))
    add(Item(id: "squirrel", name: "grey squirrel", nouns: ["squirrel", "squirrels"],
             description: "A grey squirrel — and then, once you look, four more: chasing in spirals up a chestnut trunk, leaping gaps that shouldn't be leapable, pausing upside down to check whether you've turned out to be the kind of person who carries hazelnuts.",
             isFixture: true, isCreature: true))
    add(Item(id: "meridian", name: "Prime Meridian line", nouns: ["line", "meridian", "strip", "prime"],
             description: "The Prime Meridian of the World: a brass strip set in the courtyard stones, longitude 0° 0' 0\", the line every map and clock on earth has answered to since 1884. East on one side, west on the other, and a queue of people grinning at their own feet.", isFixture: true))
    add(Item(id: "timeBall", name: "Time Ball", nouns: ["ball", "timeball"],
             description: "The bright red Time Ball on the roof of Flamsteed House. Every day since 1833 it climbs its mast at 12:55 and drops at 13:00 exactly — one of the first public time signals in the world, still keeping its appointment.", isFixture: true))
    add(Item(id: "gateClock", name: "Shepherd Gate Clock", nouns: ["clock", "shepherd", "gate"],
             description: "The Shepherd Gate Clock, set into the Observatory wall since 1852 — a 24-hour dial, and one of the first clocks ever to show Greenwich Mean Time directly to the public.",
             readText: "The dial reads out the true time of the meridian a few steps away. For a century, people set their pocket watches here — and a certain Ruth Belville then carried the time itself into London, selling accurate seconds door to door from a chronometer named Arnold.",
             isFixture: true))
    add(Item(id: "flamsteed", name: "Flamsteed House", nouns: ["flamsteed", "house", "observatory", "dome"],
             description: "Flamsteed House, Wren's little observatory of 1675, its onion dome and warm brick presiding over the courtyard — built, said the King, 'for the perfecting of navigation and astronomy', and still doing quiet business in both.", isFixture: true))

    // The viewpoint — where the going stops and the looking starts.
    add(Item(id: "wolfeStatue", name: "Wolfe statue", nouns: ["statue", "wolfe", "general"],
             description: "General James Wolfe in bronze, gazing out over the city — a Greenwich man, victor and casualty of Quebec in 1759, given the best view in London for keeps.",
             readText: "\"MAJOR-GENERAL JAMES WOLFE, 1727–1759 — victor of Quebec, resident of Greenwich, buried in St Alfege's below. This statue, a gift of the Canadian people, 1930.\" The plinth still carries shrapnel scars from a wartime bomb — he held his post.",
             isFixture: true))
    add(Item(id: "bench", name: "bench", nouns: ["bench", "seat"],
             description: "A well-worn bench at the railing, angled precisely at London. Whoever placed it knew exactly what they were doing.",
             readText: "You sit, and the afternoon reorganises itself around the view: the Queen's House square and white directly below, the river doubling around the Isle of Dogs, and the whole skyline waiting to be LOOKED at — CANARY WHARF ahead, the O2 on its peninsula, the LONDON EYE far off to the left. Squirrels conduct their business along the railing. This bench is the entire point of the hill.",
             isFixture: true, kind: "seat"))
    add(Item(id: "queensHouse", name: "Queen's House", nouns: ["queen", "queens", "house", "colonnade"],
             description: "The Queen's House directly below — Inigo Jones's perfect white cube of 1616, the first classical building in England, holding the middle of the view like a full stop.", isFixture: true))
    add(Item(id: "canaryWharf", name: "Canary Wharf", nouns: ["canary", "wharf", "towers", "skyline"],
             description: "The glass towers across the river — best appreciated from the bench.", isFixture: true))
    add(Item(id: "o2", name: "the O2", nouns: ["o2", "dome", "millennium"],
             description: "The white dome on the peninsula — best appreciated from the bench.", isFixture: true))
    add(Item(id: "londonEye", name: "London Eye", nouns: ["eye", "wheel", "london"],
             description: "The pale wheel far upriver — best appreciated from the bench.", isFixture: true))

    // Blackheath — home.
    add(Item(id: "heath", name: "the heath", nouns: ["heath", "grass", "green"],
             description: "Blackheath: wide, flat, and open to the whole sky, kites permanently aloft, the village church spire rising at the far edge. Home ground.", isFixture: true))

    var rooms: [String: Room] = [:]
    func add(_ room: Room) { rooms[room.id] = room }

    add(Room(id: "dlrStation", title: "Cutty Sark DLR Station",
             description: "The DLR from Canary Wharf sighs to a stop and lets you out at Cutty Sark station — the commute interrupted in the best possible way. The driverless train rests at the platform behind you; the way out is UP the steps, where a tea clipper is waiting.",
             exits: [.up: "cuttySark"],
             items: ["dlrTrain", "dlrSign"]))
    add(Room(id: "cuttySark", title: "The Cutty Sark",
             description: "You come up the station steps and there she is: the Cutty Sark, masts and rigging against the sky, her hull raised on glass so the ship rides above her dry dock. Nannie the figurehead reaches from the bow (READ her story). The National Maritime Museum is SOUTH; the DLR is back DOWN.",
             exits: [.down: "dlrStation", .south: "maritimeMuseum"],
             items: ["clipper", "nannie"]))
    add(Room(id: "maritimeMuseum", title: "National Maritime Museum",
             description: "The great glass court of the National Maritime Museum, free to all comers: figureheads on the walls, ship models by the fleet, and in a quiet case, Nelson's Trafalgar coat (READ the EXHIBIT). Greenwich Park begins SOUTH of the doors; the Cutty Sark is back NORTH.",
             exits: [.north: "cuttySark", .south: "parkLawn"],
             items: ["nelsonCoat", "shipModels", "figureheads"]))
    add(Room(id: "parkLawn", title: "Greenwich Park — The Lawn",
             description: "Through the gates and into the oldest Royal Park in London: broad lawns, dog-walkers, and the hill rising ahead. The kiosk by the path sells hazelnuts, ice cream, and cold beer — provisions for the summit — and keeps free park maps in a rack (TAKE one). The chestnut avenue climbs SOUTH; the museum is back NORTH.",
             exits: [.north: "maritimeMuseum", .south: "chestnutAvenue", .up: "chestnutAvenue"],
             items: ["kioskLady", "greenwichMap", "nuts", "iceCream", "beer"]))
    add(Room(id: "chestnutAvenue", title: "The Chestnut Avenue",
             description: "The path climbs the hill between ancient sweet chestnuts, planted for Charles II and now enormous, twisted, and thoroughly occupied by squirrels. The Observatory crowns the rise ahead — keep climbing SOUTH; the lawn is back NORTH.",
             exits: [.north: "parkLawn", .down: "parkLawn", .south: "observatory", .up: "observatory"],
             items: ["chestnuts", "squirrel"]))
    add(Room(id: "observatory", title: "Royal Observatory — The Meridian Courtyard",
             description: "The courtyard of the Royal Observatory, on the crown of the hill: Flamsteed House with its red Time Ball, the Shepherd Gate Clock in the wall (READ it), and set into the stones, the brass Prime Meridian line itself. The famous viewpoint and its benches are just EAST; the avenue descends back NORTH.",
             exits: [.north: "chestnutAvenue", .down: "chestnutAvenue", .east: "wolfeViewpoint"],
             items: ["meridian", "timeBall", "gateClock", "flamsteed"]))
    add(Room(id: "wolfeViewpoint", title: "The Wolfe Statue Viewpoint",
             description: "The terrace by General Wolfe's statue, at the edge of the hill, where London lays itself out below: the Queen's House, the river, and the skyline beyond. A bench waits at the railing (SIT — then LOOK at CANARY WHARF, the O2, the LONDON EYE), squirrels patrol the railing, and the path home to Blackheath runs SOUTH across the park. The Observatory courtyard is back WEST.",
             exits: [.west: "observatory", .south: "blackheath"],
             items: ["wolfeStatue", "bench", "squirrel", "queensHouse", "canaryWharf", "o2", "londonEye"]))
    add(Room(id: "blackheath", title: "Blackheath",
             description: "Out through the top gate of the park and onto Blackheath — wide, flat, and open to the sky, kites up, the village lights ahead across the grass. Home is at the far side of the green. The park (and the bench) are back NORTH.",
             exits: [.north: "wolfeViewpoint"],
             items: ["heath"]))

    return (rooms, items)
}

private func buildFujiWorld() -> (rooms: [String: Room], items: [String: Item]) {
    var items: [String: Item] = [:]
    func add(_ item: Item) { items[item.id] = item }

    // The fifth-station lodge and trailhead.
    add(Item(id: "trailMap", name: "trail map", nouns: ["map", "guide", "pamphlet"],
             description: "A free folding map of the Yoshida Trail from the lodge counter, the stages numbered like chapters.",
             isTakeable: true,
             readText: """
             "MOUNT FUJI — YOSHIDA TRAIL MAP
               • UP (or NEXT STAGE) climbs the trail: the safety center (6th), Tomoekan (7th), Taishikan (8th), the dark final stretch (9th), and the summit torii — the tenth station.
               • Every stage has food, a bench with a view, and a brand for your walking stick.
               • At the top: Kusushi Shrine and the summit brand, the post office just INSIDE (mail home!), and the crater rim EAST to Ken-ga-mine.
               • DOWN retraces the trail, and GO TO LODGE walks you back here from anywhere you've been.
             Weather turns fast above the Eighth — carry a jacket, or shelter at the huts."
             """))
    add(Item(id: "stick", name: "kongō-zue walking stick", nouns: ["stick", "kongo", "zue", "staff"],
             description: "A fresh octagonal wooden kongō-zue, the pilgrim's walking stick — smooth, pale, and waiting for its first hut brand.",
             isTakeable: true, isFixture: true, forSale: true, price: 12, kind: "stick"))
    add(Item(id: "headlamp", name: "headlamp", nouns: ["headlamp", "lamp", "light", "lantern", "torch"],
             description: "A sturdy LED headlamp on an elastic band — the difference between climbing the upper trail and guessing at it.",
             isTakeable: true, isLightSource: true, isFixture: true,
             forSale: true, price: 8, kind: "headlamp"))
    add(Item(id: "letter", name: "letter home", nouns: ["letter", "envelope", "mail", "card", "postcard"],
             description: "A sheet of good paper and an envelope already addressed home to Mom, waiting for the story of a lifetime.",
             isTakeable: true,
             readText: "\"Dear Mom — You will not believe where I am when I finish this letter. Save this envelope: the postmark is going to do the bragging for me. More from the top. — with love\"",
             isFixture: true, forSale: true, price: 3, kind: "letter"))
    add(Item(id: "jacket", name: "storm jacket", nouns: ["jacket", "raincoat", "shell", "coat"],
             description: "A serious storm jacket, sealed seams and a deep hood — proof against rain, wind, and second thoughts.",
             isTakeable: true, isFixture: true, forSale: true, price: 6, kind: "jacket"))
    add(Item(id: "oxygen", name: "canned oxygen", nouns: ["oxygen", "can", "air"],
             description: "A slim can of oxygen for the thin air up top. Mostly it's for morale, and morale counts.",
             isTakeable: true, isFixture: true, forSale: true, price: 4, kind: "oxygen"))
    add(Item(id: "shopkeeper", name: "shopkeeper", nouns: ["shopkeeper", "keeper", "vendor"],
             description: "The fifth-station shopkeeper, who has outfitted forty years of climbers and can judge your summit odds at a glance.",
             isFixture: true, isCreature: true))
    add(Item(id: "komitake", name: "Komitake Shrine", nouns: ["shrine", "komitake"],
             description: "Komitake Shrine, older than the trail itself, where climbers clap twice and ask the mountain's permission. It never hurts.", isFixture: true))
    add(Item(id: "horses", name: "pack horses", nouns: ["horses", "horse", "ponies"],
             description: "Sturdy pack horses that carry footsore visitors along the flat stretch — none of them has ever been to the summit, and none of them minds.",
             isFixture: true, isCreature: true,
             dialogue: "The nearest horse regards you with enormous, patient eyes, decides you are not carrying apples, and returns to its doze."))

    // Sixth station.
    add(Item(id: "safetyCenter", name: "safety center", nouns: ["safety", "center", "bulletin"],
             description: "The sixth-station safety center, its bulletin board layered with weather reports and trail notices.",
             readText: "\"YOSHIDA TRAIL — TONIGHT: skies clear, wind light, sunrise 04:32. Climb slowly. Rest at the huts. Lights required above the Eighth Station. The mountain decides; the climber agrees.\"",
             isFixture: true))
    add(Item(id: "guide", name: "mountain guide", nouns: ["guide", "ranger"],
             description: "A mountain guide with a face like weathered cedar and the calm of a person the mountain has never once surprised. A small brazier beside him keeps the trailhead branding iron hot.",
             isFixture: true, isCreature: true))
    add(Item(id: "onigiri", name: "onigiri", nouns: ["onigiri", "riceball", "rice", "food"],
             description: "Fat rice balls wrapped in crisp nori, stacked in a warmer by the safety center — trail fuel of champions.",
             isTakeable: true, isFixture: true, forSale: true, price: 3, kind: "food"))
    add(Item(id: "bench6", name: "trailside bench", nouns: ["bench", "seat"],
             description: "A rough bench at the sixth station, facing back down the mountain.",
             readText: "You sit at the sixth station as the last light drains from the valley: the Fuji Five Lakes going pewter, then black, and the first stars snapping on above the trail. Below, the bright huddle of the fifth station; above, a ribbon of headlamps climbing into the dark.",
             isFixture: true, kind: "seat"))

    // Seventh station — Tomoekan.
    add(Item(id: "keeper7", name: "hut keeper", nouns: ["keeper", "keeper7", "hutkeeper"],
             description: "Tomoekan's keeper, quick with tea and quicker with the branding iron.",
             isFixture: true, isCreature: true))
    add(Item(id: "brazier7", name: "brazier", nouns: ["brazier", "fire", "iron"],
             description: "A charcoal brazier with Tomoekan's branding iron resting in the coals, its tip glowing the color of the coming sunrise.", isFixture: true))
    add(Item(id: "bench7", name: "hut bench", nouns: ["bench", "seat"],
             description: "A plank bench along Tomoekan's front wall, facing back down the mountain.",
             readText: "You sit on Tomoekan's bench with the whole night below you: the Fuji Five Lakes catching starlight, the towns strung out like dropped necklaces, and a slow-moving chain of headlamps winding up the trail beneath your boots.",
             isFixture: true, kind: "seat"))
    add(Item(id: "noodles", name: "hot noodles", nouns: ["noodles", "ramen", "udon", "soup"],
             description: "A steaming bowl of udon from Tomoekan's tiny kitchen, broth fogging your glasses on contact.",
             isTakeable: true, isFixture: true, forSale: true, price: 4, kind: "food"))

    // Eighth station — Taishikan.
    add(Item(id: "keeper8", name: "hut keeper", nouns: ["keeper", "keeper8", "hutkeeper"],
             description: "Taishikan's keeper, who has watched ten thousand headlamps go up and come back down, and remembers the ones that smiled.",
             isFixture: true, isCreature: true))
    add(Item(id: "cocoa", name: "hot cocoa", nouns: ["cocoa", "chocolate", "drink"],
             description: "A steaming cup of hot cocoa, priced for altitude and worth double.",
             isTakeable: true, isFixture: true, forSale: true, price: 3, kind: "cocoa"))
    add(Item(id: "bunks", name: "sleeping bunks", nouns: ["bunks", "bunk", "beds"],
             description: "Rows of snug sleeping shelves where climbers nap until the midnight push for the summit, packed in like contented sardines.", isFixture: true))
    add(Item(id: "bench8", name: "hut bench", nouns: ["bench", "seat"],
             description: "A bench outside Taishikan, bolted down against the wind, facing the drop.",
             readText: "You sit outside Taishikan at 3,100 meters. The clouds have closed over the valley like a lid, and the world is reduced to starlight, stove smoke, and the bobbing lanterns of climbers grinding up the switchbacks below. It is very cold and completely perfect.",
             isFixture: true, kind: "seat"))

    // Ninth station.
    add(Item(id: "toriiOld", name: "weathered torii", nouns: ["torii", "gate"],
             description: "A small weathered torii marks the old ninth station, its wood silvered by wind and prayer. The true summit gate waits above.", isFixture: true))

    // The summit.
    add(Item(id: "toriiSummit", name: "summit torii", nouns: ["torii", "gate"],
             description: "The summit torii, guardian of the top of Japan, every coin-scarred grain of it lit gold by the rising sun.", isFixture: true))
    add(Item(id: "kusushi", name: "Kusushi Shrine", nouns: ["shrine", "kusushi"],
             description: "Kusushi Shrine at the summit of the Yoshida Trail, where climbers give thanks that the mountain said yes — and where the shrine's fire keeps the summit branding iron ready.", isFixture: true))
    add(Item(id: "priest", name: "shrine priest", nouns: ["priest", "monk", "kannushi"],
             description: "The Kusushi Shrine priest, wind-creased and serene, keeper of the summit branding iron — the final mark a kongō-zue can earn.",
             isFixture: true, isCreature: true))
    add(Item(id: "sunrise", name: "goraiko sunrise", nouns: ["sunrise", "goraiko", "sun", "dawn", "clouds"],
             description: "The goraiko: the sun climbing out of a sea of clouds that stretches to the curve of the earth, gold pouring across the cloud tops while the crowd on the rim shouts \"Banzai!\" It does not look real. It is the realest thing you have ever seen.", isFixture: true))
    add(Item(id: "summitBench", name: "stone ledge", nouns: ["ledge", "bench", "seat", "rock"],
             description: "A flat stone ledge facing east, pre-warmed by the first sun.",
             readText: "You sit on the ledge with the sunrise on your face and the clouds below your feet. Someone nearby is quietly crying; someone else is eating instant noodles. Both responses are correct.",
             isFixture: true, kind: "seat"))

    // The summit post office.
    add(Item(id: "postbox", name: "red postbox", nouns: ["postbox", "mailbox", "box"],
             description: "The famous red postbox of the Mount Fuji summit post office — the highest mail drop in Japan, emptied daily in season by a very fit mail carrier.",
             isOpen: true, isContainer: true, isFixture: true))
    add(Item(id: "clerk", name: "postal clerk", nouns: ["clerk", "postmaster"],
             description: "The summit postal clerk, crisp and unbothered at 3,700 meters, guardian of Japan's most coveted postmark.",
             isFixture: true, isCreature: true))

    // The crater rim and Ken-ga-mine.
    add(Item(id: "crater", name: "crater", nouns: ["crater", "caldera", "rim"],
             description: "Fuji's summit crater: a vast, silent bowl of rust and shadow, 240 meters deep, ringed by eight peaks. Snow hides in its folds even now, and the wind moving across it is the oldest sound in Japan.", isFixture: true))
    add(Item(id: "marker", name: "summit marker", nouns: ["marker", "pillar", "stone"],
             description: "The worn stone pillar on Ken-ga-mine: MOUNT FUJI — HIGHEST PEAK IN JAPAN, 3,776 METERS. Every hand that ever made it up here has touched it. Yours does too.",
             readText: "\"KEN-GA-MINE — 剣ヶ峰 — 3,776m. Highest point of Mount Fuji and of Japan.\" The stone is worn glassy where a million summit photographs have leaned.",
             isFixture: true))
    add(Item(id: "radarBase", name: "old radar station", nouns: ["radar", "dome", "station"],
             description: "The footings of the old summit weather radar, which watched for typhoons from this spot for forty years — the highest weather station in Japan until satellites took the job. The mountain outlasted it, as the mountain outlasts everything.", isFixture: true))

    var rooms: [String: Room] = [:]
    func add(_ room: Room) { rooms[room.id] = room }

    add(Room(id: "fifthStation", title: "Fifth Station — The Lodge",
             description: "The Fifth Station lodge, 2,305 meters up the mountain's shoulder — half trailhead, half carnival: tour buses idling, the shop bright with walking sticks, headlamps, and storm jackets, free trail maps on the counter (TAKE one), Komitake Shrine watching over it all, and pack horses dozing by the trail. Above, Fuji's dark cone blots out the stars. The Yoshida Trail climbs UP.",
             exits: [.up: "sixthStation", .north: "sixthStation"],
             items: ["shopkeeper", "trailMap", "stick", "headlamp", "jacket", "letter", "oxygen", "komitake", "horses"]))
    add(Room(id: "sixthStation", title: "Sixth Station — Safety Center",
             description: "The trail proper begins: volcanic gravel crunching underfoot, a switchback rising into the dark. The safety center posts tonight's weather (READ the BULLETIN), the mountain guide checks climbers through beside his little branding brazier, warm onigiri wait in the counter warmer, and a bench faces the valley (SIT for the view). The trail climbs UP; the lodge is back DOWN.",
             exits: [.up: "seventhHut", .down: "fifthStation", .north: "seventhHut", .south: "fifthStation"],
             items: ["safetyCenter", "guide", "onigiri", "bench6"]))
    add(Room(id: "seventhHut", title: "Seventh Station — Tomoekan",
             description: "The mountain hut Tomoekan clings to the slope at the seventh station, lamplight spilling from its door, hot noodles steaming at the counter, and a charcoal brazier glowing out front with the hut's branding iron in the coals. A bench faces the drop (SIT for the view). The trail climbs UP; the sixth station is DOWN.",
             exits: [.up: "eighthHut", .down: "sixthStation", .north: "eighthHut", .south: "sixthStation"],
             items: ["keeper7", "brazier7", "bench7", "noodles"]))
    add(Room(id: "eighthHut", title: "Eighth Station — Taishikan",
             description: "Taishikan, the eighth-station hut, 3,100 meters: bunks stacked snug inside, hot cocoa at the counter, the keeper's branding iron ready at the fire, and a wind-bolted bench facing the drop (SIT for the view). Above here the trail is dark, thin-aired, and exposed to whatever the night is doing. The summit push climbs UP; the seventh station is DOWN.",
             exits: [.up: "ninthStation", .down: "seventhHut", .north: "ninthStation", .south: "seventhHut"],
             items: ["keeper8", "cocoa", "bunks", "bench8"]))
    add(Room(id: "ninthStation", title: "Ninth Station — The Final Stretch",
             description: "The last stretch above the ninth station: bare volcanic rock, switchbacks cut into the cone, a weathered torii marking the old station, and the summit somewhere overhead. Your headlamp beam is the whole visible world. The summit torii is UP; Taishikan is DOWN.",
             exits: [.up: "summit", .down: "eighthHut", .north: "summit", .south: "eighthHut"],
             items: ["toriiOld"], isDark: true))
    add(Room(id: "summit", title: "The Summit — Tenth Station",
             description: "The top of the Yoshida Trail — the tenth station: the summit torii, Kusushi Shrine beyond it where the priest tends the summit branding fire, and the east ablaze with the goraiko over an endless sea of clouds. A stone ledge faces the sunrise (SIT — you've earned it). The summit post office is just INSIDE; the crater rim path leads EAST; the trail back down the mountain is DOWN.",
             exits: [.down: "ninthStation", .inside: "postOffice", .east: "craterRim", .south: "ninthStation"],
             items: ["toriiSummit", "kusushi", "priest", "sunrise", "summitBench"]))
    add(Room(id: "postOffice", title: "Summit Post Office",
             description: "A tiny wooden post office at the top of Japan — a counter, a clerk, a rack of letters and cards, and the famous red postbox. Mail dropped here carries the Mount Fuji summit postmark, and somebody's mother is about to be very proud. The torii is back OUTSIDE.",
             exits: [.outside: "summit"],
             items: ["clerk", "postbox", "letter"]))
    add(Room(id: "craterRim", title: "The Crater Rim",
             description: "The path along the crater rim, the great silent bowl falling away to one side and the sea of clouds to the other. Wind, rock, and morning light — nothing else up here but the eight peaks of the rim. Ken-ga-mine, the highest, is a short climb UP; the summit torii is back WEST.",
             exits: [.up: "kengamine", .west: "summit", .north: "kengamine"],
             items: ["crater"]))
    add(Room(id: "kengamine", title: "Ken-ga-mine — The True Summit",
             description: "Ken-ga-mine: the highest of the crater's eight peaks and the highest ground in Japan, crowned by the worn summit marker and the footings of the old weather radar. There is nowhere further up. The rim path leads back DOWN.",
             exits: [.down: "craterRim", .south: "craterRim"],
             items: ["marker", "radarBase"]))

    return (rooms, items)
}

