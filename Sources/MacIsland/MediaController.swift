import AppKit
import ImageIO

@MainActor
final class MediaController: ObservableObject {
  @Published private(set) var title = "Nothing playing"
  @Published private(set) var artist = "Play a song in Spotify."
  @Published private(set) var playing = false
  @Published private(set) var hasTrack = false
  @Published private(set) var busy = false
  @Published private(set) var error: String?
  @Published private(set) var artwork: NSImage?
  @Published private(set) var duration: Double = 0
  private var position: Double = 0
  private var positionDate = Date()
  private let artworkSession: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    return URLSession(configuration: configuration)
  }()
  private var artworkURL: URL?
  private var artworkTask: Task<Void, Never>?
  private var refreshAgain = false
  private var observers: [NSObjectProtocol] = []
  nonisolated private static let bundleID = "com.spotify.client"

  init() {
    observers.append(
      DistributedNotificationCenter.default().addObserver(
        forName: Notification.Name("com.spotify.client.PlaybackStateChanged"), object: nil,
        queue: .main
      ) { [weak self] notification in
        MainActor.assumeIsolated {
          guard let self, let info = notification.userInfo else { return }
          let nextTitle = info["Name"] as? String ?? "Nothing playing"
          if self.title != nextTitle {
            self.artworkTask?.cancel()
            self.artworkURL = nil
            self.artwork = nil
          }
          self.title = nextTitle
          self.artist = info["Artist"] as? String ?? "Spotify"
          self.playing = info["Player State"] as? String == "Playing"
          self.hasTrack = info["Name"] != nil
          self.command()
        }
      })
    observers.append(
      NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
      ) { [weak self] notification in
        guard
          let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
            as? NSRunningApplication,
          app.bundleIdentifier == Self.bundleID
        else { return }
        MainActor.assumeIsolated { self?.clear() }
      })
  }

  private func clear() {
    title = "Nothing playing"
    artist = "Play a song in Spotify."
    playing = false
    hasTrack = false
    artwork = nil
    artworkURL = nil
    artworkTask?.cancel()
    duration = 0
  }

  func refreshRunningPlayer() {
    if NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first != nil {
      command()
    }
  }

  func openPlayer() {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else {
      error = "Spotify is not installed."
      return
    }
    NSWorkspace.shared.openApplication(at: url, configuration: .init())
  }

  func elapsed(at date: Date) -> Double {
    min(duration, max(0, position + (playing ? date.timeIntervalSince(positionDate) : 0)))
  }

  func seek(to seconds: Double) {
    let value = min(duration, max(0, seconds))
    command("set player position to \(value)")
  }

  func command(_ action: String? = nil) {
    if busy {
      if action == nil { refreshAgain = true }
      return
    }
    guard NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first != nil
    else {
      error = "Open Spotify first."
      return
    }
    busy = true
    error = nil
    let script = """
      tell application id "com.spotify.client"
          \(action ?? "")
          if player state is stopped then return "stopped"
          set separator to ASCII character 31
          return (player state as text) & separator & (name of current track) & separator & (artist of current track) & separator & (artwork url of current track) & separator & (player position as text) & separator & (duration of current track as text)
      end tell
      """
    Task {
      let output = await Task.detached(priority: .userInitiated) { Self.runScript(script) }.value
      busy = false
      if let output {
        let fields = output.components(separatedBy: "\u{1f}")
        if fields.count >= 6 {
          title = fields[1]
          artist = fields[2]
          playing = fields[0].lowercased() == "playing"
          hasTrack = true
          position = Double(fields[4]) ?? 0
          duration = (Double(fields[5]) ?? 0) / 1000
          positionDate = Date()
          loadArtwork(URL(string: fields[3]))
        } else {
          clear()
        }
      } else {
        error = "Allow Spotify access in System Settings > Privacy & Security > Automation."
      }
      if refreshAgain {
        refreshAgain = false
        command()
      }
    }
  }

  private func loadArtwork(_ url: URL?) {
    guard let url, url.scheme == "https", url != artworkURL || artwork == nil else { return }
    artworkTask?.cancel()
    artworkURL = url
    artworkTask = Task {
      var request = URLRequest(url: url)
      request.timeoutInterval = 15
      guard let (data, response) = try? await artworkSession.data(for: request),
        !Task.isCancelled, artworkURL == url,
        (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 5_000_000,
        let source = CGImageSourceCreateWithData(data as CFData, nil),
        let image = CGImageSourceCreateThumbnailAtIndex(
          source, 0,
          [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 512,
            kCGImageSourceCreateThumbnailWithTransform: true,
          ] as CFDictionary)
      else { return }
      artwork = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
  }

  nonisolated private static func runScript(_ script: String) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", script]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
      let data = output.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else { return nil }
      return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    } catch { return nil }
  }
}
