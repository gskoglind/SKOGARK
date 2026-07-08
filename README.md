# SKOGARK

A tiny Zork-style text adventure, in two forms:

- **Native app** — a SwiftUI app (iOS / macOS) in [`SKOGARK/`](SKOGARK/), driven by a
  pure, deterministic game engine in
  [`SKOGARK/SKOGARK/AdventureEngine.swift`](SKOGARK/SKOGARK/AdventureEngine.swift).
- **Web app** — a self-contained static site in [`web/`](web/) that ports the same
  engine to JavaScript, so it runs in any browser with no server or build step.

Explore a white house and the caverns beneath it, light the lantern before the grue
gets you, and get the jeweled egg into the trophy case. There's a small village to the
east, too — feed the stray cat a fish if you find one.

## Play on the web

The site is published with GitHub Pages from the `web/` folder (see
[`.github/workflows/pages.yml`](.github/workflows/pages.yml)). Once deployed it's
available at:

```
https://<your-github-username>.github.io/SKOGARK/
```

### Run the web version locally

The game needs to be served over http(s) (not opened as a `file://` path), otherwise
the browser blocks `localStorage` and Save/Restore won't work:

```sh
cd web
python3 -m http.server 8000
# then open http://localhost:8000
```

## Build the native app

Open `SKOGARK.xcodeproj` in Xcode and run. Requires a recent Xcode / SDK.

## Project layout

```
SKOGARK/            Native SwiftUI app + game engine
web/                Static web port (engine.js, app.js, index.html, style.css)
.github/workflows/  GitHub Pages deployment
```
