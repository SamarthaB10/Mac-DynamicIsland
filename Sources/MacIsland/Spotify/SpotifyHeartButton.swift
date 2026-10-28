import AppKit
import SwiftUI

struct SpotifyHeartButton: View {
  @ObservedObject var library: SpotifyLibrary
  let uri: String?
  let compact: Bool
  let prepareSignIn: () -> Void
  let finishedSignIn: () -> Void
  @State private var showingConnection = false

  var body: some View {
    Button {
      if !library.connected {
        prepareSignIn()
        showingConnection = true
      } else if let uri {
        Task { await library.toggle(uri) }
      }
    } label: {
      Image(systemName: library.saved == true ? "heart.fill" : "heart")
        .font(.system(size: compact ? 16 : 18))
        .frame(width: 32, height: compact ? 22 : 28)
    }
    .buttonStyle(.plain)
    .disabled(library.saving || (library.connected && (uri?.hasPrefix("spotify:track:") != true || library.saved == nil)))
    .accessibilityLabel(label).help(label)
    .task(id: "\(uri ?? "")|\(library.connected)") { await library.select(uri) }
    .alert("Spotify library", isPresented: Binding(
      get: { library.error != nil && !showingConnection && !library.connecting },
      set: { if !$0 { library.error = nil } })
    ) { Button("OK") { library.error = nil } }
    message: { Text(library.error ?? "") }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      Task { await library.select(uri) }
    }
    .contextMenu {
      if library.connected {
        Button("Refresh Liked Songs") { Task { await library.select(uri) } }
      }
      Button("Connect Spotify…") { prepareSignIn(); showingConnection = true }
    }
    .sheet(isPresented: $showingConnection, onDismiss: finishedSignIn) {
      SpotifyConnectionView(library: library)
    }
  }

  private var label: String {
    if !library.connected { return "Connect Spotify to like songs" }
    if library.saving { return "Updating Spotify" }
    if uri == nil { return "Play a Spotify song to use Liked Songs" }
    if library.saved == nil { return "Checking Liked Songs" }
    return library.saved == true ? "Remove from Liked Songs" : "Add to Liked Songs"
  }
}

private struct SpotifyConnectionView: View {
  @ObservedObject var library: SpotifyLibrary
  @Environment(\.dismiss) private var dismiss
  @State private var signInTask: Task<Void, Never>?
  @State private var clientID = UserDefaults.standard.string(forKey: "spotifyClientID") ?? ""

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Connect Spotify").font(.headline)
      Text("Allow Mac Island to read and change your Liked Songs.")
      Link("Open Spotify developer dashboard", destination: URL(string: "https://developer.spotify.com/dashboard")!)
      Text("Create an app or use your existing app. Add this return URL:")
      Text(SpotifyLibrary.redirectURI).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
      TextField("Client ID", text: $clientID).textFieldStyle(.roundedBorder)
        .disabled(library.connecting)
      Text("Use the Spotify account that is signed in to the desktop app. No client secret is needed.")
        .font(.caption).foregroundStyle(.secondary)
      if let error = library.error { Text(error).font(.caption).textSelection(.enabled) }
      HStack {
        Button("Cancel") { library.cancelSignIn(); dismiss() }
        Spacer()
        if library.connecting { ProgressView().controlSize(.small) }
        Button(library.connecting ? "Waiting for Spotify…" : "Connect") {
          signInTask = Task {
            if await library.connect(clientID: clientID.trimmingCharacters(in: .whitespacesAndNewlines)) { dismiss() }
          }
        }.disabled(library.connecting || clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }.padding(20).frame(width: 360)
      .onDisappear { signInTask?.cancel(); library.cancelSignIn() }
  }
}
