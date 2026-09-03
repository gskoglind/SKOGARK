#!/usr/bin/env python3
"""Regenerate ASSET_MANIFEST.md from the actual state of the project.

Scans:
  - SKOGARK/Assets.xcassets   (iOS imagesets, and whether each actually holds a PNG)
  - web/images                (web PNGs)
  - SKOGARK/ContentView.swift and web/app.js (which base names the code references)

Run from the project root after every art import:
    python3 tools/build_asset_manifest.py
"""

import re
import struct
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
XCASSETS = ROOT / "SKOGARK" / "Assets.xcassets"
WEB_IMAGES = ROOT / "web" / "images"
MANIFEST = ROOT / "ASSET_MANIFEST.md"

ORIENTATIONS = ("portrait", "landscape")

# Order matters: first matching prefix wins.
ADVENTURE_GROUPS = [
    ("Explore (village & house)", (
        "bg_west_of_house", "bg_behind_house", "bg_kitchen", "bg_living_room",
        "bg_cellar_", "bg_inn_kitchen", "bg_village_square", "bg_butcher",
        "bg_bakery", "bg_fishmonger",
    )),
    ("Explore — Skógar, Iceland", ("bg_skogar_",)),
    ("Savannah — Riverboat cruise", ("bg_cruise_", "bg_river_dock", "bg_fort_jackson")),
    ("Savannah — Fort Pulaski", ("bg_pulaski_",)),
    ("Japan — Mount Fuji", ("bg_fuji_",)),
    ("Japan — Roppongi", ("bg_roppongi_",)),
    ("London — Greenwich", ("bg_greenwich_",)),
    ("Sydney", ("bg_sydney_",)),
]

# Base names the code assembles at runtime rather than naming literally
# (day/sunset suffixes on the cruise, state variants). A base matching one of
# these regexes counts as referenced even if no literal string mentions it.
DYNAMIC_REFERENCE_PATTERNS = [
    re.compile(r"^bg_cruise_\w+$"),
    re.compile(r"^bg_fort_jackson(_\w+)?$"),
]

# Imagesets that are deliberately not scene pairs. The fishmonger's stray cat
# (memorial — Georgia & Ziggy) is painted into the bg_fishmonger art itself on
# both platforms; the web adds an animated overlay (cat-sprite.js) and iOS has
# an optional, currently-unused hook for one (UIImage(named: "cat")).
KNOWN_NON_SCENES = {
    "cat_sprite": "vestigial empty imageset — iOS cat is painted into bg_fishmonger; safe to delete",
}


