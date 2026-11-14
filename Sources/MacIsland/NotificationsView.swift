import SwiftUI

struct NotificationsView: View {
  @ObservedObject var notifications: IslandNotificationStore
  let menuOpen: (Bool) -> Void
  @State private var showingSources = false
  @State private var selectedSource: NotificationSource?

  private var visibleItems: [IslandNotification] {
    notifications.items.filter { selectedSource == nil || $0.source == selectedSource }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 7) {
        Image(systemName: "bell").font(.system(size: 16))
        Text("Notifications").font(.system(size: 14, weight: .semibold))
        Spacer()
        Button("Clear All") { notifications.dismissAll() }
          .font(.system(size: 11, weight: .medium))
          .padding(.horizontal, 9).padding(.vertical, 5)
          .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
          .disabled(notifications.items.isEmpty)
        Button { showingSources.toggle() } label: {
          Image(systemName: "ellipsis").frame(width: 24, height: 24)
        }
        .accessibilityLabel("Notification settings")
        .help("Notification settings")
        .popover(isPresented: $showingSources) { settings }
      }.buttonStyle(.plain)
      HStack(alignment: .top, spacing: 10) {
        VStack(alignment: .leading, spacing: 2) {
          filterButton("All", symbol: "square.grid.2x2", source: nil,
            count: notifications.items.count)
          ForEach(NotificationSource.allCases) { source in
            filterButton(source.displayName, symbol: source.symbol, source: source,
              count: notifications.items.filter { $0.source == source }.count)
          }
          Divider().overlay(.white.opacity(0.12)).padding(.vertical, 3)
          Button { showingSources.toggle() } label: {
            Label("Settings", systemImage: "gearshape")
              .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
              .padding(.horizontal, 8)
          }.buttonStyle(.plain).help("Notification settings")
          Spacer(minLength: 0)
          Text(notifications.isConnected ? "Listening" : "Offline")
            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.65))
            .lineLimit(1).help(notifications.connectionMessage)
        }.frame(width: 112)
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 7) {
            if let error = notifications.persistenceError {
              Text(error).font(.system(size: 11)).foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading).padding(9)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                .textSelection(.enabled)
            }
            ForEach(notifications.notices) { notice in
              NotificationNoticeRow(notice: notice, clear: { notifications.clearNotice(notice) })
            }
            if visibleItems.isEmpty {
              VStack(spacing: 6) {
                Image(systemName: "bell.slash").font(.system(size: 22, weight: .light))
                  .foregroundStyle(.white.opacity(0.65)).accessibilityHidden(true)
                Text("No notifications").font(.system(size: 12, weight: .semibold))
                Text("Notifications stay here until you dismiss them.")
                  .font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
                  .multilineTextAlignment(.center)
                if !notifications.isConnected {
                  Button("Connect Ardia") { notifications.connect() }
                    .buttonStyle(.bordered).padding(.top, 5)
                }
              }.frame(maxWidth: .infinity, minHeight: 150)
            } else {
              ForEach(visibleItems.filter { !$0.isRead }) { item in card(item) }
              if visibleItems.contains(where: { $0.isRead }) {
                Text("Earlier").font(.system(size: 11, weight: .semibold))
                  .foregroundStyle(.white.opacity(0.65)).padding(.top, 5)
                ForEach(visibleItems.filter { $0.isRead }) { item in card(item) }
              }
            }
          }.padding(.trailing, 3)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .onChange(of: showingSources) { _, open in menuOpen(open) }
    .onDisappear { showingSources = false; menuOpen(false) }
  }

  private var settings: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Notification settings").font(.system(size: 12, weight: .semibold))
      Text(notifications.connectionMessage).font(.system(size: 11))
        .fixedSize(horizontal: false, vertical: true)
      Button(notifications.isConnected ? "Disconnect" : "Connect Ardia") {
        if notifications.isConnected { notifications.disconnect() }
        else { notifications.connect() }
      }
      Text("Read and dismiss currently change Mac Island only. Open goes to the source site.")
        .font(.system(size: 11)).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Divider()
      Text("Sources").font(.system(size: 11, weight: .semibold))
      ForEach(NotificationSource.allCases) { source in
        Toggle(isOn: Binding(
          get: { notifications.enabledSources.contains(source) },
          set: { notifications.setEnabled(source, enabled: $0) }
        )) {
          HStack(spacing: 7) {
            NotificationSourceIcon(source: source, size: 16)
            Text(source.displayName)
          }
        }.toggleStyle(.checkbox)
      }
    }.padding(14).frame(width: 220, alignment: .leading)
  }

  private func filterButton(_ title: String, symbol: String, source: NotificationSource?, count: Int) -> some View {
    Button { selectedSource = source } label: {
      HStack(spacing: 8) {
        Group {
          if let source { NotificationSourceIcon(source: source, size: 16) }
          else { Image(systemName: symbol).frame(width: 16) }
        }
        Text(title).lineLimit(1).layoutPriority(1)
        Spacer(minLength: 0)
        Text("\(count)").foregroundStyle(.white.opacity(0.7))
      }
      .font(.system(size: 11, weight: selectedSource == source ? .semibold : .regular))
      .padding(.horizontal, 6).frame(height: 24)
      .background(selectedSource == source ? Color.white.opacity(0.14) : Color.clear,
        in: RoundedRectangle(cornerRadius: 8))
      .contentShape(Rectangle())
    }.buttonStyle(.plain).accessibilityValue(selectedSource == source ? "Selected, \(count) notifications" : "\(count) notifications")
  }

  private func card(_ item: IslandNotification) -> some View {
    NotificationCard(item: item, open: { notifications.open(item) },
      markRead: { notifications.markRead(item) }, dismiss: { notifications.dismiss(item) })
  }
}

private struct NotificationNoticeRow: View {
  let notice: NotificationSyncNotice
  let clear: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Label(notice.title, systemImage: "exclamationmark.triangle")
        .font(.system(size: 11, weight: .semibold))
      Text(notice.detail).font(.system(size: 11)).foregroundStyle(.white.opacity(0.8))
        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
      HStack(spacing: 12) {
        Button("Clear", action: clear)
      }.font(.system(size: 11, weight: .medium)).buttonStyle(.plain)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(9)
    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
  }
}

private struct NotificationCard: View {
  let item: IslandNotification
  let open: () -> Void
  let markRead: () -> Void
  let dismiss: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 9) {
      NotificationSourceIcon(source: item.source, size: 28)
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 5) {
          Text(item.source.displayName).font(.system(size: 10, weight: .medium))
          Text(item.receivedAt, style: .relative).font(.system(size: 10))
          if !item.isRead {
            Circle().fill(.white).frame(width: 5, height: 5).accessibilityHidden(true)
            Text("Unread").font(.system(size: 10, weight: .medium))
          }
          Spacer(minLength: 0)
        }.foregroundStyle(.white.opacity(0.7))
        Text(item.title).font(.system(size: 12, weight: .semibold))
          .fixedSize(horizontal: false, vertical: true)
        if !item.body.isEmpty {
          Text(item.body).font(.system(size: 11)).foregroundStyle(.white.opacity(0.8))
            .fixedSize(horizontal: false, vertical: true)
        }
        HStack(spacing: 12) {
          Button(item.openLabel, action: open)
          if !item.isRead { Button("Mark as read", action: markRead) }
          Button("Dismiss", action: dismiss)
        }
        .font(.system(size: 10, weight: .medium))
        .buttonStyle(.plain)
        .padding(.top, 3)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(9)
    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
  }
}
