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

    /// All playable scenarios, for the selection menu.
    static let scenarios: [Scenario] = [houseScenario(), townScenario()]

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
    func has(flag: String) -> Bool { flags.contains(flag) }
    func set(flag: String) { flags.insert(flag) }
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
        case "go", "walk", "run", "climb", "enter", "crawl", "cross":
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
            emit("I don't know how to \"\(verb)\".")
        }
    }

    private func tokenize(_ input: String) -> [String] {
        let filler: Set<String> = ["the", "a", "an", "to", "at", "my", "some"]
        return input.lowercased()
            .split(whereSeparator: { !$0.isLetter })
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
