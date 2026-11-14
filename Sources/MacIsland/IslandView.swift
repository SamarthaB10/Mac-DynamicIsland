import AppKit
import SwiftUI

struct IslandView: View {
  @ObservedObject var model: IslandModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var selection
  @State private var contentExpanded = false
  @State private var moreOpen = false

  private var motion: Animation? {
    reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.86)
  }

  var body: some View {
    ZStack(alignment: .top) {
      ZStack(alignment: .top) {
        if contentExpanded {
          expandedContent
            .frame(width: model.contentSize.width, height: model.contentSize.height)
            .padding(.top, max(0, model.notchHeight - 6))
            .allowsHitTesting(model.expanded)
            .accessibilityHidden(!model.expanded)
            .transition(.opacity)
            .transaction { $0.animation = reduceMotion ? nil : .easeOut(duration: 0.14) }
        } else {
          CompactIslandView(
            media: model.media, audio: model.audio, activities: model.activities, notice: model.connectionNotice,
            notchWidth: model.notchWidth,
            open: { model.tab = .music; model.openForKeyboard?() },
            openActivity: { _ in model.tab = .activities; model.expand() }
          )
          .frame(width: model.compactSize.width, height: model.compactSize.height)
          .allowsHitTesting(!model.expanded)
          .accessibilityHidden(model.expanded)
          .transition(.opacity)
          .transaction { $0.animation = reduceMotion ? nil : .easeOut(duration: 0.12) }
        }
      }
      .frame(width: model.panelSize.width, height: model.panelSize.height, alignment: .top)
      .background(.black)
      .clipShape(RoundedRectangle(cornerRadius: model.expanded ? 40 : 18, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: model.expanded ? 40 : 18, style: .continuous)
          .strokeBorder(.white.opacity(model.dropTargeted ? 0.7 : 0.15), lineWidth: model.dropTargeted ? 2 : 0.5)
          .allowsHitTesting(false)
      }
      .offset(x: model.visible ? 0 : 80)
      .opacity(model.visible ? 1 : 0)
      .animation(motion, value: model.visible)
      .shadow(color: .black.opacity(0.42), radius: 12, y: 8)
      .animation(motion, value: model.expanded)
      .animation(motion, value: model.musicArtworkFocused)
      .animation(motion, value: model.tab)
      .animation(motion, value: model.connectionNotice)
      .padding(.top, IslandModel.canvasInset)
    }
    .frame(width: model.canvasSize.width, height: model.canvasSize.height, alignment: .top)
    .foregroundStyle(.white)
    .tint(.white)
    .font(.system(size: 12))
    .onExitCommand { model.collapse(force: true) }
    .task(id: model.expanded) {
      let expanded = model.expanded
      if expanded && !reduceMotion {
        try? await Task.sleep(for: .milliseconds(90))
      }
      guard !Task.isCancelled else { return }
      withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) { contentExpanded = expanded }
    }
    .onChange(of: reduceMotion) { _, _ in contentExpanded = model.expanded }
  }

  private var expandedContent: some View {
    VStack(spacing: 10) {
      ZStack {
        Group {
          switch model.tab {
          case .music:
            MusicView(
              media: model.media, artworkFocused: $model.musicArtworkFocused,
              showDevices: { model.tab = .devices },
              prepareSignIn: { model.connectingSpotify = true; model.openForKeyboard?() },
              finishedSignIn: { model.connectingSpotify = false; model.openForKeyboard?() })
          case .files: HubView(model: model)
          case .devices: DevicesView(audio: model.audio)
          case .activities:
            VStack(spacing: 8) {
              HStack(spacing: 8) {
                AlbumCover(media: model.media, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                  Text(model.media.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                  Text(model.media.artist).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                PlayingIndicator(playing: model.media.playing).frame(width: 24, height: 20)
              }
              ActivityListView(activities: model.activities, open: model.openActivity)
            }
          }
        }
        .id(model.tab)
        .transition(reduceMotion ? .identity : .opacity)
      }.frame(maxWidth: .infinity, maxHeight: .infinity)
      HStack(spacing: 3) {
        navigationTabs
        Spacer(minLength: 2)
        islandControls
      }.frame(height: 28)
    }
    .padding(16)
  }
  private var islandControls: some View {
    Group {
      Button { moreOpen.toggle() } label: {
        Image(systemName: "ellipsis.circle").frame(width: 28, height: 28)
      }
      .buttonStyle(IslandIconButtonStyle()).help("More").accessibilityLabel("More")
      .popover(isPresented: $moreOpen) {
        VStack(alignment: .leading, spacing: 8) {
          Button(model.pinned ? "Allow automatic close" : "Keep open") { model.togglePin(); moreOpen = false }
          Button("Audio output") { model.tab = .devices; moreOpen = false }
          Button("Saved Text") { model.tab = .files; model.hubView = .savedText; moreOpen = false; model.openForKeyboard?() }
          WeatherBadge(weather: model.weather)
        }.padding(12)
      }
      .onChange(of: moreOpen) { _, open in model.menuOpen = open }
      Button {
        model.setVisible(false)
      } label: {
        Image(systemName: "eye.slash").font(.system(size: 12, weight: .semibold))
          .frame(width: 24, height: 28)
      }.buttonStyle(IslandIconButtonStyle())
        .help("Hide Island. Move away, then return to the notch to restore it.")
        .accessibilityLabel("Hide Island")
      Button {
        model.collapse(force: true)
      } label: {
        Image(systemName: "chevron.up").font(.system(size: 12, weight: .semibold)).frame(
          width: 24, height: 28)
      }.buttonStyle(IslandIconButtonStyle()).help("Collapse Island").accessibilityLabel("Collapse Island")
    }
  }

  private var navigationTabs: some View {
    ForEach([IslandTab.music, .files, .activities], id: \.self) { tab in
      Button {
        model.tab = tab
        if tab == .music { model.musicArtworkFocused = false }
        if tab == .files { model.openForKeyboard?() }
      } label: {
        Image(systemName: tab == .music ? "music.note" : tab == .files ? "folder" : "list.bullet.rectangle")
          .frame(width: 32, height: 28)
          .background(model.tab == tab ? .white.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 7))
      }
      .buttonStyle(IslandIconButtonStyle())
      .help(tab.rawValue).accessibilityLabel(tab.rawValue)
      .accessibilityAddTraits(model.tab == tab ? .isSelected : [])
    }
  }

}

