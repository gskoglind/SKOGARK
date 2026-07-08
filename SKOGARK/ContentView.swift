import SwiftUI

@main struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// A terminal-style front end for the `Game` text-adventure engine.
struct ContentView: View {
    @State private var game = Game()
    @State private var command = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            transcriptView
            Divider()
            inputBar
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
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
