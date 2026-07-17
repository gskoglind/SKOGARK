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
    const hintButton = document.getElementById("hintButton");
    const voiceButton = document.getElementById("voiceButton");
    const sceneLayers = [document.getElementById("sceneA"), document.getElementById("sceneB")];
    const locationFlash = document.getElementById("locationFlash");
    const catSprite = document.getElementById("catSprite");
    const shipsButton = document.getElementById("shipsButton");
    const shipsOverlay = document.getElementById("shipsOverlay");
    const shipsClose = document.getElementById("shipsClose");
    const shipsMapEl = document.getElementById("shipsMap");
    const shipsStatus = document.getElementById("shipsStatus");
    const camsButton = document.getElementById("camsButton");
    const camsOverlay = document.getElementById("camsOverlay");
    const camsClose = document.getElementById("camsClose");
    const camsSelect = document.getElementById("camsSelect");
    const camsFrame = document.getElementById("camsFrame");

    // Optional live-ships feature: the URL of the AIS proxy (see server/). When
    // unset, the "Ships" button and the in-narration ship name stay disabled.
    const VESSEL_API = (window.SKOGARK_VESSEL_API || "").replace(/\/$/, "") || null;

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

    // ---- Spoken narration (text-to-speech) ----
    // The captain's narration and room descriptions are read aloud with the
    // browser's built-in speech synthesis. Command echoes ("> go west") are
    // never spoken. A titlebar toggle mutes it; the choice is remembered.
    const synth = window.speechSynthesis || null;
    let voiceOn = (function () {
        try { return localStorage.getItem("skogark.voice") !== "off"; }
        catch (e) { return true; }
    })();
    let narrator = null; // chosen SpeechSynthesisVoice, once available

    function pickVoice() {
        if (!synth) return;
        const voices = synth.getVoices();
        if (!voices.length) return;
        // Prefer an English voice; nothing critical rides on the exact pick.
        narrator = voices.find((v) => /en[-_]US/i.test(v.lang))
            || voices.find((v) => /^en/i.test(v.lang))
            || voices[0];
    }
    if (synth) {
        pickVoice();
        if (typeof synth.addEventListener === "function") {
            synth.addEventListener("voiceschanged", pickVoice);
        }
    }

    // Strip decorative rule lines and collapse whitespace so the utterance
    // sounds like prose rather than the ASCII banner.
    function speakable(text) {
        return text
            .split("\n")
            .filter((line) => !/^[─—\-=_\s]*$/.test(line))
            .join(". ")
            .trim();
    }

    function speak(text) {
        if (!voiceOn || !synth) return;
        const say = speakable(text);
        if (!say) return;
        const utterance = new SpeechSynthesisUtterance(say);
        if (narrator) utterance.voice = narrator;
        utterance.rate = 1.0;
        utterance.pitch = 0.95; // a touch lower for Captain Mike
        synth.speak(utterance);
    }

    function stopSpeaking() { if (synth) synth.cancel(); }

    function updateVoiceButton() {
        voiceButton.setAttribute("aria-pressed", String(voiceOn));
        voiceButton.textContent = voiceOn ? "\u{1F50A} Voice" : "\u{1F507} Voice";
    }

    let game = null;
    let rendered = 0; // transcript entries already on screen
    let activeLayer = 0;      // which #scene layer is currently visible
    let lastRoomID = null;    // last room the scene reacted to
    let lastSceneKey = null;  // room + lit state, so the backdrop reacts to light
    let flashTimer = null;

    // ---- Live ships map (optional, gated on VESSEL_API) ----
    let shipsMap = null;
    let shipsMarkers = null;
    let shipsTimer = null;
    let namedShipAnnounced = false;

    function ensureShipsMap() {
        if (shipsMap || !window.L) return;
        shipsMap = L.map(shipsMapEl).setView([32.083, -81.09], 13); // downtown / port
        L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
            maxZoom: 18,
            attribution: "&copy; OpenStreetMap contributors",
        }).addTo(shipsMap);
        shipsMarkers = L.layerGroup().addTo(shipsMap);
    }

    async function pollVessels() {
        if (!VESSEL_API) return;
        try {
            const res = await fetch(VESSEL_API + "/vessels", { cache: "no-store" });
            const data = await res.json();
            const list = data.vessels || [];
            if (shipsMarkers) {
                shipsMarkers.clearLayers();
                for (const v of list) {
                    const speed = (typeof v.sog === "number") ? `${v.sog.toFixed(1)} kn` : "—";
                    L.circleMarker([v.lat, v.lon], {
                        radius: 5, color: "#4ade80", weight: 1,
                        fillColor: "#4ade80", fillOpacity: 0.8,
                    })
                        .bindPopup(`<strong>${v.name || "Unknown vessel"}</strong><br>${v.kind || "vessel"} · ${speed}`)
                        .addTo(shipsMarkers);
                }
            }
            shipsStatus.textContent = `${list.length} vessel${list.length === 1 ? "" : "s"} nearby · updated just now`;
        } catch (e) {
            shipsStatus.textContent = "Couldn't reach the ship feed.";
        }
    }

    function openShips() {
        if (!VESSEL_API) return;
        shipsOverlay.hidden = false;
        ensureShipsMap();
        if (shipsMap) setTimeout(() => shipsMap.invalidateSize(), 50); // resize after unhide
        pollVessels();
        clearInterval(shipsTimer);
        shipsTimer = setInterval(pollVessels, 30000);
    }

    function closeShips() {
        shipsOverlay.hidden = true;
        clearInterval(shipsTimer);
        shipsTimer = null;
    }

    // As the boat passes the working river, Captain Mike names a real ship that
    // is out there right now (best-effort; network hiccups are ignored).
    async function maybeAnnounceShip() {
        if (!VESSEL_API || namedShipAnnounced || !game) return;
        if (game.scenario.id !== "riverboat" || !game.roomID.startsWith("port")) return;
        namedShipAnnounced = true;
        try {
            const res = await fetch(VESSEL_API + "/vessels", { cache: "no-store" });
            const data = await res.json();
            const named = (data.vessels || []).filter((v) => v.name);
            if (!named.length) return;
            const v = named[0];
            game.emit(`Captain Mike: "And there she is — the ${v.name}, a ${v.kind || "vessel"} sharing the river with us right now."`);
            render();
        } catch (e) { /* keep the tour flowing regardless */ }
    }

    // ---- Live webcams (SavannahCams HLS feeds, embedded by iframe) ----
    const CAM_BASE = "https://www.savannahcams.com/streams/cam_";
    const RIVER_CAMS = [
        { slug: "river-street-east", label: "River Street East (the riverboat!)" },
        { slug: "river-street-west", label: "River Street West" },
        { slug: "pilots-dock", label: "Savannah Pilots Dock" },
        { slug: "savannah-yacht-facility", label: "Savannah Yacht Facility" },
        { slug: "talmadge-bridge", label: "Talmadge Bridge" },
        { slug: "fort-jackson", label: "Old Fort Jackson" },
        { slug: "elba-island", label: "Elba Island" },
    ];

    // The webcam that best matches the boat's current leg of the tour.
    function camForRoom(roomID) {
        if (roomID === "fortJackson") return "fort-jackson";
        if (roomID.startsWith("bridge")) return "talmadge-bridge";
        if (roomID.startsWith("port")) return "pilots-dock";
        return "river-street-east"; // River Street leg (and the dock)
    }

    function showCam(slug) {
        camsFrame.src = CAM_BASE + slug + ".html";
        if (camsSelect.value !== slug) camsSelect.value = slug;
    }

    function buildCamSelect() {
        if (camsSelect.options.length) return; // once
        for (const cam of RIVER_CAMS) {
            const option = document.createElement("option");
            option.value = cam.slug;
            option.textContent = cam.label;
            camsSelect.appendChild(option);
        }
    }

    function openCams() {
        buildCamSelect();
        camsOverlay.hidden = false;
        showCam(game ? camForRoom(game.roomID) : "river-street-east");
    }

    function closeCams() {
        camsOverlay.hidden = true;
        camsFrame.src = "about:blank"; // stop the stream when hidden
    }

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
        namedShipAnnounced = false;
        transcriptEl.textContent = "";
        gameTitle.textContent = scenario.title;
        // The live-ships map only makes sense on the riverboat, and only when a
        // proxy URL is configured.
        shipsButton.hidden = !(VESSEL_API && scenario.id === "riverboat");
        camsButton.hidden = scenario.id !== "riverboat";
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
        stopSpeaking();
        closeShips();
        closeCams();
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
        const spoken = [];
        for (let i = rendered; i < game.transcript.length; i++) {
            const entry = game.transcript[i];
            const div = document.createElement("div");
            div.className = "entry " + (entry.isCommand ? "cmd" : "out");
            div.textContent = entry.text;
            fragment.appendChild(div);
            if (!entry.isCommand) spoken.push(entry.text);
        }
        transcriptEl.appendChild(fragment);
        rendered = game.transcript.length;
        transcriptEl.scrollTop = transcriptEl.scrollHeight;
        if (spoken.length) speak(spoken.join("\n"));
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
        stopSpeaking(); // drop any narration still playing from the last turn
        game.process(value);
        render();
        updateScene();
        maybeAnnounceShip();
        input.focus();
    });

    input.addEventListener("input", updateButton);
    menuButton.addEventListener("click", backToMenu);
    voiceButton.addEventListener("click", function () {
        voiceOn = !voiceOn;
        try { localStorage.setItem("skogark.voice", voiceOn ? "on" : "off"); } catch (e) { /* ignore */ }
        if (!voiceOn) stopSpeaking();
        updateVoiceButton();
        input.focus();
    });

    hintButton.addEventListener("click", function () {
        if (!game) return;
        stopSpeaking();
        game.process("hint");
        render();
        input.focus();
    });
    shipsButton.addEventListener("click", openShips);
    shipsClose.addEventListener("click", closeShips);
    camsButton.addEventListener("click", openCams);
    camsClose.addEventListener("click", closeCams);
    camsSelect.addEventListener("change", () => showCam(camsSelect.value));

    updateVoiceButton();
    buildMenu();
})();
