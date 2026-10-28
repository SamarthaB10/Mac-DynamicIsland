import QuartzCore
import SwiftUI

struct MusicView: View {
  @ObservedObject var media: MediaController
  @Binding var artworkFocused: Bool
  let showDevices: () -> Void
  let prepareSignIn: () -> Void
  let finishedSignIn: () -> Void
  @State private var scrub: Double?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var artworkTransition

  private var visibleError: String? {
    guard let error = media.error, error != "Open Spotify first." else { return nil }
    return error
  }

  var body: some View {
    VStack(spacing: artworkFocused ? 8 : 12) {
      if artworkFocused {
        cover(size: 128)
          .frame(maxWidth: .infinity)
          .overlay(alignment: .trailing) {
            VStack(spacing: 4) {
              previousButton
              playPauseButton
              nextButton
              saveButton
              devicesButton
            }
          }
        songDetails(centered: true)
      } else {
        HStack(spacing: 14) {
          cover(size: 60)
          songDetails(centered: false)
          Spacer(minLength: 0)
          PlayingIndicator(playing: media.playing).frame(width: 24, height: 20)
        }
      }
      progress
      if !artworkFocused {
        HStack {
          saveButton
          Spacer()
          previousButton
          Spacer()
          playPauseButton
          Spacer()
          nextButton
          Spacer()
          devicesButton
        }.frame(height: 28)
        if !media.hasTrack {
          Button { media.openPlayer() } label: {
            SpotifyMark().frame(width: 14, height: 14).frame(width: 28, height: 20)
          }.buttonStyle(.plain).accessibilityLabel("Open Spotify").help("Open Spotify")
        }
      }
      if let error = visibleError {
        Button { media.command() } label: {
          Text(error).font(.system(size: 9)).lineLimit(2)
        }.buttonStyle(.plain).accessibilityLabel("\(error) Try again")
      }
    }

  }

  private func cover(size: CGFloat) -> some View {
    Button {
      withAnimation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.86)) {
        artworkFocused.toggle()
      }
    } label: {
      AlbumCover(media: media, size: size)
        .matchedGeometryEffect(id: "cover", in: artworkTransition)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(artworkFocused ? "Show standard music layout" : "Show large album cover")
    .help(artworkFocused ? "Show standard music layout" : "Show large album cover")
  }

  private func songDetails(centered: Bool) -> some View {
    VStack(alignment: centered ? .center : .leading, spacing: 5) {
      Button { media.openPlayer() } label: {
        Text(media.title).font(.system(size: artworkFocused ? 13 : 15, weight: .semibold)).lineLimit(1)
          .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
      }.buttonStyle(.plain).help("Open this song in Spotify")
        .accessibilityLabel("Open \(media.title) in Spotify")
      Text(media.artist).font(.system(size: artworkFocused ? 11 : 12)).foregroundStyle(.white.opacity(0.55))
        .lineLimit(1)
    }
  }

  private var progress: some View {
    TimelineView(.animation(minimumInterval: 1, paused: !media.playing)) { context in
      let elapsed = scrub ?? media.elapsed(at: context.date)
      HStack(spacing: 7) {
        Text(time(elapsed)).frame(width: 29, alignment: .leading)
        SongProgress(
          value: elapsed, duration: media.duration, enabled: media.hasTrack && !media.busy,
          changed: { scrub = $0 },
          committed: {
            media.seek(to: $0)
            scrub = nil
          })
        Text("−\(time(max(0, media.duration - elapsed)))").frame(width: 34, alignment: .trailing)
      }.font(.system(size: 10).monospacedDigit()).foregroundStyle(.white.opacity(0.45))
    }
  }

  private var previousButton: some View {
    playbackButton("backward.end.fill", label: "Previous track", command: "previous track")
  }

  private var playPauseButton: some View {
    playbackButton(
      media.playing ? "pause.fill" : "play.fill", label: media.playing ? "Pause" : "Play",
      command: "playpause", prominent: true)
  }

  private var nextButton: some View {
    playbackButton("forward.end.fill", label: "Next track", command: "next track")
  }

  private var saveButton: some View {
    SpotifyHeartButton(
      library: media.library, uri: media.trackURI, compact: artworkFocused,
      prepareSignIn: prepareSignIn, finishedSignIn: finishedSignIn)
  }

  private var devicesButton: some View {
    Button(action: showDevices) {
      Image(systemName: "headphones").font(.system(size: artworkFocused ? 16 : 18)).frame(width: 32, height: artworkFocused ? 22 : 28)
    }.buttonStyle(IslandIconButtonStyle()).accessibilityLabel("Show audio devices").help("Audio devices")
  }

  private func time(_ seconds: Double) -> String {
    let value = Int(max(0, seconds))
    return "\(value / 60):\(String(format: "%02d", value % 60))"
  }

  private func playbackButton(
    _ symbol: String, label: String, command: String, prominent: Bool = false
  ) -> some View {
    Button { media.command(command) } label: {
      Image(systemName: symbol).font(.system(size: artworkFocused ? (prominent ? 20 : 16) : (prominent ? 23 : 20), weight: .semibold))
        .frame(width: 32, height: artworkFocused ? 22 : 28)
    }.buttonStyle(IslandIconButtonStyle()).accessibilityLabel(label).help(label).disabled(media.busy)
  }
}

