import SwiftUI

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

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            transcriptView
            Divider()
            inputBar
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
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.black)
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
        .background(Color.black)
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
