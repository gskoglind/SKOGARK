# SKOGARK Asset Manifest

*Generated 2026-08-27 by `tools/build_asset_manifest.py` — do not edit by hand; rerun the script after every art import.*

Each scene needs **two PNGs** (`_portrait`, `_landscape`) in **two places** (Xcode `Assets.xcassets`, `web/images/`).
Canonical sizes: portrait 1080x1920, landscape 1920x1080.

**123 scenes · 123 rows · 0 drift item(s)**

## Drift (fix these)

- None. Both platforms are in sync.

## Spare art (fine — available for future rooms)

- `bg_fuji_descent` — art exists on both platforms, no room uses it yet
- `bg_fuji_komitake` — art exists on both platforms, no room uses it yet
- `bg_sydney_star_city` — art exists on both platforms, no room uses it yet
- `bg_sydney_under_bridge` — art exists on both platforms, no room uses it yet

## Notes

- The fishmonger's stray cat (memorial — Georgia & Ziggy) is painted into the `bg_fishmonger` art on both platforms. The web adds an animated overlay (`cat-sprite.js`); iOS has an optional hook (`UIImage(named: "cat")`) that is currently unused.
- `cat_sprite` — vestigial empty imageset — iOS cat is painted into bg_fishmonger; safe to delete

## Scenes

Legend: ✓ present, **✗ MISSING**. Columns are Xcode/web × portrait/landscape.

### Explore (village & house)

| Scene | Xcode P | Xcode L | Web P | Web L |
|---|---|---|---|---|
| `bg_bakery` | ✓ | ✓ | ✓ | ✓ |
| `bg_behind_house` | ✓ | ✓ | ✓ | ✓ |
| `bg_butcher` | ✓ | ✓ | ✓ | ✓ |
| `bg_cellar_dark` | ✓ | ✓ | ✓ | ✓ |
| `bg_cellar_lit` | ✓ | ✓ | ✓ | ✓ |
| `bg_fishmonger` | ✓ | ✓ | ✓ | ✓ |
| `bg_inn_kitchen` | ✓ | ✓ | ✓ | ✓ |
| `bg_kitchen` | ✓ | ✓ | ✓ | ✓ |
| `bg_living_room` | ✓ | ✓ | ✓ | ✓ |
| `bg_living_room_open` | ✓ | ✓ | ✓ | ✓ |
| `bg_village_square` | ✓ | ✓ | ✓ | ✓ |
| `bg_west_of_house` | ✓ | ✓ | ✓ | ✓ |

### Savannah — Riverboat cruise

