import SwiftUI
import UIKit
import AVFoundation
import WebKit

@main struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// Top-level flow: pick a scenario, then play it. Selecting "Menu" from a
/// game returns here to choose again.
struct ContentView: View {
    @State private var game: Game? = nil

    var body: some View {
        Group {
            if let game {
                GameView(game: game, onExitToMenu: { self.game = nil })
            } else {
                MenuView(onSelect: { scenario in
                    self.game = Game(scenario: scenario)
                })
            }
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
    }
}

/// The two-step chooser: pick a destination, then one of its adventures.
struct MenuView: View {
    let onSelect: (Scenario) -> Void
    @State private var destination: String? = nil

    /// Destinations in the order their scenarios are registered.
    private var destinations: [String] {
        var seen: [String] = []
        for scenario in Game.scenarios where !seen.contains(scenario.destination) {
            seen.append(scenario.destination)
        }
        return seen
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Text("SKOGARK")
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                    .foregroundStyle(.green)
                Text(destination ?? "Tiny text adventures. Where to?")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(Color(white: 0.6))
            }

            VStack(spacing: 14) {
                if let destination {
                    ForEach(Game.scenarios.filter { $0.destination == destination }) { scenario in
                        Button { onSelect(scenario) } label: {
                            scenarioCard(scenario)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("scenario:\(scenario.id)")
                    }
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { self.destination = nil }
                    } label: {
                        Label("All destinations", systemImage: "chevron.left")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                } else {
                    ForEach(destinations, id: \.self) { name in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { destination = name }
                        } label: {
                            destinationCard(name)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("destination:\(name)")
                    }
                }
            }
            .frame(maxWidth: 480)
            .padding(.horizontal)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    /// A destination card: its name over a slice of that destination's art.
    private func destinationCard(_ name: String) -> some View {
        let count = Game.scenarios.filter { $0.destination == name }.count
        return ZStack(alignment: .bottomLeading) {
            if let asset = Self.destinationArt(name), let image = UIImage(named: asset) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 110)
                    .clipped()
                    .overlay(LinearGradient(colors: [.clear, .black.opacity(0.75)],
                                            startPoint: .top, endPoint: .bottom))
            } else {
                Color(white: 0.10).frame(height: 110)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.green)
                Text(count == 1 ? "1 adventure" : "\(count) adventures")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Color(white: 0.8))
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // The scaledToFill art overflows the card frame; .clipShape trims the
        // drawing but NOT hit testing, so without this the invisible overflow
        // swallows taps meant for the neighbouring cards.
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(white: 0.25), lineWidth: 1)
        )
    }

    private func scenarioCard(_ scenario: Scenario) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(scenario.title)
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .foregroundStyle(.green)
            Text(scenario.blurb)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Color(white: 0.7))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(white: 0.10), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(white: 0.25), lineWidth: 1)
        )
    }

    /// The artwork slice behind each destination card (landscape variants).
    static func destinationArt(_ name: String) -> String? {
        switch name {
        case "Explore":  return "bg_west_of_house_landscape"
        case "Savannah": return "bg_pulaski_terreplein_landscape"
        case "Japan":    return "bg_fuji_summit_landscape"
        case "London":   return "bg_greenwich_viewpoint_landscape"
        case "Sydney":   return "bg_sydney_gardens_landscape"
        default:         return nil
        }
    }
}

/// A terminal-style front end for a single `Game`.
struct GameView: View {
    let game: Game
    let onExitToMenu: () -> Void

    @State private var command = ""
    @FocusState private var inputFocused: Bool

    // Spoken narration. Captain Mike's narration and room descriptions are read
    // aloud; command echoes are never spoken. The toggle is remembered.
    @AppStorage("skogark.voice") private var voiceOn = true
    @State private var narrator = Narrator()
    @State private var spokenCount = 0

    // Live webcams (riverboat only).
    @State private var showCams = false

    private var isRiverboat: Bool { game.scenario.id == "riverboat" }

