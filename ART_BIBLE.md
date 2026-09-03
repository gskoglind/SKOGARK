# SKOGARK Art Bible

*This document is the art pipeline's memory. Gary pastes it (plus the current `ASSET_MANIFEST.md`) at the start of any art session with the Claude App, which has no memory between sessions. Read both before generating anything.*

---

## What SKOGARK is

A text-adventure game (iOS + web) that is also a memoir. Every destination is a real place from Gary Skoglind's life — Savannah, Fort Pulaski, Mount Fuji, Roppongi, Greenwich, Sydney — and several characters are real people who know they're in the game (Captain Mike of the Georgia Queen; Ranger Max at Fort Pulaski; the Roppongi bartenders Ryan, Martin, and Matt). Treat real people warmly and with care: friendly cartoon figures, never caricature, no likeness realism required.

One exception to the memoir rule: **Skógar, Iceland** (added September 2026, in the free Explore group) is the village the game is named for, and the one destination Gary hasn't visited — a pilgrimage still to be made rather than a memory. Its art is imagined the same way the adventure is: warmly, from the legend and the landscape, not from photographs of a trip.

The stray cat at the fishmonger's stall is a memorial to Gary's cats, Georgia and Ziggy. It is already painted into the fishmonger scene. If cats appear in future art, they matter — they are never generic decoration.

**V2 destinations in planning (September 2026):** Bermuda (scooters, Bermuda shorts, the Swizzle Inn, Horseshoe Bay), Windsor (the Long Walk, the Crooked House), Lake Powell / Rainbow Bridge (early-1980s day trip by four-seat prop plane), Singapore.

## How the pipeline works

Three parties, one courier:

