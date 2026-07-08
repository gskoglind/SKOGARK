// SKOGARK — text-adventure engine.
//
// A faithful JavaScript port of AdventureEngine.swift. The game logic is
// pure and deterministic: process(input) is the single entry point that
// turns a line of typed input into transcript output. No DOM access lives
// here — the UI (app.js) reads `game.transcript` after each call.

"use strict";

// The compass and vertical directions, plus "inside"/"outside". The order
// here is the reading order used when listing a room's obvious exits.
const DIRECTIONS = ["north", "south", "east", "west", "up", "down", "inside", "outside"];

// Maps typed shorthand (n, s, e, w, u, d, in, out) to a direction.
function directionFrom(word) {
    switch (word) {
        case "n": case "north": return "north";
        case "s": case "south": return "south";
        case "e": case "east": return "east";
        case "w": case "west": return "west";
        case "u": case "up": return "up";
        case "d": case "down": return "down";
        case "in": case "inside": case "enter": return "inside";
        case "out": case "outside": case "exit": case "leave": return "outside";
        default: return DIRECTIONS.includes(word) ? word : null;
    }
}

// An Item with sensible defaults for every optional flag.
function makeItem(props) {
    return Object.assign({
        id: "", name: "", nouns: [], description: "",
        isTakeable: false, isLightSource: false, isLit: false,
        isOpenable: false, isOpen: false, isContainer: false,
        contents: [], readText: null,
    }, props);
}

// A Room with named exits and the items resting there.
function makeRoom(props) {
    return Object.assign({
        id: "", title: "", description: "",
        exits: {}, items: [], isDark: false, visited: false,
    }, props);
}

const SAVE_KEY = "skogark.savegame";
const MAX_SCORE = 25;

class Game {
    constructor() {
        this.transcript = [];
        this.moves = 0;
        this.score = 0;
        this.isWon = false;

        this.rooms = {};
        this.items = {};
        this.inventory = [];
        this.currentRoomID = "westOfHouse";
        this.rugMoved = false;
        this.catFed = false;
        this.nextEntryID = 0;

        // Item IDs that behave as creatures you can give things to.
        this.creatureIDs = ["cat"];

        this.buildWorld();
        this.emit(this.bannerText(), false);
        this.describeCurrentRoom(true);
    }

    // MARK: World Construction