    // Transient "you have arrived" location card.
    @State private var flashTitle: String?
    @State private var flashOpacity: Double = 0
    @State private var flashTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            scenePane
            Divider()
            transcriptView
            Divider()
            actionBar
            Divider()
            inputBar
        }
        .background(Color.black)
        .onAppear { flashLocation(game.roomTitle); speakPending() }
        .onChange(of: game.roomID) { flashLocation(game.roomTitle) }
        .onChange(of: game.transcript.count) { speakPending() }
        .onDisappear { narrator.stop() }
        .sheet(isPresented: $showCams) {
            CamsView(initialSlug: Self.camSlug(for: game.roomID))
        }
    }

    /// The SavannahCams webcam that best matches the boat's current leg.
    static func camSlug(for roomID: String) -> String {
        if roomID == "fortJackson" { return "fort-jackson" }
        if roomID.hasPrefix("bridge") { return "talmadge-bridge" }
        if roomID.hasPrefix("port") { return "pilots-dock" }
        return "river-street-east" // River Street leg (and the dock)
    }

    /// Speaks any transcript entries added since the last check (skipping the
    /// player's own typed commands). The counter always advances, so toggling
    /// the voice on later doesn't replay a backlog.
    private func speakPending() {
        let entries = game.transcript
        guard spokenCount < entries.count else { return }
        let fresh = entries[spokenCount..<entries.count]
        spokenCount = entries.count
        guard voiceOn else { return }
        // The cannon salute at Old Fort Jackson gets an audible boom.
        if fresh.contains(where: { !$0.isCommand && $0.text.contains("BOOOM!") }) {
            SoundEffects.shared.cannonBoom()
        }
        let text = fresh.filter { !$0.isCommand }.map(\.text).joined(separator: "\n")
        narrator.speak(text)
    }

    /// A location name that fades in when the player arrives somewhere new,
    /// lingers briefly, then fades out. Purely decorative, so it ignores taps.
    private var locationFlash: some View {
        Group {
            if let flashTitle {
                Text(flashTitle)
                    .font(.system(.title2, design: .monospaced).weight(.bold))
                    .foregroundStyle(.green)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(.black.opacity(0.6), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.green.opacity(0.5), lineWidth: 1))
                    .opacity(flashOpacity)
            }
        }
        .padding(.top, 12)
        .allowsHitTesting(false)
    }

    /// Shows the arrival card for `title`, cancelling any card still on screen
    /// so rapid movement doesn't stack overlapping animations.
    private func flashLocation(_ title: String) {
        guard !title.isEmpty else { return }
        flashTask?.cancel()
        flashTitle = title
        flashTask = Task { @MainActor in
            withAnimation(.easeIn(duration: 0.25)) { flashOpacity = 1 }
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.6)) { flashOpacity = 0 }
        }
    }

    /// Location artwork in a fixed pane above the transcript, so the commentary
    /// scrolls below the image rather than over it. The device's full-screen
    /// orientation picks the art variant; rooms without art show plain black,
    /// and moving between rooms cross-fades the image.
    private var scenePane: some View {
        GeometryReader { geo in
            // Pick the art variant that best fills the pane's own shape (the
            // pane is usually wider than tall, so landscape art is the norm).
            let orientation = geo.size.width > geo.size.height ? "landscape" : "portrait"
            let assetName = backgroundImageBaseName(for: game.roomID)
                .map { "\($0)_\(orientation)" }
            ZStack {
                Color.black
                if let assetName, let image = UIImage(named: assetName) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .transition(.opacity)
                        .id(assetName)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .containerRelativeFrame(.vertical) { length, _ in length * 0.60 }
        .overlay(alignment: .bottomTrailing) { catSprite }
        .overlay(alignment: .top) { locationFlash }
        // The pane is purely decorative, and the scaledToFill artwork overflows
        // its frame — .clipped() trims the drawing but NOT hit testing, so
        // without this the invisible overflow swallows taps on the title bar
        // (the Menu/Hint/Voice buttons). Mirrors the web pane's
        // pointer-events: none.
        .allowsHitTesting(false)
        // Animate whenever the room OR its lit state changes, so lighting the
        // lantern in the cellar cross-fades from dark to the egg-lit view.
        .animation(.easeInOut(duration: 0.4), value: sceneKey)
    }

    /// A change key covering every bit of state that can swap the backdrop —
    /// room, lit state (cellar), and whether the rug has been moved (living
    /// room) — so each transition cross-fades.
    private var sceneKey: String {
        "\(game.roomID)-\(game.canSeeRoom)-\(game.has(flag: "rugMoved"))-\(game.has(flag: "cruise_sunset"))-\(game.has(flag: "cruise_afternoon"))-\(game.has(flag: "ateRamen"))-\(game.has(flag: "weatherReady"))"
    }

    /// The stray cat that loiters at the fishmonger's stall, hoping for a
    /// scrap. It sits in the bottom-right of the scene pane, on top of the
    /// artwork. Supply the transparent-background "cat" image (a cat.imageset)
    /// to light it up.
    private var catSprite: some View {
        Group {
            if game.roomID == "townFish", let cat = UIImage(named: "cat") {
                Image(uiImage: cat)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 140)
                    .padding(.trailing, 16)
                    .padding(.bottom, 8)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.4), value: game.roomID)
    }

    /// Maps a room to the base name of its artwork, factoring in state: the
    /// cellar is dark until a lit lantern is present, and the living room shows
    /// the trap door once the rug is moved. The orientation suffix
    /// ("_landscape" / "_portrait") is appended at display time, so add both
    /// variants (e.g. "bg_fishmonger_landscape" and "bg_fishmonger_portrait")
    /// to Assets.xcassets. Any room not listed here shows a black background.
    private func backgroundImageBaseName(for roomID: String) -> String? {
        let base = dayBackgroundBaseName(for: roomID)
        // The 7:00 Sunset Cruise swaps in warm dusk art for every on-board room
        // (all four decks across the five legs, plus Old Fort Jackson): no
        // narration, and a DJ throws a party up on the open-air top deck. The
        // River Street dock keeps its daytime look — you pick the sailing before
        // boarding, so the sunset flag isn't set there yet.
        if let base, game.has(flag: "cruise_sunset"),
           base.hasPrefix("bg_cruise_") || base == "bg_fort_jackson" {
            return base + "_sunset"
        }
        // The 3:30 Afternoon cruise matches the 1:00 Cannon cruise everywhere
        // except at the fort, where no salute is fired.
        if base == "bg_fort_jackson", game.has(flag: "cruise_afternoon") {
            return "bg_fort_jackson_afternoon"
        }
        return base
    }

    private func dayBackgroundBaseName(for roomID: String) -> String? {
        switch roomID {
        case "innKitchen":  return "bg_inn_kitchen"
        case "square":      return "bg_village_square"
        case "townButcher": return "bg_butcher"
        case "townBakery":  return "bg_bakery"
        case "townFish":    return "bg_fishmonger"
        case "westOfHouse": return "bg_west_of_house"
        case "behindHouse": return "bg_behind_house"
        case "kitchen":     return "bg_kitchen"
        case "livingRoom":  return game.has(flag: "rugMoved") ? "bg_living_room_open" : "bg_living_room"
        case "cellar":      return game.canSeeRoom ? "bg_cellar_lit" : "bg_cellar_dark"
        // Savannah River cruise — a sightseeing tour down the river past the
        // River Street riverfront. The dock, then four decks across five legs,
        // and the finale at Old Fort Jackson (where the 1pm Cannon Cruise fires
        // its salute). See the bg_cruise_* / bg_river_dock / bg_fort_jackson
        // imagesets (each with _landscape and _portrait variants).
        case "riverStreet": return "bg_river_dock"
        case "riverD1":     return "bg_cruise_river_d1"
        case "riverD2":     return "bg_cruise_river_d2"
        case "riverD3":     return "bg_cruise_river_d3"
        case "riverD4":     return "bg_cruise_river_d4"
        case "portD1":      return "bg_cruise_port_d1"
        case "portD2":      return "bg_cruise_port_d2"
        case "portD3":      return "bg_cruise_port_d3"
        case "portD4":      return "bg_cruise_port_d4"
        case "bridgeD1":    return "bg_cruise_bridge_d1"
        case "bridgeD2":    return "bg_cruise_bridge_d2"
        case "bridgeD3":    return "bg_cruise_bridge_d3"
        case "bridgeD4":    return "bg_cruise_bridge_d4"
        case "cityD1":      return "bg_cruise_city_d1"
        case "cityD2":      return "bg_cruise_city_d2"
        case "cityD3":      return "bg_cruise_city_d3"
        case "cityD4":      return "bg_cruise_city_d4"
        case "wavingD1":    return "bg_cruise_waving_d1"
        case "wavingD2":    return "bg_cruise_waving_d2"
        case "wavingD3":    return "bg_cruise_waving_d3"
        case "wavingD4":    return "bg_cruise_waving_d4"
        case "fortJackson": return "bg_fort_jackson"
        // Fort Pulaski National Monument — drive in through the gates, check in
        // at the visitor center, walk out past Battery Hambright to the North
        // Pier, and follow the Lighthouse Overlook Trail to the Cockspur Island
        // Lighthouse. (The fort interior is a placeholder for now.)
        case "gate":             return "bg_pulaski_gate"
        case "visitorCenter":    return "bg_pulaski_visitor_center"
        case "fort":             return "bg_pulaski_fort"
        case "drawbridge":       return "bg_pulaski_drawbridge"
        case "casemates":        return "bg_pulaski_casemates"
        case "prison":           return "bg_pulaski_prison"
        case "quarters":         return "bg_pulaski_quarters"
        case "terreplein":       return "bg_pulaski_terreplein"
        case "moatWalk":         return "bg_pulaski_moat_walk"
        case "scarredWall":      return "bg_pulaski_scarred_wall"
        case "batteryHambright": return "bg_pulaski_battery_hambright"
        case "northPier":        return "bg_pulaski_north_pier"
        case "trail1":           return "bg_pulaski_trail_1"
        case "trail2":           return "bg_pulaski_trail_2"
        case "trail3":           return "bg_pulaski_trail_3"
        case "trail4":           return "bg_pulaski_lighthouse_deck"
        // Roppongi Pub Crawl — up from the Hibiya Line into the neon crossing,
        // the three bars of the classic crawl, and the dawn ramen stand.
        // Once the ramen is eaten, the 05:12 first train waits at the platform.
        case "roppongiStation": return game.has(flag: "ateRamen") ? "bg_roppongi_first_train" : "bg_roppongi_station"
        case "crossing":        return "bg_roppongi_crossing"
        case "geronimos":       return "bg_roppongi_geronimos"
        case "sideStreet":      return "bg_roppongi_side_street"
        case "mogambos":        return "bg_roppongi_mogambos"
        case "quest":           return "bg_roppongi_quest"
        case "ramenya":         return "bg_roppongi_ramenya"
        case "ticketMachine":   return "bg_roppongi_ticket_machine"
        case "trainCar":        return "bg_roppongi_train_interior"
        case "transferStation": return "bg_roppongi_transfer"
        case "homeStation":     return "bg_roppongi_home_station"
        case "wrongTerminus":   return "bg_roppongi_missed_stop"
        case "fareAdjust":      return "bg_roppongi_fare_adjustment"
        // Mount Fuji — the Yoshida Trail night climb from the Fifth Station to
        // the summit. The ninth station is dark until the headlamp is lit, so
        // it swaps between dark and lamplit art like the cellar.
        case "fifthStation":  return "bg_fuji_fifth_station"
        case "sixthStation":  return "bg_fuji_sixth_station"
        case "seventhHut":    return "bg_fuji_seventh_hut"
        // On a rain or cold-wind night, Taishikan sits in the storm until the
        // climber shelters, and the summit's goraiko breaks through clouds.
        case "eighthHut":
            let badWeather = game.has(flag: "weatherRain") || game.has(flag: "weatherCold")
            return badWeather && !game.has(flag: "weatherReady") ? "bg_fuji_storm" : "bg_fuji_eighth_hut"
        case "ninthStation":  return game.canSeeRoom ? "bg_fuji_ninth_lit" : "bg_fuji_ninth_dark"
        case "summit":
            return game.has(flag: "weatherRain") || game.has(flag: "weatherCold")
                ? "bg_fuji_summit_clouded" : "bg_fuji_summit"
        case "postOffice":    return "bg_fuji_post_office"
        case "craterRim":     return "bg_fuji_crater_rim"
        case "kengamine":     return "bg_fuji_kengamine"
        // Sydney Harbour — a day on the ferries from Circular Quay to The Oaks.
        // The Quay goes gold once the sunset run has brought you back.
        case "circularQuay":  return game.has(flag: "sunsetReturn") ? "bg_sydney_quay_dusk" : "bg_sydney_quay"
        case "manlyDeck":     return "bg_sydney_manly_deck"
        case "theHeads":      return "bg_sydney_heads"
        case "manlyWharf":    return "bg_sydney_manly_wharf"
        case "corso":         return "bg_sydney_corso"
        case "manlyBeach":    return "bg_sydney_beach"
        case "returnDeck":    return "bg_sydney_return_deck"
        case "balmoralBeach": return "bg_sydney_balmoral"
        case "darlingDeck":   return "bg_sydney_under_bridge"
        case "starCity":      return "bg_sydney_star_city"
        case "nbDeck":        return "bg_sydney_nb_deck"
        case "nbWharf":       return "bg_sydney_nb_wharf"
        case "oaksPub":       return "bg_sydney_oaks"
        // Greenwich Park — the commute-home detour, from the DLR to Blackheath.
        case "dlrStation":     return "bg_greenwich_dlr_station"
        case "cuttySark":      return "bg_greenwich_cutty_sark"
        case "maritimeMuseum": return "bg_greenwich_museum"
        case "parkLawn":       return "bg_greenwich_park_lawn"
        case "chestnutAvenue": return "bg_greenwich_avenue"
        case "observatory":    return "bg_greenwich_observatory"
        case "wolfeViewpoint": return "bg_greenwich_viewpoint"
        case "blackheath":     return "bg_greenwich_blackheath"
        default:            return nil
        }
    }

    // MARK: Tap-action chips (a hybrid layer over the parser)

    /// One tap-action chip: a label and the command it feeds the parser.
    private struct Chip: Identifiable {
        enum Style { case move, act, give, look, util }
        let id = UUID()
        let label: String
        let cmd: String
        let style: Style
    }

    /// One-tap "special" interactions keyed by item id, for verbs the parser
    /// routes to the object handler. Mirrors the web app's table.
    private static let specialByID: [String: (label: String, cmd: String)] = [
        "bellGeronimos": ("🔔 Ring the bell", "ring bell"),
        "bellMogambos": ("🔔 Ring the bell", "ring bell"),
        "bellQuest": ("🔔 Ring the bell", "ring bell"),
        "dartboard": ("🎯 Throw darts", "throw darts"),
        "jukebox": ("🎵 Jukebox", "play jukebox"),
        "fareMachine": ("Settle the fare", "push machine"),
        "meridian": ("Straddle the line", "straddle line"),
        "rug": ("Move the rug", "move rug"),
        "cannonCruise": ("⚓ Board the Cannon Cruise", "board cannon"),
        "afternoonCruise": ("⚓ Board the Afternoon Cruise", "board afternoon"),
        "sunsetCruise": ("⚓ Board the Sunset Cruise", "board sunset"),
        "manlyFerry": ("⛴ Board the Manly ferry", "board manly"),
        "balmoralFerry": ("⛴ Board the Balmoral ferry", "board balmoral"),
        "casinoFerry": ("⛴ Board the casino ferry", "board casino"),
        "nbFerry": ("⛴ Ferry home to Neutral Bay", "board neutral"),
        "returnFerry": ("⛴ Ferry back to the Quay", "board return"),
        "bus": ("🚌 Bus up to The Oaks", "board bus"),
        "crapsTable": ("🎲 Craps — $100 on the pass line", "play craps"),
    ]
    /// Carried items with a natural one-tap verb, keyed by item KIND —
    /// bought copies get minted ids like "beer#0", so ids won't match.
    private static let invSpecialByKind: [String: (label: String, cmd: String)] = [
        "beer": ("Drink the beer", "drink beer"),
        "chips": ("🍟 Eat the fish and chips", "eat chips"),
        "schooner": ("🍺 Drink the schooner", "drink schooner"),
    ]

    /// The chips for the current turn, rebuilt from room state on every
    /// engine change (the view recomputes whenever the game mutates).
    private var chips: [Chip] {
        if game.isWon { return [Chip(label: "↺ Play again", cmd: "restart", style: .util)] }
        var chips: [Chip] = []
        let dark = !game.canSeeRoom

        // Movement — labelled with the destination room's name. Hidden in
        // the dark so unlit rooms don't leak the map.
        if !dark {
            for exit in game.obviousExitsWithTitles() {
                chips.append(Chip(label: "→ \(exit.title)", cmd: exit.direction.rawValue, style: .move))
            }
        }

        // Actions on what's in the room (skipped in the dark).
        var sawSeat = false
        let roomItemIDs = game.currentRoomItemIDs
        if !dark {
            for id in roomItemIDs {
                guard let item = game.item(id) else { continue }
                let noun = item.nouns.first ?? item.name
                if let special = Self.specialByID[id] {
                    chips.append(Chip(label: special.label, cmd: special.cmd, style: .act))
                } else if item.isCreature {
                    chips.append(Chip(label: "💬 Talk to \(item.name)", cmd: "talk to \(noun)", style: .act))
                } else if item.forSale {
                    chips.append(Chip(label: "Buy \(item.name) · \(item.price)", cmd: "buy \(noun)", style: .act))
                } else if item.isTakeable {
                    chips.append(Chip(label: "Take \(item.name)", cmd: "take \(noun)", style: .act))
                } else if item.kind == "seat" {
                    sawSeat = true
                } else if item.isFixture {
                    chips.append(Chip(label: "Look at \(item.name)", cmd: "examine \(noun)", style: .look))
                }
                if item.readText != nil {
                    chips.append(Chip(label: "Read \(item.name)", cmd: "read \(noun)", style: .look))
                }
                // Doors, windows, and containers — required in the house.
                if item.isOpenable {
                    chips.append(Chip(label: "\(item.isOpen ? "Close" : "Open") \(item.name)",
                                      cmd: "\(item.isOpen ? "close" : "open") \(noun)", style: .act))
                }
            }
            // Put a carried item into any open container in the room
            // (the trophy case, the summit postbox); the engine validates.
            for contID in roomItemIDs {
                guard let cont = game.item(contID), cont.isContainer, cont.isOpen else { continue }
                let cnoun = cont.nouns.first ?? cont.name
                for carriedID in game.carriedItemIDs {
                    guard let carried = game.item(carriedID) else { continue }
                    let gnoun = carried.nouns.first ?? carried.name
                    chips.append(Chip(label: "Put \(carried.name) → \(cont.name)",
                                      cmd: "put \(gnoun) in \(cnoun)", style: .give))
                }
            }
            // Give any carried item to any creature present; the engine validates.
            let creatures = roomItemIDs.compactMap { game.item($0) }.filter(\.isCreature)
            if !creatures.isEmpty {
                for carriedID in game.carriedItemIDs {
                    guard let carried = game.item(carriedID) else { continue }
                    let gnoun = carried.nouns.first ?? carried.name
                    for creature in creatures {
                        let cnoun = creature.nouns.first ?? creature.name
                        chips.append(Chip(label: "Give \(carried.name) → \(creature.name)",
                                          cmd: "give \(gnoun) to \(cnoun)", style: .give))
                    }
                }
            }
        }

        // Carried one-tap verbs (e.g. drink the beer at the viewpoint).
        for id in game.carriedItemIDs {
            if let kind = game.item(id)?.kind, let special = Self.invSpecialByKind[kind] {
                chips.append(Chip(label: special.label, cmd: special.cmd, style: .act))
            }
        }
        // Light sources, carried or in the room — shown even in the dark:
        // turning the lamp on is exactly what a dark room needs.
        for id in game.carriedItemIDs + roomItemIDs {
            guard let item = game.item(id), item.isLightSource else { continue }
            chips.append(Chip(label: "\(item.isLit ? "Turn off" : "🔦 Turn on") \(item.name)",
                              cmd: "turn \(item.isLit ? "off" : "on")", style: .act))
        }
        if sawSeat { chips.append(Chip(label: "Sit", cmd: "sit", style: .act)) }

        // Utility, quietly at the end.
        chips.append(Chip(label: "👁 Look", cmd: "look", style: .util))
        chips.append(Chip(label: "🎒 Items", cmd: "inventory", style: .util))
        return chips
    }

    private func chipColor(_ style: Chip.Style) -> Color {
        switch style {
        case .move: return .green
        case .give: return Color(red: 0.96, green: 0.76, blue: 0.47)
        case .util: return Color(white: 0.6)
        case .act, .look: return Color(white: 0.9)
        }
    }

    /// A horizontally scrollable row of one-tap commands, built fresh from
    /// room state each turn. Typing still works exactly as before.
    private var actionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    Button {
                        game.process(chip.cmd)
                    } label: {
                        Text(chip.label)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(chipColor(chip.style))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(white: 0.11), in: Capsule())
                            .overlay(Capsule().strokeBorder(chipColor(chip.style).opacity(0.35), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("chip:\(chip.cmd)")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(Color.black)
    }

    private var titleBar: some View {
        HStack {
            Button(action: onExitToMenu) {
                Label("Menu", systemImage: "chevron.left")
                    .font(.system(.subheadline, design: .monospaced))
            }
            .foregroundStyle(.green)
            Spacer()
            Text(game.scenario.title)
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .foregroundStyle(Color(white: 0.7))
            Button {
                narrator.stop()
                game.process("hint")
                inputFocused = true
            } label: {
                Image(systemName: "lightbulb.fill").font(.subheadline)
            }
            .foregroundStyle(.yellow)
            .padding(.leading, 12)
            .accessibilityLabel("Hint")
            Button {
                voiceOn.toggle()
                if !voiceOn { narrator.stop() }
            } label: {
                Image(systemName: voiceOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.subheadline)
            }
            .foregroundStyle(voiceOn ? .green : Color(white: 0.5))
            .padding(.leading, 12)
            .accessibilityLabel(voiceOn ? "Mute narration" : "Unmute narration")

            if isRiverboat {
                Button { showCams = true } label: {
                    Image(systemName: "video.fill").font(.subheadline)
                }
                .foregroundStyle(.green)
                .padding(.leading, 12)
                .accessibilityLabel("Live webcams")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.55))
    }

    private var transcriptView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(game.transcript) { entry in
                        Text(entry.text)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(entry.isCommand ? Color.green : Color(white: 0.9))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .id(entry.id)
                    }
                }
                .padding()
            }
            // Anchor to the bottom so the newest text stays visible when the
            // container shrinks — e.g. the software keyboard appearing in iPad
            // landscape, or a device rotation — not just when content is added.
            .defaultScrollAnchor(.bottom)
            .onChange(of: game.transcript.count) {
                if let last = game.transcript.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            Text(">")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.green)
            TextField("What do you do?", text: $command)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.green)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($inputFocused)
                .onSubmit(submit)
            Button("Go", action: submit)
                .buttonStyle(.borderedProminent)
                .disabled(command.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
        .background(Color.black.opacity(0.55))
        .onAppear { inputFocused = true }
    }

    private func submit() {
        let entered = command
        command = ""
        narrator.stop() // cut off any narration still playing from the last turn
        game.process(entered)
        inputFocused = true
    }
}