1. **Xcode Claude** writes the story and code, and decides which scenes exist. It lists needed art in `ASSET_MANIFEST.md` — new scenes appear there as **✗ MISSING** rows with their exact base names.
2. **The Claude App** (you, if you're reading this there) generates the art to this spec.
3. **Gary** carries files between the two. He should never have to explain the spec — this document is the spec.

After delivery, Gary imports each image **twice**: into Xcode's `Assets.xcassets` and into `web/images/`. The manifest script verifies both landed. (Web changes also need a cache-version bump — Xcode Claude handles that.)

## Technical spec (hard requirements)

- **Format:** PNG.
- **Every scene needs exactly two images:**
  - portrait **1080 × 1920**
  - landscape **1920 × 1080**
- **Filenames are exact and final** — they go straight into code:
  `bg_<scene>_portrait.png` and `bg_<scene>_landscape.png`
  (lowercase, underscores, e.g. `bg_swizzle_inn_portrait.png`). Use the base names from the manifest verbatim; never invent or "improve" a name.
- **No words or legible text inside the artwork — except in-world signage in the destination's own language.** Japanese neon in Roppongi is correct (the setting is Japan); a caption or narration line baked into the sky is not. Anything that isn't a sign a person in the scene could read stays shapes-only (see the fish poster in `bg_fishmonger`).
- **State variants** are separate full scenes with a suffix: `_sunset`, `_dark`/`_lit`, `_open`, `_afternoon`, day cycles `_d1`–`_d4`. The manifest names each variant explicitly.
- **Composition:** the portrait and landscape versions of a scene depict the same moment, recomposed — not a crop. Keep key subjects away from the extreme bottom edge (UI chips overlay there on phones).
- **Delivery:** loose PNGs with final filenames, one batch per adventure. No zip archives, no `_to_delete` folders, no renaming left for Gary to do.

## Style guide

*Derived 2026-08-27 by reading the shipped art, not from memory. No Claude session remembers making these images — the recipe below is reconstructed from the files themselves, which are the real source of truth. Show a future session the reference set at the end of this section before it generates anything.*

### Medium

Flat vector. **No outlines anywhere** — never a stroke around a shape. Forms separate by fill colour alone, occasionally by a thin lighter or darker band standing in for mortar, grout or planking. Everything is hard-edged. The only soft edges in the entire system are light glows and cloud tints (see Lighting).

### Geometry and camera

Rectangles, rounded rectangles, circles, simple trapezoids. The camera is always straight-on at roughly standing eye height, stage-like. Depth is implied by a single trapezoid receding to an implied centre vanishing point (the path at Fort Pulaski, the crosswalk at Roppongi) — never true multi-point perspective, never a tilted horizon.

### Composition

Strong horizontal banding: an upper/sky band, a structure band, a ground band. One dominant horizontal — counter, wall base, waterline, horizon — sits around 55-60% down the frame. Subject centred or just off-centre. **The bottom quarter stays deliberately empty** (plain floor, grass, road, deck) because UI chips overlay there. Every shipped scene does this. Keep it.

### Characters

- Head a soft rounded shape, little or no neck. Roughly 3.5-4 heads tall. Chunky, not chibi.
- Face: two solid dark oval eyes — **no whites, no pupils, no eyebrows, no nose** — a thin dark curved mouth line, and two soft blush ovals on the cheeks.
- Hair is one solid shape tucked under any headwear.
- Hands are plain rounded blobs, **no fingers**. Limbs are capsules or plain rectangles.
- Detail scales with distance: mid- and background figures lose the face entirely and become a coloured torso, a skin-tone head shape and a hat.
- Real people (Captain Mike, Ranger Max, June, the Roppongi bartenders) get the same friendly treatment — recognisable by role, clothing and setting, never by facial likeness.

### Colour

Muted, desaturated mid-tones throughout: dusty blues, brick terracotta, sage and olive greens, warm sands and tans, off-whites. **Full saturation is reserved for a few deliberate accents** — the fishmonger’s ginger cat, Roppongi’s neon, a red flag.

Palette is chosen per destination and stays consistent across that destination’s scenes:

- **Savannah riverboat** — warm sand, cream, honey wood, river blue
- **Fort Pulaski** — brick red, grass green, plain sky blue
- **Roppongi** — deep purple-navy night, magenta/cyan/green neon, warm window yellow
- **Mount Fuji** — slate greys and near-black, one warm lit window
- **Explore (house & village)** — cool off-white tile, muted blue, warm brown
- **Skógar, Iceland** — moss and sage green, basalt grey, black sand, glacier-white water, soft grey-blue sky; the one saturated accent is the rainbow at the falls

### Lighting

Flat and ambient by default. **No cast shadows** except a soft elliptical contact shadow directly beneath an object. Where light is part of the story it is a radial glow: a bright soft-edged ellipse over a darkened surround, corners vignetted down (`bg_cellar_lit`, the hut window in `bg_fuji_storm`, the moon at Roppongi).

### State variants

- **`_dark`** — near-total black, only the one essential lit element surviving. `bg_cellar_dark` is black with two cat eyes and nothing else. Be bolder than feels comfortable; most of the frame is genuinely empty.
- **`_lit`** — the same room revealed but still low-key: dark walls, one warm pool of light, vignetted corners.
- **`_sunset`** — identical geometry, palette shifted only. Sky becomes a vertical gradient from purple through magenta and coral to gold at the horizon; water and ground take the sky’s purple; warm interior surfaces cool toward mauve-grey; windows and lamps read as emitting warm yellow. **Nothing moves and nothing is added.** Compare `bg_cruise_river_d2` with `bg_cruise_river_d2_sunset` — the same drawing, recoloured.
- **`_d1`-`_d4`** — day stages on the riverboat: same vantage, shoreline and river traffic advanced, palette unchanged.

### Sky and weather

Flat colour or a simple vertical gradient. Clouds are compound rounded blobs, white by day and tinted at sunset. Sun and moon are plain circles with a soft outer halo. Birds are tiny dark chevrons, used sparingly. Rain is fine diagonal light strokes at one consistent angle across the whole frame.

### Detail density

Low — roughly 5-15 distinct elements per scene. Texture comes from repetition (rows of windows, brick courses, wall tiles, fish laid in ice), never from added fine detail. Large empty areas are correct, not unfinished.

### Portrait vs landscape

Same moment, recomposed — never a crop. The subject stays at a similar size and the surrounding elements are **rearranged** to suit the aspect. Compare `bg_fishmonger_landscape` with `bg_fishmonger_portrait`: the wall shelf and framed fish poster move from flanking the figure to stacking above it, the counter fish redistribute, and the cat shifts inward from the corner.

### Reference set

Show these to any session before it generates anything. Between them they encode every convention above.

| File | What it teaches |
|---|---|
| `bg_fishmonger_landscape` + `bg_fishmonger_portrait` | character style, the cat, the recomposition rule |
| `bg_cruise_river_d2` + `bg_cruise_river_d2_sunset` | the sunset palette shift on identical geometry |
| `bg_cellar_dark` + `bg_cellar_lit` | the dark/lit convention and the light glow |
| `bg_pulaski_fort_landscape` | how minimal an exterior is allowed to be |
| `bg_roppongi_crossing_landscape` | night palette and distant-figure treatment |

### Text in art — ruled on (Gary, Aug 27 2026)

1. `bg_roppongi_crossing`'s signage is **intended and stays**. The setting is Japan; in-world signs in the destination's own language are correct — and ALMOND is the real café at the crossing, the meeting spot of Gary's Tokyo years. The rule in the technical spec now reads accordingly.
2. `bg_fuji_storm` remains a known defect: "ABOVE THE EIGHTH · the mountain turns rough" is a stage caption baked into the sky, not in-world signage. Regenerate it (caption removed, everything else identical) whenever Fuji art is next being made. No urgency.
3. `bg_greenwich_park_lawn` has the same defect (noticed Sep 3 2026, during the Skógar delivery): "GREENWICH PARK · the lawn" is baked into the sky. Same remedy — regenerate caption-free whenever Greenwich art is next being made. No urgency.

## Skógar, Iceland — scene notes (art delivered Sep 3 2026)

Six scenes, no state variants, all sunny (the adventure says so: "today the sun is out"). Bright overcast-Nordic light, no cast shadows as usual. Any signage would be in Icelandic, but none of these scenes needs any. The waterfall, Skógafoss, is a single unbroken white curtain about 60 m tall and 25 m wide with a green cliff wall either side and black sand below — it appears at different distances in four of the six scenes, so keep its shape consistent.

| Scene | What's in it |
|---|---|
| `bg_skogar_bus_stop` | A gravel lay-by at the village edge: a bench, a bus-timetable post, a scatter of small roofs, the green cliff wall behind, and the falls as a distant white ribbon with spray standing above the rooftops. A departing bus may be small in the distance. |
| `bg_skogar_museum` | The folk museum: turf-roofed houses (living grass roofs, backs dug into the hillside) and/or the museum hall interior — a black eight-oared fishing boat, an old wooden church door with a brass ring set in it, a plate of kleinur (twisted diamond-shaped doughnuts) by a coffee urn. The brass ring is the story's relic; give it a place of honour. |
| `bg_skogar_meadow` | A flat green meadow path along the Skógá river, falls ahead mid-distance. One round Icelandic sheep standing dead-centre on the path, facing the viewer. The sheep is this destination's character — friendly, woolly, faintly official. |
| `bg_skogar_falls` | The base of Skógafoss, filling the frame: the white curtain, black sand, drifting spray — and a full double rainbow standing in the mist, one foot on the sand and one in the river. The rainbow is the destination's one saturated accent. A small steel staircase visible climbing the right-hand (eastern) slope. |
| `bg_skogar_stairs` | On the staircase partway up: switchbacking metal steps against the green slope, the falls thundering close on one side, two or three stiff-winged fulmars gliding at eye level. |
| `bg_skogar_platform` | The railed overlook at the lip of the falls: the river arriving from the highlands (a staircase of smaller falls upstream), the water simply stepping off the edge, the plunge pool churning far below, and beyond it the meadow, the village roofs, and a flat silver sea horizon. A tiny wink of gold deep in the pool's foam is welcome — subtle enough to be arguable, exactly as the legend requires. |

As built (delivered Sep 3 2026): the museum scene is the interior hall — the brass ring centred on the church door with a soft warm glow, boat and kleinur flanking, and a window looking out on two turf gables with the falls as a distant ribbon. The platform scene veils the drop in spray rising from the gorge (from the lip the curtain isn't actually visible), with the pool and the gold wink showing above it. Skógafoss keeps the same 2.3:1 curtain silhouette across all four scenes it appears in.

---

*Companion file: `ASSET_MANIFEST.md` — the current state of every asset, regenerated by `tools/build_asset_manifest.py`. This bible says how art is made; the manifest says what exists and what's needed.*
