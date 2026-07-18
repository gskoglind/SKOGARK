// SKOGARK — text-adventure engine (JavaScript port of AdventureEngine.swift).
//
// The engine is generic and deterministic: process(input) turns a line of
// typed input into transcript output. The world it runs is supplied as a
// scenario, so multiple games share one engine, one UI, and one deploy.

"use strict";

const DIRECTIONS = ["north", "south", "east", "west", "up", "down", "inside", "outside"];

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
        // "forward"/"back" read as north/south, for walking a linear trail.
        case "forward": case "ahead": case "fwd": return "north";
        case "back": case "backward": case "backwards": return "south";
        default: return DIRECTIONS.includes(word) ? word : null;
    }
}

function makeItem(props) {
    return Object.assign({
        id: "", name: "", nouns: [], description: "",
        isTakeable: false, isLightSource: false, isLit: false,
        isOpenable: false, isOpen: false, isContainer: false,
        contents: [], readText: null,
        isFixture: false, isCreature: false, dialogue: null,
        forSale: false, price: 0, kind: null,
    }, props);
}

function makeRoom(props) {
    return Object.assign({
        id: "", title: "", description: "",
        exits: {}, items: [], isDark: false, visited: false,
    }, props);
}

class Game {
    constructor(scenario) {
        this.scenario = scenario;
        this.transcript = [];
        this.moves = 0;
        this.score = 0;
        this.isWon = false;
        this.rooms = {};
        this.items = {};
        this.inventory = [];
        this.currentRoomID = "";
        this.flags = new Set();
        this.coins = 0;
        this.nextEntryID = 0;
        this.nextPurchaseID = 0;
        this.hintLevel = 0;
        this.hintStageKey = "";
        this.startFresh(false);
    }

    startFresh(clearTranscript) {
        if (clearTranscript) this.transcript = [];
        this.moves = 0;
        this.score = 0;
        this.isWon = false;
        this.inventory = [];
        this.flags = new Set();
        this.coins = this.scenario.startingCoins;
        this.nextPurchaseID = 0;
        this.hintLevel = 0;
        this.hintStageKey = "";
        const world = this.scenario.build();
        this.rooms = world.rooms;
        this.items = world.items;
        this.currentRoomID = this.scenario.startRoomID;
        this.emit(this.scenario.banner, false);
        this.describeCurrentRoom(true);
    }

    // Scenario-facing helpers (used by rule hooks).
    item(id) { return this.items[id]; }
    get roomID() { return this.currentRoomID; }
    get roomTitle() { const r = this.rooms[this.currentRoomID]; return r ? r.title : ""; }
    has(flag) { return this.flags.has(flag); }
    set(flag) { this.flags.add(flag); }
    inventoryKinds() {
        const kinds = new Set();
        for (const id of this.inventory) if (this.items[id] && this.items[id].kind) kinds.add(this.items[id].kind);
        return kinds;
    }
    consumeFromInventory(id) { this.inventory = this.inventory.filter((x) => x !== id); }
    revealItem(id, roomID) { if (this.rooms[roomID]) this.rooms[roomID].items.push(id); }

    // MARK: Input Handling

    process(rawInput) {
        const input = rawInput.trim();
        if (!input) return;
        this.emit("> " + input, true);

        const tokens = this.tokenize(input);
        if (tokens.length === 0) { this.emit("I don't understand that."); return; }
        const verb = tokens[0];

        if (this.isWon && !["restart", "restore", "load", "score", "save"].includes(verb)) {
            this.emit("You've already won. Type RESTART to play again.");
            return;
        }

        if (tokens.length === 1) {
            const dir = directionFrom(verb);
            if (dir) { this.move(dir); return; }
        }

        const rest = tokens.slice(1);
        switch (verb) {
            case "look": case "l":
                if (rest[0] === "at" && rest.length > 1) this.examine(rest.slice(1));
                else if (rest.includes("around") || rest.includes("here")) this.lookAround();
                else this.describeCurrentRoom(true);
                break;
            case "what": case "survey":
                this.lookAround();
                break;
            case "go": case "walk": case "run": case "climb":
            case "enter": case "crawl": case "cross":
            case "board": case "sail": case "depart":
            case "choose": case "select": case "ride": case "catch": case "join":
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
            case "talk": case "ask": case "speak": case "greet":
                this.talkTo(rest);
                break;
            case "buy": case "purchase":
                this.buyItem(rest);
                break;
            case "coins": case "money": case "wealth":
                this.emit(this.coins > 0 ? `You have ${this.coins} coins.` : "You don't have any money.");
                break;
            case "inventory": case "i": case "inv":
                this.showInventory();
                break;
            case "score":
                this.emit(`Your score is ${this.score} of a possible ${this.scenario.maxScore}, in ${this.moves} moves.`);
                break;
            case "hint": case "hints":
                this.showHint();
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
                this.startFresh(true);
                break;
            default: {
                // Naming a portal with no verb (e.g. a cruise by time or name
                // at the dock) is taken as "go through it".
                const id = this.resolveItem(tokens);
                const dir = (id && this.scenario.portalDirection) ? this.scenario.portalDirection(this, id) : null;
                if (dir) this.move(dir);
                else this.emit(`I don't know how to "${verb}".`);
            }
        }
    }

    tokenize(input) {
        const filler = new Set(["the", "a", "an", "to", "at", "my", "some"]);
        return input.toLowerCase()
            .split(/[^a-z0-9]+/)
            .filter((w) => w.length > 0 && !filler.has(w));
    }

    // MARK: Movement

    move(direction) {
        this.moves += 1;
        const room = this.rooms[this.currentRoomID];
        if (!room) return;

        if (this.scenario.portalGate) {
            const blocked = this.scenario.portalGate(this, direction);
            if (blocked) { this.emit(blocked); return; }
        }

        const destination = room.exits[direction];
        if (!destination) { this.emit("You can't go that way."); return; }

        this.currentRoomID = destination;
        this.describeCurrentRoom(false);
        if (this.scenario.onEnterRoom) this.scenario.onEnterRoom(this, destination);
    }

    handleGo(words) {
        for (const w of words) {
            const dir = directionFrom(w);
            if (dir) { this.move(dir); return; }
        }
        const id = this.resolveItem(words);
        if (id && this.scenario.portalDirection) {
            const dir = this.scenario.portalDirection(this, id);
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
            if (item.isFixture) {
                if (this.scenario.fixtureLine) {
                    const line = this.scenario.fixtureLine(this, itemID);
                    if (line) lines.push(line);
                }
                continue;
            }
            lines.push(`There is a ${item.name} here.`);
        }
        this.emit(lines.join("\n"));
    }

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
        if (names.length === 0) lines.push("You see nothing here worth remarking on.");
        else lines.push(`You can see: ${names.join(", ")}.`);