/// Reads game narration aloud using the system speech synthesizer. Decorative
/// rule lines (the banner's ─────) and blank lines are dropped so the utterance
/// sounds like prose.
final class Narrator {
    private let synthesizer = AVSpeechSynthesizer()

    /// Captain Mike's voice: the most natural-sounding male American voice
    /// installed, chosen once. Voices are ranked premium > enhanced > default
    /// quality (downloadable in Settings > Accessibility > Spoken Content), a
    /// male voice preferred at the best available quality. Stays American
    /// throughout — falls back to any en-US voice, then the default en-US
    /// voice, so the narrator never picks up a non-American accent.
    private static let voice: AVSpeechSynthesisVoice? = {
        let american = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == "en-US" }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
        return american.first(where: { $0.gender == .male })
            ?? american.first
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }()

    func speak(_ text: String) {
        let say = Narrator.speakable(text)
        guard !say.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: say)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 0.95 // a touch lower for Captain Mike
        utterance.voice = Narrator.voice
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    private static let decorative = Set(" ─—-=_\t")

    private static func speakable(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.isEmpty && !trimmed.allSatisfy { decorative.contains($0) }
            }
            .joined(separator: ". ")
    }
}

// MARK: - Sound Effects

/// Synthesizes short sound effects in code, so no audio-file assets are needed.
/// Currently just the cannon salute at Old Fort Jackson.
final class SoundEffects {
    static let shared = SoundEffects()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private let boom: AVAudioPCMBuffer?

