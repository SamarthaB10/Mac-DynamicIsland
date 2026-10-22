import AppKit
import SwiftUI

@MainActor
final class LockScreenController {
  var enabled = true
  private let media: MediaController
  private var panel: NSPanel?
  private var observers: [NSObjectProtocol] = []

  init(media: MediaController) {
    self.media = media
    let center = DistributedNotificationCenter.default()
    observers.append(
      center.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) {
        [weak self] _ in
        MainActor.assumeIsolated { self?.show(locked: true) }
      })
    observers.append(
      center.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) {
        [weak self] _ in
        MainActor.assumeIsolated { self?.hide() }
      })
  }

  func show(locked: Bool) {
    guard enabled || !locked,
      let screen = NSScreen.screens.first(where: { screen in
        let id =
          (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
          .uint32Value ?? 0
        return CGDisplayIsBuiltin(id) != 0
      })
    else { return }
    if panel == nil {
      let window = NSPanel(
        contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
        defer: false)
      window.isOpaque = false
      window.backgroundColor = .clear
      window.hasShadow = true
      window.hidesOnDeactivate = false
      window.isReleasedWhenClosed = false
      window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
      window.canBecomeVisibleWithoutLogin = true
      let view = LockScreenPlayerView(media: media, dismiss: { [weak self] in self?.hide() })
      let host = NSHostingView(rootView: view.preferredColorScheme(.dark))
      host.sizingOptions = []
      window.contentView = host
      panel = window
    }
    panel?.level =
      locked
      ? NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 1) : .floating
    let size = CGSize(width: 320, height: 400)
    panel?.setFrame(
      NSRect(
        x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2 - 40,
        width: size.width, height: size.height), display: true)
    panel?.orderFrontRegardless()
  }

  func hide() {
    panel?.orderOut(nil)
    panel = nil
  }
}

private struct LockScreenPlayerView: View {
  @ObservedObject var media: MediaController
  let dismiss: () -> Void
  var body: some View {
    VStack(spacing: 12) {
      HStack {
        Text("Spotify").font(.system(size: 11, weight: .medium)).foregroundStyle(
          .white.opacity(0.6))
        Spacer()
        Button(action: dismiss) {
          Image(systemName: "xmark").font(.system(size: 10)).frame(width: 24, height: 24)
        }
        .buttonStyle(.plain).accessibilityLabel("Close lock-screen player")
      }
      AlbumCover(media: media, size: 236)
      Text(media.title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
      Text(media.artist).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
      HStack(spacing: 32) {
        Button {
          media.command("previous track")
        } label: {
          Image(systemName: "backward.end.fill")
        }
        .accessibilityLabel("Previous track")
        Button {
          media.command("playpause")
        } label: {
          Image(systemName: media.playing ? "pause.fill" : "play.fill").font(.system(size: 22))
        }
        .accessibilityLabel(media.playing ? "Pause" : "Play")
        Button {
          media.command("next track")
        } label: {
          Image(systemName: "forward.end.fill")
        }
        .accessibilityLabel("Next track")
      }.buttonStyle(.plain).disabled(media.busy)
    }
    .padding(20).frame(width: 320, height: 400)
    .background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    .foregroundStyle(.white).tint(.white)
  }
}