def png_size(path: Path):
    """Read width x height from a PNG header without loading the image."""
    with path.open("rb") as f:
        head = f.read(24)
    if len(head) < 24 or head[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    w, h = struct.unpack(">II", head[16:24])
    return w, h


def scan_xcassets():
    """Map imageset name -> path of its PNG, or None if the set is empty."""
    sets = {}
    for d in sorted(XCASSETS.glob("*.imageset")):
        pngs = sorted(d.glob("*.png"))
        sets[d.stem] = pngs[0] if pngs else None
    return sets


def scan_web():
    return {p.stem: p for p in sorted(WEB_IMAGES.glob("*.png"))}


def referenced_bases():
    """Base names literally mentioned in the two UIs."""
    sources = [ROOT / "SKOGARK" / "ContentView.swift", ROOT / "web" / "app.js"]
    found = set()
    for src in sources:
        text = src.read_text()
        found.update(re.findall(r'"(bg_[a-z0-9_]+?)(?:_portrait|_landscape)?"', text))
    return found


def is_referenced(base, literals):
    if base in literals:
        return True
    return any(p.match(base) for p in DYNAMIC_REFERENCE_PATTERNS)


def group_for(base):
    for name, prefixes in ADVENTURE_GROUPS:
        if any(base.startswith(p) for p in prefixes):
            return name
    return "Ungrouped (new — add a prefix to tools/build_asset_manifest.py)"


def main():
    xc = scan_xcassets()
    web = scan_web()
    literals = referenced_bases()

    # Collect every scene base name seen anywhere (strip orientation suffixes).
    bases = set()
    for name in list(xc) + list(web):
        m = re.match(r"(.+?)_(portrait|landscape)$", name)
        if m:
            bases.add(m.group(1))

    # Scenes the code references before any art exists are the pipeline's
    # work orders: they get all-✗ rows and a "Needed art" listing, not drift.
    # A trailing underscore marks a prefix check (hasPrefix/indexOf), not a scene.
    code_only = {b for b in literals if b not in bases and not b.endswith("_")}
    bases |= code_only

    rows_by_group = {}
    drift = []
    needed = []
    spare = []
    notes = []
    dims = {}

    for base in sorted(bases):
        if base in code_only:
            needed.append(f"`{base}` — referenced by code, no art on either platform yet")
            cells = {orient: (False, False) for orient in ORIENTATIONS}
            rows_by_group.setdefault(group_for(base), []).append((base, cells))
            continue
        cells = {}
        for orient in ORIENTATIONS:
            full = f"{base}_{orient}"
            in_xc = xc.get(full)  # path or None; absent key = missing
            in_web = web.get(full)
            cells[orient] = (full in xc and in_xc is not None, in_web is not None)
            if full in xc and in_xc is None:
                drift.append(f"`{full}.imageset` exists in Xcode but contains no PNG")
            elif full not in xc:
                drift.append(f"`{full}` is missing from Assets.xcassets")
            if in_web is None:
                drift.append(f"`{full}.png` is missing from web/images")
            src = in_xc or in_web
            if src:
                dims[full] = png_size(src)
        if not is_referenced(base, literals):
            spare.append(f"`{base}` — art exists on both platforms, no room uses it yet")
        rows_by_group.setdefault(group_for(base), []).append((base, cells))

    for name in xc:
        if re.search(r"_(portrait|landscape)$", name):
            continue
        if name in KNOWN_NON_SCENES:
            notes.append(f"`{name}` — {KNOWN_NON_SCENES[name]}")
        else:
            drift.append(f"imageset `{name}` is not a scene pair or known non-scene — classify it")

    # Canonical dimensions = the most common size per orientation.
    canon = {}
    for orient in ORIENTATIONS:
        sizes = [v for k, v in dims.items() if k.endswith(orient) and v]
        if sizes:
            canon[orient] = max(set(sizes), key=sizes.count)
    for full, size in sorted(dims.items()):
        orient = full.rsplit("_", 1)[1]
        if size and canon.get(orient) and size != canon[orient]:
            drift.append(f"`{full}` is {size[0]}x{size[1]}, expected {canon[orient][0]}x{canon[orient][1]}")

    out = []
    out.append("# SKOGARK Asset Manifest")
    out.append("")
    out.append(f"*Generated {date.today().isoformat()} by `tools/build_asset_manifest.py` — do not edit by hand; rerun the script after every art import.*")
    out.append("")
    out.append("Each scene needs **two PNGs** (`_portrait`, `_landscape`) in **two places** (Xcode `Assets.xcassets`, `web/images/`).")
    canon_txt = ", ".join(f"{o} {s[0]}x{s[1]}" for o, s in canon.items())
    out.append(f"Canonical sizes: {canon_txt}.")
    out.append("")
    out.append(f"**{len(bases)} scenes · {sum(len(v) for v in rows_by_group.values())} rows · {len(drift)} drift item(s) · {len(needed)} scene(s) awaiting art**")
    out.append("")
    out.append("## Drift (fix these)")
    out.append("")
    if drift:
        for d in sorted(set(drift)):
            out.append(f"- {d}")
    else:
        out.append("- None. Both platforms are in sync.")
    out.append("")
    if needed:
        out.append("## Needed art (new scenes — generate these)")
        out.append("")
        out.append("Each needs a portrait and a landscape PNG, imported to both Xcode and web/images. See the scene notes in `ART_BIBLE.md`.")
        out.append("")
        for n in sorted(needed):
            out.append(f"- {n}")
        out.append("")
    if spare:
        out.append("## Spare art (fine — available for future rooms)")
        out.append("")
        for s in sorted(set(spare)):
            out.append(f"- {s}")
        out.append("")
    if notes:
        out.append("## Notes")
        out.append("")
        out.append("- The fishmonger's stray cat (memorial — Georgia & Ziggy) is painted into the `bg_fishmonger` art on both platforms. The web adds an animated overlay (`cat-sprite.js`); iOS has an optional hook (`UIImage(named: \"cat\")`) that is currently unused.")
        for n in sorted(set(notes)):
            out.append(f"- {n}")
        out.append("")
    out.append("## Scenes")
    out.append("")
    out.append("Legend: ✓ present, **✗ MISSING**. Columns are Xcode/web × portrait/landscape.")

    group_order = [g for g, _ in ADVENTURE_GROUPS] + [
        g for g in rows_by_group if g not in {n for n, _ in ADVENTURE_GROUPS}
    ]
    for group in group_order:
        rows = rows_by_group.get(group)
        if not rows:
            continue
        out.append("")
        out.append(f"### {group}")
        out.append("")
        out.append("| Scene | Xcode P | Xcode L | Web P | Web L |")
        out.append("|---|---|---|---|---|")
        for base, cells in rows:
            marks = []
            for orient in ORIENTATIONS:
                x, w = cells[orient]
                marks.append("✓" if x else "**✗**")
                marks.append("✓" if w else "**✗**")
            # reorder: xcode P, xcode L, web P, web L
            xp, wp, xl, wl = marks
            out.append(f"| `{base}` | {xp} | {xl} | {wp} | {wl} |")

    out.append("")

    MANIFEST.write_text("\n".join(out) + "\n")
    print(f"Wrote {MANIFEST} — {len(bases)} scenes, {len(set(drift))} drift item(s), {len(needed)} scene(s) awaiting art")
    for d in sorted(set(drift)):
        print(f"  DRIFT: {d}")
    for n in sorted(needed):
        print(f"  NEEDED: {n}")


if __name__ == "__main__":
    main()