| Scene | Xcode P | Xcode L | Web P | Web L |
|---|---|---|---|---|
| `bg_cruise_bridge_d1` | ✓ | ✓ | ✓ | ✓ |
| `bg_cruise_bridge_d1_sunset` | ✓ | ✓ | ✓ | ✓ |
| `bg_cruise_bridge_d2` | ✓ | ✓ | ✓ | ✓ |
| `bg_cruise_bridge_d2_sunset` | ✓ | ✓ | ✓ | ✓ |
| `bg_cruise_bridge_d3` | ✓ | ✓ | ✓ | ✓ |
| `bg_cruise_bridge_d3_sunset` | ✓ | ✓ | ✓ | ✓ |
| `bg_cruise_bridge_d4` | ✓ | ✓ | ✓ | ✓ |
| `bg_cruise_bridge_d4_sunset` | ✓ | ✓ | ✓ | ✓ |
| `bg_cruise_city_d1` | ✓ | ✓ | ✓ | ✓ |
| `bg_cruise_city_d1_sunset` | ✓ | ✓ | ✓ | ✓ |
| `bg_cruise_city_d2` | ✓ | ✓ | ✓ | ✓ |
| `bg_cruise_city_d2_sunset` | ✓ | ✓ | ✓ | ✓ |
| `bg_cruise_city_d3` | ✓ | ✓ | ✓ | ✓ |
| `bg_cruise_city_d3_sunset` | ✓ | ✓ | ✓ | ✓ |
| `bg_cruise_city_d4` | ✓ | ✓ | ✓ | ✓ |
| `bg_cruise_city_d4_sunset` | ✓ | ✓ | ✓ | ✓ |
| `bg_cruise_port_d1` | ✓ | ✓ | ✓ | ✓ |
| `bg_cruise_port_d1_sunset` | ✓ | ✓ | ✓ | ✓ |
| `bg_cruise_port_d2` | ✓ | ✓ | ✓ | ✓ |
| `bg_cruise_port_d2_sunset` | ✓ | ✓ | ✓ | ✓ |
| `bg_cruise_port_d3` | ✓ | ✓ | ✓ | ✓ |
| `bg_cruise_port_d3_sunset` | ✓ | ✓ | ✓ | ✓ |
| `bg_cruise_port_d4` | ✓ | ✓ | ✓ | ✓ |
| `bg_cruise_port_d4_sunset` | ✓ | ✓ | ✓ | ✓ |
| `bg_cruise_river_d1` | ✓ | ✓ | ✓ | ✓ |
| `bg_cruise_river_d1_sunset` | ✓ | ✓ | ✓ | ✓ |
| `bg_cruise_river_d2` | ✓ | ✓ | ✓ | ✓ |
| `bg_cruise_river_d2_sunset` | ✓ | ✓ | ✓ | ✓ |
| `bg_cruise_river_d3` | ✓ | ✓ | ✓ | ✓ |
| `bg_cruise_river_d3_sunset` | ✓ | ✓ | ✓ | ✓ |
| `bg_cruise_river_d4` | ✓ | ✓ | ✓ | ✓ |
| `bg_cruise_river_d4_sunset` | ✓ | ✓ | ✓ | ✓ |
| `bg_cruise_waving_d1` | ✓ | ✓ | ✓ | ✓ |
| `bg_cruise_waving_d1_sunset` | ✓ | ✓ | ✓ | ✓ |
| `bg_cruise_waving_d2` | ✓ | ✓ | ✓ | ✓ |
| `bg_cruise_waving_d2_sunset` | ✓ | ✓ | ✓ | ✓ |
| `bg_cruise_waving_d3` | ✓ | ✓ | ✓ | ✓ |
| `bg_cruise_waving_d3_sunset` | ✓ | ✓ | ✓ | ✓ |
| `bg_cruise_waving_d4` | ✓ | ✓ | ✓ | ✓ |
| `bg_cruise_waving_d4_sunset` | ✓ | ✓ | ✓ | ✓ |
| `bg_fort_jackson` | ✓ | ✓ | ✓ | ✓ |
| `bg_fort_jackson_afternoon` | ✓ | ✓ | ✓ | ✓ |
| `bg_fort_jackson_sunset` | ✓ | ✓ | ✓ | ✓ |
| `bg_river_dock` | ✓ | ✓ | ✓ | ✓ |

### Savannah — Fort Pulaski

| Scene | Xcode P | Xcode L | Web P | Web L |
|---|---|---|---|---|
| `bg_pulaski_battery_hambright` | ✓ | ✓ | ✓ | ✓ |
| `bg_pulaski_casemates` | ✓ | ✓ | ✓ | ✓ |
| `bg_pulaski_drawbridge` | ✓ | ✓ | ✓ | ✓ |
| `bg_pulaski_fort` | ✓ | ✓ | ✓ | ✓ |
| `bg_pulaski_gate` | ✓ | ✓ | ✓ | ✓ |
| `bg_pulaski_lighthouse_deck` | ✓ | ✓ | ✓ | ✓ |
| `bg_pulaski_moat_walk` | ✓ | ✓ | ✓ | ✓ |
| `bg_pulaski_north_pier` | ✓ | ✓ | ✓ | ✓ |
| `bg_pulaski_prison` | ✓ | ✓ | ✓ | ✓ |
| `bg_pulaski_quarters` | ✓ | ✓ | ✓ | ✓ |
| `bg_pulaski_scarred_wall` | ✓ | ✓ | ✓ | ✓ |
| `bg_pulaski_terreplein` | ✓ | ✓ | ✓ | ✓ |
| `bg_pulaski_trail_1` | ✓ | ✓ | ✓ | ✓ |
| `bg_pulaski_trail_2` | ✓ | ✓ | ✓ | ✓ |
| `bg_pulaski_trail_3` | ✓ | ✓ | ✓ | ✓ |
| `bg_pulaski_visitor_center` | ✓ | ✓ | ✓ | ✓ |

### Japan — Mount Fuji

