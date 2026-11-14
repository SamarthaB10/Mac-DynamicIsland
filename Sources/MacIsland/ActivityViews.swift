import SwiftUI

// Native counterparts of islandcn's progress ring and activity detail row.
struct ActivityProgressRing: View {
  let activity: IslandActivity
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      if activity.state == .running, let progress = activity.progress {
        Circle().stroke(.white.opacity(0.18), lineWidth: 2)
        Circle().trim(from: 0, to: progress)
          .stroke(.cyan, style: StrokeStyle(lineWidth: 2, lineCap: .round))
          .rotationEffect(.degrees(-90))
          .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: progress)
        Image(systemName: activity.kind.symbol).font(.system(size: 8, weight: .semibold))
      } else if activity.state == .running && !reduceMotion {
        ProgressView().controlSize(.mini).tint(.cyan)
      } else {
        Image(systemName: activity.symbol)
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(activity.state == .failed ? Color.orange : .cyan)
      }
    }
    .frame(width: 22, height: 22)
    .accessibilityHidden(true)
  }
}

struct CompactActivityButton: View {
  let activity: IslandActivity
  let open: () -> Void

  var body: some View {
    Button(action: open) { ActivityProgressRing(activity: activity).frame(width: 26, height: 28) }
      .buttonStyle(IslandIconButtonStyle())
      .help(activity.accessibilitySummary)
      .accessibilityLabel("Open \(activity.accessibilitySummary)")
  }
}

struct ActivityJobStrip: View {
  @ObservedObject var activities: ActivityStore
  let open: (IslandActivity) -> Void
  let menuOpen: (Bool) -> Void
  @State private var showingDetails = false

  var body: some View {
    if let activity = activities.primary {
      HStack(spacing: 8) {
        ActivityProgressRing(activity: activity)
        Button { open(activity) } label: {
          VStack(alignment: .leading, spacing: 2) {
            Text(activity.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            Text(activity.detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
          }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("Open \(activity.accessibilitySummary)")
        Button { showingDetails.toggle() } label: {
          HStack(spacing: 4) {
            Text("\(activities.ordered.count)")
            Image(systemName: "chevron.down")
          }.frame(height: 28)
        }
        .buttonStyle(IslandIconButtonStyle())
        .help("Show all activities")
        .accessibilityLabel("Show all activities, \(activities.ordered.count) total")
        .popover(isPresented: $showingDetails) {
          ActivityListView(activities: activities, open: { item in
            showingDetails = false
            open(item)
          }).padding(12).frame(width: 340, height: 240)
        }
      }
      .padding(.horizontal, 10).padding(.vertical, 5)
      .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
      .onChange(of: showingDetails) { _, showing in menuOpen(showing) }
      .onDisappear { menuOpen(false) }
    }
  }
}

struct ActivityListView: View {
  @ObservedObject var activities: ActivityStore
  let open: (IslandActivity) -> Void

  var body: some View {
    ScrollView {
      if activities.ordered.isEmpty {
        VStack(spacing: 8) {
          Image(systemName: "rectangle.stack").font(.system(size: 24))
          Text("No active work").font(.headline)
          Text("Drive transfers and Hub file actions appear here.")
            .font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 24)
      }
      VStack(spacing: 8) {
        ForEach(activities.ordered) { activity in
          HStack(spacing: 10) {
            ActivityProgressRing(activity: activity)
            Button {
              open(activity)
            } label: {
              VStack(alignment: .leading, spacing: 4) {
                Text(activity.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                Text(activity.detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(
                  2)
                if activity.state == .running, let progress = activity.progress {
                  ProgressView(value: progress).tint(.cyan)
                    .accessibilityLabel("Progress")
                }
              }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Open \(activity.accessibilitySummary)")
            if activity.canCancel {
              Button {
                activities.cancel(activity.id)
              } label: {
                Image(systemName: "stop.circle").frame(width: 28, height: 28)
              }.buttonStyle(IslandIconButtonStyle())
                .accessibilityLabel("Cancel \(activity.title)")
                .help("Cancel \(activity.title)")
            } else if activity.state.isFinished {
              Button {
                activities.dismiss(activity.id)
              } label: {
                Image(systemName: "xmark.circle").frame(width: 28, height: 28)
              }.buttonStyle(IslandIconButtonStyle())
                .accessibilityLabel("Dismiss \(activity.title)")
            }
          }
          .padding(10).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityLabel("Activities")
  }
}

// Observe playback here so Activity reflects track changes without a tab change.
struct ActivityMusicStrip: View {
  @ObservedObject var media: MediaController

  var body: some View {
    HStack(spacing: 8) {
      AlbumCover(media: media, size: 28)
      VStack(alignment: .leading, spacing: 2) {
        Text(media.hasTrack ? media.title : "Spotify")
          .font(.system(size: 11, weight: .semibold)).lineLimit(1)
        Text(media.hasTrack ? media.artist : "No current song")
          .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
      }
      Spacer(minLength: 0)
      Button { media.command("playpause") } label: {
        Image(systemName: media.playing ? "pause.fill" : "play.fill")
          .frame(width: 28, height: 28)
      }
      .buttonStyle(IslandIconButtonStyle())
      .accessibilityLabel(media.playing ? "Pause" : "Play")
      .help(media.playing ? "Pause" : "Play")
      .disabled(!media.hasTrack || media.busy)
    }
  }
}