    buildWorld() {
        this.items = {};
        const addItem = (p) => { const it = makeItem(p); this.items[it.id] = it; };
        addItem({ id: "leaflet", name: "leaflet", nouns: ["leaflet", "paper", "mail"],
            description: "A small paper leaflet.", isTakeable: true,
            readText: "\"WELCOME TO SKOGARK!\n\nSkoGarK is a game of adventure and low cunning. In it you will explore a house and the caverns beneath it in search of treasure. Beware the grue — it lurks in darkness. Type HELP if you get stuck.\"" });
        addItem({ id: "mailbox", name: "small mailbox", nouns: ["mailbox", "box"],
            description: "It's a small mailbox.", isOpenable: true, isContainer: true,
            contents: ["leaflet"] });
        addItem({ id: "window", name: "window", nouns: ["window"],
            description: "The kitchen window is slightly ajar.", isOpenable: true });
        addItem({ id: "lantern", name: "brass lantern", nouns: ["lantern", "lamp", "light"],
            description: "A battered brass lantern.", isTakeable: true, isLightSource: true });
        addItem({ id: "bottle", name: "glass bottle", nouns: ["bottle", "water"],
            description: "A glass bottle containing a little water.", isTakeable: true });
        addItem({ id: "rug", name: "oriental rug", nouns: ["rug", "carpet"],
            description: "A large oriental rug in the center of the room." });
        addItem({ id: "trapdoor", name: "trap door", nouns: ["trapdoor", "trap", "door", "hatch"],
            description: "A closed wooden trap door in the floor.", isOpenable: true });
        addItem({ id: "case", name: "trophy case", nouns: ["case", "trophy"],
            description: "A handsome glass trophy case, waiting to be filled.",
            isOpenable: true, isContainer: true });
        addItem({ id: "egg", name: "jeweled egg", nouns: ["egg", "jewel", "treasure"],
            description: "A stunning jeweled egg that glitters even in faint light.",
            isTakeable: true });
        addItem({ id: "fish", name: "fresh fish", nouns: ["fish", "herring", "catch"],
            description: "A fat, silver fish fresh from the stall, still glistening.",
            isTakeable: true });
        addItem({ id: "cat", name: "stray cat", nouns: ["cat", "kitten", "stray"],
            description: "A scruffy stray cat with matted fur, watching the fishmonger's stall with hungry, hopeful eyes." });

        this.rooms = {};
        const addRoom = (p) => { const r = makeRoom(p); this.rooms[r.id] = r; };
        addRoom({ id: "westOfHouse", title: "West of House",
            description: "You are standing in an open field west of a white house, with a boarded front door. A small mailbox stands here.",
            exits: { east: "behindHouse", north: "behindHouse" }, items: ["mailbox"] });
        addRoom({ id: "behindHouse", title: "Behind House",
            description: "You are behind the white house. A path leads into the forest to the east. One window into the kitchen is slightly ajar.",
            exits: { west: "westOfHouse", inside: "kitchen", east: "forestPath" }, items: ["window"] });
        addRoom({ id: "kitchen", title: "Kitchen",
            description: "You are in the kitchen of the white house. A table sits in the middle of the room. A passage leads west, and a dark staircase leads up. To the east, a window opens onto the yard.",
            exits: { west: "livingRoom", outside: "behindHouse", east: "behindHouse" }, items: ["lantern", "bottle"] });
        addRoom({ id: "livingRoom", title: "Living Room",
            description: "You are in the living room. There is a trophy case here, and a large oriental rug lies in the center of the floor. A doorway leads east to the kitchen.",
            exits: { east: "kitchen", down: "cellar" }, items: ["case", "rug"] });
        addRoom({ id: "cellar", title: "Cellar",
            description: "You are in a damp, cramped cellar carved from the rock. A rickety staircase leads up toward the living room.",
            exits: { up: "livingRoom" }, items: ["egg"], isDark: true });

        // The village, reached along the forest path east of the house.
        addRoom({ id: "forestPath", title: "Forest Path",
            description: "A narrow dirt path winds through cool, whispering pines. The white house lies back to the west, while ahead to the east the trees thin toward the rooftops of a village.",
            exits: { west: "behindHouse", east: "villageSquare" } });
        addRoom({ id: "villageSquare", title: "Village Square",
            description: "You stand on the cobbles at the heart of a small village. Shops crowd the edges: a butcher to the north and a bakery to the south. A lane leads east toward the market, and the forest path returns west toward the house.",
            exits: { west: "forestPath", north: "butcher", south: "bakery", east: "marketRow" } });
        addRoom({ id: "marketRow", title: "Market Row",
            description: "A bustling market row, hemmed in by timber-framed storefronts. A fishmonger's stall stands to the north and a blacksmith's forge glows to the south. The village square lies back to the west.",
            exits: { west: "villageSquare", north: "fishmonger", south: "blacksmith" }, items: ["cat"] });
        addRoom({ id: "butcher", title: "The Butcher",
            description: "The butcher's shop smells of sawdust and cold iron. Cuts of meat hang from steel hooks while a broad-shouldered butcher wipes his hands on a striped apron. The square is back to the south.",
            exits: { south: "villageSquare" } });
        addRoom({ id: "bakery", title: "The Bakery",
            description: "Warm air and the scent of fresh bread fill the bakery. Loaves and pastries are stacked on wooden shelves, and a flour-dusted baker nods you a greeting. The square lies north.",
            exits: { north: "villageSquare" } });
        addRoom({ id: "fishmonger", title: "The Fishmonger",
            description: "The fishmonger's stall glistens with the day's catch laid out on crushed ice. A brisk woman in oilskins calls her prices to no one in particular. Market row is back to the south.",
            exits: { south: "marketRow" }, items: ["fish"] });
        addRoom({ id: "blacksmith", title: "The Blacksmith",
            description: "Heat rolls off the blacksmith's forge, and the ring of hammer on anvil fills the air. A soot-streaked smith pauses, tongs in hand, to size you up. Market row lies north.",
            exits: { north: "marketRow" } });
    }

