# SKOGARK AIS proxy

A tiny service that feeds the game's live "ships on the river" map. It holds your
AIS key (which must never ship in the static web/native client), keeps a live
WebSocket open to [AISStream.io](https://aisstream.io) for a bounding box around
the Savannah River and the Port of Savannah, and serves a CORS-enabled JSON
snapshot the apps poll.

## 1. Get a free AIS key

1. Sign up at <https://aisstream.io>.
2. Create an API key.

## 2. Run it locally

```sh
cd server
npm install
AISSTREAM_API_KEY=your_key_here npm start
# → SKOGARK AIS proxy listening on :8080
```

Check it:

```sh
curl localhost:8080/health      # { "ok": true, "tracked": N }
curl localhost:8080/vessels     # { "updated": ..., "count": N, "vessels": [...] }
```

Each vessel looks like:

```json
{ "mmsi": 366123456, "name": "MAERSK ...", "lat": 32.08, "lon": -81.09,
  "sog": 8.3, "cog": 271.0, "type": 70, "kind": "cargo ship", "destination": "SAVANNAH" }
```

## 3. Deploy it (so GitHub Pages can reach it)

Any always-on Node host works (the WebSocket must stay open, so a persistent
process — not a short-lived serverless function). Render / Railway / Fly.io are
easy:

- Root/working dir: `server/`
- Build: `npm install`
- Start: `npm start`
- Set env var `AISSTREAM_API_KEY`.

Note the public URL it gives you (e.g. `https://skogark-ais.onrender.com`).

## 4. Point the apps at it

- **Web:** copy `web/config.example.js` to `web/config.js` and set
  `window.SKOGARK_VESSEL_API` to your proxy URL. The "🚢 Ships" button appears
  only when this is set.
- **Native:** set the same URL in the app's vessel-map config (see the native
  map wiring when it's added).

## Environment variables

| Var | Required | Default | Meaning |
|-----|----------|---------|---------|
| `AISSTREAM_API_KEY` | yes | — | Your AISStream key |
| `PORT` | no | `8080` | HTTP port |
| `BBOX` | no | `31.95,-81.20,32.20,-80.80` | `swLat,swLon,neLat,neLon` watch box |
| `STALE_SECONDS` | no | `900` | Drop vessels unseen for this long |

## Notes

- Respect AISStream's terms and rate limits.
- This keeps state in memory only; restarting clears the snapshot (it refills
  within a minute or two as new AIS messages arrive).