    private init() {
        boom = SoundEffects.makeBoom(format: format)
        engine.attach(player)
        try? engine.connectNode(player, to: engine.mainMixerNode, format: format)
    }

    /// Plays a deep cannon boom. Best-effort: silently does nothing if the audio
    /// engine can't start.
    func cannonBoom() {
        guard let boom else { return }
        player.scheduleBuffer(boom, at: nil, options: .interrupts, completionHandler: nil)
        do {
            if !engine.isRunning { try engine.start() }
            try player.playAudio()
        } catch {
            return
        }
    }

    /// Builds a ~0.9s boom: a low sine sweeping downward for the thump plus
    /// heavily lowpassed white noise for the crack, both under a fast-attack
    /// exponential decay.
    private static func makeBoom(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let duration = 0.9
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frameCount

        let twoPi = 2.0 * Double.pi
        var phase = 0.0
        var lpNoise = 0.0
        for i in 0..<Int(frameCount) {
            let progress = Double(i) / Double(frameCount)
            let env = (1.0 - progress) * (1.0 - progress) // exponential-ish decay
            let freq = 90.0 - 60.0 * progress             // 90 Hz -> 30 Hz sweep
            phase += twoPi * freq / sampleRate
            let tone = sin(phase)
            let white = Double.random(in: -1.0...1.0)
            lpNoise += 0.06 * (white - lpNoise)           // one-pole lowpass
            let sample = (tone * 0.8 + lpNoise * 0.6) * env
            channel[i] = Float(max(-1.0, min(1.0, sample)))
        }
        return buffer
    }
}