private struct SpotifyMark: View {
  var body: some View {
    GeometryReader { geometry in
      let size = geometry.size.width
      ZStack {
        Circle().fill(.white)
        Path { path in
          for row in 0..<3 {
            let y = size * (0.34 + CGFloat(row) * 0.19)
            let inset = size * (0.22 + CGFloat(row) * 0.025)
            path.move(to: CGPoint(x: inset, y: y))
            path.addQuadCurve(
              to: CGPoint(x: size - inset, y: y + size * 0.055),
              control: CGPoint(x: size * 0.52, y: y - size * 0.12))
          }
        }.stroke(.black, style: StrokeStyle(lineWidth: size * 0.075, lineCap: .round))
      }
    }
  }
}

struct AlbumCover: View {
  @ObservedObject var media: MediaController
  let size: CGFloat

  var body: some View {
    Group {
      if let artwork = media.artwork {
        Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
      } else {
        Image(systemName: "music.note").font(.system(size: size * 0.38))
          .frame(width: size, height: size).background(.white.opacity(0.1))
      }
    }
    .frame(width: size, height: size).clipped()
    .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
    .accessibilityLabel(media.artwork == nil ? "Album cover unavailable" : "Album cover")
  }
}

struct PlayingIndicator: View {
  let playing: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Group {
      if playing && !reduceMotion {
        AnimatedMusicBars()
      } else {
        Image(systemName: playing ? "waveform" : "pause.fill").font(.system(size: 11))
      }
    }.accessibilityLabel(playing ? "Music is playing" : "Music is paused")
  }
}

private struct AnimatedMusicBars: NSViewRepresentable {
  func makeNSView(context: Context) -> MusicBarsView { MusicBarsView() }
  func updateNSView(_ view: MusicBarsView, context: Context) {}
}

private final class MusicBarsView: NSView {
  private var bars: [CALayer] = []

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    for _ in 0..<5 {
      let bar = CALayer()
      bar.backgroundColor = NSColor.white.cgColor
      bar.cornerRadius = 1
      layer?.addSublayer(bar)
      bars.append(bar)
    }
  }

  required init?(coder: NSCoder) { nil }

  override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for (index, bar) in bars.enumerated() {
      bar.bounds = CGRect(x: 0, y: 0, width: 2, height: bounds.height)
      bar.position = CGPoint(x: bounds.midX - 8 + CGFloat(index) * 4, y: bounds.midY)
    }
    CATransaction.commit()
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    for (index, bar) in bars.enumerated() {
      bar.removeAllAnimations()
      guard window != nil else { continue }
      // Core Animation runs these bars without invalidating the SwiftUI view each frame.
      let animation = CABasicAnimation(keyPath: "transform.scale.y")
      animation.fromValue = 0.2
      animation.toValue = 0.95
      animation.duration = 0.3 + Double(index) * 0.07
      animation.autoreverses = true
      animation.repeatCount = .infinity
      animation.timeOffset = Double(index) * 0.11
      animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      bar.add(animation, forKey: "playback")
    }
  }
}

private struct SongProgress: View {
  let value: Double
  let duration: Double
  let enabled: Bool
  let changed: (Double) -> Void
  let committed: (Double) -> Void
  @State private var dragging = false
  var body: some View {
    GeometryReader { geometry in
      let fraction = min(1, max(0, value / max(1, duration)))
      ZStack(alignment: .leading) {
        Capsule().fill(.white.opacity(0.1))
        Capsule().fill(.white.opacity(0.48)).frame(width: geometry.size.width * fraction)
        if dragging {
          Circle().fill(.white).frame(width: 8, height: 8)
            .offset(x: max(0, geometry.size.width * fraction - 4))
        }
      }
      .frame(height: dragging ? 6 : 5)
      .frame(height: geometry.size.height)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { event in
            guard enabled else { return }
            dragging = true
            changed(min(1, max(0, event.location.x / geometry.size.width)) * duration)
          }
          .onEnded { event in
            guard enabled else { return }
            dragging = false
            committed(min(1, max(0, event.location.x / geometry.size.width)) * duration)
          })
    }
    .frame(height: 14)
    .focusable(enabled)
    .onMoveCommand { direction in
      guard enabled else { return }
      if direction == .left { committed(max(0, value - 5)) }
      if direction == .right { committed(min(duration, value + 5)) }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Song position")
    .accessibilityValue("\(Int(value)) of \(Int(duration)) seconds")
    .accessibilityAdjustableAction { direction in
      guard enabled else { return }
      committed(min(duration, max(0, value + (direction == .increment ? 5 : -5))))
    }
  }
}
