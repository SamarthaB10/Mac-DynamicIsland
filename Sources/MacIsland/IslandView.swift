import AppKit
import SwiftUI

struct IslandView: View {
  @ObservedObject var model: IslandModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var selection

  private var motion: Animation? {
    reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.86)
  }

  var body: some View {
    ZStack(alignment: .top) {
      ZStack(alignment: .top) {
        if model.expanded {
          expandedContent
            .frame(width: model.contentSize.width, height: model.contentSize.height)
            .padding(.top, max(0, model.notchHeight - 6))
            .overlay(alignment: .top) {
              HStack {
                Spacer(minLength: model.notchWidth)
                WeatherBadge(weather: model.weather)
              }
              .padding(.horizontal, 18)
              .frame(height: model.notchHeight)
            }
            .transition(.opacity)
        } else {
          CompactIslandView(
            media: model.media, audio: model.audio, notice: model.connectionNotice,
            notchWidth: model.notchWidth,
            open: { model.openForKeyboard?() }
          )
          .frame(width: model.compactSize.width, height: model.compactSize.height)
          .transition(.opacity)
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
      .animation(motion, value: model.tab)
      .animation(motion, value: model.connectionNotice)
      .padding(.top, IslandModel.canvasInset)
    }
    .frame(width: model.canvasSize.width, height: model.canvasSize.height, alignment: .top)
    .foregroundStyle(.white)
    .tint(.white)
    .font(.system(size: 12))
    .onExitCommand { model.collapse(force: true) }
  }

  private var expandedContent: some View {
    VStack(spacing: 10) {
      ZStack {
        Group {
          switch model.tab {
          case .music:
            MusicView(media: model.media, showDevices: { withAnimation { model.tab = .devices } })
          case .files: HubView(model: model)
          case .devices: DevicesView(audio: model.audio)
          }
        }.id(model.tab).transition(.opacity)
      }.frame(maxWidth: .infinity, maxHeight: .infinity)
      HStack(spacing: 3) {
        ForEach(IslandTab.allCases, id: \.self) { tab in
          Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { model.tab = tab }
            if tab == .files { model.openForKeyboard?() }
            if tab == .devices {
              model.audio.refresh()
              model.weather.refreshIfNeeded()
            }
          } label: {
            Text(tab.rawValue)
              .font(.system(size: 10.5, weight: .semibold))
              .padding(.horizontal, 9).padding(.vertical, 6)
              .background {
                if model.tab == tab {
                  Capsule().fill(.white.opacity(0.15)).matchedGeometryEffect(
                    id: "tab", in: selection)
                }
              }
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(model.tab == tab ? .isSelected : [])
        }
        Spacer(minLength: 2)
        Button {
          model.togglePin()
        } label: {
          Image(systemName: model.pinned ? "pin.fill" : "pin")
            .frame(width: 24, height: 28).foregroundStyle(.white.opacity(model.pinned ? 1 : 0.6))
        }.buttonStyle(.plain).help(model.pinned ? "Allow automatic close" : "Keep open")
          .accessibilityLabel(model.pinned ? "Unpin island" : "Pin island")
        Button {
          model.collapse(force: true)
        } label: {
          Image(systemName: "chevron.up").font(.system(size: 12, weight: .semibold)).frame(
            width: 24, height: 28)
        }.buttonStyle(.plain).help("Collapse Island").accessibilityLabel("Collapse Island")
      }
    }
    .padding(16)
  }

}

struct CompactIslandView: View {
  @ObservedObject var media: MediaController
  @ObservedObject var audio: AudioController
  let notice: String?
  let notchWidth: CGFloat
  let open: () -> Void

  var body: some View {
    Button(action: open) {
      HStack(spacing: notchWidth > 0 ? 0 : 10) {
        if notchWidth > 0 {
          Group {
            if notice != nil {
              Image(systemName: audio.headphones ? "headphones" : "speaker.wave.2")
                .font(.system(size: 19)).symbolEffect(.bounce, value: notice)
            } else {
              AlbumCover(media: media, size: 22)
            }
          }.frame(width: 44)
          Color.clear.frame(width: notchWidth)
          PlayingIndicator(playing: media.playing).frame(width: 44, height: 16)
        } else if let notice {
          Image(systemName: audio.headphones ? "headphones" : "speaker.wave.2")
            .font(.system(size: 23)).symbolEffect(.bounce, value: notice)
          VStack(alignment: .leading, spacing: 2) {
            Text(notice).font(.system(size: 10.5, weight: .semibold)).lineLimit(1)
            Text("Connected").font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
          }
          Spacer(minLength: 0)
          if let battery = audio.battery { BatteryRing(percent: battery) }
        } else {
          AlbumCover(media: media, size: 24)
          VStack(alignment: .leading, spacing: 2) {
            Text(media.hasTrack ? media.title : "Spotify").font(
              .system(size: 10.5, weight: .semibold)
            ).lineLimit(1)
            Text(media.hasTrack ? media.artist : "Move here to open")
              .font(.system(size: 9)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
          }
          Spacer(minLength: 0)
          PlayingIndicator(playing: media.playing).frame(width: 20, height: 14)
        }
      }.padding(.horizontal, notchWidth > 0 ? 0 : 12).frame(
        maxWidth: .infinity, maxHeight: .infinity)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Open Island")
    .help("Move near the notch to open. Move away to close.")
  }
}