// MARK: - Live Webcams

/// A minimal WKWebView wrapper for embedding a live webcam page.
struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
    }
}

/// The SavannahCams live webcams along the river, embedded in a sheet with a
/// picker. Opens on the camera matching the boat's current leg.
struct CamsView: View {
    let initialSlug: String
    @Environment(\.dismiss) private var dismiss
    @State private var slug: String

    static let base = "https://www.savannahcams.com/streams/cam_"
    static let cams: [(slug: String, label: String)] = [
        ("river-street-east", "River Street East (the riverboat!)"),
        ("river-street-west", "River Street West"),
        ("pilots-dock", "Savannah Pilots Dock"),
        ("savannah-yacht-facility", "Savannah Yacht Facility"),
        ("talmadge-bridge", "Talmadge Bridge"),
        ("fort-jackson", "Old Fort Jackson"),
        ("elba-island", "Elba Island"),
    ]

    init(initialSlug: String) {
        self.initialSlug = initialSlug
        _slug = State(initialValue: initialSlug)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let url = URL(string: Self.base + slug + ".html") {
                    WebView(url: url)
                }
                Text("Live webcams courtesy of SavannahCams.com")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
            .navigationTitle("River Cams")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Picker("Camera", selection: $slug) {
                        ForEach(Self.cams, id: \.slug) { cam in
                            Text(cam.label).tag(cam.slug)
                        }
                    }
                    .pickerStyle(.menu)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}


#Preview {
    ContentView()
}

#Preview("Game — Fort Pulaski") {
    GameView(game: Game(scenario: Game.fortPulaskiScenario()), onExitToMenu: {})
        .preferredColorScheme(.dark)
}