    // MARK: Input Handling

    process(rawInput) {
        const input = rawInput.trim();
        if (!input) return;
        this.emit("> " + input, true);

        const tokens = this.tokenize(input);
        if (tokens.length === 0) { this.emit("I don't understand that."); return; }
        const verb = tokens[0];

        // After winning, only meta commands remain available.
        if (this.isWon && !["restart", "restore", "load", "score", "save"].includes(verb)) {
            this.emit("You've already won. Type RESTART to play again.");
            return;
        }

        // A bare direction word means "go that way".
        if (tokens.length === 1) {
            const dir = directionFrom(verb);
            if (dir) { this.move(dir); return; }
        }

        const rest = tokens.slice(1);
        switch (verb) {
            case "look": case "l":
                if (rest[0] === "at" && rest.length > 1) {
                    this.examine(rest.slice(1));
                } else if (rest.includes("around") || rest.includes("here")) {
                    this.lookAround();
                } else {
                    this.describeCurrentRoom(true);
                }
                break;
            case "what": case "survey":
                this.lookAround();
                break;
            case "go": case "walk": case "run": case "climb":
            case "enter": case "crawl": case "cross":
                this.handleGo(rest);
                break;
            case "examine": case "x": case "inspect": case "read":
                if (verb === "read") this.readItem(rest); else this.examine(rest);
                break;
            case "take": case "get": case "grab": case "pick":
                this.take(rest.filter((w) => w !== "up"));
                break;
            case "drop":
                this.drop(rest);
                break;
            case "open":
                this.setOpen(rest, true);
                break;
            case "close": case "shut":
                this.setOpen(rest, false);
                break;
            case "move": case "push": case "pull": case "slide":
                this.moveObject(rest);
                break;
            case "turn":
                this.turn(rest);
                break;
            case "light": case "activate":
                this.turnLantern(true);
                break;
            case "extinguish":
                this.turnLantern(false);
                break;
            case "put": case "place": case "insert":
                this.put(rest);
                break;
            case "give": case "offer": case "feed":
                this.give(rest);
                break;
            case "inventory": case "i": case "inv":
                this.showInventory();
                break;
            case "score":
                this.emit(`Your score is ${this.score} of a possible ${MAX_SCORE}, in ${this.moves} moves.`);
                break;
            case "why":
                this.emit("Why not? Adventure rarely waits for a reason. Type HELP if you're stuck.");
                break;
            case "help": case "?":
                this.emit(this.helpText());
                break;
            case "save":
                this.save();
                break;
            case "restore": case "load":
                this.restore();
                break;
            case "restart":
                this.restart();
                break;
            default:
                this.emit(`I don't know how to "${verb}".`);
        }
    }

    tokenize(input) {
        const filler = new Set(["the", "a", "an", "to", "at", "my", "some"]);
        return input.toLowerCase()
            .split(/[^a-z]+/)
            .filter((w) => w.length > 0 && !filler.has(w));
    }

    // MARK: Movement

    move(direction) {
        this.moves += 1;
        const room = this.rooms[this.currentRoomID];
        if (!room) return;

        // Entering the house requires the kitchen window to be open.
        if (direction === "inside" && this.currentRoomID === "behindHouse" &&
            !(this.items["window"] && this.items["window"].isOpen)) {
            this.emit("The window is closed. You'll need to open it first.");
            return;
        }

        // Descending to the cellar requires an open trap door.
        if (direction === "down" && this.currentRoomID === "livingRoom") {
            if (!this.rugMoved) { this.emit("You can't go that way."); return; }
            if (!(this.items["trapdoor"] && this.items["trapdoor"].isOpen)) {
                this.emit("The trap door is closed."); return;
            }
        }

        const destination = room.exits[direction];
        if (!destination) { this.emit("You can't go that way."); return; }

        this.currentRoomID = destination;
        this.describeCurrentRoom(false);
    }

