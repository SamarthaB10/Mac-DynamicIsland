import SwiftUI

struct MusicView: View {
  @ObservedObject var media: MediaController
  let showDevices: () -> Void
  @State private var scrub: Double?

  var body: some View {
    VStack(spacing: 12) {
      HStack(spacing: 14) {
        AlbumCover(media: media, size: 60)
        VStack(alignment: .leading, spacing: 5) {
          Button {
            media.openPlayer()
          } label: {
            Text(media.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
              .frame(maxWidth: .infinity, alignment: .leading)
          }.buttonStyle(.plain).help("Open this song in Spotify")
            .accessibilityLabel("Open \(media.title) in Spotify")
          Text(media.artist).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
            .lineLimit(1)
        }
        Spacer(minLength: 0)
        PlayingIndicator(playing: media.playing).frame(width: 24, height: 20)
      }
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
      HStack {
        Button {
          media.openPlayer()
        } label: {
          Image(systemName: "heart").font(.system(size: 18))
        }
        .buttonStyle(.plain).accessibilityLabel("Open Spotify to save this song").help(
          "Save this song in Spotify")
        Spacer()
        playbackButton("backward.end.fill", label: "Previous track", command: "previous track")
        Spacer()
        playbackButton(
          media.playing ? "pause.fill" : "play.fill", label: media.playing ? "Pause" : "Play",
          command: "playpause", prominent: true)
        Spacer()
        playbackButton("forward.end.fill", label: "Next track", command: "next track")
        Spacer()
        Button(action: showDevices) { Image(systemName: "headphones").font(.system(size: 18)) }
          .buttonStyle(.plain).accessibilityLabel("Show audio devices").help("Audio devices")
      }.frame(height: 28)
      if let error = media.error {
        Button {
          media.command()
        } label: {
          Text(error).font(.system(size: 9)).lineLimit(2)
        }
        .buttonStyle(.plain).accessibilityLabel("\(error) Try again")
      }
    }
  }

  private func time(_ seconds: Double) -> String {
    let value = Int(max(0, seconds))
    return "\(value / 60):\(String(format: "%02d", value % 60))"
  }

  private func playbackButton(
    _ symbol: String, label: String, command: String, prominent: Bool = false
  ) -> some View {
    Button {
      media.command(command)
    } label: {
      Image(systemName: symbol).font(.system(size: prominent ? 23 : 20, weight: .semibold))
        .frame(width: 32, height: 28)
    }.buttonStyle(.plain).accessibilityLabel(label).help(label).disabled(media.busy)
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

private struct AnimatedMusicBars: View {
  @State private var moving = false
  private let heights: [CGFloat] = [0.35, 0.8, 0.55, 1, 0.45]

  var body: some View {
    GeometryReader { geometry in
      HStack(spacing: 2) {
        ForEach(0..<5) { index in
          Capsule().fill(.white)
            .frame(
              width: 2,
              height: max(
                2, geometry.size.height * (moving ? heights[index] : 1.1 - heights[index]))
            )
            .animation(
              .easeInOut(duration: 0.42 + Double(index) * 0.06).repeatForever(autoreverses: true),
              value: moving)
        }
      }.frame(width: geometry.size.width, height: geometry.size.height)
    }.onAppear { moving = true }
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
