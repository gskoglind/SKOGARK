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
        // "forward"/"back" read as north/south, for walking a linear trail,
        // and "next (stage)"/"onward" advance the same way.
        case "forward": case "ahead": case "fwd": case "next": case "onward": return "north";
        case "back": case "backward": case "backwards": return "south";
        case "ascend": return "up";
        case "descend": return "down";
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
    // Spends coins if the purse covers it; returns whether it did.
    spend(amount) {
        if (this.coins < amount) return false;
        this.coins -= amount;
        return true;
    }
    isCarrying(id) { return this.inventory.includes(id); }
    isCarryingKind(kind) {
        return this.inventory.some((id) => this.items[id] && this.items[id].kind === kind);
    }

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
                // A bare CLIMB means climb UP (stairs, decks, the mountain).
                if (verb === "climb" && rest.length === 0) this.move("up");
                else this.handleGo(rest);
                break;
            case "examine": case "x": case "inspect": case "read": case "watch": case "view":
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
            case "ring": case "throw": case "play":
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
            case "sit": case "rest":
                this.sitDown();
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
        // "stage" is filler so "NEXT STAGE" reads as the direction NEXT.
        const filler = new Set(["the", "a", "an", "to", "at", "my", "some", "stage"]);
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
        // Place names win over direction words embedded in them, so
        // "go to north pier" heads for the pier rather than reading "north".
        const nonDirectional = words.filter((w) => !directionFrom(w));
        if (nonDirectional.length) {
            const room = this.rooms[this.currentRoomID];
            if (room) {
                for (const dir of DIRECTIONS) {
                    const destinationID = room.exits[dir];
                    if (!destinationID) continue;
                    if (this.titleMatches(this.rooms[destinationID], nonDirectional)) { this.move(dir); return; }
                }
            }
            if (this.walkToward(nonDirectional)) return;
        }
        for (const w of words) {
            const dir = directionFrom(w);
            if (dir) { this.move(dir); return; }
        }
        const id = this.resolveItem(words);
        if (id && this.scenario.portalDirection) {
            const dir = this.scenario.portalDirection(this, id);
            if (dir) { this.move(dir); return; }
        }
        this.emit("Go where?");
    }

    // True when any of the player's words appears in the room's title.
    titleMatches(room, words) {
        if (!room) return false;
        const titleWords = new Set(room.title.toLowerCase().split(/[^a-z]+/).filter(Boolean));
        return words.some((w) => titleWords.has(w));
    }

    // Walks toward a previously visited room the player names from anywhere
    // ("go to the visitor center" from deep in the fort), following the
    // shortest chain of exits one step at a time — every step is a real move,
    // so gates still gate and each room announces itself. Returns false when
    // no visited room matches the words.
    walkToward(words) {
        const anyMatch = Object.values(this.rooms).some((r) =>
            r.visited && r.id !== this.currentRoomID && this.titleMatches(r, words));
        if (!anyMatch) return false;

        // Breadth-first search over exits to the nearest matching visited room.
        const queue = [this.currentRoomID];
        const cameFrom = {};
        const seen = new Set([this.currentRoomID]);
        let target = null;
        while (queue.length) {
            const id = queue.shift();
            const room = this.rooms[id];
            if (id !== this.currentRoomID && room && room.visited && this.titleMatches(room, words)) {
                target = id;
                break;
            }
            if (!room) continue;
            for (const dir of DIRECTIONS) {
                const dest = room.exits[dir];
                if (!dest || seen.has(dest)) continue;
                seen.add(dest);
                cameFrom[dest] = { room: id, dir };
                queue.push(dest);
            }
        }
        if (!target) return false;

        const path = [];
        let cursor = target;
        while (cursor !== this.currentRoomID && cameFrom[cursor]) {
            path.push(cameFrom[cursor].dir);
            cursor = cameFrom[cursor].room;
        }
        path.reverse();
        if (!path.length || path.length > 10) return false;

        for (const dir of path) {
            const before = this.currentRoomID;
            this.move(dir);
            if (this.currentRoomID === before) break;   // a gate blocked the way
        }
        return true;
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
        // Always list the ways out — especially on revisits, when the full
        // description (and its woven-in directions) doesn't reprint.
        const exits = this.obviousExits();
        if (exits.length) lines.push(`Obvious exits: ${exits.join(", ")}.`);
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
        this.emit(`The ${item.name} is now ${on ? "on" : "off"}.`);
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

    // Sit on a bench or other seat in the room (any item of kind "seat").
    // The seat's readText is the view from it; a plain line otherwise.
    sitDown() {
        this.moves += 1;
        if (!this.canSee()) { this.emit("It's too dark to find a seat."); return; }
        const visible = this.visibleItemIDs();
        const id = visible.find((i) => this.items[i] && this.items[i].kind === "seat");
        const seat = id && this.items[id];
        if (!seat) { this.emit("There's nowhere comfortable to sit here."); return; }
        this.emit(seat.readText || `You rest for a spell on the ${seat.name}.`);
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
        destination: "Explore",
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
        destination: "Explore",
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
        destination: "Savannah",
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
// Island. Drive in through the gates, check in at the visitor center, explore
// the fort inside and out — the parade ground, the gun casemates, the prison
// casemates of the Immortal 600, the cannon-lined terreplein upstairs with its
// river view, and the shell-scarred southeast angle on the moat walk — then
// head out past Battery Hambright to the North Pier and follow the Lighthouse
// Overlook Trail to the Cockspur Lighthouse.
function fortPulaskiScenario() {
    // The nine points of interest the visitor is here to see.
    const stops = ["checkedIn", "sawFort", "sawTerreplein", "sawPrison",
        "sawSurrender", "sawBreach", "sawBattery", "sawPier", "sawLighthouse"];
    return {
        id: "fortPulaski",
        title: "Explore Fort Pulaski",
        destination: "Savannah",
        blurb: "Drive onto Cockspur Island to visit Fort Pulaski National Monument: check in at the visitor center, explore the fort from the parade ground to the cannon-lined terreplein, circle the moat to the shell-scarred walls, watch the ships from the North Pier, and follow the marsh trail to the Cockspur Lighthouse.",
        banner: [
            "FORT PULASKI",
            "A visit to the National Monument on Cockspur Island. (c) 2026",
            "Type HELP for commands. Drive NORTH to the visitor center to check in.",
            "─────────────────────────────",
        ].join("\n"),
        startRoomID: "gate",
        maxScore: 60,
        startingCoins: 0,
        build: buildFortPulaskiWorld,
        fixtureLine(game, id) {
            // Wayfinding signs print on every visit, not just the first,
            // so the fort never leaves you guessing which way is which.
            switch (id) {
                case "paradeSign":
                    return "A wooden signpost points the way: gun casemates NORTH · prison casemates WEST · Colonel Olmstead's quarters SOUTH · terreplein cannons UP · sally port OUT.";
                case "bridgeSign":
                    return "A small sign by the drawbridge: parade ground IN · moat walk SOUTH · visitor center OUT.";
                case "ballplayers":
                    return "Across the grass, reenactors in Union blue are deep in a vintage game of base ball — bats cracking, cheers rolling off the casemate walls.";
                default:
                    return null;
            }
        },
        onTalk(game, id) {
            if (id !== "ranger") return false;
            const beenInside = game.has("sawFort");
            const beenNorth = game.has("sawBattery") || game.has("sawPier");
            const beenTrail = game.has("sawLighthouse");
            // Until the guest has explored somewhere, Max tells the fort's story.
            if (!beenInside && !beenNorth && !beenTrail) {
                game.emit("Ranger Max leans on the desk. \"Fort Pulaski is named for Casimir Pulaski — a Polish nobleman and cavalry commander, the 'father of the American cavalry,' who fell leading a charge at the Siege of Savannah in 1779. The fort took eighteen years to build, and a young Lieutenant Robert E. Lee helped lay out its dikes. Everyone believed these seven-and-a-half-foot brick walls were invincible — until April 1862, when Union rifled cannon on Tybee Island breached them in about thirty hours and made every masonry fort in the world obsolete overnight. The fort itself is just INSIDE across the drawbridge — climb up top for the view, and walk the moat around to see what the cannon fire did. The path NORTH leads to Battery Hambright and the North Pier, and the Lighthouse Overlook Trail heads EAST.\"");
                return true;
            }
            // On return visits Max asks how the guest enjoyed wherever
            // they've been, then points toward what they haven't seen yet.
            // Remember what he's asked about so the visitor-center nudge
            // only fires when there's fresh news.
            if (beenInside) game.set("toldMaxFort");
            if (game.has("sawPier")) {
                game.set("toldMaxPier");
            } else if (game.has("sawBattery")) {
                game.set("toldMaxBattery");
            }
            if (beenTrail) game.set("toldMaxTrail");
            let talk = "Ranger Max looks up from the desk. \"Back again! ";
            if (beenInside) {
                if (game.has("sawBreach")) {
                    talk += "Did you enjoy the fort? I see you found the southeast angle — lay a hand on those shell scars and you're touching the exact spot where every masonry fort on earth went out of date. ";
                } else {
                    talk += "Did you enjoy the fort? Before you leave, walk the moat around to the southeast angle — you can still see where the shells came through in 1862. ";
                }
            }
            if (game.has("sawPier")) {
                talk += "How was the North Pier — best ship-watching on the island, isn't it? Poor Lieutenant Hambright, though: last in his class at West Point, and his battery never fired a shot. ";
            } else if (game.has("sawBattery")) {
                talk += "Did you enjoy Battery Hambright? Named for the West Point 'Goat' of 1893, dead last in his class. Keep on up the path to the North Pier and watch the ships come in. ";
            }
            if (beenTrail) {
                talk += "And how was the lighthouse trail? Smallest lighthouse in Georgia — over five thousand shells passed right over her in 1862 and she never lost a brick. ";
            }
            const left = [];
            if (!beenInside) left.push("the fort itself is just INSIDE across the drawbridge");
            if (!beenNorth) left.push("the path NORTH leads to Battery Hambright and the North Pier");
            if (!beenTrail) left.push("the Lighthouse Overlook Trail heads EAST");
            if (left.length === 0) {
                talk += "You've made the full circuit — not much left I could tell you that you haven't seen with your own eyes.\"";
            } else {
                talk += "Still to see: " + left.join(", and ") + ".\"";
            }
            game.emit(talk);
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
                    game.win("You've seen it all: checked in with Ranger Max, crossed the drawbridge to the parade ground, stood among the cannons on the terreplein with the whole river spread below, paid your respects in the prison casemates, stood in the room where Colonel Olmstead gave up his sword, run your fingers over the shell-scarred southeast angle, watched the ships from the North Pier, and spied the Cockspur Lighthouse from the marsh trail. Fort Pulaski thanks you for visiting — come back any time.");
                }
            };
            switch (roomID) {
                case "visitorCenter":
                    if (!game.has("checkedIn")) {
                        award("checkedIn", 5, "Ranger Max welcomes you to Fort Pulaski National Monument from behind the desk and checks you in. \"Cockspur Island has guarded the mouth of the Savannah River for a very long time — TALK TO MAX or READ the EXHIBIT to hear the story. The fort is just INSIDE, the riverside path to Battery Hambright and the North Pier is NORTH, and the Lighthouse Overlook Trail heads EAST. Take a PARK MAP from the desk — READ MAP any time for the lay of the land.\"");
                    } else if (!game.isWon) {
                        // Max waves the guest over when they come back with
                        // somewhere new to chat about since the last talk.
                        const news = (game.has("sawFort") && !game.has("toldMaxFort"))
                            || (game.has("sawPier") && !game.has("toldMaxPier"))
                            || (!game.has("sawPier") && game.has("sawBattery") && !game.has("toldMaxBattery"))
                            || (game.has("sawLighthouse") && !game.has("toldMaxTrail"));
                        if (news) {
                            game.emit("Ranger Max looks up from the desk and waves. \"Back from exploring? Come TALK to me when you have a minute — I'd love to hear how it went.\"");
                        }
                    }
                    break;
                case "fort":
                    award("sawFort", 5, "You step through the sally port onto the parade ground — a broad green field ringed by brick casemate arches under the garrison flag. Eighteen years and some twenty-five million bricks went into these walls, finished in 1847, and a young Robert E. Lee helped engineer the site. The gun galleries are NORTH, the prison casemates WEST, and a stone stair climbs UP to the cannons on the terreplein.");
                    // The vintage base ball match is in full swing right here
                    // on the parade ground. Optional bonus.
                    if (!game.has("sawBallgame")) {
                        game.set("sawBallgame");
                        game.award(5, "Across the grass, a vintage base ball match is in full swing — bearded men in Union blue swatting a lemon-peel ball and legging it between the sacks, to whoops and hollers off the casemate walls. In 1862 the soldiers of the 48th New York played base ball on this very field, and a photographer caught them at it: one of the earliest photographs of the game ever taken. (WATCH the PLAYERS, or TALK to them.)");
                    }
                    break;
                case "terreplein":
                    award("sawTerreplein", 10, "You come up onto the terreplein, the fort's open upper level, and the view stops you flat: the Savannah River spreading to the sea, container ships riding the channel, the little Cockspur Lighthouse on its shell bar below, and the low green line of Tybee Island across the water — where the Union gunners set their batteries in 1862. Great black cannons stand watch along the ramparts, muzzles out over the river they were built to close.");
                    break;
                case "prison":
                    award("sawPrison", 5, "These dim casemates served as a prison. In the winter of 1864–65 they held the \"Immortal 600\" — Confederate officers confined here in the cold on scant rations; thirteen of them never left the island. Rough wooden bunks and names scratched into the brick remember them.");
                    break;
                case "quarters":
                    award("sawSurrender", 5, "You step into Colonel Olmstead's quarters, kept much as they looked on April 11, 1862. Framed pictures on the wall show the scene: at 2:30 that afternoon, with the southeast wall breached and Union shells reaching for the twenty tons of powder in the magazine, the 25-year-old colonel — who had answered the surrender demand a day earlier with \"I am here to defend the fort, not to surrender it\" — handed his sword across this table to the Union officers. Days later, General David Hunter sent the sword back: the defense had been honorable. In the whole thirty-hour battle, only two men died — one from each side. The sword itself rests in the visitor center museum.");
                    break;
                case "scarredWall":
                    award("sawBreach", 5, "Here it is — the reason this fort changed history. The southeast angle is pocked and cratered with shell strikes, and the smoother, darker patch of brick marks where the wall was breached and rebuilt. On April 10–11, 1862, Union rifled cannon on Tybee Island — a mile away, farther than any smoothbore could reach — chewed through these seven-and-a-half-foot walls in thirty hours. When shells began threatening the powder magazine, Colonel Olmstead surrendered, and every masonry fort on earth was obsolete by lunchtime.");
                    break;
                case "batteryHambright":
                    award("sawBattery", 5, "You come to Battery Hambright, a squat concrete gun emplacement half-swallowed by the marsh grass, its gun wells empty and open to the sky. It's named for Lieutenant Horace G. Hambright — the West Point \"Goat\" of 1893, the cadet who graduates dead last in his class — a well-liked young officer who died out west in 1896 and was honored here in 1904. Poured about 1900 over a foundation of 30,000 bricks salvaged from the original fort village, it was built to guard the river mouth in the Spanish-American War era — yet it never received its guns and never fired a shot. Last in his class, and his battery never fired a shot: somehow it fits.");
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
            if (!game.has("sawFort")) todo.push("the parade ground");
            if (!game.has("sawTerreplein")) todo.push("the cannons up on the terreplein");
            if (!game.has("sawPrison")) todo.push("the prison casemates");
            if (!game.has("sawSurrender")) todo.push("Colonel Olmstead's quarters");
            if (!game.has("sawBreach")) todo.push("the shell-scarred southeast angle");
            if (!game.has("sawBattery")) todo.push("Battery Hambright");
            if (!game.has("sawPier")) todo.push("the North Pier");
            if (!game.has("sawLighthouse")) todo.push("the Lighthouse Overlook");
            if (todo.length === 0) {
                return { key: "done", clues: ["You've seen every stop — enjoy the view!"] };
            }
            return { key: "todo:" + todo.join("|"), clues: [
                "Still to explore: " + todo.join(", ") + ".",
                "The fort is INSIDE from the visitor center: cross the drawbridge to the parade ground, with the gun casemates NORTH, the prison casemates WEST, Colonel Olmstead's quarters SOUTH, and stairs UP to the terreplein. From the drawbridge, SOUTH follows the moat around to the battered southeast wall.",
                "Outside the fort: NORTH from the visitor center passes Battery Hambright to the North Pier, and the Lighthouse Overlook Trail heads EAST — go FORWARD four stops to the deck and its binoculars.",
            ] };
        },
    };
}

// Roppongi Pub Crawl: one loud, neon night out in Tokyo's most famous bar
// district. Ride the escalator up from the Hibiya Line into Roppongi Crossing,
// then work the classic gaijin circuit — ring the bell at Geronimo's shot bar,
// treat homesick Roy at tiny Mogambo's, and throw darts with the expat league
// at Bar Quest — before landing the night at the ramen stand as the sky goes
// pale. Every bar hangs a bell over the counter: RING it and you buy the whole
// bar a round, ringer's choice — and now and then another guest rings it, and
// you're included.
function roppongiScenario() {
    return {
        id: "roppongi",
        title: "Roppongi Pub Crawl",
        destination: "Japan",
        blurb: "One neon night in Tokyo's famous bar district: ring the bell at Geronimo's, treat a homesick regular at Mogambo's, throw darts at Bar Quest, then dawn ramen and the 05:12 first train home.",
        banner: [
            "ROPPONGI PUB CRAWL",
            "One night out in Tokyo. (c) 2026",
            "Type HELP for commands. Ride the escalator UP to the crossing.",
            "─────────────────────────────",
        ].join("\n"),
        startRoomID: "roppongiStation",
        maxScore: 60,
        startingCoins: 50,
        build: buildRoppongiWorld,
        portalGate(game, direction) {
            // The first train only runs at dawn: the gates are shuttered
            // until the crawl is done and the ramen eaten.
            if (game.roomID === "roppongiStation" && direction === "inside" && !game.has("ateRamen")) {
                return "The ticket gates are shuttered and the platform is dark — the last train left at 00:24, and nothing runs until the 05:12 first train. (Finish the crawl and eat your ramen first.)";
            }
            return null;
        },
        fixtureLine(game, id) {
            const item = game.item(id);
            if (!item) return null;
            if (item.forSale) {
                const name = item.name.charAt(0).toUpperCase() + item.name.slice(1);
                return `${name} is on the menu — ${item.price} coins.`;
            }
            switch (id) {
                case "bellGeronimos":
                    return game.has("rangBell")
                        ? "The famous bell hangs quiet over the bar — you've already had your CLANG tonight."
                        : "Over the bar hangs THE bell. House rule: RING it and you buy the whole bar a round, ringer's choice.";
                case "bellMogambos":
                    return game.has("rangBellMogambos")
                        ? "Mogambo's little bell hangs quiet, still swinging faintly from your round."
                        : "A little brass bell hangs over the counter. Same rule as everywhere in Roppongi: RING it, and the round's on you — ringer's choice.";
                case "bellQuest":
                    return game.has("rangBellQuest")
                        ? "Quest's bell hangs quiet over the taps, its rope still warm from your big moment."
                        : "A ship's bell hangs over the taps. The plaque under it reads: RING FOR GLORY — ROUND FOR THE HOUSE, RINGER'S CHOICE.";
                case "dartboard":
                    return game.has("threwDarts")
                        ? "The dartboard on the far wall still shows your lucky triple-20."
                        : "A battered dartboard waits on the far wall, the expat league eyeing fresh blood. (THROW DARTS to chalk in.)";
                case "ryan": return "Ryan works the rail of shot glasses behind the bar like a church organ.";
                case "martin": return "Martin presides over the tiny bar, remembering everyone's name.";
                case "roy": return "Roy, a big homesick Texan, nurses an empty glass at the end of the bar.";
                case "matt": return "Matt pulls pints behind the long counter, keeping half an eye on the darts.";
                case "cook": return "The cook tends his steaming pots behind the counter, towel knotted around his head.";
                case "tout": return "A fast-talking tout works the corner, promising the best deals in Roppongi.";
                case "salarymen": return "A knot of cheerful salarymen sways past, neckties knotted around their heads.";
                default: return null;
            }
        },
        onMoveObject(game, id) {
            switch (id) {
                case "bellGeronimos":
                    if (game.has("rangBell")) {
                        game.emit("Ryan shakes his head, grinning. \"Once a night, champ. Legends pace themselves.\"");
                        return true;
                    }
                    if (!game.spend(15)) {
                        game.emit(`Ringing the bell means buying the whole bar a round — 15 coins, and you have ${game.coins}. Ryan gives you a look of genuine sympathy.`);
                        return true;
                    }
                    game.set("rangBell");
                    game.award(10, `You reach up and give the bell a mighty CLANG. The bar erupts. "Ringer's choice!" Ryan shouts, and you call it — tequila! — and a rank of shots goes rattling down the counter. Strangers pound your back; somebody asks how to spell your name for a plaque. Fifteen coins well spent: for one golden moment you are the most popular person in Roppongi. (You have ${game.coins} coins left.)`);
                    return true;
                case "bellMogambos":
                    if (game.has("rangBellMogambos")) {
                        game.emit("Martin catches your hand halfway to the rope. \"Pace yourself, friend. The night is long and the blender needs a rest.\"");
                        return true;
                    }
                    if (!game.spend(15)) {
                        game.emit(`Mogambo's bell plays by Roppongi rules — a round for the house is 15 coins, and you have ${game.coins}. Martin pretends not to have noticed you reaching.`);
                        return true;
                    }
                    game.set("rangBellMogambos");
                    game.emit(`CLANG! "Ringer's choice!" Martin calls. "Margaritas," you declare, and the blender roars like a jet on takeoff. Eight frozen margaritas for eight stools, and the whole bar toasts you by name — Martin's already learned it. (You have ${game.coins} coins left.)`);
                    return true;
                case "bellQuest":
                    if (game.has("rangBellQuest")) {
                        game.emit("Matt raises an eyebrow at the bell rope. \"Encore's extra, and your public can wait.\"");
                        return true;
                    }
                    if (!game.spend(15)) {
                        game.emit(`Quest's bell means a round for the whole pub — 15 coins, and you have ${game.coins}. Matt polishes a glass and lets the moment pass kindly.`);
                        return true;
                    }
                    game.set("rangBellQuest");
                    game.emit(`CLANG! The whole pub turns. "Ringer's choice!" calls Matt. "Pints all round!" you announce, and the taps run bright while the darts corner drums the tables. Somebody starts the jukebox in your honor. (You have ${game.coins} coins left.)`);
                    return true;
                case "dartboard":
                    if (game.has("threwDarts")) {
                        game.emit("\"Another leg?\" the oil trader offers. You bow out while you're ahead — retire undefeated, that's the secret.");
                        return true;
                    }
                    game.set("threwDarts");
                    game.award(10, "You chalk in with the expat league — an oil trader, two English teachers, and a bassist between gigs. Your first two darts wander wide. The third thuds home in the triple-20 and the corner erupts; Matt rings last orders off the back of it. You retire one leg up, a legend of exactly one leg.");
                    return true;
                case "jukebox":
                    game.emit("You punch in your pick and 'Take Me Home, Country Roads' rolls out for the ninth time tonight. The entire pub sings the chorus. It is impossible not to.");
                    return true;
                case "fareMachine":
                    if (game.has("fareSettled")) {
                        game.emit("Settled already — the gate is ready for you. Step back OUT.");
                        return true;
                    }
                    if (game.spend(5)) {
                        game.set("fareSettled");
                        game.emit(`You feed in what the machine asks — five coins for the overshoot — and it clunks out a crisp little adjustment ticket. The gate will open now. Step back OUT. (You have ${game.coins} coins left.)`);
                    } else {
                        game.set("fareSettled");
                        game.emit("Your wallet is as empty as the last train was full. The night-shift attendant leans out, takes one look at your face, and waves you through with a tired nod — \"first train, huh.\" The gate will open. Step back OUT.");
                    }
                    return true;
                default:
                    return false;
            }
        },
        onGive(game, gift, recipient) {
            if (recipient !== "roy") return false;
            if (game.has("treatedRoy")) {
                game.emit("Roy raises what's left of the margarita to you. \"One's my limit, partner. Two and I start singin'.\"");
                return true;
            }
            if (!(game.item(gift) && game.item(gift).kind === "margarita")) {
                const gname = game.item(gift) ? game.item(gift).name : "offering";
                game.emit(`Roy eyes the ${gname} and shakes his head kindly. "Mighty generous — but round here I only drink Martin's frozen margarita."`);
                return true;
            }
            game.consumeFromInventory(gift);
            game.set("treatedRoy");
            game.award(10, "Roy takes the frozen margarita in both hands like it's the last helicopter out of somewhere. \"From Kenji? Well I'll be.\" One long pull and he's telling Galveston stories; by the second he's promised you a bed on the Gulf Coast any time you're passing. Martin gives you a quiet nod — you've done a good thing tonight.");
            return true;
        },
        onTalk(game, id) {
            switch (id) {
                case "roy":
                    if (game.has("treatedRoy")) {
                        game.emit("\"You're alright, partner,\" Roy says, raising the frosty glass. \"Anybody gives you trouble tonight, you tell 'em Roy sent you.\"");
                    } else {
                        game.emit("\"Galveston,\" Roy sighs into his empty glass. \"You know what they don't got in this whole shining city? A decent frozen margarita.\" Behind the bar, Martin polishes a glass and nods meaningfully at the blender.");
                    }
                    return true;
                case "cook": {
                    const left = [];
                    if (!game.has("rangBell")) left.push("the bell at Geronimo's");
                    if (!game.has("treatedRoy")) left.push("Roy's margarita at Mogambo's");
                    if (!game.has("threwDarts")) left.push("darts at Quest");
                    if (left.length === 0) {
                        game.emit(game.has("ateRamen")
                            ? "\"05:12,\" the cook says, jerking his chin toward the crossing. \"First train. You'll make it.\""
                            : "\"Sit,\" the cook says, already reaching for a bowl.");
                    } else {
                        game.emit(`The cook taps his ladle on the pot. "Ramen is the period at the end of the sentence — not the middle. Still on your list: ${left.join(", ")}. Come back when the crawl is done."`);
                    }
                    return true;
                }
                default:
                    return false;
            }
        },
        onEnterRoom(game, roomID) {
            const award = (flag, points, note) => {
                if (game.has(flag)) return;
                game.set(flag);
                game.award(points, note);
            };
            // On a return visit to each bar, another guest rings the bell —
            // round for the house, ringer's choice, and you're included.
            // Once per bar, and never after the night has been won.
            const guestRingsBell = (flag, note) => {
                if (game.has(flag) || game.isWon) return;
                game.set(flag);
                game.emit(note);
            };
            switch (roomID) {
                case "crossing":
                    award("hitTheTown", 5, "You ride the escalator up out of the station and Roppongi hits you all at once — neon stacked ten stories high, the Shuto Expressway thundering overhead on its great green legs, touts calling, taxis sweeping past, a hundred bars leaking a hundred songs. The night is officially on. (Kenji's NAPKIN has the plan, if you grabbed it.)");
                    break;
                case "geronimos":
                    if (!game.has("sawGeronimos")) {
                        award("sawGeronimos", 5, "Up the narrow stairs and into Geronimo Shot Bar — small, loud, and famous on five continents. Brass plaques of honored drinkers plate every wall (READ them), Ryan holds court behind the bar, and everyone who walks in glances up at the bell. You did too.");
                    } else {
                        guestRingsBell("guestRangGeronimos", "CLANG! Before the door even shuts behind you, a just-promoted banker down the bar rings the bell. \"Ringer's choice — tequila!\" Shots for the whole house, and Ryan slides one your way without asking. House rules are house rules.");
                    }
                    break;
                case "mogambos":
                    if (!game.has("sawMogambos")) {
                        award("sawMogambos", 5, "You duck into Mogambo's — a bar the size of a generous closet and warmer than most living rooms. Martin greets you from behind the counter like he's been expecting you for years. At the end of the bar, a big man in a pearl-snap shirt stares into an empty glass.");
                    } else {
                        guestRingsBell("guestRangMogambos", "As you settle back in, one of the eight stools stands up and rings the little bell — CLANG! \"Ringer's choice: margaritas, all around!\" Martin's blender roars like a jet engine, and yours arrives with extra salt. You didn't even have to ask.");
                    }
                    break;
                case "quest":
                    if (!game.has("sawQuest")) {
                        award("sawQuest", 5, "Bar Quest: a proper pub transplanted whole into Tokyo — long oak counter, taps polished bright, a jukebox mid-singalong, and a darts corner where the expat league holds court. Matt nods you in. Nobody stays a stranger here longer than one pint.");
                    } else {
                        guestRingsBell("guestRangQuest", "CLANG! The night's darts winner rings the bell at the end of the bar. \"Ringer's choice — whisky, the good one!\" Matt walks the bottle down the line, you included. Rules are rules.");
                    }
                    break;
                case "roppongiStation":
                    // The classic all-nighter bookends: come down too early
                    // and the last train is long gone; come down after the
                    // ramen and the 05:12 first train waits to carry you home.
                    if (game.has("ateRamen") && !game.isWon) {
                        if (!game.has("boardedFirstTrain")) {
                            game.set("boardedFirstTrain");
                            game.emit("Down the long escalator one last time. The platform is cool and near-empty, and at 05:12 the first Hibiya Line train of the morning slides in with its lights on. But there is no riding home for free — the TICKET MACHINES are INSIDE by the gates. BUY a TICKET, then step IN to board.");
                        }
                    } else if (game.has("hitTheTown") && !game.has("sawShutters") && !game.isWon) {
                        game.set("sawShutters");
                        game.emit("Down on the platform the shutters are half-drawn and the departure board is blank — the last train left at 00:24. No way home now but through the night. First train: 05:12. Better make it a night worth staying up for.");
                    }
                    break;
                case "trainCar":
                    game.emit("The doors chime shut and Roppongi slides away behind you. One stop — Kamiyachō — and the train eases in at your transfer. This is where you change: get OFF, go FORWARD onto the platform.");
                    break;
                case "wrongTerminus":
                    if (!game.has("wentWrong")) {
                        game.set("wentWrong");
                        game.emit("Somewhere around the third unfamiliar station name it dawns on you — you never changed trains. By the time you surface it is two hours and a small fortune later, blinking at a terminus you have never heard of. Nothing for it but the long ride BACK to the transfer — and DOWN to your home line this time.");
                    }
                    break;
                case "homeStation":
                    if (!game.isWon) {
                        if (game.isCarryingKind("ticket") || game.has("fareSettled")) {
                            game.win("You feed the ticket into the gate and the little flaps snap open — home. The street outside is going pink over the rooftops, the birds are up, and somewhere a train chimes off toward the day everyone else is starting. You made the 05:12, rode it home, and the perfect crawl is complete: the bell, the margarita, the darts, the ramen, and the last quiet leg through a waking city. Oyasumi.");
                        } else {
                            game.emit("You reach the gate and pat your pockets — no ticket. The flap stays shut with a soft beep of reproach. The 精算 fare-adjustment machine is right beside you: go IN, PUSH it to settle up, then come back OUT to the gate.");
                        }
                    }
                    break;
                case "ramenya": {
                    const done = game.has("rangBell") && game.has("treatedRoy") && game.has("threwDarts");
                    if (done && !game.has("ateRamen")) {
                        game.set("ateRamen");
                        game.award(10, "The cook takes one look at you and doesn't ask — a bowl of shoyu ramen lands on the counter, and it is the best thing anyone has ever eaten anywhere. You rang the bell at Geronimo's, fixed Roy's homesickness at Mogambo's, went one leg up on the darts league at Quest — and now the sky over the expressway is going pale. One thing left, and every Tokyo all-nighter ends the same way: the 05:12 first train. GO TO STATION when the bowl is empty — it's DOWN from the crossing.");
                    } else if (!game.isWon) {
                        game.emit("The cook looks up from his pots and reads you like a menu. \"Not yet,\" he says, not unkindly. \"Ramen is for AFTER the crawl. TALK to me if you've lost the thread.\"");
                    }
                    break;
                }
                default:
                    break;
            }
        },
        hintStage(game) {
            if (!game.has("hitTheTown")) {
                return { key: "surface", clues: [
                    "The night is waiting at street level.",
                    "TAKE the NAPKIN and a MAP from the rack, then ride the escalator UP to Roppongi Crossing.",
                ] };
            }
            const todo = [];
            if (!game.has("rangBell")) todo.push(game.has("sawGeronimos") ? "ring the bell at Geronimo's" : "find Geronimo's shot bar");
            if (!game.has("treatedRoy")) todo.push(game.has("sawMogambos") ? "treat Roy at Mogambo's" : "find Mogambo's");
            if (!game.has("threwDarts")) todo.push(game.has("sawQuest") ? "throw darts at Bar Quest" : "find Bar Quest");
            if (todo.length === 0) {
                if (game.has("ateRamen")) {
                    switch (game.roomID) {
                        case "ticketMachine":
                            return { key: "board", clues: [
                                "The gate at the far end is hungry — you'll want a ticket.",
                                "BUY TICKET, then step IN to board the 05:12.",
                            ] };
                        case "trainCar":
                            return { key: "ride", clues: [
                                "One stop to the transfer — don't get comfortable.",
                                "Go FORWARD (off the train) when it slides into the transfer.",
                            ] };
                        case "transferStation":
                            return { key: "change", clues: [
                                "Your home line leaves from Platform 2.",
                                "Go DOWN to Platform 2 — the train waiting at THIS platform runs the wrong way.",
                            ] };
                        case "wrongTerminus":
                            return { key: "wrong", clues: [
                                "Everyone does this exactly once.",
                                "Ride BACK to the transfer, then DOWN to your home line.",
                            ] };
                        case "homeStation":
                        case "fareAdjust":
                            return (game.isCarryingKind("ticket") || game.has("fareSettled"))
                                ? { key: "tapout", clues: [
                                    "You're one gate from a hot shower.",
                                    "Go OUT through the gate — you're home.",
                                ] }
                                : { key: "fare", clues: [
                                    "No ticket — and the gate knows.",
                                    "Go IN to the fare-adjustment machines, PUSH the MACHINE to settle up, then back OUT through the gate.",
                                ] };
                        default:
                            return { key: "train", clues: [
                                "One thing left — the 05:12 first train home.",
                                "GO TO STATION (DOWN from Roppongi Crossing), BUY a TICKET at the gates INSIDE, then board the train IN.",
                            ] };
                    }
                }
                return { key: "ramen", clues: [
                    "The crawl is done — and every good Tokyo night ends the same way.",
                    "Follow the red lantern: the ramen stand is SOUTH off the side street.",
                ] };
            }
            return { key: "todo:" + todo.join("|"), clues: [
                `Still on the crawl: ${todo.join(", ")}. (Kenji's napkin has the plan.)`,
                "Geronimo's is UP the stairs right at the crossing. The side street EAST of the crossing leads to Mogambo's (NORTH) and Bar Quest (EAST), with the ramen stand SOUTH.",
                "At Geronimo's: RING BELL (15 coins — a round for the house, ringer's choice). At Mogambo's: BUY MARGARITA, then GIVE MARGARITA TO ROY. At Quest: THROW DARTS.",
            ] };
        },
    };
}

// Mount Fuji: a night climb of the Yoshida Trail from the Fuji Subaru Line
// Fifth Station to the summit. Gear up at the fifth-station shop — the
// traditional kongō-zue walking stick and a headlamp — then climb station by
// station, earning each hut's brand burned into the stick. The weather is
// rolled fresh each game at the sixth station: on a rain or cold-wind night
// the stretch above the Eighth is impassable without a storm jacket or a paid
// rest by the hut stove. Reach the goraiko sunrise at the summit torii, earn
// the summit brand at Kusushi Shrine, linger over the crater rim and
// Ken-ga-mine — then win by mailing the letter home to Mom from the highest
// post office in Japan, at the tenth station.
function fujiScenario() {
    return {
        id: "fuji",
        title: "Climb Mount Fuji",
        destination: "Japan",
        blurb: "A night climb of the Yoshida Trail from the Fifth Station: earn every hut's brand on a kongō-zue walking stick, weather whatever the mountain throws at you, greet the goraiko sunrise, and seal the climb by mailing a letter home to Mom from the very top of Japan.",
        banner: [
            "MOUNT FUJI",
            "A night climb of the Yoshida Trail. (c) 2026",
            "Type HELP for commands. Gear up at the lodge, then climb UP, stage by stage.",
            "─────────────────────────────",
        ].join("\n"),
        startRoomID: "fifthStation",
        maxScore: 60,
        startingCoins: 50,
        build: buildFujiWorld,
        portalGate(game, direction) {
            if (game.roomID !== "eighthHut" || (direction !== "north" && direction !== "up")) return null;
            if (!game.inventoryKinds().has("headlamp")) {
                return "The hut keeper steps into the trail, kind but immovable. \"Nobody goes above the Eighth at night without a light. The lodge shop sells HEADLAMPS — GO TO LODGE and gear up; the mountain will wait.\"";
            }
            // Weather rolled at the sixth station: rain or bitter wind closes
            // the exposed final stretch until the climber shelters with the
            // keeper or carries a storm jacket.
            const sheltered = game.has("weatherReady") || game.inventoryKinds().has("jacket");
            if (game.has("weatherRain") && !sheltered) {
                return "Above the Eighth the squall owns the trail — rain flying sideways, headlamps turning back. The keeper shakes his head: \"Not into that without a shell. TALK to me and wait it out warm — or a STORM JACKET from the fifth station would see you through.\"";
            }
            if (game.has("weatherCold") && !sheltered) {
                return "The north wind comes over the ridge like a wall — stinging cold, climbers hunching back into the hut. The keeper catches your sleeve: \"Not into that unprotected. TALK to me and warm up first — or a STORM JACKET would cut it.\"";
            }
            return null;
        },
        exitHidden(game, direction) {
            // The mountain speaks in UP and DOWN. North/south still work
            // (FORWARD, NEXT STAGE) but shadow the canonical climb exits,
            // so they stay out of the listings.
            return direction === "north" || direction === "south";
        },
        fixtureLine(game, id) {
            const item = game.item(id);
            if (!item) return null;
            if (item.forSale) {
                const name = item.name.charAt(0).toUpperCase() + item.name.slice(1);
                return `${name} is for sale here — ${item.price} coins.`;
            }
            switch (id) {
                case "keeper7":
                    return game.has("brand7")
                        ? "Tomoekan's keeper tends the branding iron in the fire, your stick's fresh brand still fragrant."
                        : "Tomoekan's keeper tends a branding iron glowing in the fire. (GIVE your STICK to the KEEPER for the hut's brand — 3 coins.)";
                case "keeper8":
                    return game.has("brand8")
                        ? "Taishikan's keeper nods at the twin brands on your stick with professional approval."
                        : "Taishikan's keeper stands ready at the fire with the hut's iron. (GIVE your STICK to the KEEPER for the brand — 3 coins.)";
                case "shopkeeper": return "The shopkeeper arranges walking sticks, headlamps, and storm jackets with equal ceremony.";
                case "guide":
                    return game.has("brand6")
                        ? "The mountain guide waves climbers through, your stick's trailhead brand already vouching for you."
                        : "A mountain guide checks climbers through beside a small brazier. (GIVE your STICK to the GUIDE for the trailhead brand — 3 coins.)";
                case "priest":
                    return "A shrine priest tends Kusushi Shrine's branding fire. (Once your stick carries every hut's mark, GIVE it to the PRIEST for the summit brand — 5 coins — and the climb is sealed.)";
                case "clerk": return "The postal clerk waits behind the little counter, stamps at the ready.";
                case "horses": return "Pack horses doze by the trailhead, unimpressed by the altitude.";
                default: return null;
            }
        },
        onGive(game, gift, recipient) {
            if (!["guide", "keeper7", "keeper8", "priest"].includes(recipient)) return false;
            if (!(game.item(gift) && game.item(gift).kind === "stick")) {
                game.emit("A smile, a wave of the hand — the branding iron is for walking sticks. (The fifth-station shop sells the traditional kongō-zue.)");
                return true;
            }
            // The summit brand at Kusushi Shrine crowns a finished stick.
            if (recipient === "priest") {
                const missing = [];
                if (!game.has("brand6")) missing.push("the trailhead brand (6th station)");
                if (!game.has("brand7")) missing.push("Tomoekan's brand (7th station)");
                if (!game.has("brand8")) missing.push("Taishikan's brand (8th station)");
                if (missing.length) {
                    game.emit(`The priest turns your stick gently, reading its marks, and shakes his head. "The summit brand crowns a finished stick. You are missing: ${missing.join(", ")}. The huts below will gladly mend that — the mountain is patient."`);
                    return true;
                }
                if (game.has("summitBrand")) {
                    game.emit("Your kongō-zue already carries the summit brand — there is no higher mark to give it.");
                    return true;
                }
                if (!game.spend(5)) {
                    game.emit(`The summit brand is 5 coins, and you have ${game.coins}. The priest bows — the shrine can wait, but it cannot haggle.`);
                    return true;
                }
                game.set("summitBrand");
                let note = "The priest draws the iron from the shrine's fire, and with a hiss the summit brand crowns your kongō-zue — the final mark above the three earned below. The stick tells the entire story now: fifth station to the sky.";
                if (game.has("weatherRain")) {
                    note += " It tells the rain, too — anyone who reads it will know the night the mountain tested you.";
                } else if (game.has("weatherCold")) {
                    note += " It remembers the wind, too — anyone who reads it will know the night the mountain tested you.";
                }
                note += " One thing remains, and the priest says it for you: \"Someone at home is waiting to hear. The post office is just inside the torii.\"";
                game.award(10, note);
                return true;
            }
            // The station brands on the way up.
            const hut = recipient === "guide"
                ? { flag: "brand6", name: "the trailhead",
                    note: "The guide grins, pulls the trailhead iron from the little brazier beside the safety center, and burns the first mark into your kongō-zue. \"There. Now the stick is honest.\" One brand down, the mountain to go." }
                : recipient === "keeper7"
                ? { flag: "brand7", name: "Tomoekan",
                    note: "The keeper takes your kongō-zue, lays the glowing iron against it, and Tomoekan's brand chars crisply into the wood — smoke, cedar, ceremony. He hands it back with both hands and a small bow." }
                : { flag: "brand8", name: "Taishikan",
                    note: "Taishikan's iron hisses against the wood beside the marks already earned — station by station, the stick is becoming a story. The keeper studies his work, nods once, and returns it like a sword being sheathed." };
            if (game.has(hut.flag)) {
                game.emit(`Your stick already carries ${hut.name}'s brand — one per station, that's the tradition.`);
                return true;
            }
            if (!game.spend(3)) {
                game.emit(`The brand is 3 coins, and you have ${game.coins}. The iron goes back in the fire apologetically.`);
                return true;
            }
            game.set(hut.flag);
            game.award(5, hut.note + ` (You have ${game.coins} coins left.)`);
            return true;
        },
        onPut(game, object, target) {
            // The finale: at the tenth station, the letter home to Mom goes
            // into the red postbox — and that wins the climb.
            if (target !== "postbox") return;
            if (!(game.item(object) && game.item(object).kind === "letter")) return;
            game.award(10, null);
            let closing = "The clerk cancels the stamp with a soft, official thump — MOUNT FUJI SUMMIT POST OFFICE — and the letter home to Mom begins its journey down the mountain in a mail sack, carrying the whole night inside it: the stations, the stove smoke, the sea of clouds catching fire at dawn.";
            const fullStick = game.has("brand6") && game.has("brand7")
                && game.has("brand8") && game.has("summitBrand");
            if (fullStick) {
                closing += " Beside you leans a kongō-zue burned with every brand from the trailhead to the sky — but Mom gets the news first. That's the rule, and it's a good one.";
            }
            if (game.has("weatherRain")) {
                closing += " Outside, the last of the rain is drying off the rocks, already turning into a better story.";
            } else if (game.has("weatherCold")) {
                closing += " Outside, the north wind has given up, which is more than it can say for you.";
            }
            game.win(closing);
        },
        onTalk(game, id) {
            switch (id) {
                case "shopkeeper":
                    game.emit("\"Climbing tonight?\" The shopkeeper sizes you up and taps the counter. \"Then you'll want the kongō-zue — the walking stick. Every station on the trail burns its brand into it, and the shrine at the summit burns the last; come down with a full stick and you'll never need to tell the story, it tells itself. A HEADLAMP too — it's dark above the Eighth. A STORM JACKET, if the mountain turns rough. And a POSTCARD-sized LETTER, if you know anyone at home waiting to hear from the top of Japan.\"");
                    return true;
                case "guide": {
                    let talk;
                    if (game.has("weatherRain")) {
                        talk = "\"Rain on the way,\" the guide says, sniffing the wind. \"You'll feel it above the Eighth — a STORM JACKET sheds it, or shelter at Taishikan until it passes. The huts have food and fire; use them.";
                    } else if (game.has("weatherCold")) {
                        talk = "\"North wind tonight,\" the guide says, zipping his collar to the chin. \"Bitter cold on the final stretch. A STORM JACKET blunts it, or warm up at Taishikan before the push. The huts have food and fire; use them.";
                    } else {
                        talk = "\"Clear and calm,\" the guide says, patting the air with both hands. \"The mountain is in a good mood — it isn't always. Slowly, slowly: climbed with the legs, summited with the lungs.";
                    }
                    talk += game.has("brand6")
                        ? " And sit a while at every stage — the views climb with you.\""
                        : " And GIVE me that STICK before you go up — the trailhead brand starts the collection.\"";
                    game.emit(talk);
                    return true;
                }
                case "clerk":
                    game.emit("\"Welcome to the top of Japan,\" the clerk says, entirely serious. \"Highest post office in the country, and the best mail we handle is the kind that goes home. PUT your LETTER IN the POSTBOX and we'll do the rest — the postmark says Mount Fuji, and mothers frame that sort of thing.\"");
                    return true;
                case "priest":
                    game.emit("\"You made the sunrise,\" the priest says, as if confirming a fact about the weather. \"When your stick carries every station's mark, GIVE it here and the shrine will burn the summit brand — the climb, sealed. But the top rewards lingering: the crater rim is EAST, and the post office is just INSIDE the torii. The mountain does not hurry, and neither should you.\"");
                    return true;
                case "keeper7":
                case "keeper8": {
                    // On a foul-weather night, Taishikan's keeper offers the
                    // shelter that reopens the trail above — and never leaves
                    // a broke climber out in it.
                    if (id === "keeper8" &&
                        (game.has("weatherRain") || game.has("weatherCold")) &&
                        !game.has("weatherReady")) {
                        game.set("weatherReady");
                        if (game.spend(4)) {
                            game.emit(game.has("weatherRain")
                                ? "The keeper pulls you in by the stove. Hot noodles, steam on the windows, rain drumming the roof like applause — and then, gradually, not. The squall rattles off down the valley and the stars come back out. (4 coins well spent — the trail above is yours.)"
                                : "The keeper sits you by the stove with hot cocoa until the feeling returns to your fingers. Outside, the wind drops from a howl to a mutter. \"Now,\" he says, \"now you're ready.\" (4 coins well spent — the trail above is yours.)");
                        } else {
                            game.emit("You turn out your pockets — not enough. The keeper waves it off and pulls you in anyway. \"Mountain code. Pay me on the way down.\" Noodles, stove, and by the time you're warm again, the weather has moved on. The trail above is yours.");
                        }
                        return true;
                    }
                    const flag = id === "keeper7" ? "brand7" : "brand8";
                    if (game.has(flag)) {
                        game.emit("\"Good brand, good climb,\" the keeper says, glancing at your stick. \"The summit is waiting — slowly, slowly. And the bench out front has the best view on the mountain, if you ask me. SIT a while.\"");
                    } else {
                        game.emit("\"Rest a moment,\" the keeper says, nodding at the fire where the branding iron glows. \"There's food at the counter and a bench with a view. And if you carry the kongō-zue, GIVE it here — every station burns its own mark, and this one is ours. Three coins, and it lasts a lifetime.\"");
                    }
                    return true;
                }
                default:
                    return false;
            }
        },
        onEnterRoom(game, roomID) {
            const award = (flag, points, note) => {
                if (game.has(flag)) return;
                game.set(flag);
                game.award(points, note);
            };
            switch (roomID) {
                case "sixthStation":
                    // The mountain rolls its weather once per game, announced
                    // by the guide at the safety center. The roll is stored in
                    // flags, so SAVE/RESTORE keeps the same night.
                    if (game.has("weatherRolled")) break;
                    game.set("weatherRolled");
                    switch (Math.floor(Math.random() * 3)) {
                        case 0:
                            game.set("weatherClear");
                            game.emit("At the safety center the guide reads the sky like a menu. \"Clear and calm tonight — the mountain is in a good mood. It isn't always. Go gently, and enjoy the view from every stage.\"");
                            break;
                        case 1:
                            game.set("weatherRain");
                            game.emit("The guide sniffs the wind and frowns. \"Smell that? Rain, coming up the valley. It'll catch the trail above the Eighth before you do. A STORM JACKET sheds it — or shelter at Taishikan until it blows through. The huts have food and fire; use them.\"");
                            break;
                        default:
                            game.set("weatherCold");
                            game.emit("The guide zips his collar to the chin. \"North wind tonight — bitter cold on the final stretch, the kind that argues. A STORM JACKET blunts it, or warm up at Taishikan before the push. The huts have food and fire; use them.\"");
                            break;
                    }
                    break;
                case "summit":
                    award("sawSummit", 15, "You haul yourself up the last worn steps, under the summit torii — and stop. The east is turning. Below you lies a sea of clouds to the edge of the world, and as you watch, the sun breaks over it — the goraiko, the honored arrival of light — spilling gold across the cloud tops while every climber on the rim raises their arms and shouts \"Banzai!\" three times into the dawn. You came up a mountain in the dark, and this is what was waiting.");
                    break;
                case "kengamine":
                    award("sawKengamine", 10, "One last rise — and there is nothing above you. Ken-ga-mine, 3,776 meters: the highest point of Mount Fuji, and of Japan, marked by a worn stone pillar every climber touches. The old weather-radar dome kept watch here for forty years; now it's just you, the thin bright air, and the entire country arranged politely below.");
                    break;
                default:
                    break;
            }
        },
        hintStage(game) {
            const kinds = game.inventoryKinds();
            if (!(kinds.has("stick") && kinds.has("headlamp"))) {
                return { key: "gear", clues: [
                    "A proper climb starts with proper gear — TALK to the SHOPKEEPER, and TAKE a trail MAP from the counter.",
                    "BUY the STICK and the HEADLAMP — and mind the forecast: a STORM JACKET and a LETTER home round out the kit. Then climb UP, stage by stage.",
                ] };
            }
            if (game.roomID === "ninthStation" && !game.canSee()) {
                return { key: "dark", clues: [
                    "It's pitch black on the upper trail.",
                    "TURN ON your HEADLAMP.",
                ] };
            }
            if (game.roomID === "eighthHut" &&
                (game.has("weatherRain") || game.has("weatherCold")) &&
                !game.has("weatherReady") && !kinds.has("jacket")) {
                return { key: "weather", clues: [
                    "The weather owns the trail above the Eighth tonight.",
                    "TALK to the KEEPER to shelter with hot food until it passes (4 coins) — or a STORM JACKET from the fifth station gets you through it.",
                ] };
            }
            const todo = [];
            if (!game.has("brand6")) todo.push("the trailhead brand (6th station — the GUIDE)");
            if (!game.has("brand7")) todo.push("Tomoekan's brand (7th station)");
            if (!game.has("brand8")) todo.push("Taishikan's brand (8th station)");
            if (todo.length) {
                return { key: "brands:" + todo.join("|"), clues: [
                    `Still to burn into your stick: ${todo.join(", ")}.`,
                    "At each station, GIVE STICK TO the brander — 3 coins a mark. The trail climbs UP (or NEXT STAGE), with food, benches, and views at every stage. GO TO LODGE any time you need the shop.",
                ] };
            }
            if (!game.has("sawSummit")) {
                return { key: "climb", clues: [
                    "Every station brand is burned — now it's just you and the mountain.",
                    "Keep climbing UP. Above the Eighth it gets dark — TURN ON your HEADLAMP — and the goraiko waits at the top.",
                ] };
            }
            if (!game.has("summitBrand")) {
                return { key: "seal", clues: [
                    "The shrine at the tenth station crowns a finished stick.",
                    "GIVE your STICK TO the PRIEST at Kusushi Shrine — 5 coins — for the summit brand.",
                ] };
            }
            if (!game.has("sawKengamine")) {
                return { key: "kengamine", clues: [
                    "The torii isn't quite the top — the true summit is across the crater.",
                    "Head EAST to the crater rim, then UP to Ken-ga-mine. (And SIT anywhere along the way — the views are the point.)",
                ] };
            }
            return { key: "mom", clues: [
                "One thing remains, and it isn't for you — someone at home is waiting to hear.",
                kinds.has("letter")
                    ? "The post office is just INSIDE the torii — PUT the LETTER IN the POSTBOX, and the climb is complete."
                    : "The post office INSIDE the torii sells letters — BUY one, then PUT the LETTER IN the POSTBOX, and the climb is complete.",
            ] };
        },
    };
}

const SCENARIOS = [houseScenario(), townScenario(), riverboatScenario(), fortPulaskiScenario(), roppongiScenario(), fujiScenario()];

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
    addItem({ id: "map", name: "park map", nouns: ["map", "brochure", "guide", "pamphlet"],
        description: "A folding park map of Fort Pulaski National Monument, free from the stack on the desk.",
        isTakeable: true,
        readText: "\"FORT PULASKI — PARK MAP\n  • The fort: INSIDE across the drawbridge. On the parade ground, the gun casemates are NORTH, the prison casemates WEST, Colonel Olmstead's quarters (the surrender room) SOUTH, and stairs lead UP to the cannons on the terreplein.\n  • Moat walk: SOUTH from the drawbridge, then EAST to the shell-scarred southeast angle.\n  • Battery Hambright & the North Pier: NORTH along the riverside path.\n  • Lighthouse Overlook Trail: EAST of the visitor center — FORWARD four stops to the observation deck.\nBenches throughout — SIT and stay awhile.\nLost? GO TO VISITOR CENTER walks you back from anywhere you've been.\"" });
    addItem({ id: "ranger", name: "Ranger Max", nouns: ["ranger", "max", "guide", "attendant"],
        description: "Ranger Max, a National Park Service ranger in a flat-brimmed hat, glad to share the fort's story.",
        isFixture: true, isCreature: true });
    addItem({ id: "exhibit", name: "history exhibit", nouns: ["exhibit", "display", "history", "panel", "panels"],
        description: "A wall of exhibit panels tracing the fort from its brick-by-brick construction to the day its walls were breached.",
        readText: "\"THE STORY OF FORT PULASKI\nNamed for Casimir Pulaski, the Polish-born 'father of the American cavalry,' who fell at the 1779 Siege of Savannah. Begun in 1829 and eighteen years in the building — a young Robert E. Lee helped survey its dikes. Its walls were thought impregnable until April 11–12, 1862, when Union rifled cannon on Tybee Island breached them in about thirty hours, ending the age of masonry forts.\"",
        isFixture: true });

    // Battery Hambright.
    addItem({ id: "battery", name: "Battery Hambright", nouns: ["battery", "hambright", "emplacement", "concrete"],
        description: "A squat, poured-concrete gun battery from around 1900, its gun wells empty and open to the sky. It is named for Lieutenant Horace G. Hambright, who graduated dead last in the West Point class of 1893 — the class \"Goat\" — and died young in 1896; the battery never received its guns and never fired a shot.",
        isFixture: true });
    addItem({ id: "marker", name: "historical marker", nouns: ["marker", "plaque", "tablet"],
        description: "A cast historical marker beside the battery.",
        readText: "\"BATTERY HORACE HAMBRIGHT — Built 1899–1900 to guard the mouth of the Savannah River, and named in 1904 for Lt. Horace G. Hambright, U.S.A. — last-ranked graduate (the 'Goat') of the West Point class of 1893, remembered fondly by his fellow officers. Poured over 30,000 bricks salvaged from the original fort construction village. Designed for two rapid-fire 3-inch guns on disappearing mounts; the guns were never installed.\"",
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

    // The fort — drawbridge and moat.
    addItem({ id: "fortwalls", name: "fort", nouns: ["fort", "pulaski", "walls"],
        description: "Fort Pulaski itself — a massive five-sided brick fortress ringed by a moat, its walls seven and a half feet thick. They were thought invincible until the rifled cannon on Tybee Island proved otherwise in 1862.", isFixture: true });
    addItem({ id: "drawbridgeItem", name: "drawbridge", nouns: ["drawbridge", "bridge"],
        description: "A stout wooden drawbridge on chains, spanning the moat to the fort's arched sally port.", isFixture: true });
    addItem({ id: "moat", name: "moat", nouns: ["moat", "water"],
        description: "The moat rings the fort, seven feet deep and fed by the tide. Dragonflies stitch the surface — and is that a small alligator gliding along the far bank? It is.", isFixture: true });

    // The vintage base ball match, in full swing on the parade ground.
    // WATCH PLAYERS is the main event.
    addItem({ id: "ballplayers", name: "ballplayers", nouns: ["players", "ballplayers", "player", "game", "match", "baseball", "ball", "reenactors", "soldiers"],
        description: "You watch an inning. The striker squares up, the pitcher lobs the lemon-peel ball underhand, and — CRACK — it sails over the shortscout's head. The runner tears around the sacks in his wool uniform while the fielders give chase bare-handed, and the whole garrison seems to cheer. Behind them, a fellow with a box camera on a tripod is fussing with his plates, recreating the famous photograph: the 48th New York at play on this parade ground in 1862 — one of the earliest photographs of baseball ever taken.",
        isFixture: true, isCreature: true,
        dialogue: "\"Straight out of the 1862 photograph!\" a player calls, tapping his bat. \"The Forty-Eighth New York played ball right here between drills — earliest picture of the game anyone knows of. Rules of the day: underhand pitching, no gloves, and a ball caught on one bounce is an out. Stay for an inning!\"" });

    // Wayfinding signs inside the fort.
    addItem({ id: "paradeSign", name: "signpost", nouns: ["signpost", "sign", "signs"],
        description: "A weathered wooden signpost with arms pointing every which way: gun casemates NORTH, prison casemates WEST, Colonel Olmstead's quarters SOUTH, the terreplein UP, and the sally port OUT.", isFixture: true });
    addItem({ id: "bridgeSign", name: "sign", nouns: ["sign", "signs", "signpost"],
        description: "A small park sign: parade ground IN across the drawbridge, moat walk SOUTH along the bank, visitor center back OUT.", isFixture: true });

    // Parade ground.
    addItem({ id: "flag", name: "garrison flag", nouns: ["flag", "colors", "flagpole"],
        description: "The garrison flag riding the sea breeze above the ramparts, just as it did over the 1862 siege.", isFixture: true });
    addItem({ id: "paradeBench", name: "wooden bench", nouns: ["bench", "benches", "seat"],
        description: "A simple wooden park bench in the shade at the edge of the parade ground.",
        readText: "You settle onto the bench at the edge of the parade ground. The flag snaps overhead, swallows loop between the casemate arches, and for a moment the fort is yours alone.",
        isFixture: true, kind: "seat" });

    // Colonel Olmstead's quarters — the surrender room.
    addItem({ id: "surrenderTable", name: "writing table", nouns: ["table", "desk"],
        description: "The plain writing table where, on April 11, 1862, Colonel Olmstead handed over his sword and signed away the fort.", isFixture: true });
    addItem({ id: "pictures", name: "framed pictures", nouns: ["pictures", "picture", "photos", "photographs", "frames"],
        description: "Framed period pictures of the surrender that took place in this room.",
        readText: "You study the framed pictures: Union officers crowd the small room, hats in hand, while Colonel Olmstead stands at the table, sword reversed, hilt offered. The caption reads: \"Surrender of Fort Pulaski — April 11, 1862, 2:30 p.m.\"",
        isFixture: true });

    // Olmstead's sword, displayed in the visitor center museum.
    addItem({ id: "sword", name: "Olmstead's sword", nouns: ["sword", "olmstead", "saber", "sabre"],
        description: "Colonel Charles Olmstead's own sword, resting in a museum case — the one he handed over when the fort fell in April 1862, and which General David Hunter sent back to him days later because the surrender had been honorable.", isFixture: true });

    // Gun casemates.
    addItem({ id: "casemateGun", name: "casemate cannon", nouns: ["cannon", "gun", "smoothbore"],
        description: "A big black smoothbore on its wooden carriage, aimed out through the embrasure at the river channel — exactly the kind of gun the rifled cannon across the water made obsolete.", isFixture: true });

    // Prison casemates.
    addItem({ id: "bunks", name: "wooden bunks", nouns: ["bunks", "bunk", "beds"],
        description: "Rows of rough wooden bunks, stacked close in the cold brick chamber where the Immortal 600 were held.", isFixture: true });
    addItem({ id: "graffiti", name: "carved names", nouns: ["graffiti", "names", "carvings"],
        description: "Names and dates scratched into the soft brick by prisoners' hands.",
        readText: "You lean close to the brick and pick out the shallow scratches: initials, a date — 1864 — and a name half-worn away. Men counting days.", isFixture: true });

    // Terreplein.
    addItem({ id: "cannons", name: "rampart cannons", nouns: ["cannon", "cannons", "gun", "guns"],
        description: "A rank of great black cannons along the terreplein's ramparts, muzzles trained over the river channel they once commanded.", isFixture: true });
    addItem({ id: "terrepleinBench", name: "bench", nouns: ["bench", "benches", "seat"],
        description: "A bench set between two cannons, facing out over the river.",
        readText: "You sit between the cannons with the wind off the Atlantic in your face, watching a container ship the size of a city block glide past the little lighthouse below. Hard to beat this seat anywhere in Georgia.",
        isFixture: true, kind: "seat" });

    // Moat walk and the battered southeast angle.
    addItem({ id: "moatBench", name: "bench", nouns: ["bench", "benches", "seat"],
        description: "A bench on the grassy bank, facing the fort across the moat.",
        readText: "You take the bench by the moat. The brick walls rise mirror-doubled in the still water, a heron stalks the reeds, and the dragonflies mind their own business.",
        isFixture: true, kind: "seat" });
    addItem({ id: "shells", name: "embedded shells", nouns: ["shell", "shells", "shot", "iron"],
        description: "Union shot and shell from 1862, still lodged in the brickwork where they struck — round dimples from smoothbores, deep gouges from the rifled guns.", isFixture: true });
    addItem({ id: "breach", name: "repaired breach", nouns: ["breach", "wall", "scars", "brick", "patch"],
        description: "The patch of smoother, darker brick marks where the wall was shot through in April 1862 and rebuilt afterward. Around it the original face is cratered like the moon.", isFixture: true });

    const rooms = {};
    const addRoom = (p) => { const r = makeRoom(p); rooms[r.id] = r; };

    addRoom({ id: "gate", title: "Fort Pulaski Gates",
        description: "You drive in through the park gates and along the causeway across the marsh onto Cockspur Island. Ahead, the brick ramparts of Fort Pulaski rise behind their moat. The visitor center is just NORTH.",
        exits: { north: "visitorCenter" }, items: ["gates", "entrancesign"] });
    addRoom({ id: "visitorCenter", title: "Visitor Center",
        description: "The Fort Pulaski visitor center: a cool room of exhibits and a bookstore, where Ranger Max waits at the desk to check you in. The fort's drawbridge is just INSIDE. A walking path leads NORTH toward the river, past Battery Hambright to the North Pier; the Lighthouse Overlook trailhead is EAST; and your car is parked back SOUTH.",
        exits: { south: "gate", inside: "drawbridge", north: "batteryHambright", east: "trail1" }, items: ["ranger", "exhibit", "map", "sword"] });

    // The fort — cross the moat, explore inside and up top, and circle the
    // walls outside to see what the 1862 cannon fire left behind.
    addRoom({ id: "drawbridge", title: "The Drawbridge",
        description: "A wooden drawbridge crosses the tidal moat to the fort's arched sally port, brick walls rising sheer from the water. Go INSIDE to the parade ground, follow the grassy bank SOUTH along the moat, or head back OUTSIDE to the visitor center.",
        exits: { outside: "visitorCenter", inside: "fort", south: "moatWalk" }, items: ["fortwalls", "drawbridgeItem", "moat", "bridgeSign"] });
    addRoom({ id: "fort", title: "Parade Ground",
        description: "The broad green parade ground inside Fort Pulaski, ringed by brick casemate arches, with the garrison flag overhead. The gun casemates are NORTH, the prison casemates WEST, Colonel Olmstead's quarters SOUTH, and a stone stair climbs UP to the terreplein and its cannons. A wooden bench sits in the shade — SIT a while if you like. The sally port leads back OUTSIDE.",
        exits: { outside: "drawbridge", north: "casemates", west: "prison", south: "quarters", up: "terreplein" }, items: ["flag", "paradeBench", "paradeSign", "ballplayers"] });
    addRoom({ id: "quarters", title: "Colonel Olmstead's Quarters",
        description: "The colonel's quarters off the parade ground, kept as they were in 1862 — a narrow bed, a plain writing table, and framed pictures on the wall of the surrender that happened in this very room (READ the PICTURES). The parade ground is back NORTH.",
        exits: { north: "fort" }, items: ["surrenderTable", "pictures"] });
    addRoom({ id: "casemates", title: "Gun Casemates",
        description: "A long gallery of arched brick casemates, cool and echoing, each with a great black cannon aimed out through its embrasure at the river channel. The parade ground is back SOUTH.",
        exits: { south: "fort" }, items: ["casemateGun"] });
    addRoom({ id: "prison", title: "Prison Casemates",
        description: "Dim casemates fitted with rows of rough wooden bunks — the prison of the Immortal 600. Names are scratched into the brick (READ them if you dare the chill). The parade ground is back EAST.",
        exits: { east: "fort" }, items: ["bunks", "graffiti"] });
    addRoom({ id: "terreplein", title: "The Terreplein",
        description: "The fort's open upper level, high above the parade ground, cannons ranked along the ramparts. The whole mouth of the Savannah River spreads below — ships in the channel, the Cockspur Lighthouse on its bar, Tybee Island on the horizon. A bench faces the water between two guns. The stair leads back DOWN.",
        exits: { down: "fort" }, items: ["cannons", "terrepleinBench", "lighthouse", "containership"] });
    addRoom({ id: "moatWalk", title: "Along the Moat",
        description: "A grassy bank between the moat and the marsh, the fort's brick walls doubled in the still water. A bench faces the reflection. The path curls EAST around the walls toward the southeast angle; the drawbridge is back NORTH.",
        exits: { north: "drawbridge", east: "scarredWall" }, items: ["moatBench", "moat"] });
    addRoom({ id: "scarredWall", title: "The Battered Southeast Angle",
        description: "The fort's southeast corner, the face that took the Union bombardment of 1862. The brick is pocked and cratered with shell strikes, iron shot still lodged in the wall, and a broad patch of darker brick marks the repaired breach. Across the water lies Tybee Island, where the batteries fired from. The moat walk leads back WEST.",
        exits: { west: "moatWalk" }, items: ["shells", "breach"] });
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

function buildRoppongiWorld() {
    const items = {};
    const addItem = (p) => { const it = makeItem(p); items[it.id] = it; };

    // The station, and Kenji's marching orders.
    addItem({ id: "napkin", name: "bar napkin", nouns: ["napkin", "note", "plan", "list"],
        description: "A bar napkin covered in Kenji's confident scrawl — tonight's marching orders.",
        isTakeable: true,
        readText: "\"THE CLASSIC ROPPONGI CRAWL — do it right:\n  1. GERONIMO'S — up the stairs at the crossing. Ring the bell. Yes, really.\n  2. MOGAMBO'S — tiny place off the side street. Buy Roy a frozen margarita and tell him it's from me.\n  3. BAR QUEST — down the side street. Throw darts with the league.\n  Finish: ramen under the red lantern, SOUTH off the side street.\nText me when you're home. — Kenji\"" });
    addItem({ id: "roppongiMap", name: "Roppongi map", nouns: ["map", "guide", "pamphlet"],
        description: "A free fold-out night map of Roppongi from the rack by the ticket gates, creased along well-worn lines.",
        isTakeable: true,
        readText: "\"ROPPONGI NIGHT MAP\n  • Roppongi Crossing: UP the escalator from the station — Almond's pink awning marks the corner.\n  • Geronimo Shot Bar: UP the narrow stairs right at the crossing, second floor.\n  • The side street: EAST of the crossing. Mogambo's is NORTH, Bar Quest is EAST.\n  • Ramen stand: SOUTH off the side street — follow the red lantern.\nLost? GO TO <place> walks you back from anywhere you've been.\"" });
    addItem({ id: "stationSign", name: "station sign", nouns: ["sign", "board"],
        description: "The backlit station sign, gray and steady amid the rush.",
        readText: "\"ROPPONGI — Hibiya Line. Exit 3: Roppongi Crossing / Gaien-Higashi-dori. Last train 00:24. First train 05:12.\" You intend to see both.",
        isFixture: true });
    addItem({ id: "vendingMachine", name: "vending machine", nouns: ["vending", "machine"],
        description: "A vending machine glowing like a small shrine, offering hot corn soup, cold coffee, and eleven kinds of tea. Tokyo in one appliance.", isFixture: true });
    addItem({ id: "salarymen", name: "salarymen", nouns: ["salarymen", "salaryman", "crowd", "commuters"],
        description: "A knot of cheerful salarymen fresh from an office party, one necktie already promoted to headband.",
        isFixture: true, isCreature: true,
        dialogue: "\"Konbanwa!\" the salarymen chorus, bowing in ragged unison. The one with the necktie around his head gives you a double thumbs-up: \"Roppongi! Best night! Ganbatte!\"" });

    // Roppongi Crossing.
    addItem({ id: "almond", name: "Almond café", nouns: ["almond", "cafe", "awning"],
        description: "Almond — the coffee shop with the famous pink awning that has anchored Roppongi Crossing since 1964. Half the meetups in Tokyo begin with the words \"in front of Almond.\"", isFixture: true });
    addItem({ id: "expressway", name: "Shuto Expressway", nouns: ["expressway", "overpass", "highway"],
        description: "The Shuto Expressway runs directly over the crossing on massive green legs, traffic drumming overhead like weather.", isFixture: true });
    addItem({ id: "tout", name: "tout", nouns: ["tout", "hawker", "barker"],
        description: "A fast-talking tout in a shiny jacket, scanning the crowd for the undecided.",
        isFixture: true, isCreature: true,
        dialogue: "\"My friend! Best bars, best prices!\" The tout drops the pitch the moment he sees your napkin. \"Ah — the classic crawl. Respect. Geronimo's is UP right here at the crossing; the side street EAST has the rest. And skip anywhere with a menu in four currencies.\"" });

    // Geronimo Shot Bar.
    addItem({ id: "bellGeronimos", name: "bell", nouns: ["bell"],
        description: "A polished ship's bell on a short rope, hung dead center over the bar. The hand-lettered card beneath reads: RING FOR GLORY — ROUND FOR THE HOUSE, RINGER'S CHOICE, 15 COINS.", isFixture: true });
    addItem({ id: "plaques", name: "brass plaques", nouns: ["plaques", "plaque", "brass", "wall", "names"],
        description: "Hundreds of brass plaques, floor to ceiling — the honor roll of Geronimo's regulars from every corner of the earth.",
        readText: "You scan the plaques: a bush pilot from Anchorage, an entire rugby team from Auckland, a violinist from Vienna. The newest one is still shiny; the oldest is worn smooth by thirty years of thumbs. There's space left on the wall.",
        isFixture: true });
    addItem({ id: "shot", name: "tequila shot", nouns: ["shot", "tequila", "shots"],
        description: "The house tequila shot, poured generous.",
        isTakeable: true, isFixture: true, forSale: true, price: 8, kind: "shot" });
    addItem({ id: "ryan", name: "Ryan", nouns: ["ryan", "bartender", "barkeep"],
        description: "Ryan, Geronimo's bartender — fast hands, faster grin, and total command of the room.",
        isFixture: true, isCreature: true,
        dialogue: "\"Welcome to Geronimo's!\" Ryan calls over the noise, not missing a pour. \"Rules are on the wall and the bell speaks for itself. RING it and everyone in here is your friend for life — or at least until closing.\"" });

    // Mogambo's.
    addItem({ id: "bellMogambos", name: "bell", nouns: ["bell"],
        description: "A little brass bell over Mogambo's counter, polished by years of celebrations. Same rule as everywhere: ring it, and the round's on you — ringer's choice.", isFixture: true });
    addItem({ id: "margarita", name: "frozen margarita", nouns: ["margarita", "marg", "cocktail"],
        description: "Martin's frozen margarita — Mogambo's pride, blended to a snowdrift and salted like the Gulf of Mexico.",
        isTakeable: true, isFixture: true, forSale: true, price: 9, kind: "margarita" });
    addItem({ id: "martin", name: "Martin", nouns: ["martin", "bartender", "master"],
        description: "Martin, Mogambo's bartender and mayor of its eight stools, who remembers every name he's ever been told.",
        isFixture: true, isCreature: true,
        dialogue: "\"First time? Then it isn't,\" Martin says warmly, wiping the counter. \"This is Mogambo's — everyone's local. The margarita is frozen, famous, and nine coins. And if you're feeling generous—\" he tilts his head toward the end of the bar, \"—somebody down there needs one more than you do.\"" });
    addItem({ id: "roy", name: "Roy", nouns: ["roy", "texan", "regular"],
        description: "Roy: big, sunburned, pearl-snap shirt, and about as far from Galveston, Texas as a man can get. His glass has been empty a while.",
        isFixture: true, isCreature: true });

    // Bar Quest.
    addItem({ id: "bellQuest", name: "bell", nouns: ["bell"],
        description: "A ship's bell over the taps, its rope frayed by celebration. The plaque reads: RING FOR GLORY — ROUND FOR THE HOUSE, RINGER'S CHOICE.", isFixture: true });
    addItem({ id: "pint", name: "pint of lager", nouns: ["pint", "beer", "lager", "ale"],
        description: "A proper pint of lager, pulled slow, with an inch of head.",
        isTakeable: true, isFixture: true, forSale: true, price: 7, kind: "pint" });
    addItem({ id: "matt", name: "Matt", nouns: ["matt", "bartender", "barman"],
        description: "Matt, Bar Quest's bartender — unflappable, generous with coasters, and the final word in all darts disputes.",
        isFixture: true, isCreature: true,
        dialogue: "\"Evenin',\" says Matt, setting a coaster in front of you out of pure reflex. \"Pint's seven coins, darts are free, and the league—\" he nods at the corner \"—is always short a player. THROW some DARTS if you fancy your chances.\"" });
    addItem({ id: "dartboard", name: "dartboard", nouns: ["darts", "dart", "dartboard", "board"],
        description: "A bristle dartboard that has absorbed a decade of expat ambition. The chalk scoreboard beside it reads like a UN roll call.", isFixture: true });
    addItem({ id: "jukebox", name: "jukebox", nouns: ["jukebox", "music"],
        description: "A jukebox loaded with three decades of singalongs. Somebody has queued 'Country Roads' again. Somebody always has.", isFixture: true });

    // The side street.
    addItem({ id: "tower", name: "Tokyo Tower", nouns: ["tower", "tokyo"],
        description: "Tokyo Tower, orange and white and lit like a carnival, rises over the low rooftops at the end of the street — close enough to feel like scenery hung there just for you.", isFixture: true });

    // The ride home: ticket machines at the gates, the fare-adjustment
    // machine at the far end for anyone who arrives ticketless.
    addItem({ id: "ticketMachines", name: "ticket machines", nouns: ["machine", "machines", "kensyoki", "vending"],
        description: "A row of blue ticket machines under a big fare map. BUY a TICKET to your home station — you will need it to get out at the far end.",
        isFixture: true });
    addItem({ id: "ticket", name: "train ticket", nouns: ["ticket", "kippu", "fare"],
        description: "A little magnetic-stripe ticket home. Hang onto it — the gate eats it on the way out, and no ticket means a trip to the fare-adjustment machine.",
        isTakeable: true, isFixture: true, forSale: true, price: 3, kind: "ticket" });
    addItem({ id: "fareMachine", name: "fare adjustment machine", nouns: ["machine", "farebox", "seisan", "adjustment"],
        description: "The orange 精算 fare-adjustment machine beside the gate. PUSH it to settle up and the gate will open.",
        isFixture: true });

    // The ramen stand.
    addItem({ id: "cook", name: "ramen cook", nouns: ["cook", "chef", "master", "ojisan"],
        description: "The ramen cook, towel knotted around his head, working his pots with the calm of a man who has seen every kind of 4 a.m.",
        isFixture: true, isCreature: true });
    addItem({ id: "stool", name: "counter stool", nouns: ["stool", "seat"],
        description: "A worn wooden stool at the ramen counter, shaped by ten thousand late nights.",
        readText: "You settle onto the stool. Steam rises, the cook works in unhurried silence, and Roppongi's last stragglers drift past the curtain. The best seat in Tokyo at this hour.",
        isFixture: true, kind: "seat" });
    addItem({ id: "noren", name: "noren curtain", nouns: ["noren", "curtain", "banner"],
        description: "The short noren curtain across the stall's front, dyed deep red and breathing steam — the single kanji on it promises RAMEN, and it does not lie.", isFixture: true });

    const rooms = {};
    const addRoom = (p) => { const r = makeRoom(p); rooms[r.id] = r; };

    addRoom({ id: "roppongiStation", title: "Roppongi Station",
        description: "The Hibiya Line platform at Roppongi, deep enough underground that the escalator ride feels like a pilgrimage. Kenji couldn't come tonight, but his marching orders — scrawled on a bar napkin — lie folded on the bench beside you (TAKE it, READ it), and a rack by the ticket gates offers free Roppongi maps. The escalator leads UP to the crossing.",
        exits: { up: "crossing", inside: "ticketMachine" }, items: ["napkin", "roppongiMap", "stationSign", "vendingMachine", "salarymen"] });
    addRoom({ id: "crossing", title: "Roppongi Crossing",
        description: "The heart of Roppongi at full night volume: the Shuto Expressway roaring overhead, Almond's pink awning glowing on the corner, taxis, touts, and ten thousand watts of stacked neon. A narrow stairway climbs UP to Geronimo Shot Bar; the side street EAST leads deeper into bar country; the station is back DOWN.",
        exits: { down: "roppongiStation", up: "geronimos", east: "sideStreet" }, items: ["almond", "expressway", "tout"] });
    addRoom({ id: "geronimos", title: "Geronimo Shot Bar",
        description: "Geronimo's, second floor: a shot bar the size of a train car with the volume of a stadium. Brass plaques plate the walls (READ them), Ryan holds court behind the bar, and the famous bell hangs over everything. The stairs lead back DOWN to the crossing.",
        exits: { down: "crossing" }, items: ["bellGeronimos", "plaques", "ryan", "shot"] });
    addRoom({ id: "sideStreet", title: "The Side Street",
        description: "A narrow street of stacked bar signs — six glowing floors of them on every building, each promising a different tiny world. Tokyo Tower burns orange at the end of the block like a lucky charm. Mogambo's doorway is NORTH; Bar Quest's brass-lettered door is EAST; a red lantern and the smell of broth wait SOUTH; the crossing is back WEST.",
        exits: { west: "crossing", north: "mogambos", east: "quest", south: "ramenya" }, items: ["tower"] });
    addRoom({ id: "mogambos", title: "Mogambo's",
        description: "Inside Mogambo's: eight stools, one Martin, and a thousand stories. The blender sits ready for margarita duty, a little bell hangs over the counter, and Roy holds down the end stool. The side street is back SOUTH.",
        exits: { south: "sideStreet" }, items: ["bellMogambos", "martin", "roy", "margarita"] });
    addRoom({ id: "quest", title: "Bar Quest",
        description: "Bar Quest, open until the first train and honest about it: long oak counter, taps polished bright, a bell over the bar, a jukebox mid-singalong, and the darts corner where the expat league holds court. Matt keeps the pints coming. The side street is back WEST.",
        exits: { west: "sideStreet" }, items: ["bellQuest", "matt", "pint", "dartboard", "jukebox"] });
    addRoom({ id: "ramenya", title: "The Ramen Stand",
        description: "A tiny late-night ramen stand under a glowing red lantern, steam rolling out beneath the noren curtain. A worn counter stool waits (SIT, if the night has caught up with you) while the cook tends his pots. The side street is back NORTH.",
        exits: { north: "sideStreet" }, items: ["cook", "stool", "noren"] });

    // The ride home — the last leg of any proper Tokyo all-nighter.
    addRoom({ id: "ticketMachine", title: "The Ticket Gates",
        description: "The ticket gates at Roppongi, quiet at dawn. A row of blue TICKET MACHINES glows under a big fare map. BUY a TICKET here, then step IN to the platform and board the first train. The station hall is back OUT.",
        exits: { outside: "roppongiStation", inside: "trainCar" },
        items: ["ticketMachines", "ticket"] });
    addRoom({ id: "trainCar", title: "The First Train",
        description: "Inside the 05:12 Hibiya Line car: warm, half-empty, a few nodding heads and a route map glowing over the doors. It is just ONE STOP to your transfer — get OFF (go FORWARD) when it slides in.",
        exits: { north: "transferStation", outside: "transferStation" }, items: [] });
    addRoom({ id: "transferStation", title: "The Transfer",
        description: "A cavernous transfer station, one stop from Roppongi. Your home line is DOWN the stairs to Platform 2 — three stops and you are home. The train still waiting at THIS platform runs the other way, out to the end of the line; do NOT stay aboard it. (Go DOWN for home.)",
        exits: { down: "homeStation", north: "wrongTerminus" }, items: [] });
    addRoom({ id: "wrongTerminus", title: "The End of the Line",
        description: "You stayed on the wrong train and rode it all the way to a sleepy terminus somewhere out in the suburbs, hours from home, the platform empty and the sun already up. Nothing for it but to ride all the way BACK to the transfer.",
        exits: { south: "transferStation", outside: "transferStation" }, items: [] });
    addRoom({ id: "homeStation", title: "Your Station",
        description: "Your own little station at last, the morning gone pink over the rooftops. The exit gates stand between you and a hot shower — TAP OUT (go OUT) with your ticket. No ticket? The 精算 fare-adjustment machine is just IN from the gate.",
        exits: { outside: "homeStation", inside: "fareAdjust" }, items: [] });
    addRoom({ id: "fareAdjust", title: "Fare Adjustment",
        description: "The little bank of fare-adjustment machines beside the blocked gate. No ticket, no exit — but the orange 精算 machine will sort you out. PUSH it to settle the fare, then step back OUT to the gate.",
        exits: { outside: "homeStation" }, items: ["fareMachine"] });

    return { rooms, items };
}

function buildFujiWorld() {
    const items = {};
    const addItem = (p) => { const it = makeItem(p); items[it.id] = it; };

    // The fifth-station lodge and trailhead.
    addItem({ id: "trailMap", name: "trail map", nouns: ["map", "guide", "pamphlet"],
        description: "A free folding map of the Yoshida Trail from the lodge counter, the stages numbered like chapters.",
        isTakeable: true,
        readText: "\"MOUNT FUJI — YOSHIDA TRAIL MAP\n  • UP (or NEXT STAGE) climbs the trail: the safety center (6th), Tomoekan (7th), Taishikan (8th), the dark final stretch (9th), and the summit torii — the tenth station.\n  • Every stage has food, a bench with a view, and a brand for your walking stick.\n  • At the top: Kusushi Shrine and the summit brand, the post office just INSIDE (mail home!), and the crater rim EAST to Ken-ga-mine.\n  • DOWN retraces the trail, and GO TO LODGE walks you back here from anywhere you've been.\nWeather turns fast above the Eighth — carry a jacket, or shelter at the huts.\"" });
    addItem({ id: "stick", name: "kongō-zue walking stick", nouns: ["stick", "kongo", "zue", "staff"],
        description: "A fresh octagonal wooden kongō-zue, the pilgrim's walking stick — smooth, pale, and waiting for its first hut brand.",
        isTakeable: true, isFixture: true, forSale: true, price: 12, kind: "stick" });
    addItem({ id: "headlamp", name: "headlamp", nouns: ["headlamp", "lamp", "light", "lantern", "torch"],
        description: "A sturdy LED headlamp on an elastic band — the difference between climbing the upper trail and guessing at it.",
        isTakeable: true, isLightSource: true, isFixture: true, forSale: true, price: 8, kind: "headlamp" });
    addItem({ id: "letter", name: "letter home", nouns: ["letter", "envelope", "mail", "card", "postcard"],
        description: "A sheet of good paper and an envelope already addressed home to Mom, waiting for the story of a lifetime.",
        isTakeable: true,
        readText: "\"Dear Mom — You will not believe where I am when I finish this letter. Save this envelope: the postmark is going to do the bragging for me. More from the top. — with love\"",
        isFixture: true, forSale: true, price: 3, kind: "letter" });
    addItem({ id: "jacket", name: "storm jacket", nouns: ["jacket", "raincoat", "shell", "coat"],
        description: "A serious storm jacket, sealed seams and a deep hood — proof against rain, wind, and second thoughts.",
        isTakeable: true, isFixture: true, forSale: true, price: 6, kind: "jacket" });
    addItem({ id: "oxygen", name: "canned oxygen", nouns: ["oxygen", "can", "air"],
        description: "A slim can of oxygen for the thin air up top. Mostly it's for morale, and morale counts.",
        isTakeable: true, isFixture: true, forSale: true, price: 4, kind: "oxygen" });
    addItem({ id: "shopkeeper", name: "shopkeeper", nouns: ["shopkeeper", "keeper", "vendor"],
        description: "The fifth-station shopkeeper, who has outfitted forty years of climbers and can judge your summit odds at a glance.",
        isFixture: true, isCreature: true });
    addItem({ id: "komitake", name: "Komitake Shrine", nouns: ["shrine", "komitake"],
        description: "Komitake Shrine, older than the trail itself, where climbers clap twice and ask the mountain's permission. It never hurts.", isFixture: true });
    addItem({ id: "horses", name: "pack horses", nouns: ["horses", "horse", "ponies"],
        description: "Sturdy pack horses that carry footsore visitors along the flat stretch — none of them has ever been to the summit, and none of them minds.",
        isFixture: true, isCreature: true,
        dialogue: "The nearest horse regards you with enormous, patient eyes, decides you are not carrying apples, and returns to its doze." });

    // Sixth station.
    addItem({ id: "safetyCenter", name: "safety center", nouns: ["safety", "center", "bulletin"],
        description: "The sixth-station safety center, its bulletin board layered with weather reports and trail notices.",
        readText: "\"YOSHIDA TRAIL — TONIGHT: skies clear, wind light, sunrise 04:32. Climb slowly. Rest at the huts. Lights required above the Eighth Station. The mountain decides; the climber agrees.\"",
        isFixture: true });
    addItem({ id: "guide", name: "mountain guide", nouns: ["guide", "ranger"],
        description: "A mountain guide with a face like weathered cedar and the calm of a person the mountain has never once surprised. A small brazier beside him keeps the trailhead branding iron hot.",
        isFixture: true, isCreature: true });
    addItem({ id: "onigiri", name: "onigiri", nouns: ["onigiri", "riceball", "rice", "food"],
        description: "Fat rice balls wrapped in crisp nori, stacked in a warmer by the safety center — trail fuel of champions.",
        isTakeable: true, isFixture: true, forSale: true, price: 3, kind: "food" });
    addItem({ id: "bench6", name: "trailside bench", nouns: ["bench", "seat"],
        description: "A rough bench at the sixth station, facing back down the mountain.",
        readText: "You sit at the sixth station as the last light drains from the valley: the Fuji Five Lakes going pewter, then black, and the first stars snapping on above the trail. Below, the bright huddle of the fifth station; above, a ribbon of headlamps climbing into the dark.",
        isFixture: true, kind: "seat" });

    // Seventh station — Tomoekan.
    addItem({ id: "keeper7", name: "hut keeper", nouns: ["keeper", "keeper7", "hutkeeper"],
        description: "Tomoekan's keeper, quick with tea and quicker with the branding iron.",
        isFixture: true, isCreature: true });
    addItem({ id: "brazier7", name: "brazier", nouns: ["brazier", "fire", "iron"],
        description: "A charcoal brazier with Tomoekan's branding iron resting in the coals, its tip glowing the color of the coming sunrise.", isFixture: true });
    addItem({ id: "bench7", name: "hut bench", nouns: ["bench", "seat"],
        description: "A plank bench along Tomoekan's front wall, facing back down the mountain.",
        readText: "You sit on Tomoekan's bench with the whole night below you: the Fuji Five Lakes catching starlight, the towns strung out like dropped necklaces, and a slow-moving chain of headlamps winding up the trail beneath your boots.",
        isFixture: true, kind: "seat" });
    addItem({ id: "noodles", name: "hot noodles", nouns: ["noodles", "ramen", "udon", "soup"],
        description: "A steaming bowl of udon from Tomoekan's tiny kitchen, broth fogging your glasses on contact.",
        isTakeable: true, isFixture: true, forSale: true, price: 4, kind: "food" });

    // Eighth station — Taishikan.
    addItem({ id: "keeper8", name: "hut keeper", nouns: ["keeper", "keeper8", "hutkeeper"],
        description: "Taishikan's keeper, who has watched ten thousand headlamps go up and come back down, and remembers the ones that smiled.",
        isFixture: true, isCreature: true });
    addItem({ id: "cocoa", name: "hot cocoa", nouns: ["cocoa", "chocolate", "drink"],
        description: "A steaming cup of hot cocoa, priced for altitude and worth double.",
        isTakeable: true, isFixture: true, forSale: true, price: 3, kind: "cocoa" });
    addItem({ id: "bunks", name: "sleeping bunks", nouns: ["bunks", "bunk", "beds"],
        description: "Rows of snug sleeping shelves where climbers nap until the midnight push for the summit, packed in like contented sardines.", isFixture: true });
    addItem({ id: "bench8", name: "hut bench", nouns: ["bench", "seat"],
        description: "A bench outside Taishikan, bolted down against the wind, facing the drop.",
        readText: "You sit outside Taishikan at 3,100 meters. The clouds have closed over the valley like a lid, and the world is reduced to starlight, stove smoke, and the bobbing lanterns of climbers grinding up the switchbacks below. It is very cold and completely perfect.",
        isFixture: true, kind: "seat" });

    // Ninth station.
    addItem({ id: "toriiOld", name: "weathered torii", nouns: ["torii", "gate"],
        description: "A small weathered torii marks the old ninth station, its wood silvered by wind and prayer. The true summit gate waits above.", isFixture: true });

    // The summit.
    addItem({ id: "toriiSummit", name: "summit torii", nouns: ["torii", "gate"],
        description: "The summit torii, guardian of the top of Japan, every coin-scarred grain of it lit gold by the rising sun.", isFixture: true });
    addItem({ id: "kusushi", name: "Kusushi Shrine", nouns: ["shrine", "kusushi"],
        description: "Kusushi Shrine at the summit of the Yoshida Trail, where climbers give thanks that the mountain said yes — and where the shrine's fire keeps the summit branding iron ready.", isFixture: true });
    addItem({ id: "priest", name: "shrine priest", nouns: ["priest", "monk", "kannushi"],
        description: "The Kusushi Shrine priest, wind-creased and serene, keeper of the summit branding iron — the final mark a kongō-zue can earn.",
        isFixture: true, isCreature: true });
    addItem({ id: "sunrise", name: "goraiko sunrise", nouns: ["sunrise", "goraiko", "sun", "dawn", "clouds"],
        description: "The goraiko: the sun climbing out of a sea of clouds that stretches to the curve of the earth, gold pouring across the cloud tops while the crowd on the rim shouts \"Banzai!\" It does not look real. It is the realest thing you have ever seen.", isFixture: true });
    addItem({ id: "summitBench", name: "stone ledge", nouns: ["ledge", "bench", "seat", "rock"],
        description: "A flat stone ledge facing east, pre-warmed by the first sun.",
        readText: "You sit on the ledge with the sunrise on your face and the clouds below your feet. Someone nearby is quietly crying; someone else is eating instant noodles. Both responses are correct.",
        isFixture: true, kind: "seat" });

    // The summit post office.
    addItem({ id: "postbox", name: "red postbox", nouns: ["postbox", "mailbox", "box"],
        description: "The famous red postbox of the Mount Fuji summit post office — the highest mail drop in Japan, emptied daily in season by a very fit mail carrier.",
        isOpen: true, isContainer: true, isFixture: true });
    addItem({ id: "clerk", name: "postal clerk", nouns: ["clerk", "postmaster"],
        description: "The summit postal clerk, crisp and unbothered at 3,700 meters, guardian of Japan's most coveted postmark.",
        isFixture: true, isCreature: true });

    // The crater rim and Ken-ga-mine.
    addItem({ id: "crater", name: "crater", nouns: ["crater", "caldera", "rim"],
        description: "Fuji's summit crater: a vast, silent bowl of rust and shadow, 240 meters deep, ringed by eight peaks. Snow hides in its folds even now, and the wind moving across it is the oldest sound in Japan.", isFixture: true });
    addItem({ id: "marker", name: "summit marker", nouns: ["marker", "pillar", "stone"],
        description: "The worn stone pillar on Ken-ga-mine: MOUNT FUJI — HIGHEST PEAK IN JAPAN, 3,776 METERS. Every hand that ever made it up here has touched it. Yours does too.",
        readText: "\"KEN-GA-MINE — 剣ヶ峰 — 3,776m. Highest point of Mount Fuji and of Japan.\" The stone is worn glassy where a million summit photographs have leaned.",
        isFixture: true });
    addItem({ id: "radarBase", name: "old radar station", nouns: ["radar", "dome", "station"],
        description: "The footings of the old summit weather radar, which watched for typhoons from this spot for forty years — the highest weather station in Japan until satellites took the job. The mountain outlasted it, as the mountain outlasts everything.", isFixture: true });

    const rooms = {};
    const addRoom = (p) => { const r = makeRoom(p); rooms[r.id] = r; };

    addRoom({ id: "fifthStation", title: "Fifth Station — The Lodge",
        description: "The Fifth Station lodge, 2,305 meters up the mountain's shoulder — half trailhead, half carnival: tour buses idling, the shop bright with walking sticks, headlamps, and storm jackets, free trail maps on the counter (TAKE one), Komitake Shrine watching over it all, and pack horses dozing by the trail. Above, Fuji's dark cone blots out the stars. The Yoshida Trail climbs UP.",
        exits: { up: "sixthStation", north: "sixthStation" },
        items: ["shopkeeper", "trailMap", "stick", "headlamp", "jacket", "letter", "oxygen", "komitake", "horses"] });
    addRoom({ id: "sixthStation", title: "Sixth Station — Safety Center",
        description: "The trail proper begins: volcanic gravel crunching underfoot, a switchback rising into the dark. The safety center posts tonight's weather (READ the BULLETIN), the mountain guide checks climbers through beside his little branding brazier, warm onigiri wait in the counter warmer, and a bench faces the valley (SIT for the view). The trail climbs UP; the lodge is back DOWN.",
        exits: { up: "seventhHut", down: "fifthStation", north: "seventhHut", south: "fifthStation" },
        items: ["safetyCenter", "guide", "onigiri", "bench6"] });
    addRoom({ id: "seventhHut", title: "Seventh Station — Tomoekan",
        description: "The mountain hut Tomoekan clings to the slope at the seventh station, lamplight spilling from its door, hot noodles steaming at the counter, and a charcoal brazier glowing out front with the hut's branding iron in the coals. A bench faces the drop (SIT for the view). The trail climbs UP; the sixth station is DOWN.",
        exits: { up: "eighthHut", down: "sixthStation", north: "eighthHut", south: "sixthStation" },
        items: ["keeper7", "brazier7", "bench7", "noodles"] });
    addRoom({ id: "eighthHut", title: "Eighth Station — Taishikan",
        description: "Taishikan, the eighth-station hut, 3,100 meters: bunks stacked snug inside, hot cocoa at the counter, the keeper's branding iron ready at the fire, and a wind-bolted bench facing the drop (SIT for the view). Above here the trail is dark, thin-aired, and exposed to whatever the night is doing. The summit push climbs UP; the seventh station is DOWN.",
        exits: { up: "ninthStation", down: "seventhHut", north: "ninthStation", south: "seventhHut" },
        items: ["keeper8", "cocoa", "bunks", "bench8"] });
    addRoom({ id: "ninthStation", title: "Ninth Station — The Final Stretch",
        description: "The last stretch above the ninth station: bare volcanic rock, switchbacks cut into the cone, a weathered torii marking the old station, and the summit somewhere overhead. Your headlamp beam is the whole visible world. The summit torii is UP; Taishikan is DOWN.",
        exits: { up: "summit", down: "eighthHut", north: "summit", south: "eighthHut" },
        items: ["toriiOld"], isDark: true });
    addRoom({ id: "summit", title: "The Summit — Tenth Station",
        description: "The top of the Yoshida Trail — the tenth station: the summit torii, Kusushi Shrine beyond it where the priest tends the summit branding fire, and the east ablaze with the goraiko over an endless sea of clouds. A stone ledge faces the sunrise (SIT — you've earned it). The summit post office is just INSIDE; the crater rim path leads EAST; the trail back down the mountain is DOWN.",
        exits: { down: "ninthStation", inside: "postOffice", east: "craterRim", south: "ninthStation" },
        items: ["toriiSummit", "kusushi", "priest", "sunrise", "summitBench"] });
    addRoom({ id: "postOffice", title: "Summit Post Office",
        description: "A tiny wooden post office at the top of Japan — a counter, a clerk, a rack of letters and cards, and the famous red postbox. Mail dropped here carries the Mount Fuji summit postmark, and somebody's mother is about to be very proud. The torii is back OUTSIDE.",
        exits: { outside: "summit" }, items: ["clerk", "postbox", "letter"] });
    addRoom({ id: "craterRim", title: "The Crater Rim",
        description: "The path along the crater rim, the great silent bowl falling away to one side and the sea of clouds to the other. Wind, rock, and morning light — nothing else up here but the eight peaks of the rim. Ken-ga-mine, the highest, is a short climb UP; the summit torii is back WEST.",
        exits: { up: "kengamine", west: "summit", north: "kengamine" }, items: ["crater"] });
    addRoom({ id: "kengamine", title: "Ken-ga-mine — The True Summit",
        description: "Ken-ga-mine: the highest of the crater's eight peaks and the highest ground in Japan, crowned by the worn summit marker and the footings of the old weather radar. There is nowhere further up. The rim path leads back DOWN.",
        exits: { down: "craterRim", south: "craterRim" }, items: ["marker", "radarBase"] });

    return { rooms, items };
}
