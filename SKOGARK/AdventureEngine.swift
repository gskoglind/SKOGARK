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
/// act as light sources, or serve as containers for other items.
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

    func matches(_ word: String) -> Bool {
        nouns.contains(word)
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
/// that turns a line of typed input into transcript output.
@Observable
final class Game {
    private(set) var transcript: [TranscriptEntry] = []
    private(set) var moves = 0
    private(set) var score = 0
    private(set) var isWon = false

    private var rooms: [String: Room] = [:]
    private var items: [String: Item] = [:]
    private var inventory: [String] = []
    private var currentRoomID: String = "westOfHouse"
    private var rugMoved = false
    private var catFed = false
    private var nextEntryID = 0

    /// Item IDs that behave as creatures you can give things to.
    private let creatureIDs: Set<String> = ["cat"]

    private let maxScore = 25

    init() {
        buildWorld()
        emit(bannerText, asCommand: false)
        describeCurrentRoom(force: true)
    }

    // MARK: World Construction

    private func buildWorld() {
        items = [:]
        add(Item(id: "leaflet", name: "leaflet", nouns: ["leaflet", "paper", "mail"],
                 description: "A small paper leaflet.", isTakeable: true,
                 readText: "\"WELCOME TO SKOGARK!\n\nSkoGarK is a game of adventure and low cunning. In it you will explore a house and the caverns beneath it in search of treasure. Beware the grue — it lurks in darkness. Type HELP if you get stuck.\""))
        add(Item(id: "mailbox", name: "small mailbox", nouns: ["mailbox", "box"],
                 description: "It's a small mailbox.", isOpenable: true, isContainer: true,
                 contents: ["leaflet"]))
        add(Item(id: "window", name: "window", nouns: ["window"],
                 description: "The kitchen window is slightly ajar.", isOpenable: true))
        add(Item(id: "lantern", name: "brass lantern", nouns: ["lantern", "lamp", "light"],
                 description: "A battered brass lantern.", isTakeable: true, isLightSource: true))
        add(Item(id: "bottle", name: "glass bottle", nouns: ["bottle", "water"],
                 description: "A glass bottle containing a little water.", isTakeable: true))
        add(Item(id: "rug", name: "oriental rug", nouns: ["rug", "carpet"],
                 description: "A large oriental rug in the center of the room."))
        add(Item(id: "trapdoor", name: "trap door", nouns: ["trapdoor", "trap", "door", "hatch"],
                 description: "A closed wooden trap door in the floor.", isOpenable: true))
        add(Item(id: "case", name: "trophy case", nouns: ["case", "trophy"],
                 description: "A handsome glass trophy case, waiting to be filled.",
                 isOpenable: true, isContainer: true))
        add(Item(id: "egg", name: "jeweled egg", nouns: ["egg", "jewel", "treasure"],
                 description: "A stunning jeweled egg that glitters even in faint light.",
                 isTakeable: true))
        add(Item(id: "fish", name: "fresh fish", nouns: ["fish", "herring", "catch"],
                 description: "A fat, silver fish fresh from the stall, still glistening.",
                 isTakeable: true))
        add(Item(id: "cat", name: "stray cat", nouns: ["cat", "kitten", "stray"],
                 description: "A scruffy stray cat with matted fur, watching the fishmonger's stall with hungry, hopeful eyes."))

        rooms = [:]
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
    }

    private func add(_ item: Item) { items[item.id] = item }
    private func add(_ room: Room) { rooms[room.id] = room }

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
            // "what can i see", "what's here", or a bare SURVEY.
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
        case "inventory", "i", "inv":
            showInventory()
        case "score":
            emit("Your score is \(score) of a possible \(maxScore), in \(moves) moves.")
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

        // Entering the house requires the kitchen window to be open.
        if direction == .inside, currentRoomID == "behindHouse",
           items["window"]?.isOpen != true {
            emit("The window is closed. You'll need to open it first.")
            return
        }

        // Descending to the cellar requires an open trap door.
        if direction == .down, currentRoomID == "livingRoom" {
            guard rugMoved else {
                emit("You can't go that way.")
                return
            }
            guard items["trapdoor"]?.isOpen == true else {
                emit("The trap door is closed.")
                return
            }
        }

        guard let destination = room.exits[direction] else {
            emit("You can't go that way.")
            return
        }

        currentRoomID = destination
        describeCurrentRoom()
    }

    /// Handles a movement verb whose object may be a direction word, a
    /// portal you pass through ("go through the window", "enter window"),
    /// or the name of an adjacent room ("go to the kitchen").
    private func handleGo(_ words: [String]) {
        // 1. An explicit direction word anywhere in the phrase.
        if let dir = words.compactMap({ Direction.from($0) }).first {
            move(dir)
            return
        }
        // 2. A named portal, such as the kitchen window or the trap door.
        if let id = resolveItem(words), let dir = portalDirection(for: id) {
            move(dir)
            return
        }
        // 3. The name of an adjacent room ("enter kitchen").
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

    /// Maps a portal item — one you travel through rather than pick up — to
    /// the direction that passes through it from the current room.
    private func portalDirection(for id: String) -> Direction? {
        switch id {
        case "window":
            if currentRoomID == "behindHouse" { return .inside }
            if currentRoomID == "kitchen" { return .outside }
            return nil
        case "trapdoor":
            return .down
        default:
            return nil
        }
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
            // Fixtures are woven into the room description already.
            if !item.isTakeable && ["mailbox", "window", "case", "rug", "trapdoor"].contains(itemID) {
                if itemID == "trapdoor" {
                    lines.append("A trap door is set into the floor. It is \(item.isOpen ? "open" : "closed").")
                } else if itemID == "case" {
                    let contents = item.contents.compactMap { items[$0]?.name }
                    if contents.isEmpty {
                        lines.append("The trophy case is \(item.isOpen ? "open and empty" : "closed").")
                    } else {
                        lines.append("The trophy case contains: \(contents.joined(separator: ", ")).")
                    }
                }
                continue
            }
            lines.append("There is a \(item.name) here.")
        }
        emit(lines.joined(separator: "\n"))
    }

    /// A low-spoiler perception command ("what can I see" / "look around").
    /// Lists the objects visible in the current room and its obvious exits,
    /// relying on the engine's existing visibility — so genuinely hidden
    /// things (like the trap door beneath the rug) stay hidden until found.
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

    /// The directions the player could reasonably know they can travel,
    /// in a stable reading order. Gated passages that haven't been
    /// discovered yet (the cellar stairs under the rug) are withheld so
    /// this stays a hint-free perception aid.
    private func obviousExits() -> [Direction] {
        guard let room = rooms[currentRoomID] else { return [] }
        return Direction.allCases.filter { direction in
            guard room.exits[direction] != nil else { return false }
            if currentRoomID == "livingRoom", direction == .down, !rugMoved { return false }
            return true
        }
    }

    // MARK: Item Resolution

    /// Finds a visible item matching the given noun words, searching the
    /// player's inventory and the current room (including open containers).
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
            // Include contents of open containers in the room.
            for itemID in room.items {
                if let item = items[itemID], item.isContainer, item.isOpen {
                    ids += item.contents
                }
            }
        }
        // Include contents of open containers carried by the player.
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
        guard item.isTakeable else {
            emit("You can't take the \(item.name).")
            return
        }
        removeItemFromWorld(id)
        inventory.append(id)
        if id == "egg" { award(5, "You've found a treasure!") }
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
        if id == "rug" {
            if rugMoved {
                emit("You've already moved the rug aside.")
                return
            }
            rugMoved = true
            rooms["livingRoom"]?.items.append("trapdoor")
            award(2, nil)
            emit("With a great heave you drag the rug aside, revealing a dusty trap door set into the floor.")
            return
        }
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
        // Split the words around "in"/"into"/"inside"/"on".
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

        if targetID == "case" && objectID == "egg" {
            award(10, nil)
            winGame()
        }
    }

    /// Give a carried item to a creature. Word order is free ("give fish to
    /// cat" or "feed cat fish") since the tokenizer strips "to"; roles are
    /// resolved by matching a visible creature and a carried item.
    private func give(_ words: [String]) {
        moves += 1
        let visible = visibleItemIDs()
        let recipientID = words.lazy.compactMap { word in
            visible.first { self.items[$0]?.matches(word) == true && self.creatureIDs.contains($0) }
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

        // The stray cat rewards a fish — but only the first time.
        if recipientID == "cat", giftID == "fish" {
            if catFed {
                emit("The cat has already had its fill and just blinks at you contentedly.")
                return
            }
            catFed = true
            inventory.removeAll { $0 == giftID }
            award(3, nil)
            emit("You offer the fish to the stray cat. It gulps the treat down, then winds around your ankles with a rumbling purr. You've made a friend.")
            return
        }

        emit("The \(recipient.name) has no interest in the \(gift.name).")
    }

    private func showInventory() {
        if inventory.isEmpty {
            emit("You are empty-handed.")
            return
        }
        let lines = ["You are carrying:"] + inventory.compactMap { items[$0].map { "  a \($0.name)" } }
        emit(lines.joined(separator: "\n"))
    }

    // MARK: Helpers

    private func removeItemFromWorld(_ id: String) {
        rooms[currentRoomID]?.items.removeAll { $0 == id }
        // Also remove from any container it might live in.
        for (key, var item) in items where item.contents.contains(id) {
            item.contents.removeAll { $0 == id }
            items[key] = item
        }
    }

    private func award(_ points: Int, _ note: String?) {
        score += points
        if let note { emit(note) }
    }

    private func winGame() {
        isWon = true
        emit("""

        The jeweled egg settles into the trophy case with a soft, satisfying click. Light dances through the glass.

        *** You have won! ***

        Your score is \(score) of a possible \(maxScore), in \(moves) moves.
        Type RESTART to play again.
        """)
    }

    // MARK: Save & Restore

    private static let saveKey = "skogark.savegame"

    /// True when a saved game exists on disk (used by the UI to enable
    /// a Restore affordance).
    var hasSavedGame: Bool {
        UserDefaults.standard.data(forKey: Self.saveKey) != nil
    }

    /// A serializable capture of every piece of mutable game state.
    private struct Snapshot: Codable {
        var rooms: [String: Room]
        var items: [String: Item]
        var inventory: [String]
        var currentRoomID: String
        var rugMoved: Bool
        var catFed: Bool?
        var score: Int
        var moves: Int
        var isWon: Bool
        var transcript: [TranscriptEntry]
        var nextEntryID: Int
    }

    private func save() {
        let snapshot = Snapshot(
            rooms: rooms, items: items, inventory: inventory,
            currentRoomID: currentRoomID, rugMoved: rugMoved, catFed: catFed,
            score: score, moves: moves, isWon: isWon,
            transcript: transcript, nextEntryID: nextEntryID
        )
        do {
            let data = try JSONEncoder().encode(snapshot)
            UserDefaults.standard.set(data, forKey: Self.saveKey)
            emit("Game saved.")
        } catch {
            emit("Something went wrong and the game could not be saved.")
        }
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: Self.saveKey) else {
            emit("There is no saved game to restore.")
            return
        }
        do {
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
            rooms = snapshot.rooms
            items = snapshot.items
            inventory = snapshot.inventory
            currentRoomID = snapshot.currentRoomID
            rugMoved = snapshot.rugMoved
            catFed = snapshot.catFed ?? false
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
        transcript = []
        moves = 0
        score = 0
        isWon = false
        inventory = []
        currentRoomID = "westOfHouse"
        rugMoved = false
        catFed = false
        buildWorld()
        emit(bannerText, asCommand: false)
        describeCurrentRoom(force: true)
    }

    private func emit(_ text: String, asCommand: Bool = false) {
        transcript.append(TranscriptEntry(id: nextEntryID, text: text, isCommand: asCommand))
        nextEntryID += 1
    }

    // MARK: Static Text

    private var bannerText: String {
        """
        SKOGARK
        A tiny text adventure. (c) 2026
        Type HELP for a list of commands.
        ─────────────────────────────
        """
    }

    private var helpText: String {
        """
        Some things you can type:
          Directions: NORTH/N, SOUTH/S, EAST/E, WEST/W, UP/U, DOWN/D, IN, OUT
          LOOK (L)              — describe your surroundings
          LOOK AROUND           — list what you can see here, and the exits
          EXAMINE <thing> (X)   — inspect something
          READ <thing>          — read something
          TAKE / DROP <thing>   — pick up or set down an item
          OPEN / CLOSE <thing>  — for doors, windows, containers
          MOVE <thing>          — shift a heavy object
          TURN ON / OFF LAMP    — control a light source
          PUT <thing> IN <thing>— place an item in a container
          GIVE <thing> TO <someone> — offer an item to a creature
          INVENTORY (I)         — list what you're carrying
          SCORE                 — check your progress
          SAVE / RESTORE        — save or reload your game
          RESTART               — start over
        """
    }
}
