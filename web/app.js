// SKOGARK — front end (web equivalent of ContentView.swift).
//
// Shows a scenario menu, then a scrolling transcript + input line for the
// chosen game. "Menu" returns to the chooser. New transcript entries are
// appended and the newest line is kept pinned to the bottom.

"use strict";

(function () {
    const menuEl = document.getElementById("menu");
    const gameEl = document.getElementById("game");
    const scenarioList = document.getElementById("scenarioList");
    const transcriptEl = document.getElementById("transcript");
    const form = document.getElementById("inputBar");
    const input = document.getElementById("command");
    const goButton = form.querySelector("button[type=submit]");
    const menuButton = document.getElementById("menuButton");
    const gameTitle = document.getElementById("gameTitle");
    const sceneLayers = [document.getElementById("sceneA"), document.getElementById("sceneB")];
    const locationFlash = document.getElementById("locationFlash");
    const catSprite = document.getElementById("catSprite");

    // Image files for the web app, loaded from web/images/. Each room maps to a
    // base name; the "_landscape" / "_portrait" variant is chosen at runtime to
    // match the viewport. Add matching files to light up a location; any room
    // not listed simply stays black. (Separate from the iOS Assets.xcassets.)
    const ROOM_BACKGROUNDS = {
        innKitchen:  "bg_inn_kitchen",
        square:      "bg_village_square",
        townButcher: "bg_butcher",
        townBakery:  "bg_bakery",
        townFish:    "bg_fishmonger",
        westOfHouse: "bg_west_of_house",
        behindHouse: "bg_behind_house",
        kitchen:     "bg_kitchen",
        // livingRoom and cellar are state-dependent — see backgroundBase().
    };
    // Inlined data-URI sprite (see cat-sprite.js); falls back to a file if absent.
    const CAT_SPRITE = window.SKOGARK_CAT_SPRITE || "images/cat_sprite.png";
    const CAT_ROOM = "townFish";   // the stray cat waits at the fishmonger
    const portraitQuery = window.matchMedia("(orientation: portrait)");

    // Resolves a room to its background base name. The cellar is dark until a
    // lit lantern is present, so it swaps between dark and egg-lit art.
    function backgroundBase(roomID) {
        if (roomID === "cellar") {
            return (game && game.canSee()) ? "bg_cellar_lit" : "bg_cellar_dark";
        }
        if (roomID === "livingRoom") {
            return (game && game.has("rugMoved")) ? "bg_living_room_open" : "bg_living_room";
        }
        return ROOM_BACKGROUNDS[roomID] || null;
    }

    // Resolves a room to its orientation-appropriate background URL (or null).
    function backgroundURL(roomID) {
        const base = backgroundBase(roomID);
        if (!base) return null;
        const orientation = portraitQuery.matches ? "portrait" : "landscape";
        return `images/${base}_${orientation}.png`;
    }

    catSprite.style.backgroundImage = `url("${CAT_SPRITE}")`;

    let game = null;
    let rendered = 0; // transcript entries already on screen
    let activeLayer = 0;      // which #scene layer is currently visible
    let lastRoomID = null;    // last room the scene reacted to
    let lastSceneKey = null;  // room + lit state, so the backdrop reacts to light
    let flashTimer = null;

    function buildMenu() {
        for (const scenario of SCENARIOS) {
            const button = document.createElement("button");
            button.type = "button";
            button.className = "scenario";

            const title = document.createElement("div");
            title.className = "scenario-title";
            title.textContent = scenario.title;

            const blurb = document.createElement("div");
            blurb.className = "scenario-blurb";
            blurb.textContent = scenario.blurb;

            button.append(title, blurb);
            button.addEventListener("click", () => startGame(scenario));
            scenarioList.appendChild(button);
        }
    }

    function startGame(scenario) {
        game = new Game(scenario);
        rendered = 0;
        lastRoomID = null;
        transcriptEl.textContent = "";
        gameTitle.textContent = scenario.title;
        menuEl.hidden = true;
        gameEl.hidden = false;
        render();
        updateScene();
        updateButton();
        input.focus();
    }

    function backToMenu() {
        gameEl.hidden = true;
        menuEl.hidden = false;
        game = null;
        clearScene();
    }

    // ---- Scene (background art, arrival card, cat sprite) ----

    // Reacts to the scene: cross-fades the backdrop when the room OR its lit
    // state changes (so lighting the cellar lantern reveals the egg), and
    // flashes the location card / toggles the cat only when the room changes.
    function updateScene() {
        if (!game) return;
        const roomID = game.roomID;
        const sceneKey = roomID + "|" + game.canSee() + "|" + game.has("rugMoved");
        if (sceneKey === lastSceneKey) return;   // nothing visual changed
        const roomChanged = roomID !== lastRoomID;
        lastSceneKey = sceneKey;
        lastRoomID = roomID;

        const url = backgroundURL(roomID);
        const incoming = 1 - activeLayer;
        sceneLayers[incoming].style.backgroundImage = url ? `url("${url}")` : "none";
        sceneLayers[incoming].classList.add("visible");
        sceneLayers[activeLayer].classList.remove("visible");
        activeLayer = incoming;

        if (roomChanged) {
            catSprite.classList.toggle("visible", roomID === CAT_ROOM);
            flashLocation(game.roomTitle);
        }
    }

    // Swap the current backdrop to the other orientation variant on rotate.
    portraitQuery.addEventListener("change", function () {
        if (!game || lastRoomID === null) return;
        const url = backgroundURL(lastRoomID);
        sceneLayers[activeLayer].style.backgroundImage = url ? `url("${url}")` : "none";
    });

    // Shows the arrival card, cancelling any card still fading so quick moves
    // don't leave it stuck on screen.
    function flashLocation(title) {
        if (!title) return;
        clearTimeout(flashTimer);
        locationFlash.textContent = title;
        locationFlash.classList.add("show");
        flashTimer = setTimeout(() => locationFlash.classList.remove("show"), 1600);
    }

    // Resets the scene to plain black (used when returning to the menu).
    function clearScene() {
        clearTimeout(flashTimer);
        sceneLayers.forEach(layer => {
            layer.classList.remove("visible");
            layer.style.backgroundImage = "none";
        });
        catSprite.classList.remove("visible");
        locationFlash.classList.remove("show");
        lastRoomID = null;
        lastSceneKey = null;
    }

    function render() {
        const fragment = document.createDocumentFragment();
        for (let i = rendered; i < game.transcript.length; i++) {
            const entry = game.transcript[i];
            const div = document.createElement("div");
            div.className = "entry " + (entry.isCommand ? "cmd" : "out");
            div.textContent = entry.text;
            fragment.appendChild(div);
        }
        transcriptEl.appendChild(fragment);
        rendered = game.transcript.length;
        transcriptEl.scrollTop = transcriptEl.scrollHeight;
    }

    function updateButton() {
        goButton.disabled = input.value.trim().length === 0;
    }

    form.addEventListener("submit", function (event) {
        event.preventDefault();
        if (!game) return;
        const value = input.value;
        if (value.trim().length === 0) return;
        input.value = "";
        updateButton();
        game.process(value);
        render();
        updateScene();
        input.focus();
    });

    input.addEventListener("input", updateButton);
    menuButton.addEventListener("click", backToMenu);

    buildMenu();
})();
