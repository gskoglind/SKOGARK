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

    let game = null;
    let rendered = 0; // transcript entries already on screen

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
        transcriptEl.textContent = "";
        gameTitle.textContent = scenario.title;
        menuEl.hidden = true;
        gameEl.hidden = false;
        render();
        updateButton();
        input.focus();
    }

    function backToMenu() {
        gameEl.hidden = true;
        menuEl.hidden = false;
        game = null;
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
        input.focus();
    });

    input.addEventListener("input", updateButton);
    menuButton.addEventListener("click", backToMenu);

    buildMenu();
})();