struct CompactIslandView: View {
  @ObservedObject var media: MediaController
  @ObservedObject var audio: AudioController
  @ObservedObject var activities: ActivityStore
  let notice: String?
  let notchWidth: CGFloat
  let open: () -> Void
  let openActivity: (IslandActivity) -> Void

  var body: some View {
    HStack(spacing: notchWidth > 0 ? 0 : 10) {
      Button(action: open) {
        HStack(spacing: 8) {
          AlbumCover(media: media, size: 22)
          if notchWidth <= 0 {
            VStack(alignment: .leading, spacing: 2) {
              Text(media.hasTrack ? media.title : "Spotify")
                .font(.system(size: 10.5, weight: .semibold)).lineLimit(1)
              Text(notice ?? (media.hasTrack ? media.artist : "Move here to open"))
                .font(.system(size: 9)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
          }
        }.frame(width: notchWidth > 0 ? 44 : nil)
      }.buttonStyle(.plain).accessibilityLabel("Open Now Playing, \(media.hasTrack ? media.title : "Spotify")")
      if notchWidth > 0 { Color.clear.frame(width: notchWidth).allowsHitTesting(false) }
      else { Spacer(minLength: 0) }
      HStack(spacing: 2) {
        Button(action: open) {
          PlayingIndicator(playing: media.playing)
            .frame(width: activities.primary == nil ? (notice == nil ? 40 : 22) : 14, height: 26)
        }.buttonStyle(.plain).accessibilityLabel("Open Now Playing")
        if let activity = activities.primary {
          CompactActivityButton(activity: activity) {
            activities.bringForward(activity.id)
            openActivity(activity)
          }
          .id(activity.id)
          .transition(.opacity)
        } else if notice != nil {
          Image(systemName: audio.headphones ? "headphones" : "speaker.wave.2")
            .font(.system(size: 10)).accessibilityLabel(notice ?? "Audio output changed")
        }
      }.frame(width: notchWidth > 0 ? 44 : nil)
    }
    .padding(.horizontal, notchWidth > 0 ? 0 : 12)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
