import SwiftUI
import UIKit

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

    // Transient "you have arrived" location card.
    @State private var flashTitle: String?
    @State private var flashOpacity: Double = 0
    @State private var flashTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            transcriptView
            Divider()
            inputBar
        }
        .background(backgroundView)
        .overlay(alignment: .bottomTrailing) { catSprite }
        .overlay(alignment: .top) { locationFlash }
        .onAppear { flashLocation(game.roomTitle) }
        .onChange(of: game.roomID) { flashLocation(game.roomTitle) }
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

    /// Full-bleed location artwork behind the terminal, with a dark gradient
    /// scrim so the monospaced text stays legible. Rooms without art fall back
    /// to plain black, and moving between rooms cross-fades the image.
    private var backgroundView: some View {
        GeometryReader { geo in
            // Compare width vs height rather than size class: on iPad both
            // orientations are .regular, so size class can't tell them apart.
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
                    LinearGradient(
                        colors: [.black.opacity(0.35), .black.opacity(0.75)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        // Animate whenever the room OR its lit state changes, so lighting the
        // lantern in the cellar cross-fades from dark to the egg-lit view.
        .animation(.easeInOut(duration: 0.4), value: sceneKey)
    }

    /// A change key covering every bit of state that can swap the backdrop —
    /// room, lit state (cellar), and whether the rug has been moved (living
    /// room) — so each transition cross-fades.
    private var sceneKey: String {
        "\(game.roomID)-\(game.canSeeRoom)-\(game.has(flag: "rugMoved"))"
    }

    /// The stray cat that loiters at the fishmonger's stall, hoping for a
    /// scrap. It lives on the content layer (not the full-bleed background) so it
    /// stays above the software keyboard — in iPad landscape especially — and
    /// sits just above the input row. Supply the transparent-background "cat"
    /// image (a cat.imageset) to light it up.
    private var catSprite: some View {
        Group {
            if game.roomID == "townFish", let cat = UIImage(named: "cat") {
                Image(uiImage: cat)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 170)
                    .padding(.trailing, 20)
                    .padding(.bottom, 72)
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
        game.process(entered)
        inputFocused = true
    }
}

#Preview {
    ContentView()
}