    // Handles a movement verb whose object may be a direction word, a portal
    // you pass through ("go through the window"), or an adjacent room name.
    handleGo(words) {
        for (const w of words) {
            const dir = directionFrom(w);
            if (dir) { this.move(dir); return; }
        }
        const id = this.resolveItem(words);
        if (id) {
            const dir = this.portalDirection(id);
            if (dir) { this.move(dir); return; }
        }
        const room = this.rooms[this.currentRoomID];
        if (room) {
            for (const dir of DIRECTIONS) {
                const destinationID = room.exits[dir];
                if (!destinationID) continue;
                const destination = this.rooms[destinationID];
                if (!destination) continue;
                const titleWords = new Set(destination.title.toLowerCase().split(/[^a-z]+/).filter(Boolean));
                if (words.some((w) => titleWords.has(w))) { this.move(dir); return; }
            }
        }
        this.emit("Go where?");
    }

    // Maps a portal item to the direction that passes through it from here.
    portalDirection(id) {
        if (id === "window") {
            if (this.currentRoomID === "behindHouse") return "inside";
            if (this.currentRoomID === "kitchen") return "outside";
            return null;
        }
        if (id === "trapdoor") return "down";
        return null;
    }

    // MARK: Description & Visibility

    canSee() {
        const room = this.rooms[this.currentRoomID];
        if (!room) return false;
        if (!room.isDark) return true;
        const candidates = this.inventory.concat(room.items);
        return candidates.some((id) => this.items[id] && this.items[id].isLit);
    }

    describeCurrentRoom(force) {
        const room = this.rooms[this.currentRoomID];
        if (!room) return;

        if (!this.canSee()) {
            this.emit("Pitch black.\nIt is so dark you can't see a thing. You are likely to be eaten by a grue.");
            room.visited = true;
            return;
        }

        const firstVisit = !room.visited;
        room.visited = true;

        const lines = [room.title];
        if (firstVisit || force) lines.push(room.description);
        for (const itemID of room.items) {
            const item = this.items[itemID];
            if (!item) continue;
            // Fixtures are woven into the room description already.
            if (!item.isTakeable && ["mailbox", "window", "case", "rug", "trapdoor"].includes(itemID)) {
                if (itemID === "trapdoor") {
                    lines.push(`A trap door is set into the floor. It is ${item.isOpen ? "open" : "closed"}.`);
                } else if (itemID === "case") {
                    const contents = item.contents.map((c) => this.items[c] && this.items[c].name).filter(Boolean);
                    if (contents.length === 0) {
                        lines.push(`The trophy case is ${item.isOpen ? "open and empty" : "closed"}.`);
                    } else {
                        lines.push(`The trophy case contains: ${contents.join(", ")}.`);
                    }
                }
                continue;
            }
            lines.push(`There is a ${item.name} here.`);
        }
        this.emit(lines.join("\n"));
    }

    // A low-spoiler perception command ("what can I see" / "look around").
    lookAround() {
        if (!this.canSee()) { this.emit("It's too dark to see anything."); return; }
        const room = this.rooms[this.currentRoomID];
        if (!room) return;

        const lines = [];
        const names = [];
        for (const itemID of room.items) {
            const item = this.items[itemID];
            if (!item) continue;
            if (item.isContainer && item.isOpen && item.contents.length > 0) {
                const inside = item.contents.map((c) => this.items[c] && this.items[c].name).filter(Boolean);
                names.push(`${item.name} (holding ${inside.join(", ")})`);
            } else {
                names.push(item.name);
            }
        }
        if (names.length === 0) {
            lines.push("You see nothing here worth remarking on.");
        } else {
            lines.push(`You can see: ${names.join(", ")}.`);
        }

        const exits = this.obviousExits();
        if (exits.length > 0) {
            lines.push(`Obvious exits: ${exits.join(", ")}.`);
        }
        this.emit(lines.join("\n"));
    }

    // Directions the player could reasonably know they can travel. Gated
    // passages not yet discovered (the cellar stairs) are withheld.
    obviousExits() {
        const room = this.rooms[this.currentRoomID];
        if (!room) return [];
        return DIRECTIONS.filter((dir) => {
            if (!room.exits[dir]) return false;
            if (this.currentRoomID === "livingRoom" && dir === "down" && !this.rugMoved) return false;
            return true;
        });
    }

