// SKOGARK — terminal front end.
//
// The web equivalent of ContentView.swift: a scrolling transcript plus an
// input line. It reads game.transcript after each command and appends the
// new entries, then keeps the newest line pinned to the bottom (the web
// counterpart of defaultScrollAnchor(.bottom)).

"use strict";

(function () {
    const game = new Game();

    const transcriptEl = document.getElementById("transcript");
    const form = document.getElementById("inputBar");
    const input = document.getElementById("command");
    const goButton = form.querySelector("button[type=submit]");

    // How many transcript entries are already on screen.
    let rendered = 0;

    function render() {
        const fragment = document.createDocumentFragment();
        for (let i = rendered; i < game.transcript.length; i++) {
            const entry = game.transcript[i];
            const div = document.createElement("div");
            div.className = "entry " + (entry.isCommand ? "cmd" : "out");
            div.textContent = entry.text; // textContent keeps newlines literal (CSS pre-wrap renders them)
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
        const value = input.value;
        if (value.trim().length === 0) return;
        input.value = "";
        updateButton();
        game.process(value);
        render();
        input.focus();
    });

    input.addEventListener("input", updateButton);

    updateButton();
    render();
    input.focus();
})();
