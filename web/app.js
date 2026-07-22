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
    const actionBar = document.getElementById("actionBar");
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
        // Savannah River cruise — a sightseeing tour down the river past the
        // River Street riverfront, ending at Old Fort Jackson.
        riverStreet: "bg_river_dock",
        riverD1:     "bg_cruise_river_d1",
        riverD2:     "bg_cruise_river_d2",
        riverD3:     "bg_cruise_river_d3",
        riverD4:     "bg_cruise_river_d4",
        portD1:      "bg_cruise_port_d1",
        portD2:      "bg_cruise_port_d2",
        portD3:      "bg_cruise_port_d3",
        portD4:      "bg_cruise_port_d4",
        bridgeD1:    "bg_cruise_bridge_d1",
        bridgeD2:    "bg_cruise_bridge_d2",
        bridgeD3:    "bg_cruise_bridge_d3",
        bridgeD4:    "bg_cruise_bridge_d4",
        cityD1:      "bg_cruise_city_d1",
        cityD2:      "bg_cruise_city_d2",
        cityD3:      "bg_cruise_city_d3",
        cityD4:      "bg_cruise_city_d4",
        wavingD1:    "bg_cruise_waving_d1",
        wavingD2:    "bg_cruise_waving_d2",
        wavingD3:    "bg_cruise_waving_d3",
        wavingD4:    "bg_cruise_waving_d4",
        fortJackson: "bg_fort_jackson",
        // Fort Pulaski National Monument — drive in through the gates, check in
        // at the visitor center, walk out past Battery Hambright to the North
        // Pier, and follow the Lighthouse Overlook Trail to the Cockspur Island
        // Lighthouse. (The fort interior is a placeholder for now.)
        gate:             "bg_pulaski_gate",
        visitorCenter:    "bg_pulaski_visitor_center",
        fort:             "bg_pulaski_fort",
        drawbridge:       "bg_pulaski_drawbridge",
        casemates:        "bg_pulaski_casemates",
        prison:           "bg_pulaski_prison",
        quarters:         "bg_pulaski_quarters",
        terreplein:       "bg_pulaski_terreplein",
        moatWalk:         "bg_pulaski_moat_walk",
        scarredWall:      "bg_pulaski_scarred_wall",
        batteryHambright: "bg_pulaski_battery_hambright",
        northPier:        "bg_pulaski_north_pier",
        trail1:           "bg_pulaski_trail_1",
        trail2:           "bg_pulaski_trail_2",
        trail3:           "bg_pulaski_trail_3",
        trail4:           "bg_pulaski_lighthouse_deck",
        // Roppongi Pub Crawl — up from the Hibiya Line into the neon crossing,
        // the three bars of the classic crawl, the dawn ramen stand, and the
        // ride home on the 05:12. (roppongiStation is state-dependent — see
        // backgroundBase().)
        crossing:         "bg_roppongi_crossing",
        geronimos:        "bg_roppongi_geronimos",
        sideStreet:       "bg_roppongi_side_street",
        mogambos:         "bg_roppongi_mogambos",
        quest:            "bg_roppongi_quest",
        ramenya:          "bg_roppongi_ramenya",
        ticketMachine:    "bg_roppongi_ticket_machine",
        trainCar:         "bg_roppongi_train_interior",
        transferStation:  "bg_roppongi_transfer",
        homeStation:      "bg_roppongi_home_station",
        wrongTerminus:    "bg_roppongi_missed_stop",
        fareAdjust:       "bg_roppongi_fare_adjustment",
        // Mount Fuji — the Yoshida Trail night climb from the Fifth Station to
        // the summit.
        fifthStation:     "bg_fuji_fifth_station",
        sixthStation:     "bg_fuji_sixth_station",
        seventhHut:       "bg_fuji_seventh_hut",
        postOffice:       "bg_fuji_post_office",
        craterRim:        "bg_fuji_crater_rim",
        kengamine:        "bg_fuji_kengamine",
        // Greenwich Park — the commute-home detour, from the DLR to Blackheath.
        dlrStation:       "bg_greenwich_dlr_station",
        cuttySark:        "bg_greenwich_cutty_sark",
        maritimeMuseum:   "bg_greenwich_museum",
        parkLawn:         "bg_greenwich_park_lawn",
        chestnutAvenue:   "bg_greenwich_avenue",
        observatory:      "bg_greenwich_observatory",
        wolfeViewpoint:   "bg_greenwich_viewpoint",
        blackheath:       "bg_greenwich_blackheath",
        // livingRoom, cellar, roppongiStation, and Fuji's eighthHut /
        // ninthStation / summit are state-dependent — see backgroundBase().
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
        // Fuji's ninth station is dark until the headlamp comes on.
        if (roomID === "ninthStation") {
            return (game && game.canSee()) ? "bg_fuji_ninth_lit" : "bg_fuji_ninth_dark";
        }
        // Once the ramen is eaten, the 05:12 first train waits at the platform.
        if (roomID === "roppongiStation") {
            return (game && game.has("ateRamen")) ? "bg_roppongi_first_train" : "bg_roppongi_station";
        }
        // On a rain or cold-wind night, Taishikan sits in the storm until the
        // climber shelters, and the summit's goraiko breaks through clouds.
        if (roomID === "eighthHut") {
            const bad = game && (game.has("weatherRain") || game.has("weatherCold"));
            return (bad && !game.has("weatherReady")) ? "bg_fuji_storm" : "bg_fuji_eighth_hut";
        }
        if (roomID === "summit") {
            const bad = game && (game.has("weatherRain") || game.has("weatherCold"));
            return bad ? "bg_fuji_summit_clouded" : "bg_fuji_summit";
        }
        const base = ROOM_BACKGROUNDS[roomID] || null;
        // The 7:00 Sunset Cruise swaps in warm dusk art (no narration; a DJ
        // parties on the top deck) for every on-board room plus Old Fort Jackson.
        // The pre-boarding River Street dock keeps its daytime look.
        if (base && game && game.has && game.has("cruise_sunset") &&
            (base.indexOf("bg_cruise_") === 0 || base === "bg_fort_jackson")) {
            return base + "_sunset";
        }
        // The 3:30 Afternoon cruise matches the 1:00 Cannon cruise everywhere
        // except at the fort, where no salute is fired.
        if (base === "bg_fort_jackson" && game && game.has && game.has("cruise_afternoon")) {
            return "bg_fort_jackson_afternoon";
        }
        return base;
    }

    // Resolves a room to its orientation-appropriate background URL (or null).
    // The variant is chosen by the scene pane's own shape (usually wider than
    // tall, so landscape art is the norm), matching the iOS scene pane.
    function backgroundURL(roomID) {
        const base = backgroundBase(roomID);
        if (!base) return null;
        const scene = document.getElementById("scene");
        const paneIsWide = !scene || scene.clientWidth >= scene.clientHeight;
        const orientation = paneIsWide ? "landscape" : "portrait";
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
    let voicesReady = false; // true once the voice list has actually loaded
    let pendingText = null; // narration requested before voices were ready

    function pickVoice() {
        if (!synth) return;
        const voices = synth.getVoices();
        if (!voices.length) return;
        // One-time dump of everything Chrome exposes, so voice problems can be
        // diagnosed from the console (name / lang / local vs. remote / default).
        if (!pickVoice._dumped) {
            pickVoice._dumped = true;
            console.info("SKOGARK available voices:",
                voices.map((v) => v.name + " (" + v.lang + ")"
                    + (v.localService ? " local" : " REMOTE")
                    + (v.default ? " default" : "")));
        }
        // Rank en-US voices by how natural they sound, so the narrator is the
        // best voice the browser has rather than whatever's first:
        //   1. Edge's "Natural" neural voices (excellent),
        //   2. Apple "(Enhanced)"/"(Premium)" voices the user has downloaded,
        //   3. Siri voices,
        //   4. Chrome's remote "Google US English" (network-backed but good;
        //      long lines are chunked in speak() to dodge its cutoff bug),
        //   5. the better built-in compacts (Samantha, Alex, Aaron, …).
        // Apple's legacy novelty voices (Fred, Ralph, Zarvox, …) sound like a
        // 1980s robot and are never picked. A male-sounding name is a small
        // tiebreak within a tier — Captain Mike — never a tier jump. Only an
        // en-US voice is ever assigned (an explicit utterance.voice overrides
        // utterance.lang); with none installed, narrator stays null and the
        // utterance's lang="en-US" drives pronunciation alone.
        const NOVELTY = /albert|bad news|bahh|bells|boing|bubbles|cellos|deranged|fred|good news|hysterical|jester|junior|kathy|organ|ralph|superstar|trinoids|whisper|wobble|zarvox|\beddy\b|\bflo\b|grandma|grandpa|\breed\b|rocko|sandy|shelley/;
        const MALE = /\b(male|guy|andrew|christopher|eric|roger|steffan|davis|tony|jason|aaron|alex|evan|tom|nathan|david)\b/;
        function voiceScore(v) {
            if (!/en[-_]US/i.test(v.lang)) return 0;
            const name = v.name.toLowerCase();
            if (NOVELTY.test(name)) return 0;
            let score = 10;
            if (name.includes("natural")) score += 1000;
            else if (name.includes("enhanced") || name.includes("premium")) score += 900;
            else if (name.includes("siri")) score += 800;
            else if (name.includes("google us english")) score += 700;
            else if (/samantha|alex|aaron|nicky|evan|tom|allison|ava|susan|joelle/.test(name)) score += 100;
            if (MALE.test(name)) score += 30;
            if (v.localService) score += 5; // reliability tiebreak
            return score;
        }
        let best = null;
        let bestScore = 0;
        for (const v of voices) {
            const score = voiceScore(v);
            if (score > bestScore) { best = v; bestScore = score; }
        }
        narrator = best;
        if (narrator) {
            console.info("SKOGARK narrator voice:", narrator.name, "(" + narrator.lang + ")",
                narrator.localService ? "local" : "REMOTE");
        } else {
            console.warn("SKOGARK: no en-US voice installed; relying on lang='en-US'. "
                + "Install a US English voice for a proper American narrator.");
        }
        // The voice list is loaded now. Release any narration that arrived
        // before it, so the first line isn't spoken in Chrome's default voice.
        voicesReady = true;
        if (pendingText !== null) {
            const text = pendingText;
            pendingText = null;
            speak(text);
        }
    }
    if (synth) {
        pickVoice();
        if (typeof synth.addEventListener === "function") {
            synth.addEventListener("voiceschanged", pickVoice);
        }
        // Safety net: some Chrome states never fire "voiceschanged". Don't lose
        // narration forever — after a short wait, speak with whatever we have.
        setTimeout(function () {
            if (voicesReady) return;
            voicesReady = true;
            if (pendingText !== null) {
                const text = pendingText;
                pendingText = null;
                speak(text);
            }
        }, 1200);
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

    // Splits prose into sentence-boundary chunks of roughly ≤220 characters.
    // Chrome silently cuts speech off after ~15 seconds on one utterance
    // (worst with its remote Google voices); several short utterances queued
    // back-to-back sound identical and never hit the limit.
    function speechChunks(text) {
        const sentences = text.match(/[^.!?]+[.!?]+["')\]]*\s*|[^.!?]+$/g) || [text];
        const parts = [];
        let buffer = "";
        for (const sentence of sentences) {
            if (buffer && buffer.length + sentence.length > 220) {
                parts.push(buffer);
                buffer = sentence;
            } else {
                buffer += sentence;
            }
        }
        if (buffer.trim()) parts.push(buffer);
        return parts;
    }

    function speak(text) {
        if (!voiceOn || !synth) return;
        // If the voice list hasn't loaded yet, speaking now lets Chrome use its
        // default voice (often British) and ignore our en-US request. Stash the
        // latest line instead; pickVoice flushes it once a US voice is chosen.
        if (!voicesReady) { pendingText = text; return; }
        const say = speakable(text);
        if (!say) return;
        for (const chunk of speechChunks(say)) {
            const utterance = new SpeechSynthesisUtterance(chunk);
            if (narrator) utterance.voice = narrator;
            utterance.lang = "en-US"; // force US English pronunciation
            utterance.rate = 1.0;
            utterance.pitch = 0.95; // a touch lower for Captain Mike
            synth.speak(utterance);
        }
    }

    function stopSpeaking() { if (synth) synth.cancel(); }

    // Synthesized cannon salute for Old Fort Jackson — a deep, decaying boom
    // built with the Web Audio API so no sound-file asset is needed. Shares the
    // narration mute (voiceOn): a low sine sweep for the thump plus a lowpassed
    // noise burst for the crack, both under a fast-attack exponential decay.
    let audioCtx = null;
    function playCannonBoom() {
        if (!voiceOn) return;
        const AC = window.AudioContext || window.webkitAudioContext;
        if (!AC) return;
        try {
            if (!audioCtx) audioCtx = new AC();
            if (audioCtx.state === "suspended") audioCtx.resume();
            const ctx = audioCtx;
            const now = ctx.currentTime;
            const master = ctx.createGain();
            master.gain.setValueAtTime(0.9, now);
            master.connect(ctx.destination);

            // Low-frequency thump: a sine sweeping down from 90 Hz to 30 Hz.
            const osc = ctx.createOscillator();
            osc.type = "sine";
            osc.frequency.setValueAtTime(90, now);
            osc.frequency.exponentialRampToValueAtTime(30, now + 0.5);
            const oscGain = ctx.createGain();
            oscGain.gain.setValueAtTime(1.0, now);
            oscGain.gain.exponentialRampToValueAtTime(0.001, now + 0.9);
            osc.connect(oscGain).connect(master);
            osc.start(now);
            osc.stop(now + 0.95);

            // Noise burst for the crack, lowpassed so it booms rather than hisses.
            const dur = 0.9;
            const buffer = ctx.createBuffer(1, Math.floor(ctx.sampleRate * dur), ctx.sampleRate);
            const chan = buffer.getChannelData(0);
            for (let i = 0; i < chan.length; i++) {
                const decay = 1 - i / chan.length;
                chan[i] = (Math.random() * 2 - 1) * decay * decay;
            }
            const noise = ctx.createBufferSource();
            noise.buffer = buffer;
            const lp = ctx.createBiquadFilter();
            lp.type = "lowpass";
            lp.frequency.setValueAtTime(400, now);
            lp.frequency.exponentialRampToValueAtTime(120, now + 0.4);
            const noiseGain = ctx.createGain();
            noiseGain.gain.setValueAtTime(0.8, now);
            noiseGain.gain.exponentialRampToValueAtTime(0.001, now + dur);
            noise.connect(lp).connect(noiseGain).connect(master);
            noise.start(now);
            noise.stop(now + dur);
        } catch (e) { /* audio is best-effort */ }
    }

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
    let announcedMMSIs = new Set(); // vessels Captain Mike has already called out
    let lastShipLeg = null;         // so we announce at most once per cruise leg

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
    // A cruise leg id, e.g. "riverD4" -> "river" (the dock and fort have none).
    function legOf(roomID) { return roomID.replace(/D\d+$/, ""); }

    async function maybeAnnounceShip() {
        if (!VESSEL_API || !game || game.scenario.id !== "riverboat") return;
        const legs = ["river", "port", "bridge", "city", "waving"];
        const leg = legOf(game.roomID);
        if (!legs.includes(leg) || leg === lastShipLeg) return; // once per leg
        lastShipLeg = leg;
        try {
            const res = await fetch(VESSEL_API + "/vessels", { cache: "no-store" });
            const data = await res.json();
            const fresh = (data.vessels || []).filter((v) => v.name && !announcedMMSIs.has(v.mmsi));
            if (!fresh.length) return;
            const v = fresh[0];
            announcedMMSIs.add(v.mmsi);
            game.emit(`Captain Mike: "Off to the side, the ${v.name} — a ${v.kind || "vessel"} on the river with us."`);
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

    // The artwork slice behind each destination card on the opening screen.
    const DESTINATION_ART = {
        Explore:  "bg_west_of_house_landscape",
        Savannah: "bg_pulaski_terreplein_landscape",
        Japan:    "bg_fuji_summit_landscape",
        London:   "bg_greenwich_viewpoint_landscape",
    };
    const taglineEl = document.querySelector("#menu .tagline");

    // Two-step chooser: destination cards first, then that destination's
    // adventures with a way back.
    function buildMenu(destination = null) {
        scenarioList.textContent = "";
        if (taglineEl) taglineEl.textContent = destination || "Tiny text adventures. Where to?";

        if (!destination) {
            const names = [];
            for (const s of SCENARIOS) if (!names.includes(s.destination)) names.push(s.destination);
            for (const name of names) {
                const count = SCENARIOS.filter((s) => s.destination === name).length;
                const button = document.createElement("button");
                button.type = "button";
                button.className = "scenario destination";
                const art = DESTINATION_ART[name];
                if (art) {
                    button.style.backgroundImage =
                        `linear-gradient(rgba(0,0,0,0.35), rgba(0,0,0,0.8)), url("images/${art}.png")`;
                }
                const title = document.createElement("div");
                title.className = "scenario-title";
                title.textContent = name;
                const blurb = document.createElement("div");
                blurb.className = "scenario-blurb";
                blurb.textContent = count === 1 ? "1 adventure" : `${count} adventures`;
                button.append(title, blurb);
                button.addEventListener("click", () => buildMenu(name));
                scenarioList.appendChild(button);
            }
            return;
        }

        for (const scenario of SCENARIOS.filter((s) => s.destination === destination)) {
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
        const back = document.createElement("button");
        back.type = "button";
        back.className = "menu-back";
        back.textContent = "‹ All destinations";
        back.addEventListener("click", () => buildMenu());
        scenarioList.appendChild(back);
    }

    function startGame(scenario) {
        game = new Game(scenario);
        rendered = 0;
        lastRoomID = null;
        announcedMMSIs = new Set();
        lastShipLeg = null;
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
        renderActions();
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
        if (actionBar) actionBar.textContent = "";
    }

    // ---- Scene (background art, arrival card, cat sprite) ----

    // Reacts to the scene: cross-fades the backdrop when the room OR its lit
    // state changes (so lighting the cellar lantern reveals the egg), and
    // flashes the location card / toggles the cat only when the room changes.
    function updateScene() {
        if (!game) return;
        const roomID = game.roomID;
        const sceneKey = roomID + "|" + game.canSee() + "|" + game.has("rugMoved") + "|" + game.has("cruise_sunset") + "|" + game.has("cruise_afternoon");
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
            if (!entry.isCommand) {
                spoken.push(entry.text);
                // The cannon salute at Old Fort Jackson gets an audible boom.
                if (entry.text.indexOf("BOOOM!") !== -1) playCannonBoom();
            }
        }
        transcriptEl.appendChild(fragment);
        rendered = game.transcript.length;
        transcriptEl.scrollTop = transcriptEl.scrollHeight;
        if (spoken.length) speak(spoken.join("\n"));
    }

    function updateButton() {
        goButton.disabled = input.value.trim().length === 0;
    }

    // ---- Tap-action chips (hybrid layer over the parser) ----
    // Each chip just feeds a command string into the same game.process() the
    // text box uses. Built fresh from room state after every turn. Typing still
    // works unchanged.

    // One-tap "special" interactions keyed by item id, for verbs the parser
    // routes to the object handler (ring / throw / play / push / straddle).
    const SPECIAL_BY_ID = {
        bellGeronimos: { label: "\u{1F514} Ring the bell", cmd: "ring bell" },
        bellMogambos:  { label: "\u{1F514} Ring the bell", cmd: "ring bell" },
        bellQuest:     { label: "\u{1F514} Ring the bell", cmd: "ring bell" },
        dartboard:     { label: "\u{1F3AF} Throw darts",    cmd: "throw darts" },
        jukebox:       { label: "\u{1F3B5} Jukebox",        cmd: "play jukebox" },
        fareMachine:   { label: "Settle the fare",          cmd: "push machine" },
        meridian:      { label: "Straddle the line",        cmd: "straddle line" },
        rug:           { label: "Move the rug",             cmd: "move rug" },
        cannonCruise:    { label: "⚓ Board the Cannon Cruise",    cmd: "board cannon" },
        afternoonCruise: { label: "⚓ Board the Afternoon Cruise", cmd: "board afternoon" },
        sunsetCruise:    { label: "⚓ Board the Sunset Cruise",    cmd: "board sunset" },
    };
    // Carried items with a natural one-tap verb, keyed by item KIND — bought
    // copies get minted ids like "beer#0", so ids won't match here.
    const INV_SPECIAL = {
        beer: { label: "Drink the beer", cmd: "drink beer" },
    };

    function cap(s) { return s ? s.charAt(0).toUpperCase() + s.slice(1) : s; }

    function makeChip(label, cmd, cls) {
        const b = document.createElement("button");
        b.type = "button";
        b.className = "chip" + (cls ? " " + cls : "");
        b.textContent = label;
        b.addEventListener("click", function () { runCommand(cmd); });
        return b;
    }

    function renderActions() {
        if (!actionBar) return;
        actionBar.textContent = "";
        if (!game) return;
        if (game.isWon) {
            actionBar.appendChild(makeChip("↺ Play again", "restart", "util"));
            return;
        }
        const frag = document.createDocumentFragment();
        const room = game.rooms[game.roomID];
        const dark = !game.canSee();

        // Movement — labelled with the destination room's name where known.
        // Hidden in the dark so unlit rooms don't leak the map.
        if (room && !dark) {
            for (const dir of game.obviousExits()) {
                const destID = room.exits[dir];
                const dest = destID && game.rooms[destID];
                const label = "→ " + (dest && dest.title ? dest.title : cap(dir));
                frag.appendChild(makeChip(label, dir, "move"));
            }
        }

        // Actions on what's in the room (skipped in the dark).
        let sawSeat = false;
        if (room && !dark) {
            for (const id of room.items) {
                const item = game.item(id);
                if (!item) continue;
                const noun = (item.nouns && item.nouns[0]) || item.name;
                if (SPECIAL_BY_ID[id]) {
                    frag.appendChild(makeChip(SPECIAL_BY_ID[id].label, SPECIAL_BY_ID[id].cmd, "do"));
                } else if (item.isCreature) {
                    frag.appendChild(makeChip("\u{1F4AC} Talk to " + item.name, "talk to " + noun, "do"));
                } else if (item.forSale) {
                    frag.appendChild(makeChip("Buy " + item.name + " · " + item.price, "buy " + noun, "do"));
                } else if (item.isTakeable) {
                    frag.appendChild(makeChip("Take " + item.name, "take " + noun, "do"));
                } else if (item.kind === "seat") {
                    sawSeat = true;
                } else if (item.isFixture) {
                    frag.appendChild(makeChip("Look at " + item.name, "examine " + noun, "look"));
                }
                if (item.readText) {
                    frag.appendChild(makeChip("Read " + item.name, "read " + noun, "look"));
                }
                // Doors, windows, and containers — required in the house.
                if (item.isOpenable) {
                    frag.appendChild(makeChip(
                        (item.isOpen ? "Close " : "Open ") + item.name,
                        (item.isOpen ? "close " : "open ") + noun, "do"));
                }
            }
            // Put a carried item into any open container in the room
            // (the trophy case, the summit postbox); the engine validates.
            for (const contID of room.items) {
                const cont = game.item(contID);
                if (!cont || !cont.isContainer || !cont.isOpen) continue;
                const cnoun = (cont.nouns && cont.nouns[0]) || cont.name;
                for (const carriedID of game.inventory) {
                    const carried = game.item(carriedID);
                    if (!carried) continue;
                    const gnoun = (carried.nouns && carried.nouns[0]) || carried.name;
                    frag.appendChild(makeChip(
                        "Put " + carried.name + " → " + cont.name,
                        "put " + gnoun + " in " + cnoun, "give"));
                }
            }
            // Give any carried item to any creature present; the engine validates.
            const creatures = room.items
                .map(function (id) { return game.item(id); })
                .filter(function (it) { return it && it.isCreature; });
            if (creatures.length) {
                for (const carriedID of game.inventory) {
                    const carried = game.item(carriedID);
                    if (!carried) continue;
                    const gnoun = (carried.nouns && carried.nouns[0]) || carried.name;
                    for (const cre of creatures) {
                        const cnoun = (cre.nouns && cre.nouns[0]) || cre.name;
                        frag.appendChild(makeChip(
                            "Give " + carried.name + " → " + cre.name,
                            "give " + gnoun + " to " + cnoun, "give"));
                    }
                }
            }
        }

        // Carried one-tap verbs (e.g. drink the beer at the viewpoint).
        for (const id of game.inventory) {
            const carried = game.item(id);
            const special = carried && carried.kind && INV_SPECIAL[carried.kind];
            if (special) frag.appendChild(makeChip(special.label, special.cmd, "do"));
        }
        // Light sources, carried or in the room — the cellar and the ninth
        // station are tap-only climbs too. (Shown even in the dark: turning
        // the lamp on is exactly what a dark room needs.)
        const lightIDs = game.inventory.concat(room ? room.items : []);
        for (const id of lightIDs) {
            const it = game.item(id);
            if (!it || !it.isLightSource) continue;
            frag.appendChild(makeChip(
                (it.isLit ? "Turn off " : "\u{1F526} Turn on ") + it.name,
                "turn " + (it.isLit ? "off" : "on"), "do"));
        }
        if (sawSeat) frag.appendChild(makeChip("Sit", "sit", "do"));

        // Utility, quietly at the end.
        frag.appendChild(makeChip("\u{1F441} Look", "look", "util"));
        frag.appendChild(makeChip("\u{1F392} Items", "inventory", "util"));

        actionBar.appendChild(frag);
        actionBar.scrollLeft = 0;
    }

    // Run a command from a tapped chip: same path as the form, but we don't
    // focus the text input, so the mobile keyboard stays down for tap-only play.
    function runCommand(cmd) {
        if (!game) return;
        stopSpeaking();
        game.process(cmd);
        render();
        updateScene();
        maybeAnnounceShip();
        renderActions();
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
        renderActions();
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
        renderActions();
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