        const exits = this.obviousExits();
        if (exits.length > 0) lines.push(`Obvious exits: ${exits.join(", ")}.`);
        this.emit(lines.join("\n"));
    }

    obviousExits() {
        const room = this.rooms[this.currentRoomID];
        if (!room) return [];
        return DIRECTIONS.filter((dir) => {
            if (!room.exits[dir]) return false;
            if (this.scenario.exitHidden && this.scenario.exitHidden(this, dir)) return false;
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
                text += contents.length === 0 ? " It is open and empty." : ` It contains: ${contents.join(", ")}.`;
            } else {
                text += " It is closed.";
            }
        }
        if (item.isLightSource) text += item.isLit ? " It is currently lit." : " It is not lit.";
        if (item.forSale) text += ` It's for sale for ${item.price} coins.`;
        this.emit(text);
    }

    readItem(words) {
        if (!this.canSee()) { this.emit("It's too dark to read."); return; }
        const id = this.resolveItem(words);
        const item = id && this.items[id];
        if (!item) { this.emit("You don't see that here."); return; }
        if (item.readText != null) this.emit(item.readText);
        else this.emit(`There's nothing to read on the ${item.name}.`);
    }

    take(words) {
        this.moves += 1;
        if (!this.canSee()) { this.emit("It's too dark to see what you're grabbing."); return; }
        const id = this.resolveItem(words);
        const item = id && this.items[id];
        if (!item) { this.emit("You don't see that here."); return; }
        if (this.inventory.includes(id)) { this.emit(`You're already carrying the ${item.name}.`); return; }
        if (item.forSale) { this.emit("That's for sale — you'll have to BUY it."); return; }
        if (!item.isTakeable) {
            // "Take the 1pm cruise" reads as boarding it, not pocketing it.
            const dir = this.scenario.portalDirection ? this.scenario.portalDirection(this, id) : null;
            if (dir) { this.move(dir); return; }
            this.emit(`You can't take the ${item.name}.`); return;
        }
        this.removeItemFromWorld(id);
        this.inventory.push(id);
        if (this.scenario.onTake) this.scenario.onTake(this, id);
        this.emit("Taken.");
    }

    drop(words) {
        this.moves += 1;
        const id = this.resolveItem(words.filter((w) => w !== "down"));
        if (!id || !this.inventory.includes(id) || !this.items[id]) { this.emit("You're not carrying that."); return; }
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
        if (this.scenario.onMoveObject && this.scenario.onMoveObject(this, id)) return;
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
            this.emit("You need to be holding that first."); return;
        }
        const object = this.items[objectID];
        const targetID = this.resolveItem(targetWords);
        const target = targetID && this.items[targetID];
        if (!target || !target.isContainer) { this.emit("You can't put anything in that."); return; }
        if (!target.isOpen) { this.emit(`The ${target.name} is closed.`); return; }

        this.inventory = this.inventory.filter((x) => x !== objectID);
        target.contents.push(objectID);
        this.emit(`You place the ${object.name} in the ${target.name}.`);

        if (this.scenario.onPut) this.scenario.onPut(this, objectID, targetID);
    }

    give(words) {
        this.moves += 1;
        const visible = this.visibleItemIDs();
        let recipientID = null;
        for (const word of words) {
            const id = visible.find((id) => this.items[id] && this.items[id].nouns.includes(word) && this.items[id].isCreature);
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

        if (this.scenario.onGive && this.scenario.onGive(this, giftID, recipientID)) return;
        this.emit(`The ${recipient.name} has no interest in the ${gift.name}.`);
    }

    talkTo(words) {
        if (!this.canSee()) { this.emit("It's too dark to see who you'd talk to."); return; }
        const visible = this.visibleItemIDs();
        let id = null;
        for (const word of words) {
            const found = visible.find((i) => this.items[i] && this.items[i].nouns.includes(word) && this.items[i].isCreature);
            if (found) { id = found; break; }
        }
        const npc = id && this.items[id];
        if (!npc) { this.emit("There's no one here to talk to."); return; }
        if (this.scenario.onTalk && this.scenario.onTalk(this, id)) return;
        if (npc.dialogue) this.emit(npc.dialogue);
        else this.emit(`The ${npc.name} has nothing to say.`);
    }

    buyItem(words) {
        this.moves += 1;
        if (!this.canSee()) { this.emit("It's too dark to shop."); return; }
        // Resolve specifically to a for-sale ware (so a copy already in the
        // player's bag doesn't shadow the restocking stall item).
        const visible = this.visibleItemIDs();
        let wareID = null;
        for (const word of words) {
            const found = visible.find((i) => this.items[i] && this.items[i].nouns.includes(word) && this.items[i].forSale);
            if (found) { wareID = found; break; }
        }
        if (!wareID) {
            const other = this.resolveItem(words);
            if (other && this.items[other]) this.emit(`The ${this.items[other].name} isn't for sale.`);
            else this.emit("You don't see that here.");
            return;
        }
        const ware = this.items[wareID];
        if (this.coins < ware.price) {
            this.emit(`You can't afford the ${ware.name} — it costs ${ware.price} coins and you have ${this.coins}.`);
            return;
        }
        this.coins -= ware.price;
        // Mint a fresh carried copy; the stall keeps its ware and restocks.
        const boughtID = `${wareID}#${this.nextPurchaseID}`;
        this.nextPurchaseID += 1;
        this.items[boughtID] = Object.assign(makeItem({}), ware, {
            id: boughtID, isTakeable: true, isFixture: false, forSale: false,
        });
        this.inventory.push(boughtID);
        this.emit(`You buy the ${ware.name} for ${ware.price} coins. You have ${this.coins} left.`);
    }

    // Progressive, opt-in hint. Each call escalates from a gentle nudge to an
    // explicit instruction; the level resets when the player reaches a new
    // puzzle stage.
    showHint() {
        if (!this.scenario.hintStage) {
            this.emit("No hints are available here — you're on your own!");
            return;
        }
        const stage = this.scenario.hintStage(this);
        if (stage.key !== this.hintStageKey) {
            this.hintStageKey = stage.key;
            this.hintLevel = 0;
        }
        const clues = stage.clues;
        if (!clues || clues.length === 0) { this.emit("No hint right now."); return; }
        const index = Math.min(this.hintLevel, clues.length - 1);
        let output = clues[index];
        if (this.hintLevel < clues.length - 1) {
            output += "\n(Type HINT again for a bigger hint.)";
            this.hintLevel += 1;
        }
        this.emit(output);
    }

    showInventory() {
        const lines = [];
        if (this.inventory.length === 0) {
            lines.push("You are empty-handed.");
        } else {
            lines.push("You are carrying:");
            for (const id of this.inventory) if (this.items[id]) lines.push(`  a ${this.items[id].name}`);
        }
        if (this.scenario.startingCoins > 0) lines.push(`You have ${this.coins} coins.`);
        this.emit(lines.join("\n"));
    }

    // MARK: Helpers

    removeItemFromWorld(id) {
        const room = this.rooms[this.currentRoomID];
        if (room) room.items = room.items.filter((x) => x !== id);
        for (const key in this.items) {
            const item = this.items[key];
            if (item.contents.includes(id)) item.contents = item.contents.filter((x) => x !== id);
        }
    }

    award(points, note) {
        this.score += points;
        if (note) this.emit(note);
    }

    win(message) {
        this.isWon = true;
        this.emit(
            "\n" + message +
            "\n\n*** You have won! ***\n\n" +
            `Your score is ${this.score} of a possible ${this.scenario.maxScore}, in ${this.moves} moves.` +
            "\nType RESTART to play again."
        );
    }

    emit(text, asCommand = false) {
        this.transcript.push({ id: this.nextEntryID, text: text, isCommand: asCommand });
        this.nextEntryID += 1;
    }

    // MARK: Save & Restore

    saveKey() { return `skogark.${this.scenario.id}.savegame`; }

    save() {
        const snapshot = {
            rooms: this.rooms, items: this.items, inventory: this.inventory,
            currentRoomID: this.currentRoomID, flags: Array.from(this.flags), coins: this.coins,
            nextPurchaseID: this.nextPurchaseID,
            score: this.score, moves: this.moves, isWon: this.isWon,
            transcript: this.transcript, nextEntryID: this.nextEntryID,
        };
        try {
            localStorage.setItem(this.saveKey(), JSON.stringify(snapshot));
            this.emit("Game saved.");
        } catch (e) {
            this.emit("Something went wrong and the game could not be saved.");
        }
    }

    restore() {
        let data = null;
        try { data = localStorage.getItem(this.saveKey()); } catch (e) { data = null; }
        if (!data) { this.emit("There is no saved game to restore."); return; }
        try {
            const s = JSON.parse(data);
            this.rooms = s.rooms;
            this.items = s.items;
            this.inventory = s.inventory;
            this.currentRoomID = s.currentRoomID;
            this.flags = new Set(s.flags || []);
            this.coins = s.coins || 0;
            this.nextPurchaseID = s.nextPurchaseID || 0;
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

    // MARK: Static Text

    helpText() {
        const lines = [
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
        ];
        if (this.scenario.startingCoins > 0) {
            lines.push("  BUY <thing>           — purchase goods in a shop");
            lines.push("  COINS                 — check your money");
        }
        lines.push(
            "  INVENTORY (I)         — list what you're carrying",
            "  SCORE                 — check your progress",
            "  HINT                  — a nudge toward your next step",
            "  SAVE / RESTORE        — save or reload your game",
            "  RESTART               — start over"
        );
        return lines.join("\n");
    }
}

// MARK: - Scenarios

function houseScenario() {
    return {
        id: "house",
        title: "Explore a House",
        blurb: "Explore a house and the caverns beneath it in search of treasure. Beware the grue.",
        banner: [
            "SKOGARK",
            "A tiny text adventure. (c) 2026",
            "Type HELP for a list of commands.",
            "─────────────────────────────",
        ].join("\n"),
        startRoomID: "westOfHouse",
        maxScore: 25,
        startingCoins: 0,
        build: buildHouseWorld,
        portalGate(game, direction) {
            if (direction === "inside" && game.roomID === "behindHouse" &&
                !(game.item("window") && game.item("window").isOpen)) {
                return "The window is closed. You'll need to open it first.";
            }
            if (direction === "down" && game.roomID === "livingRoom") {
                if (!game.has("rugMoved")) return "You can't go that way.";
                if (!(game.item("trapdoor") && game.item("trapdoor").isOpen)) return "The trap door is closed.";
            }
            return null;
        },
        portalDirection(game, id) {
            if (id === "window") {
                if (game.roomID === "behindHouse") return "inside";
                if (game.roomID === "kitchen") return "outside";
                return null;
            }
            if (id === "trapdoor") return "down";
            return null;
        },
        exitHidden(game, direction) {
            return game.roomID === "livingRoom" && direction === "down" && !game.has("rugMoved");
        },
        fixtureLine(game, id) {
            const item = game.item(id);
            if (!item) return null;
            if (id === "trapdoor") {
                return `A trap door is set into the floor. It is ${item.isOpen ? "open" : "closed"}.`;
            }
            if (id === "case") {
                const contents = item.contents.map((c) => game.item(c) && game.item(c).name).filter(Boolean);
                return contents.length === 0
                    ? `The trophy case is ${item.isOpen ? "open and empty" : "closed"}.`
                    : `The trophy case contains: ${contents.join(", ")}.`;
            }
            return null; // mailbox, window, rug — woven into prose
        },
        onTake(game, id) {
            if (id === "egg") game.award(5, "You've found a treasure!");
        },
        onMoveObject(game, id) {
            if (id !== "rug") return false;
            if (game.has("rugMoved")) { game.emit("You've already moved the rug aside."); return true; }
            game.set("rugMoved");
            game.revealItem("trapdoor", "livingRoom");
            game.award(2, null);
            game.emit("With a great heave you drag the rug aside, revealing a dusty trap door set into the floor.");
            return true;
        },
        onGive(game, gift, recipient) {
            if (recipient !== "cat" || gift !== "fish") return false;
            if (game.has("catFed")) { game.emit("The cat has already had its fill and just blinks at you contentedly."); return true; }
            game.set("catFed");
            game.consumeFromInventory(gift);
            game.award(3, null);
            game.emit("You offer the fish to the stray cat. It gulps the treat down, then winds around your ankles with a rumbling purr. You've made a friend.");
            return true;
        },
        onPut(game, object, target) {
            if (target === "case" && object === "egg") {
                game.award(10, null);
                game.win("The jeweled egg settles into the trophy case with a soft, satisfying click. Light dances through the glass.");
            }
        },
        hintStage(game) {
            if (game.item("case") && game.item("case").contents.includes("egg")) {
                return { key: "done", clues: ["The egg is in the case — you've done it!"] };
            }
            if (!(game.item("window") && game.item("window").isOpen)) {
                return { key: "enter", clues: [
                    "The house looks sealed from the front — try looking around the back.",
                    "Behind the house a window is ajar: OPEN WINDOW, then go IN.",
                ] };
            }
            if (!(game.item("lantern") && game.item("lantern").isLit)) {
                return { key: "light", clues: [
                    "It's pitch dark underground, and a grue lurks there. You'll want a light before you descend.",
                    "There's a brass lantern in the kitchen — TAKE LANTERN, then TURN ON LANTERN.",
                ] };
            }
            if (!game.has("rugMoved")) {
                return { key: "rug", clues: [
                    "The living room hides a way down; something on the floor is in the way.",
                    "MOVE the RUG to uncover a trap door.",
                ] };
            }
            if (!(game.item("trapdoor") && game.item("trapdoor").isOpen)) {
                return { key: "trap", clues: [
                    "You've found the trap door — but it's no use to you closed.",
                    "OPEN the TRAP DOOR, then go DOWN.",
                ] };
            }
            if (!game.isCarrying("egg")) {
                return { key: "egg", clues: [
                    "The treasure lies in the darkness below.",
                    "Go DOWN into the cellar (lantern lit!) and TAKE the EGG.",
                ] };
            }
            return { key: "deliver", clues: [
                "You have the treasure — now it needs a home.",
                "Return to the living room, OPEN CASE, and PUT EGG IN CASE.",
            ] };
        },
    };
}

function townScenario() {
    return {
        id: "town",
        title: "Explore the Town",
        blurb: "The cook needs supplies for a feast. Shop the village with a purse of coins and deliver the goods.",
        banner: [
            "MARKET ERRAND",
            "A tiny SkoGarK tale. (c) 2026",
            "Type HELP for commands, and READ LIST for your task.",
            "─────────────────────────────",
        ].join("\n"),
        startRoomID: "innKitchen",
        maxScore: 20,
        startingCoins: 25,
        build: buildTownWorld,
        fixtureLine(game, id) {
            const item = game.item(id);
            if (!item) return null;
            if (item.forSale) {
                const name = item.name.charAt(0).toUpperCase() + item.name.slice(1);
                return `${name} is on offer here — ${item.price} coins.`;
            }
            if (item.isCreature) {
                switch (id) {
                    case "cook": return "The cook waits by the hearth for her supplies.";
                    case "butcherman": return "A burly butcher stands behind the counter.";
                    case "baker": return "A cheerful baker dusts flour from her hands.";
                    case "fishwife": return "A brisk fishwife tends her glistening stall.";
                    case "cat": return "A skinny stray cat loiters by the stall, eyeing the fish hopefully.";
                    default: return null;
                }
            }
            return null;
        },
        onGive(game, gift, recipient) {
            // Optional side-quest: the stray cat by the fishmonger wants a fish.
            if (recipient === "cat") {
                if (game.has("catFed")) {
                    game.emit("The cat has already had its fill and just blinks at you contentedly.");
                    return true;
                }
                if (!(game.item(gift) && game.item(gift).kind === "fish")) {
                    const gname = game.item(gift) ? game.item(gift).name : "offering";
                    game.emit(`The cat sniffs the ${gname} and turns away — it only wants fish.`);
                    return true;
                }
                game.set("catFed");
                game.consumeFromInventory(gift);
                game.award(5, null);
                game.emit("You set the fish down for the stray cat. It pounces, devours the treat, and rubs against your leg with a rumbling purr.");
                return true;
            }
            if (recipient !== "cook") return false;
            const goods = ["meat", "bread", "fish"];
            const kind = game.item(gift) ? game.item(gift).kind : null;
            if (!kind || !goods.includes(kind)) {
                game.emit('The cook chuckles. "That\'s not on my list, friend."');
                return true;
            }
            game.consumeFromInventory(gift);
            game.set(`delivered_${kind}`);
            game.award(5, null);
            const deliveredCount = goods.filter((g) => game.has(`delivered_${g}`)).length;
            if (deliveredCount === goods.length) {
                game.win('The cook beams as you hand over the last of the shopping. "A feast fit for the whole village — thank you, and keep the change!"');
            } else {
                const name = game.item(gift) ? game.item(gift).name : "goods";
                game.emit(`The cook takes the ${name} with a grateful nod. (${deliveredCount} of ${goods.length} delivered.)`);
            }
            return true;
        },
        onTalk(game, id) {
            if (id !== "cook") return false;
            const goods = ["meat", "bread", "fish"];
            const remaining = goods
                .filter((g) => !game.has(`delivered_${g}`))
                .map((g) => game.item(g) && game.item(g).name)
                .filter(Boolean);
            if (remaining.length === 0) {
                game.emit('"You\'ve brought everything — bless you!" the cook says.');
            } else {
                game.emit(`"I still need: ${remaining.join(", ")}. Buy them from the shops around the square and bring them back to me. Mind your coins!" the cook says.`);
            }
            return true;
        },
        hintStage(game) {
            const goods = [
                { kind: "meat", name: "cut of meat", shop: "the butcher (east of the square)" },
                { kind: "bread", name: "loaf of bread", shop: "the bakery (west of the square)" },
                { kind: "fish", name: "fresh fish", shop: "the fishmonger (north of the square)" },
            ];
            const needed = goods.filter((g) => !game.has(`delivered_${g.kind}`));
            if (needed.length === 0) {
                return { key: "done", clues: ["You've delivered everything the cook wanted!"] };
            }
            const carried = game.inventoryKinds();
            const toBuy = needed.filter((g) => !carried.has(g.kind));
            const key = "left:" + needed.map((g) => g.kind).join(",") +
                "|buy:" + toBuy.map((g) => g.kind).join(",");

            const clues = [];
            clues.push(`The cook still needs: ${needed.map((g) => g.name).join(", ")}. (Try READ LIST or TALK TO COOK.)`);
            if (toBuy.length === 0) {
                clues.push("You've bought what's left — head back to the inn (south of the square) and GIVE each item TO COOK.");
            } else {
                clues.push(`Where to shop: ${toBuy.map((g) => `${g.name} at ${g.shop}`).join("; ")}.`);
            }
            let finalClue = "BUY each item (mind your 25 coins), then return to the inn and GIVE <item> TO COOK.";
            if (!game.has("catFed")) {
                finalClue += " Bonus: a spare fish pleases the stray cat by the fishmonger (+5).";
            }
            clues.push(finalClue);
            return { key: key, clues: clues };
        },
    };
}

function riverboatScenario() {
    // True once the guest has picked one of the three sailings.
    const choseCruise = (game) =>
        game.has("cruise_cannon") || game.has("cruise_afternoon") || game.has("cruise_sunset");
    return {
        id: "riverboat",
        title: "Savannah Riverboat",
        blurb: "Take a paddle-steamer sightseeing tour on the Savannah River: pick a sailing, board at River Street, and ride past the busy port to Old Fort Jackson as Captain Mike narrates.",
        banner: [
            "SAVANNAH RIVERBOAT",
            "A narrated cruise on the Savannah River. (c) 2026",
            "Type HELP for commands, and READ SCHEDULE for today's sailings.",
            "─────────────────────────────",
        ].join("\n"),
        startRoomID: "riverStreet",
        maxScore: 25,
        startingCoins: 0,
        build: buildRiverboatWorld,
        portalGate(game, direction) {
            if (game.roomID === "riverStreet" && direction === "north" && !choseCruise(game)) {
                return "\"Which sailing?\" Captain Mike calls down from the deck. \"Board the CANNON, the AFTERNOON, or the SUNSET cruise.\"";
            }
            return null;
        },
        portalDirection(game, id) {
            // Choosing a sailing and stepping aboard are one action: each cruise
            // placard boards the boat and records the choice.
            if (game.roomID !== "riverStreet") return null;
            switch (id) {
                case "cannonCruise": game.set("cruise_cannon"); return "north";
                case "afternoonCruise": game.set("cruise_afternoon"); return "north";
                case "sunsetCruise": game.set("cruise_sunset"); return "north";
                default: return null;
            }
        },
        fixtureLine(game, id) {
            if (id === "captain") return "Captain Mike stands at the wheel, narrating the tour.";
            if (id === "guests") return "Fellow sightseers wait on the wharf, tickets in hand.";
            return null; // schedule, gangway, ships, bridge, fort — woven into the prose
        },
        onTalk(game, id) {
            if (id === "guests") {
                game.emit("\"First time on the boat?\" a fellow passenger asks. \"They say Captain Mike tells the best stories on the river.\"");
                return true;
            }
            if (id === "captain") {
                game.emit("\"Welcome aboard the Savannah Cruise!\" the captain says. \"Four decks to enjoy — two dining rooms below, the air-conditioned sightseeing lounge on the third, and this open deck up top for the best views. We'll steam upriver past the port to the Talmadge Bridge, come about, and call on Old Fort Jackson. Head WEST from the top deck when you're ready.\"");
                return true;
            }
            return false;
        },
        onEnterRoom(game, roomID) {
            // Each new leg is announced once, no matter which of the four decks
            // the passenger is on. The cannon and afternoon cruises get Captain
            // Mike's narrated history; the 7 o'clock sunset cruise has no tour — a
            // DJ works the open-air top deck instead, so the legs get party lines
            // and the top deck plays dance music (see updateDanceMusic in app.js).
            const sunset = game.has("cruise_sunset");
            if (roomID === "fortJackson") {
                if (game.isWon) return;
                if (sunset) {
                    game.emit("The DJ eases into a mellow sunset anthem as Old Fort Jackson's brick ramparts drift past, glowing in the last of the light.");
                } else {
                    game.emit("Captain Mike: \"Old Fort Jackson ahead is one of the oldest standing brick forts in the nation, guarding this bend of the river since the War of 1812 and held by Confederate defenders through the Civil War.\"");
                }
                if (game.has("cruise_cannon")) {
                    game.emit("At Old Fort Jackson a cannon crew in period dress touches off the great gun — BOOOM! — a plume of white smoke and a salute that rolls across the water and thumps in your chest.");
                }
                let closing;
                if (sunset) {
                    closing = "Old Fort Jackson's brick ramparts glow in the last of the sunset as the boat turns for the lamplit run home to River Street.";
                } else if (game.has("cruise_cannon")) {
                    closing = "With the cannon's echo still fading over the marsh, Captain Mike brings the boat about for the run home to River Street.";
                } else {
                    closing = "The boat eases past Old Fort Jackson's weathered ramparts, then comes about for the easy run home to River Street.";
                }
                game.award(15, null);
                game.win(closing);
            } else if (roomID.startsWith("port") && !game.has("sawPort")) {
                game.set("sawPort");
                game.award(5, sunset
                    ? "The DJ on the top deck kicks off the night — a thumping bassline rolls out over the water and the dance floor fills as the lit-up Port of Savannah slides past in the dusk."
                    : "Captain Mike: \"Off to starboard lies the Port of Savannah, one of the busiest in the nation. Towering container ships ride the channel while stout tugboats shoulder them to their berths.\"");
            } else if (roomID.startsWith("bridge") && !game.has("sawBridge")) {
                game.set("sawBridge");
                game.award(5, sunset
                    ? "The boat swings around beneath the Talmadge Bridge, its lights flickering on against the purple sky, and the DJ drops the beat — the whole top deck throws their hands up. (Head EAST to continue to Old Fort Jackson.)"
                    : "Captain Mike: \"Overhead soars the Talmadge Memorial Bridge, its cables strung like a harp above the river. Here we come about for the slow run downriver.\" (Head EAST to continue to Old Fort Jackson.)");
            } else if (roomID.startsWith("city") && !game.has("sawCity")) {
                game.set("sawCity");
                game.emit(sunset
                    ? "Downtown Savannah glitters past as the DJ mixes into a deep, rolling groove and glow sticks trace the rail."
                    : "Captain Mike: \"Savannah was founded in 1733 by General James Oglethorpe — the last of the thirteen colonies, laid out in that famous grid of leafy squares you can still walk today. That gold dome is City Hall; beside it stands the old Cotton Exchange, from the days when Savannah set the world's price for cotton. And from this very river, in 1819, the SS Savannah steamed off to become the first steamship to cross the Atlantic.\"");
            } else if (roomID.startsWith("waving") && !game.has("sawWaving")) {
                game.set("sawWaving");
                if (sunset) {
                    game.emit("The DJ cues a floor-filler and the whole boat sings along, waving at a passing freighter — an old Savannah tradition, remixed.");
                } else {
                    game.emit("Captain Mike: \"That little white figure on the point is the Waving Girl — Florence Martus, who for forty-four years greeted every ship entering the port, waving a handkerchief by day and a lantern by night. These marshes carried Savannah's cotton and naval stores out to the world.\"");
                    game.emit("Captain Mike: \"Now, those refineries coming up on the bank — that's my favorite. See those big piles? That's the cereal. And those three tall silos yonder? Whole milk, oat milk, and skim. Biggest bowl of breakfast on the Georgia coast — all we're missing is a spoon the size of the Talmadge Bridge!\"");
                }
            }
        },
        hintStage(game) {
            if (!choseCruise(game)) {
                return { key: "board", clues: [
                    "Today's sailings are chalked on the schedule board at the dock — READ the SCHEDULE.",
                    "Pick one and step aboard: BOARD THE CANNON CRUISE (or the AFTERNOON, or the SUNSET cruise).",
                ] };
            }
            // Only the open-air top deck (D4) drives the boat onward; every
            // leg's other decks are yours to explore with UP/DOWN.
            const room = game.roomID;
            const onTopDeck = room.endsWith("D4");
            if (room.startsWith("city") || room.startsWith("waving")) {
                return onTopDeck
                    ? { key: "east4", clues: [
                        "Captain Mike is telling the city's story — no rush.",
                        "Continue EAST; Old Fort Jackson is downriver.",
                    ] }
                    : { key: "eastUp", clues: [
                        "You can roam all four decks here with UP and DOWN.",
                        "To carry on, climb UP to the open-air deck and keep heading EAST to Old Fort Jackson.",
                    ] };
            }
            if (room.startsWith("bridge")) {
                return onTopDeck
                    ? { key: "bridge4", clues: [
                        "The boat comes about beneath the bridge to head downriver.",
                        "Go EAST to run down to Old Fort Jackson.",
                    ] }
                    : { key: "bridgeUp", clues: [
                        "You can wander all four decks here with UP and DOWN.",
                        "To carry on, climb UP to the open-air deck; the boat turns here, so head EAST toward Old Fort Jackson.",
                    ] };
            }
            if (room.startsWith("port")) {
                return onTopDeck
                    ? { key: "port4", clues: [
                        "The Talmadge Bridge lies just ahead upriver.",
                        "Continue WEST to reach the bridge.",
                    ] }
                    : { key: "portUp", clues: [
                        "Explore the decks with UP and DOWN.",
                        "To carry on, climb UP to the open-air deck and head WEST toward the bridge.",
                    ] };
            }
            // River Street leg (riverD1…riverD4).
            return onTopDeck
                ? { key: "river4", clues: [
                    "You're up on the open-air deck — time to get underway.",
                    "Head WEST to steam upriver toward the Talmadge Bridge.",
                ] }
                : { key: "riverUp", clues: [
                    "You can visit all four decks with UP and DOWN — two dining rooms, the sightseeing lounge, and the open-air deck up top.",
                    "To get underway, climb UP to the open-air deck and head WEST.",
                ] };
        },
    };
}

// Fort Pulaski: a self-guided visit to the National Monument on Cockspur
// Island. Drive in through the gates, check in at the visitor center, then walk
// out past Battery Hambright to the historic North Pier, and follow the
// Lighthouse Overlook Trail through the marsh to the Cockspur Island Lighthouse.
// (The fort itself — inside and out, with its cannon-lined upstairs — is left as
// a placeholder for a future update.)
function fortPulaskiScenario() {
    // The four points of interest the visitor is here to see.
    const stops = ["checkedIn", "sawBattery", "sawPier", "sawLighthouse"];
    return {
        id: "fortPulaski",
        title: "Explore Fort Pulaski",
        blurb: "Drive onto Cockspur Island to visit Fort Pulaski National Monument: check in at the visitor center, walk out past Battery Hambright to the historic North Pier, and follow the Lighthouse Overlook Trail through the marsh to spy the Cockspur Island Lighthouse.",
        banner: [
            "FORT PULASKI",
            "A visit to the National Monument on Cockspur Island. (c) 2026",
            "Type HELP for commands. Drive NORTH to the visitor center to check in.",
            "─────────────────────────────",
        ].join("\n"),
        startRoomID: "gate",
        maxScore: 25,
        startingCoins: 0,
        build: buildFortPulaskiWorld,
        onTalk(game, id) {
            if (id !== "ranger") return false;
            game.emit("Ranger Max leans on the desk. \"Fort Pulaski is named for Casimir Pulaski — a Polish nobleman and cavalry commander, the 'father of the American cavalry,' who fell leading a charge at the Siege of Savannah in 1779. The fort took eighteen years to build, and a young Lieutenant Robert E. Lee helped lay out its dikes. Everyone believed these seven-and-a-half-foot brick walls were invincible — until April 1862, when Union rifled cannon on Tybee Island breached them in about thirty hours and made every masonry fort in the world obsolete overnight. Take the walking path NORTH to Battery Hambright and the North Pier, and don't miss the Lighthouse Overlook Trail heading EAST.\"");
            return true;
        },
        onEnterRoom(game, roomID) {
            // Reaching each of the four points of interest is announced and
            // scored once; seeing all four ends the visit.
            const award = (flag, points, note) => {
                if (game.has(flag)) return;
                game.set(flag);
                game.award(points, note);
                if (stops.every((f) => game.has(f))) {
                    game.win("You've driven in through the gates, checked in at the visitor center, walked out to Battery Hambright and the North Pier, and followed the marsh trail to the Cockspur Island Lighthouse. The old fort itself — its drawbridge, casemates, and the cannon-lined terreplein upstairs — waits for another day. (More of Fort Pulaski is coming soon.)");
                }
            };
            switch (roomID) {
                case "visitorCenter":
                    award("checkedIn", 5, "Ranger Max welcomes you to Fort Pulaski National Monument from behind the desk and checks you in. \"Cockspur Island has guarded the mouth of the Savannah River for a very long time — TALK TO MAX or READ the EXHIBIT to hear the story. The riverside path to Battery Hambright and the North Pier is NORTH, and the Lighthouse Overlook Trail heads EAST.\"");
                    break;
                case "batteryHambright":
                    award("sawBattery", 5, "You come to Battery Hambright, a squat concrete gun emplacement half-swallowed by the marsh grass, its gun wells empty and open to the sky. It's named for Lieutenant Horace G. Hambright, a young West Point officer who died out west in 1896 and was honored here in 1904. Poured about 1900 over a foundation of 30,000 bricks salvaged from the original fort village, it was built to guard the river mouth in the Spanish-American War era — yet it never received its guns and never fired a shot.");
                    break;
                case "northPier":
                    award("sawPier", 5, "Out at the end of the Historic North Pier, you settle in to watch the traffic where the Savannah River meets the sea: a towering container ship slides seaward stacked with steel boxes, a Coast Guard boat throttles past on patrol, and a fast river pilot boat darts out to put a harbor pilot aboard an inbound freighter.");
                    break;
                case "trail4":
                    award("sawLighthouse", 10, "The trail ends at a small observation deck. You lean into the mounted binoculars and there it is across the marsh: the Cockspur Island Lighthouse — the smallest lighthouse in Georgia — standing on its oyster-shell bar, its base shaped like a ship's prow to cut the waves. It survived the 1862 bombardment of Fort Pulaski with over five thousand shots screaming directly overhead, and stands quiet now, relit for history.");
                    break;
                default:
                    break;
            }
        },
        hintStage(game) {
            if (!game.has("checkedIn")) {
                return { key: "checkin", clues: [
                    "Start by driving up to the visitor center to check in.",
                    "Go NORTH from the gates to the visitor center.",
                ] };
            }
            const todo = [];
            if (!game.has("sawBattery")) todo.push("Battery Hambright");
            if (!game.has("sawPier")) todo.push("the North Pier");
            if (!game.has("sawLighthouse")) todo.push("the Lighthouse Overlook");
            if (todo.length === 0) {
                return { key: "done", clues: ["You've seen every stop — enjoy the view!"] };
            }
            return { key: "todo:" + todo.join("|"), clues: [
                "Still to explore: " + todo.join(", ") + ".",
                "From the visitor center, NORTH walks you past Battery Hambright to the North Pier; EAST starts the Lighthouse Overlook Trail — go FORWARD four stops to the deck and its binoculars, then head BACK.",
            ] };
        },
    };
}

const SCENARIOS = [houseScenario(), townScenario(), riverboatScenario(), fortPulaskiScenario()];

// MARK: - World Builders

function buildHouseWorld() {
    const items = {};
    const addItem = (p) => { const it = makeItem(p); items[it.id] = it; };
    addItem({ id: "leaflet", name: "leaflet", nouns: ["leaflet", "paper", "mail"],
        description: "A small paper leaflet.", isTakeable: true,
        readText: "\"WELCOME TO SKOGARK!\n\nSkoGarK is a game of adventure and low cunning. In it you will explore a house and the caverns beneath it in search of treasure. Beware the grue — it lurks in darkness. Type HELP if you get stuck.\"" });
    addItem({ id: "mailbox", name: "small mailbox", nouns: ["mailbox", "box"],
        description: "It's a small mailbox.", isOpenable: true, isContainer: true, contents: ["leaflet"], isFixture: true });
    addItem({ id: "window", name: "window", nouns: ["window"],
        description: "The kitchen window is slightly ajar.", isOpenable: true, isFixture: true });
    addItem({ id: "lantern", name: "brass lantern", nouns: ["lantern", "lamp", "light"],
        description: "A battered brass lantern.", isTakeable: true, isLightSource: true });
    addItem({ id: "bottle", name: "glass bottle", nouns: ["bottle", "water"],
        description: "A glass bottle containing a little water.", isTakeable: true });
    addItem({ id: "rug", name: "oriental rug", nouns: ["rug", "carpet"],
        description: "A large oriental rug in the center of the room.", isFixture: true });
    addItem({ id: "trapdoor", name: "trap door", nouns: ["trapdoor", "trap", "door", "hatch"],
        description: "A closed wooden trap door in the floor.", isOpenable: true, isFixture: true });
    addItem({ id: "case", name: "trophy case", nouns: ["case", "trophy"],
        description: "A handsome glass trophy case, waiting to be filled.", isOpenable: true, isContainer: true, isFixture: true });
    addItem({ id: "egg", name: "jeweled egg", nouns: ["egg", "jewel", "treasure"],
        description: "A stunning jeweled egg that glitters even in faint light.", isTakeable: true });
    addItem({ id: "fish", name: "fresh fish", nouns: ["fish", "herring", "catch"],
        description: "A fat, silver fish fresh from the stall, still glistening.", isTakeable: true });
    addItem({ id: "cat", name: "stray cat", nouns: ["cat", "kitten", "stray"],
        description: "A scruffy stray cat with matted fur, watching the fishmonger's stall with hungry, hopeful eyes.",
        isCreature: true, dialogue: "The stray cat regards you with lofty indifference." });

    const rooms = {};
    const addRoom = (p) => { const r = makeRoom(p); rooms[r.id] = r; };
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

    return { rooms, items };
}

function buildTownWorld() {
    const items = {};
    const addItem = (p) => { const it = makeItem(p); items[it.id] = it; };
    addItem({ id: "list", name: "shopping list", nouns: ["list", "note", "paper"],
        description: "The cook's shopping list, in a hurried scrawl.", isTakeable: true,
        readText: "\"FEAST SHOPPING\n  • a cut of meat — from the butcher\n  • a loaf of bread — from the bakery\n  • a fresh fish — from the fishmonger\nBring them all back to me. Here's your purse. — Cook\"" });
    addItem({ id: "cook", name: "cook", nouns: ["cook", "innkeeper", "woman"],
        description: "The inn's cook, rosy-cheeked and flour-dusted, waiting for her supplies.",
        isFixture: true, isCreature: true });
    addItem({ id: "meat", name: "cut of meat", nouns: ["meat", "beef", "cut"],
        description: "A good red cut, trimmed and ready.", isTakeable: true, isFixture: true, forSale: true, price: 8, kind: "meat" });
    addItem({ id: "bread", name: "loaf of bread", nouns: ["bread", "loaf"],
        description: "A crusty loaf, still warm from the oven.", isTakeable: true, isFixture: true, forSale: true, price: 5, kind: "bread" });
    addItem({ id: "fish", name: "fresh fish", nouns: ["fish", "herring", "catch"],
        description: "A silvery fish laid out on crushed ice.", isTakeable: true, isFixture: true, forSale: true, price: 6, kind: "fish" });
    addItem({ id: "butcherman", name: "butcher", nouns: ["butcher", "man"],
        description: "A burly butcher in a striped apron.", isFixture: true, isCreature: true,
        dialogue: "\"Finest cuts in the village,\" the butcher grunts. \"Eight coins and that one's yours — just say BUY MEAT.\"" });
    addItem({ id: "baker", name: "baker", nouns: ["baker"],
        description: "A cheerful baker, sleeves rolled and dusted with flour.", isFixture: true, isCreature: true,
        dialogue: "\"Fresh from the oven!\" the baker beams. \"Five coins a loaf — BUY BREAD whenever you like.\"" });
    addItem({ id: "fishwife", name: "fishwife", nouns: ["fishwife", "fishmonger", "woman"],
        description: "A brisk fishwife in oilskins.", isFixture: true, isCreature: true,
        dialogue: "\"Caught this very morning,\" says the fishwife. \"Six coins — BUY FISH and it's yours.\"" });
    addItem({ id: "cat", name: "stray cat", nouns: ["cat", "kitten", "stray"],
        description: "A skinny stray cat loiters by the fishmonger's stall, watching the catch with hungry, hopeful eyes.",
        isFixture: true, isCreature: true,
        dialogue: "The stray cat mews at you and glances pointedly at the fish." });

    const rooms = {};
    const addRoom = (p) => { const r = makeRoom(p); rooms[r.id] = r; };
    addRoom({ id: "innKitchen", title: "The Inn Kitchen",
        description: "You're in the warm kitchen of the village inn. The cook has sent you out for tonight's feast — a shopping list lies on the table, and a purse of coins is already in your pocket. The square is just outside to the north. (Word is a stray cat haunts the fishmonger's stall and would adore a spare fish, if your coins stretch that far.)",
        exits: { north: "square" }, items: ["list", "cook"] });
    addRoom({ id: "square", title: "Village Square",
        description: "The cobbled square, ringed with shops. The butcher is to the east, the bakery to the west, and the fishmonger to the north. The inn's kitchen is back to the south.",
        exits: { south: "innKitchen", east: "townButcher", west: "townBakery", north: "townFish" } });
    addRoom({ id: "townButcher", title: "The Butcher",
        description: "Cuts of meat hang from steel hooks, and a broad-shouldered butcher stands ready behind the counter. The square is back to the west.",
        exits: { west: "square" }, items: ["meat", "butcherman"] });
    addRoom({ id: "townBakery", title: "The Bakery",
        description: "Shelves of loaves and pastries fill the warm little bakery. The square lies east.",
        exits: { east: "square" }, items: ["bread", "baker"] });
    addRoom({ id: "townFish", title: "The Fishmonger",
        description: "The day's catch glistens on crushed ice while the fishwife calls her prices. The square is back to the south.",
        exits: { south: "square" }, items: ["fish", "fishwife", "cat"] });

    return { rooms, items };
}

function buildRiverboatWorld() {
    const items = {};
    const addItem = (p) => { const it = makeItem(p); items[it.id] = it; };

    // Dockside fixtures at River Street.
    addItem({ id: "schedule", name: "schedule board", nouns: ["schedule", "board", "sign", "chalkboard"],
        description: "A chalkboard easel by the gangway listing today's sailings.",
        readText: "\"SAVANNAH BELLE — TODAY'S SAILINGS\n  • 1:00  The CANNON Cruise — includes a cannon salute at Fort Jackson\n  • 3:30  The AFTERNOON Cruise\n  • 7:00  The SUNSET Cruise\nEvery cruise runs west to the Talmadge Bridge, then down to Old Fort Jackson.\nBOARD the cruise you'd like.\"",
        isFixture: true });
    addItem({ id: "gangway", name: "gangway", nouns: ["gangway", "gangplank", "ramp"],
        description: "A broad wooden gangway sloping up to the boat's main deck.", isFixture: true });
    addItem({ id: "guests", name: "guests", nouns: ["guests", "guest", "passengers", "tourists", "crowd"],
        description: "Cheerful guests in sun hats and windbreakers, waiting to board.",
        isFixture: true, isCreature: true });
    addItem({ id: "cannonCruise", name: "Cannon Cruise", nouns: ["cannon", "one", "noon", "first", "1", "1pm"],
        description: "The 1:00 sailing — it includes a cannon salute at Old Fort Jackson.", isFixture: true });
    addItem({ id: "afternoonCruise", name: "Afternoon Cruise", nouns: ["afternoon", "half", "three", "matinee", "3", "3pm", "330", "30"],
        description: "The 3:30 sailing, an easy afternoon run to the fort and back.", isFixture: true });
    addItem({ id: "sunsetCruise", name: "Sunset Cruise", nouns: ["sunset", "evening", "seven", "dusk", "7", "7pm"],
        description: "The 7:00 sailing, timed to catch the sunset over the marshes.", isFixture: true });

    // Aboard and along the river.
    addItem({ id: "captain", name: "Captain Mike", nouns: ["captain", "mike", "skipper", "pilot"],
        description: "Captain Mike, the boat's weathered and genial skipper, one hand on the wheel and a microphone in the other.",
        isFixture: true, isCreature: true });
    addItem({ id: "containership", name: "container ship", nouns: ["container", "ship", "freighter", "cargo"],
        description: "A colossal container ship stacked with steel boxes from every corner of the world, riding low with cargo.", isFixture: true });
    addItem({ id: "tugboat", name: "tugboat", nouns: ["tug", "tugboat", "tugs"],
        description: "A squat, powerful tugboat churning past, its wake rocking the boat.", isFixture: true });
    addItem({ id: "bridge", name: "Talmadge Bridge", nouns: ["bridge", "talmadge", "cables", "span"],
        description: "The Talmadge Memorial Bridge, a soaring cable-stayed span high above the river.", isFixture: true });
    addItem({ id: "fort", name: "Old Fort Jackson", nouns: ["fort", "jackson", "ramparts", "walls"],
        description: "Old Fort Jackson, a squat brick fortress guarding a bend in the river.", isFixture: true });
    addItem({ id: "cannon", name: "cannon", nouns: ["cannon", "gun"],
        description: "A black iron cannon on the fort's rampart, manned by a crew in period dress.", isFixture: true });

    const rooms = {};
    const addRoom = (p) => { const r = makeRoom(p); rooms[r.id] = r; };

    addRoom({ id: "riverStreet", title: "River Street Dock",
        description: "You're on the cobblestones of River Street, just east of the Hyatt, where the paddle steamer Savannah Cruise is moored. A gangway leads aboard, and a chalk schedule board lists today's sailings. Fellow sightseers line up around you, tickets in hand. (READ the SCHEDULE, then BOARD a cruise.)",
        exits: { north: "riverD1" },
        items: ["schedule", "gangway", "guests", "cannonCruise", "afternoonCruise", "sunsetCruise"] });

    // The boat is a four-deck boat; each cruise leg has all four decks, so
    // passengers can roam UP/DOWN at every stage. The tour advances from the
    // open-air top deck (D4): WEST to the bridge, then EAST to the fort.

    // Leg 1 — moored at River Street, downtown Savannah in view.
    addRoom({ id: "riverD1", title: "First Deck — Dining Room",
        description: "The first-deck dining room, white-clothed tables and a Lowcountry buffet, windows framing the cobblestones of River Street. A stairway leads UP.",
        exits: { up: "riverD2" } });
    addRoom({ id: "riverD2", title: "Second Deck — Dining Room",
        description: "A second, airier dining room, its tall windows looking out on the historic River Street storefronts. Stairs lead UP and DOWN.",
        exits: { up: "riverD3", down: "riverD1" } });
    addRoom({ id: "riverD3", title: "Third Deck — Sightseeing Lounge",
        description: "The air-conditioned sightseeing lounge, wrapped in panoramic glass, cool and quiet above the waterfront bustle. Stairs lead UP and DOWN.",
        exits: { up: "riverD4", down: "riverD2" } });
    addRoom({ id: "riverD4", title: "Fourth Deck — Open-Air Deck",
        description: "The breezy open-air top deck. Captain Mike is at the wheel, and off the rail stand the golden dome of City Hall, the old Cotton Exchange, and the Waving Girl statue on her lonely watch. Head WEST to get underway upriver; stairs lead DOWN.",
        exits: { west: "portD4", down: "riverD3" }, items: ["captain"] });

    // Leg 2 — the working river, amid the Port of Savannah.
    addRoom({ id: "portD1", title: "First Deck — Dining Room",
        description: "The first-deck dining room; through the windows the steel hulls of container ships slide past, close enough to read their names. A stairway leads UP.",
        exits: { up: "portD2" }, items: ["containership", "tugboat"] });
    addRoom({ id: "portD2", title: "Second Deck — Dining Room",
        description: "The second-deck dining room, dessert plates rattling as a tugboat's wake rolls under the boat. Stairs lead UP and DOWN.",
        exits: { up: "portD3", down: "portD1" }, items: ["containership", "tugboat"] });
    addRoom({ id: "portD3", title: "Third Deck — Sightseeing Lounge",
        description: "The cool sightseeing lounge; behind the glass, towering cranes work the busy terminals of the Port of Savannah. Stairs lead UP and DOWN.",
        exits: { up: "portD4", down: "portD2" }, items: ["containership", "tugboat"] });
    addRoom({ id: "portD4", title: "Fourth Deck — Open-Air Deck",
        description: "The open-air deck amid the working river — container ships and tugboats on every side, the Talmadge Bridge climbing into the sky ahead. Continue WEST toward the bridge; stairs lead DOWN.",
        exits: { west: "bridgeD4", down: "portD3" }, items: ["captain", "containership", "tugboat"] });

    // Leg 3 — beneath the Talmadge Bridge, where the boat comes about.
    addRoom({ id: "bridgeD1", title: "First Deck — Dining Room",
        description: "The first-deck dining room; the light dims for a moment as the great bridge passes overhead. A stairway leads UP.",
        exits: { up: "bridgeD2" }, items: ["bridge"] });
    addRoom({ id: "bridgeD2", title: "Second Deck — Dining Room",
        description: "The second-deck dining room, passengers pressing to the windows to crane up at the span. Stairs lead UP and DOWN.",
        exits: { up: "bridgeD3", down: "bridgeD1" }, items: ["bridge"] });
    addRoom({ id: "bridgeD3", title: "Third Deck — Sightseeing Lounge",
        description: "The sightseeing lounge; through the glass the Talmadge's pale cables fan out far above. Stairs lead UP and DOWN.",
        exits: { up: "bridgeD4", down: "bridgeD2" }, items: ["bridge"] });
    addRoom({ id: "bridgeD4", title: "Fourth Deck — Open-Air Deck",
        description: "The open-air deck beneath the Talmadge Memorial Bridge, its pale cables soaring overhead. Captain Mike brings the boat about here for the slow run downriver — head EAST and he'll walk you through Savannah's history all the way to Old Fort Jackson; stairs lead DOWN.",
        exits: { east: "cityD4", down: "bridgeD3" }, items: ["captain", "bridge"] });

    // Eastbound history legs — the slow downriver run, narrated by Captain Mike.
    // Leg 4 — the historic downtown riverfront.
    addRoom({ id: "cityD1", title: "First Deck — Dining Room",
        description: "The first-deck dining room; out the windows the historic riverfront slides slowly by — cobblestone River Street and the tall façades of the old cotton warehouses. A stairway leads UP.",
        exits: { up: "cityD2" } });
    addRoom({ id: "cityD2", title: "Second Deck — Dining Room",
        description: "The second-deck dining room; above the rooftops rises the gold dome of City Hall. Stairs lead UP and DOWN.",
        exits: { up: "cityD3", down: "cityD1" } });
    addRoom({ id: "cityD3", title: "Third Deck — Sightseeing Lounge",
        description: "The sightseeing lounge; through the glass, the restored Cotton Exchange and the ballast-stone ramps of the old wharves. Stairs lead UP and DOWN.",
        exits: { up: "cityD4", down: "cityD2" } });
    addRoom({ id: "cityD4", title: "Fourth Deck — Open-Air Deck",
        description: "The open-air deck off historic downtown Savannah, the old city drifting slowly past. Continue EAST toward Old Fort Jackson; stairs lead DOWN.",
        exits: { east: "wavingD4", down: "cityD3" }, items: ["captain"] });

    // Leg 5 — the eastern riverfront and the Waving Girl.
    addRoom({ id: "wavingD1", title: "First Deck — Dining Room",
        description: "The first-deck dining room; the banks open to marsh grass and the long view downriver. A stairway leads UP.",
        exits: { up: "wavingD2" } });
    addRoom({ id: "wavingD2", title: "Second Deck — Dining Room",
        description: "The second-deck dining room; passengers wave at a passing freighter, keeping up an old Savannah tradition. Stairs lead UP and DOWN.",
        exits: { up: "wavingD3", down: "wavingD1" } });
    addRoom({ id: "wavingD3", title: "Third Deck — Sightseeing Lounge",
        description: "The sightseeing lounge; the little white statue of the Waving Girl slips by on the point. Stairs lead UP and DOWN.",
        exits: { up: "wavingD4", down: "wavingD2" } });
    addRoom({ id: "wavingD4", title: "Fourth Deck — Open-Air Deck",
        description: "The open-air deck along the eastern riverfront; riverside refineries — great heaped piles and three tall silos — slide past as Old Fort Jackson comes into view downriver. Continue EAST; stairs lead DOWN.",
        exits: { east: "fortJackson", down: "wavingD3" }, items: ["captain"] });

    // Arrival — reaching the fort wins.
    addRoom({ id: "fortJackson", title: "Old Fort Jackson",
        description: "The boat rounds a marshy bend to Old Fort Jackson, its brick ramparts standing guard where the river narrows.",
        exits: { west: "wavingD4" }, items: ["fort", "cannon"] });

    return { rooms, items };
}

function buildFortPulaskiWorld() {
    const items = {};
    const addItem = (p) => { const it = makeItem(p); items[it.id] = it; };

    // Entrance.
    addItem({ id: "gates", name: "park gates", nouns: ["gate", "gates"],
        description: "The park entrance gates, open onto the causeway that runs across the marsh to Cockspur Island.", isFixture: true });
    addItem({ id: "entrancesign", name: "entrance sign", nouns: ["sign", "entrance"],
        description: "A brown National Park Service sign: FORT PULASKI NATIONAL MONUMENT.",
        readText: "\"FORT PULASKI NATIONAL MONUMENT — Cockspur Island, Georgia. Established 1924. Drive ahead to the visitor center to begin your visit.\"",
        isFixture: true });

    // Visitor center.
    addItem({ id: "ranger", name: "Ranger Max", nouns: ["ranger", "max", "guide", "attendant"],
        description: "Ranger Max, a National Park Service ranger in a flat-brimmed hat, glad to share the fort's story.",
        isFixture: true, isCreature: true });
    addItem({ id: "exhibit", name: "history exhibit", nouns: ["exhibit", "display", "history", "panel", "panels"],
        description: "A wall of exhibit panels tracing the fort from its brick-by-brick construction to the day its walls were breached.",
        readText: "\"THE STORY OF FORT PULASKI\nNamed for Casimir Pulaski, the Polish-born 'father of the American cavalry,' who fell at the 1779 Siege of Savannah. Begun in 1829 and eighteen years in the building — a young Robert E. Lee helped survey its dikes. Its walls were thought impregnable until April 11–12, 1862, when Union rifled cannon on Tybee Island breached them in about thirty hours, ending the age of masonry forts.\"",
        isFixture: true });

    // Battery Hambright.
    addItem({ id: "battery", name: "Battery Hambright", nouns: ["battery", "hambright", "emplacement", "concrete"],
        description: "A squat, poured-concrete gun battery from around 1900, its gun wells empty and open to the sky. It is named for Lieutenant Horace G. Hambright, a West Point officer who died young in 1896; the battery never received its guns and never fired a shot.",
        isFixture: true });
    addItem({ id: "marker", name: "historical marker", nouns: ["marker", "plaque", "tablet"],
        description: "A cast historical marker beside the battery.",
        readText: "\"BATTERY HORACE HAMBRIGHT — Built 1899–1900 to guard the mouth of the Savannah River, and named in 1904 for Lt. Horace G. Hambright, U.S.A. Poured over 30,000 bricks salvaged from the original fort construction village. Designed for two rapid-fire 3-inch guns on disappearing mounts; the guns were never installed.\"",
        isFixture: true });

    // North Pier and the river traffic.
    addItem({ id: "pier", name: "North Pier", nouns: ["pier", "dock", "wharf"],
        description: "The historic North Pier, reaching out into the channel where the Savannah River opens to the Atlantic.", isFixture: true });
    addItem({ id: "containership", name: "container ship", nouns: ["container", "ship", "freighter", "cargo"],
        description: "A colossal container ship riding the channel, stacked with steel boxes bound to or from the busy Port of Savannah.", isFixture: true });
    addItem({ id: "coastguard", name: "Coast Guard boat", nouns: ["coast", "guard", "cutter", "patrol"],
        description: "A bright, orange-striped Coast Guard boat throttling past on patrol.", isFixture: true });
    addItem({ id: "pilotboat", name: "river pilot boat", nouns: ["pilot", "pilotboat"],
        description: "A fast river pilot boat, out to put a harbor pilot aboard an inbound freighter for the run up to Savannah.", isFixture: true });

    // Lighthouse Overlook Trail.
    addItem({ id: "crabs", name: "fiddler crabs", nouns: ["crab", "crabs", "fiddler", "fiddlers"],
        description: "Mud fiddler crabs — the males waving one oversized claw — scattering sideways into their burrows as you pass.", isFixture: true });
    addItem({ id: "binoculars", name: "binoculars", nouns: ["binoculars", "scope"],
        description: "A pair of mounted binoculars fixed on the channel, trained across the marsh toward the lighthouse.", isFixture: true });
    addItem({ id: "lighthouse", name: "Cockspur Island Lighthouse", nouns: ["lighthouse", "cockspur", "light", "beacon"],
        description: "The Cockspur Island Lighthouse — the smallest in Georgia — on its oyster-shell bar, its base shaped like a ship's prow to cut the waves. It stood through the 1862 bombardment with thousands of shots passing overhead; it's closed to the public but plain to see from here.", isFixture: true });
    addItem({ id: "deck", name: "observation deck", nouns: ["deck", "overlook", "platform"],
        description: "A small wooden observation deck at the marsh's edge.", isFixture: true });

    // The fort itself (placeholder for a future update).
    addItem({ id: "fortwalls", name: "fort", nouns: ["fort", "pulaski", "walls", "drawbridge", "moat"],
        description: "Fort Pulaski itself — a massive brick fortress ringed by a moat, its far wall still scarred where Union rifled cannon breached it in 1862. Exploring the parade ground, the casemates, and the cannon-lined terreplein upstairs is coming in a future update.", isFixture: true });

    const rooms = {};
    const addRoom = (p) => { const r = makeRoom(p); rooms[r.id] = r; };

    addRoom({ id: "gate", title: "Fort Pulaski Gates",
        description: "You drive in through the park gates and along the causeway across the marsh onto Cockspur Island. Ahead, the brick ramparts of Fort Pulaski rise behind their moat. The visitor center is just NORTH.",
        exits: { north: "visitorCenter" }, items: ["gates", "entrancesign"] });
    addRoom({ id: "visitorCenter", title: "Visitor Center",
        description: "The Fort Pulaski visitor center: a cool room of exhibits and a bookstore, where Ranger Max waits at the desk to check you in. The fort's drawbridge is just INSIDE. A walking path leads NORTH toward the river, past Battery Hambright to the North Pier; the Lighthouse Overlook trailhead is EAST; and your car is parked back SOUTH.",
        exits: { south: "gate", inside: "fort", north: "batteryHambright", east: "trail1" }, items: ["ranger", "exhibit"] });
    addRoom({ id: "fort", title: "Fort Pulaski",
        description: "You cross the drawbridge into Fort Pulaski. The parade ground opens before you, casemates ringing the walls and a stone stair climbing to the terreplein — the upper level where the cannons stand watch over the river. (Exploring the fort inside and out, including the cannon-lined upstairs, is coming soon.) The visitor center is back OUTSIDE.",
        exits: { outside: "visitorCenter" }, items: ["fortwalls"] });
    addRoom({ id: "batteryHambright", title: "Battery Hambright",
        description: "The path from the visitor center brings you to Battery Hambright, a low concrete gun battery set among the marsh grass, its gun wells empty and open to the sky. The North Pier lies ahead to the NORTH; the visitor center is back SOUTH.",
        exits: { south: "visitorCenter", north: "northPier" }, items: ["battery", "marker"] });
    addRoom({ id: "northPier", title: "Historic North Pier",
        description: "The Historic North Pier reaches out into the channel at the mouth of the Savannah River, where it opens to the Atlantic — a fine spot to watch the river traffic pass. Battery Hambright and the visitor center are back SOUTH.",
        exits: { south: "batteryHambright" }, items: ["pier", "containership", "coastguard", "pilotboat"] });

    // The Lighthouse Overlook Trail — four stops through marshy maritime woods,
    // walked FORWARD (deeper) and BACK (toward the fort).
    addRoom({ id: "trail1", title: "Lighthouse Overlook — Trailhead",
        description: "A flat, sandy path slips into the maritime woods northeast of the fort, live oaks draped in Spanish moss overhead. Fiddler crabs scatter from the path ahead, big claws waving. The trail leads FORWARD into the marsh; the fort is BACK the way you came.",
        exits: { north: "trail2", south: "visitorCenter" }, items: ["crabs"] });
    addRoom({ id: "trail2", title: "Lighthouse Overlook — Into the Marsh",
        description: "The woods open onto broad stands of green cordgrass running to the horizon. Hundreds of fiddler crabs pour sideways into their burrows as your shadow falls across the mud. The path runs FORWARD and BACK.",
        exits: { north: "trail3", south: "trail1" }, items: ["crabs"] });
    addRoom({ id: "trail3", title: "Lighthouse Overlook — The Dike",
        description: "The path climbs onto an old earthen dike, oyster shells crunching underfoot and the salt smell strong on the breeze. More fiddler crabs scurry clear ahead. Continue FORWARD toward the overlook, or head BACK.",
        exits: { north: "trail4", south: "trail2" }, items: ["crabs"] });
    addRoom({ id: "trail4", title: "Lighthouse Overlook — The Deck",
        description: "A small wooden observation deck at the marsh's edge, a pair of mounted binoculars fixed on the channel. Out across the water stands the Cockspur Island Lighthouse. The trail runs BACK the way you came.",
        exits: { south: "trail3" }, items: ["deck", "binoculars", "lighthouse"] });

    return { rooms, items };
}
