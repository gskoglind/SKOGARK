// SKOGARK — AIS proxy.
//
// The web and native apps are static clients, so they can't hold a secret AIS
// key. This tiny service does: it holds the key, keeps a live WebSocket open to
// AISStream.io for a bounding box around the Savannah River / Port of Savannah,
// keeps an in-memory snapshot of recent vessels, and serves that snapshot as
// CORS-enabled JSON at GET /vessels. The apps just poll that endpoint.
//
// Run locally:   AISSTREAM_API_KEY=xxxx npm start
// Env vars:
//   AISSTREAM_API_KEY  (required)  your free key from https://aisstream.io
//   PORT               (optional)  HTTP port, default 8080
//   BBOX               (optional)  "swLat,swLon,neLat,neLon", default Savannah
//   STALE_SECONDS      (optional)  drop vessels unseen for this long, default 900

import http from "node:http";
import { WebSocket } from "ws";

const API_KEY = process.env.AISSTREAM_API_KEY;
const PORT = Number(process.env.PORT || 8080);
const STALE_SECONDS = Number(process.env.STALE_SECONDS || 900);

// Default bounding box: lower Savannah River, from downtown/River Street out
// past the port terminals toward the sea buoy.
const [swLat, swLon, neLat, neLon] = (process.env.BBOX || "31.95,-81.20,32.20,-80.80")
    .split(",").map(Number);

if (!API_KEY) {
    console.error("Missing AISSTREAM_API_KEY. Get a free key at https://aisstream.io and set it in the environment.");
    process.exit(1);
}

// MMSI -> vessel record. Position reports carry the coordinates; static-data
// reports carry the name and ship type. We merge both into one record.
const vessels = new Map();

function upsert(mmsi, patch) {
    const now = Date.now();
    const prev = vessels.get(mmsi) || { mmsi };
    vessels.set(mmsi, { ...prev, ...patch, lastSeen: now });
}

function pruneStale() {
    const cutoff = Date.now() - STALE_SECONDS * 1000;
    for (const [mmsi, v] of vessels) if (v.lastSeen < cutoff) vessels.delete(mmsi);
}

// Rough AIS ship-type code → friendly label (enough for narration flavor).
function shipKind(type) {
    if (type == null) return null;
    if (type >= 70 && type <= 79) return "cargo ship";
    if (type >= 80 && type <= 89) return "tanker";
    if (type >= 60 && type <= 69) return "passenger ship";
    if (type >= 50 && type <= 59) return "tug or workboat";
    if (type >= 40 && type <= 49) return "high-speed craft";
    if (type >= 30 && type <= 39) return "fishing or special craft";
    return "vessel";
}

let socket = null;
let reconnectDelay = 1000;

function connect() {
    socket = new WebSocket("wss://stream.aisstream.io/v0/stream");

    socket.on("open", () => {
        reconnectDelay = 1000;
        socket.send(JSON.stringify({
            APIKey: API_KEY,
            BoundingBoxes: [[[swLat, swLon], [neLat, neLon]]],
            FilterMessageTypes: ["PositionReport", "ShipStaticData"],
        }));
        console.log(`AIS stream connected; watching [${swLat},${swLon}]–[${neLat},${neLon}].`);
    });

    socket.on("message", (raw) => {
        let msg;
        try { msg = JSON.parse(raw.toString()); } catch { return; }
        const meta = msg.MetaData || {};
        const mmsi = meta.MMSI;
        if (!mmsi) return;
        const name = (meta.ShipName || "").trim();

        if (msg.MessageType === "PositionReport") {
            const pr = (msg.Message && msg.Message.PositionReport) || {};
            upsert(mmsi, {
                name: name || undefined,
                lat: pr.Latitude ?? meta.latitude,
                lon: pr.Longitude ?? meta.longitude,
                sog: pr.Sog,   // speed over ground, knots
                cog: pr.Cog,   // course over ground, degrees
            });
        } else if (msg.MessageType === "ShipStaticData") {
            const sd = (msg.Message && msg.Message.ShipStaticData) || {};
            upsert(mmsi, {
                name: (sd.Name || name || "").trim() || undefined,
                type: sd.Type,
                kind: shipKind(sd.Type),
                destination: (sd.Destination || "").trim() || undefined,
            });
        }
    });

    socket.on("close", () => {
        console.warn(`AIS stream closed; reconnecting in ${reconnectDelay}ms.`);
        setTimeout(connect, reconnectDelay);
        reconnectDelay = Math.min(reconnectDelay * 2, 30000);
    });

    socket.on("error", (err) => {
        console.error("AIS stream error:", err.message);
        try { socket.close(); } catch { /* ignore */ }
    });
}

connect();
setInterval(pruneStale, 60000);

const server = http.createServer((req, res) => {
    res.setHeader("Access-Control-Allow-Origin", "*");
    const url = new URL(req.url, "http://localhost");

    if (url.pathname === "/health") {
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ ok: socket && socket.readyState === WebSocket.OPEN, tracked: vessels.size }));
        return;
    }

    if (url.pathname === "/vessels") {
        pruneStale();
        // Only vessels with a known position; named ones first (nicer for narration).
        const list = [...vessels.values()]
            .filter((v) => typeof v.lat === "number" && typeof v.lon === "number")
            .sort((a, b) => (b.name ? 1 : 0) - (a.name ? 1 : 0));
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ updated: Date.now(), count: list.length, vessels: list }));
        return;
    }

    res.writeHead(404, { "Content-Type": "text/plain" });
    res.end("Not found. Try /vessels or /health.");
});

server.listen(PORT, () => console.log(`SKOGARK AIS proxy listening on :${PORT}`));