    // MARK: Item Resolution

    resolveItem(words) {
        const candidateIDs = this.visibleItemIDs();
        for (const word of words) {
            const id = candidateIDs.find((id) => this.items[id] && this.items[id].nouns.includes(word));
            if (id) return id;
        }
        return null;
    }

    visibleItemIDs() {
        let ids = this.inventory.slice();
        const room = this.rooms[this.currentRoomID];
        if (room) {
            ids = ids.concat(room.items);
            for (const itemID of room.items) {
                const item = this.items[itemID];
                if (item && item.isContainer && item.isOpen) ids = ids.concat(item.contents);
            }
        }
        for (const itemID of this.inventory) {
            const item = this.items[itemID];
            if (item && item.isContainer && item.isOpen) ids = ids.concat(item.contents);
        }
        return ids;
    }

    // MARK: Verbs

    examine(words) {
        if (!this.canSee()) { this.emit("It's too dark to see anything."); return; }
        const id = this.resolveItem(words);
        const item = id && this.items[id];
        if (!item) { this.emit("You don't see that here."); return; }
        let text = item.description;
        if (item.isContainer) {
            if (item.isOpen) {
                const contents = item.contents.map((c) => this.items[c] && this.items[c].name).filter(Boolean);
                text += contents.length === 0 ? " It is open and empty."
                    : ` It contains: ${contents.join(", ")}.`;
            } else {
                text += " It is closed.";
            }
        }
        if (item.isLightSource) {
            text += item.isLit ? " It is currently lit." : " It is not lit.";
        }
        this.emit(text);
    }

    readItem(words) {
        if (!this.canSee()) { this.emit("It's too dark to read."); return; }
        const id = this.resolveItem(words);
        const item = id && this.items[id];
        if (!item) { this.emit("You don't see that here."); return; }
        if (item.readText != null) {
            this.emit(item.readText);
        } else {
            this.emit(`There's nothing to read on the ${item.name}.`);
        }
    }

    take(words) {
        this.moves += 1;
        if (!this.canSee()) { this.emit("It's too dark to see what you're grabbing."); return; }
        const id = this.resolveItem(words);
        const item = id && this.items[id];
        if (!item) { this.emit("You don't see that here."); return; }
        if (this.inventory.includes(id)) { this.emit(`You're already carrying the ${item.name}.`); return; }
        if (!item.isTakeable) { this.emit(`You can't take the ${item.name}.`); return; }
        this.removeItemFromWorld(id);
        this.inventory.push(id);
        if (id === "egg") this.award(5, "You've found a treasure!");
        this.emit("Taken.");
    }

    drop(words) {
        this.moves += 1;
        const id = this.resolveItem(words.filter((w) => w !== "down"));
        if (!id || !this.inventory.includes(id) || !this.items[id]) {
            this.emit("You're not carrying that.");
            return;
        }
        const item = this.items[id];
        this.inventory = this.inventory.filter((x) => x !== id);
        this.rooms[this.currentRoomID].items.push(id);
        this.emit(`You drop the ${item.name}.`);
    }

    setOpen(words, open) {
        this.moves += 1;
        const id = this.resolveItem(words);
        const item = id && this.items[id];
        if (!item) { this.emit("You don't see that here."); return; }
        if (!item.isOpenable) { this.emit(`You can't ${open ? "open" : "close"} the ${item.name}.`); return; }
        if (item.isOpen === open) { this.emit(`It's already ${open ? "open" : "closed"}.`); return; }
        item.isOpen = open;
        if (item.isContainer && open && item.contents.length > 0) {
            const contents = item.contents.map((c) => this.items[c] && this.items[c].name).filter(Boolean);
            this.emit(`Opening the ${item.name} reveals: ${contents.join(", ")}.`);
        } else {
            this.emit(`${open ? "Opened" : "Closed"}.`);
        }
    }