| Scene | Xcode P | Xcode L | Web P | Web L |
|---|---|---|---|---|
| `bg_fuji_crater_rim` | ✓ | ✓ | ✓ | ✓ |
| `bg_fuji_descent` | ✓ | ✓ | ✓ | ✓ |
| `bg_fuji_eighth_hut` | ✓ | ✓ | ✓ | ✓ |
| `bg_fuji_fifth_station` | ✓ | ✓ | ✓ | ✓ |
| `bg_fuji_kengamine` | ✓ | ✓ | ✓ | ✓ |
| `bg_fuji_komitake` | ✓ | ✓ | ✓ | ✓ |
| `bg_fuji_ninth_dark` | ✓ | ✓ | ✓ | ✓ |
| `bg_fuji_ninth_lit` | ✓ | ✓ | ✓ | ✓ |
| `bg_fuji_post_office` | ✓ | ✓ | ✓ | ✓ |
| `bg_fuji_seventh_hut` | ✓ | ✓ | ✓ | ✓ |
| `bg_fuji_sixth_station` | ✓ | ✓ | ✓ | ✓ |
| `bg_fuji_storm` | ✓ | ✓ | ✓ | ✓ |
| `bg_fuji_summit` | ✓ | ✓ | ✓ | ✓ |
| `bg_fuji_summit_clouded` | ✓ | ✓ | ✓ | ✓ |

### Japan — Roppongi

| Scene | Xcode P | Xcode L | Web P | Web L |
|---|---|---|---|---|
| `bg_roppongi_crossing` | ✓ | ✓ | ✓ | ✓ |
| `bg_roppongi_fare_adjustment` | ✓ | ✓ | ✓ | ✓ |
| `bg_roppongi_first_train` | ✓ | ✓ | ✓ | ✓ |
| `bg_roppongi_geronimos` | ✓ | ✓ | ✓ | ✓ |
| `bg_roppongi_home_station` | ✓ | ✓ | ✓ | ✓ |
| `bg_roppongi_missed_stop` | ✓ | ✓ | ✓ | ✓ |
| `bg_roppongi_mogambos` | ✓ | ✓ | ✓ | ✓ |
| `bg_roppongi_quest` | ✓ | ✓ | ✓ | ✓ |
| `bg_roppongi_ramenya` | ✓ | ✓ | ✓ | ✓ |
| `bg_roppongi_side_street` | ✓ | ✓ | ✓ | ✓ |
| `bg_roppongi_station` | ✓ | ✓ | ✓ | ✓ |
| `bg_roppongi_ticket_machine` | ✓ | ✓ | ✓ | ✓ |
| `bg_roppongi_train_interior` | ✓ | ✓ | ✓ | ✓ |
| `bg_roppongi_transfer` | ✓ | ✓ | ✓ | ✓ |

### London — Greenwich

| Scene | Xcode P | Xcode L | Web P | Web L |
|---|---|---|---|---|
| `bg_greenwich_avenue` | ✓ | ✓ | ✓ | ✓ |
| `bg_greenwich_blackheath` | ✓ | ✓ | ✓ | ✓ |
| `bg_greenwich_cutty_sark` | ✓ | ✓ | ✓ | ✓ |
| `bg_greenwich_dlr_station` | ✓ | ✓ | ✓ | ✓ |
| `bg_greenwich_museum` | ✓ | ✓ | ✓ | ✓ |
| `bg_greenwich_observatory` | ✓ | ✓ | ✓ | ✓ |
| `bg_greenwich_park_lawn` | ✓ | ✓ | ✓ | ✓ |
| `bg_greenwich_viewpoint` | ✓ | ✓ | ✓ | ✓ |

### Sydney

| Scene | Xcode P | Xcode L | Web P | Web L |
|---|---|---|---|---|
| `bg_sydney_balmoral` | ✓ | ✓ | ✓ | ✓ |
| `bg_sydney_beach` | ✓ | ✓ | ✓ | ✓ |
| `bg_sydney_corso` | ✓ | ✓ | ✓ | ✓ |
| `bg_sydney_gardens` | ✓ | ✓ | ✓ | ✓ |
| `bg_sydney_heads` | ✓ | ✓ | ✓ | ✓ |
| `bg_sydney_manly_deck` | ✓ | ✓ | ✓ | ✓ |
| `bg_sydney_manly_wharf` | ✓ | ✓ | ✓ | ✓ |
| `bg_sydney_nb_deck` | ✓ | ✓ | ✓ | ✓ |
| `bg_sydney_nb_wharf` | ✓ | ✓ | ✓ | ✓ |
| `bg_sydney_oaks` | ✓ | ✓ | ✓ | ✓ |
| `bg_sydney_quay` | ✓ | ✓ | ✓ | ✓ |
| `bg_sydney_quay_dusk` | ✓ | ✓ | ✓ | ✓ |
| `bg_sydney_return_deck` | ✓ | ✓ | ✓ | ✓ |
| `bg_sydney_star_city` | ✓ | ✓ | ✓ | ✓ |
| `bg_sydney_under_bridge` | ✓ | ✓ | ✓ | ✓ |

