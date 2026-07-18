import SwiftUI
import UIKit
import AVFoundation
import WebKit
import MapKit

/// Configuration for the optional live-ship map. Set `vesselAPIBase` to the URL
/// of your deployed AIS proxy (see server/README.md) to enable the in-app map
/// and Captain Mike naming a real nearby ship. Leave it `nil` to hide those.
enum RiverboatConfig {
    static let vesselAPIBase: String? = nil
}

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

/// The scenario chooser.
struct MenuView: View {
    let onSelect: (Scenario) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Text("SKOGARK")
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                    .foregroundStyle(.green)
                Text("A tiny text adventure")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(Color(white: 0.6))
            }

            VStack(spacing: 14) {
                ForEach(Game.scenarios) { scenario in
                    Button {
                        onSelect(scenario)
                    } label: {
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
                    .buttonStyle(.plain)
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

    // Live webcams / ship map (riverboat only).
    @State private var showCams = false
    @State private var showShips = false
    @State private var announcedShipMMSIs: Set<Int> = []
    @State private var lastShipLeg: String? = nil

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
            inputBar
        }
        .background(Color.black)
        .onAppear { flashLocation(game.roomTitle); speakPending() }
        .onChange(of: game.roomID) { flashLocation(game.roomTitle); announceShipIfNeeded() }
        .onChange(of: game.transcript.count) { speakPending() }
        .onDisappear { narrator.stop() }
        .sheet(isPresented: $showCams) {
            CamsView(initialSlug: Self.camSlug(for: game.roomID))
        }
        .sheet(isPresented: $showShips) {
            if let base = RiverboatConfig.vesselAPIBase {
                ShipMapView(apiBase: base)
            }
        }
    }

    /// The SavannahCams webcam that best matches the boat's current leg.
    static func camSlug(for roomID: String) -> String {
        if roomID == "fortJackson" { return "fort-jackson" }
        if roomID.hasPrefix("bridge") { return "talmadge-bridge" }
        if roomID.hasPrefix("port") { return "pilots-dock" }
        return "river-street-east" // River Street leg (and the dock)
    }

    /// As the boat passes the working river, Captain Mike names a real ship out
    /// there right now (best-effort; needs a configured proxy, ignores errors).
    /// A cruise leg id, e.g. "riverD4" -> "river" (the dock and fort have none).
    private func legOf(_ roomID: String) -> String {
        if let r = roomID.range(of: "D[0-9]+$", options: .regularExpression) {
            return String(roomID[..<r.lowerBound])
        }
        return roomID
    }

    /// Announces a different real nearby ship once per cruise leg (needs the
    /// AIS proxy; silent otherwise, and network errors are ignored).
    private func announceShipIfNeeded() {
        guard let base = RiverboatConfig.vesselAPIBase, isRiverboat,
              let url = URL(string: base + "/vessels") else { return }
        let legs: Set<String> = ["river", "port", "bridge", "city", "waving"]
        let leg = legOf(game.roomID)
        guard legs.contains(leg), leg != lastShipLeg else { return }
        lastShipLeg = leg
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let resp = try? JSONDecoder().decode(VesselResponse.self, from: data) else { return }
            await MainActor.run {
                guard let ship = resp.vessels.first(where: {
                    !($0.name ?? "").isEmpty && !announcedShipMMSIs.contains($0.mmsi)
                }) else { return }
                announcedShipMMSIs.insert(ship.mmsi)
                game.emit("Captain Mike: \"Off to the side, the \(ship.name!) — a \(ship.kind ?? "vessel") on the river with us.\"")
            }
        }
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
        // Animate whenever the room OR its lit state changes, so lighting the
        // lantern in the cellar cross-fades from dark to the egg-lit view.
        .animation(.easeInOut(duration: 0.4), value: sceneKey)
    }

    /// A change key covering every bit of state that can swap the backdrop —
    /// room, lit state (cellar), and whether the rug has been moved (living
    /// room) — so each transition cross-fades.
    private var sceneKey: String {
        "\(game.roomID)-\(game.canSeeRoom)-\(game.has(flag: "rugMoved"))-\(game.has(flag: "cruise_sunset"))-\(game.has(flag: "cruise_afternoon"))"
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
        case "batteryHambright": return "bg_pulaski_battery_hambright"
        case "northPier":        return "bg_pulaski_north_pier"
        case "trail1":           return "bg_pulaski_trail_1"
        case "trail2":           return "bg_pulaski_trail_2"
        case "trail3":           return "bg_pulaski_trail_3"
        case "trail4":           return "bg_pulaski_lighthouse_deck"
        default:            return nil
        }
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

                if RiverboatConfig.vesselAPIBase != nil {
                    Button { showShips = true } label: {
                        Image(systemName: "map.fill").font(.subheadline)
                    }
                    .foregroundStyle(.green)
                    .padding(.leading, 12)
                    .accessibilityLabel("Live ship map")
                }
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

    /// Captain Mike's voice: a male American voice, chosen once. Stays American
    /// throughout — falls back to any en-US voice, then the default en-US voice,
    /// so the narrator never picks up a non-American accent.
    private static let voice: AVSpeechSynthesisVoice? = {
        let american = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "en-US" }
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

// MARK: - Live Ship Map

/// One vessel from the AIS proxy's /vessels feed.
struct Vessel: Identifiable, Decodable {
    let mmsi: Int
    let name: String?
    let lat: Double
    let lon: Double
    let sog: Double?
    let kind: String?

    var id: Int { mmsi }
    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
}

struct VesselResponse: Decodable {
    let vessels: [Vessel]
}

/// A live map of vessels on the Savannah River, polled from the AIS proxy.
struct ShipMapView: View {
    let apiBase: String
    @Environment(\.dismiss) private var dismiss
    @State private var vessels: [Vessel] = []
    @State private var status = "Loading live ship positions…"

    private static let savannah = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 32.083, longitude: -81.09),
            span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
        )
    )

    var body: some View {
        NavigationStack {
            Map(initialPosition: Self.savannah) {
                ForEach(vessels) { vessel in
                    Marker(vessel.name ?? "Vessel", systemImage: "ferry.fill", coordinate: vessel.coordinate)
                        .tint(.green)
                }
            }
            .overlay(alignment: .bottom) {
                Text(status)
                    .font(.footnote)
                    .padding(8)
                    .background(.black.opacity(0.6), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(.bottom, 12)
            }
            .navigationTitle("Ships on the River")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await pollLoop() }
        }
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            await fetchOnce()
            try? await Task.sleep(for: .seconds(30))
        }
    }

    private func fetchOnce() async {
        guard let url = URL(string: apiBase + "/vessels") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let resp = try JSONDecoder().decode(VesselResponse.self, from: data)
            vessels = resp.vessels
            status = "\(resp.vessels.count) vessel\(resp.vessels.count == 1 ? "" : "s") nearby · updated just now"
        } catch {
            status = "Couldn't reach the ship feed."
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