    moveObject(words) {
        this.moves += 1;
        const id = this.resolveItem(words);
        if (!id) { this.emit("You don't see that here."); return; }
        if (id === "rug") {
            if (this.rugMoved) { this.emit("You've already moved the rug aside."); return; }
            this.rugMoved = true;
            this.rooms["livingRoom"].items.push("trapdoor");
            this.award(2, null);
            this.emit("With a great heave you drag the rug aside, revealing a dusty trap door set into the floor.");
            return;
        }
        this.emit(`Moving the ${this.items[id] ? this.items[id].name : "that"} accomplishes nothing.`);
    }

    turn(words) {
        if (words.includes("on")) this.turnLantern(true);
        else if (words.includes("off")) this.turnLantern(false);
        else this.emit("Turn it on or off?");
    }

    turnLantern(on) {
        this.moves += 1;
        const id = this.resolveItem(["lantern"]);
        const item = id && this.items[id];
        if (!item) { this.emit("You don't have a light source."); return; }
        if (item.isLit === on) { this.emit(`The lantern is already ${on ? "on" : "off"}.`); return; }
        item.isLit = on;
        this.emit(`The brass lantern is now ${on ? "on" : "off"}.`);
        // Re-describe if turning it on suddenly reveals a dark room.
        if (on) this.describeCurrentRoom(true);
    }

    put(words) {
        this.moves += 1;
        const separators = new Set(["in", "into", "inside", "on"]);
        const sepIndex = words.findIndex((w) => separators.has(w));
        if (sepIndex === -1) { this.emit('Put what where? Try "put egg in case".'); return; }
        const objectWords = words.slice(0, sepIndex);
        const targetWords = words.slice(sepIndex + 1);

        const objectID = this.resolveItem(objectWords);
        if (!objectID || !this.inventory.includes(objectID) || !this.items[objectID]) {
            this.emit("You need to be holding that first.");
            return;
        }
        const object = this.items[objectID];
        const targetID = this.resolveItem(targetWords);
        const target = targetID && this.items[targetID];
        if (!target || !target.isContainer) { this.emit("You can't put anything in that."); return; }
        if (!target.isOpen) { this.emit(`The ${target.name} is closed.`); return; }

        this.inventory = this.inventory.filter((x) => x !== objectID);
        target.contents.push(objectID);
        this.emit(`You place the ${object.name} in the ${target.name}.`);

        if (targetID === "case" && objectID === "egg") {
            this.award(10, null);
            this.winGame();
        }
    }

    // Give a carried item to a creature. Word order is free ("give fish to
    // cat" or "feed cat fish") since the tokenizer strips "to"; roles are
    // resolved by matching a visible creature and a carried item.
    give(words) {
        this.moves += 1;
        const visible = this.visibleItemIDs();
        let recipientID = null;
        for (const word of words) {
            const id = visible.find((id) => this.items[id] && this.items[id].nouns.includes(word) && this.creatureIDs.includes(id));
            if (id) { recipientID = id; break; }
        }
        let giftID = null;
        for (const word of words) {
            const id = this.inventory.find((id) => this.items[id] && this.items[id].nouns.includes(word));
            if (id) { giftID = id; break; }
        }

        const recipient = recipientID && this.items[recipientID];
        if (!recipient) { this.emit("There's no one here to give anything to."); return; }
        const gift = giftID && this.items[giftID];
        if (!gift) { this.emit(`You need to be holding something to give the ${recipient.name}.`); return; }

        // The stray cat rewards a fish — but only the first time.
        if (recipientID === "cat" && giftID === "fish") {
            if (this.catFed) { this.emit("The cat has already had its fill and just blinks at you contentedly."); return; }
            this.catFed = true;
            this.inventory = this.inventory.filter((x) => x !== giftID);
            this.award(3, null);
            this.emit("You offer the fish to the stray cat. It gulps the treat down, then winds around your ankles with a rumbling purr. You've made a friend.");
            return;
        }

        this.emit(`The ${recipient.name} has no interest in the ${gift.name}.`);
    }

    showInventory() {
        if (this.inventory.length === 0) { this.emit("You are empty-handed."); return; }
        const lines = ["You are carrying:"].concat(
            this.inventory.map((id) => this.items[id] ? `  a ${this.items[id].name}` : null).filter((x) => x !== null)
        );
        this.emit(lines.join("\n"));
    }

    // MARK: Helpers

    removeItemFromWorld(id) {
        const room = this.rooms[this.currentRoomID];
        if (room) room.items = room.items.filter((x) => x !== id);
        // Also remove from any container it might live in.
        for (const key in this.items) {
            const item = this.items[key];
            if (item.contents.includes(id)) item.contents = item.contents.filter((x) => x !== id);
        }
    }

    award(points, note) {
        this.score += points;
        if (note) this.emit(note);
    }

    winGame() {
        this.isWon = true;
        this.emit(
            "\nThe jeweled egg settles into the trophy case with a soft, satisfying click. Light dances through the glass." +
            "\n\n*** You have won! ***\n\n" +
            `Your score is ${this.score} of a possible ${MAX_SCORE}, in ${this.moves} moves.` +
            "\nType RESTART to play again."
        );
    }

    // MARK: Save & Restore (browser localStorage instead of UserDefaults)

    save() {
        const snapshot = {
            rooms: this.rooms, items: this.items, inventory: this.inventory,
            currentRoomID: this.currentRoomID, rugMoved: this.rugMoved, catFed: this.catFed,
            score: this.score, moves: this.moves, isWon: this.isWon,
            transcript: this.transcript, nextEntryID: this.nextEntryID,
        };
        try {
            localStorage.setItem(SAVE_KEY, JSON.stringify(snapshot));
            this.emit("Game saved.");
        } catch (e) {
            this.emit("Something went wrong and the game could not be saved.");
        }
    }

    restore() {
        let data = null;
        try { data = localStorage.getItem(SAVE_KEY); } catch (e) { data = null; }
        if (!data) { this.emit("There is no saved game to restore."); return; }
        try {
            const s = JSON.parse(data);
            this.rooms = s.rooms;
            this.items = s.items;
            this.inventory = s.inventory;
            this.currentRoomID = s.currentRoomID;
            this.rugMoved = s.rugMoved;
            this.catFed = s.catFed || false;
            this.score = s.score;
            this.moves = s.moves;
            this.isWon = s.isWon;
            this.transcript = s.transcript;
            this.nextEntryID = s.nextEntryID;
            this.emit("Game restored.");
            this.describeCurrentRoom(true);
        } catch (e) {
            this.emit("The saved game could not be read.");
        }
    }

    restart() {
        this.transcript = [];
        this.moves = 0;
        this.score = 0;
        this.isWon = false;
        this.inventory = [];
        this.currentRoomID = "westOfHouse";
        this.rugMoved = false;
        this.catFed = false;
        this.buildWorld();
        this.emit(this.bannerText(), false);
        this.describeCurrentRoom(true);
    }

    emit(text, asCommand = false) {
        this.transcript.push({ id: this.nextEntryID, text: text, isCommand: asCommand });
        this.nextEntryID += 1;
    }

    // MARK: Static Text

    bannerText() {
        return [
            "SKOGARK",
            "A tiny text adventure. (c) 2026",
            "Type HELP for a list of commands.",
            "─────────────────────────────",
        ].join("\n");
    }

    helpText() {
        return [
            "Some things you can type:",
            "  Directions: NORTH/N, SOUTH/S, EAST/E, WEST/W, UP/U, DOWN/D, IN, OUT",
            "  LOOK (L)              — describe your surroundings",
            "  LOOK AROUND           — list what you can see here, and the exits",
            "  EXAMINE <thing> (X)   — inspect something",
            "  READ <thing>          — read something",
            "  TAKE / DROP <thing>   — pick up or set down an item",
            "  OPEN / CLOSE <thing>  — for doors, windows, containers",
            "  MOVE <thing>          — shift a heavy object",
            "  TURN ON / OFF LAMP    — control a light source",
            "  PUT <thing> IN <thing>— place an item in a container",
            "  GIVE <thing> TO <someone> — offer an item to a creature",
            "  INVENTORY (I)         — list what you're carrying",
            "  SCORE                 — check your progress",
            "  SAVE / RESTORE        — save or reload your game",
            "  RESTART               — start over",
        ].join("\n");
    }
}
