import Combine
import Foundation

enum ActivityKind {
  case upload, download, processing, timer, notification

  var symbol: String {
    switch self {
    case .upload: "arrow.up.doc"
    case .download: "arrow.down.doc"
    case .processing: "doc.badge.gearshape"
    case .timer: "timer"
    case .notification: "bell.fill"
    }
  }
}

enum ActivityGroup { case drive, hub }

enum ActivityState {
  case running, cancelling, succeeded, failed, cancelled
  var isFinished: Bool { self == .succeeded || self == .failed || self == .cancelled }
}

struct IslandActivity: Identifiable {
  let id: UUID
  let kind: ActivityKind
  let group: ActivityGroup?
  let order: Int
  var title: String
  var detail = "In progress"
  var priority: Int
  var state = ActivityState.running
  var progress: Double?
  var canCancel: Bool
  var expires: Date?

  var symbol: String {
    switch state {
    case .running: kind.symbol
    case .cancelling: "hourglass"
    case .succeeded: "checkmark.circle.fill"
    case .failed: "exclamationmark.triangle.fill"
    case .cancelled: "xmark.circle"
    }
  }

  var accessibilitySummary: String {
    let amount =
      state == .running ? progress.map { ", \(Int($0 * 100)) percent" } ?? ", progress unknown" : ""
    return "\(title), \(detail)\(amount)"
  }
}

// Owns activity display state. Service adapters own the work and confirm its end.
@MainActor
final class ActivityStore: ObservableObject {
  @Published private(set) var activities: [IslandActivity] = []
  private var nextOrder = 0
  private var cancelActions: [UUID: () -> Void] = [:]
  private var expiryTasks: [UUID: Task<Void, Never>] = [:]
  private var front: [ActivityGroup: UUID] = [:]
  private var notificationSummary: UUID?

  // Keeps unread notifications available without displacing running jobs.
  func setNotificationCount(_ count: Int) {
    if count == 0 {
      if let id = notificationSummary { activities.removeAll { $0.id == id } }
      notificationSummary = nil
      return
    }
    if notificationSummary == nil {
      notificationSummary = start(kind: .notification, title: "Notifications", priority: 5)
    }
    guard let id = notificationSummary else { return }
    update(id, progress: nil, title: "\(count) unread notifications", detail: "Open Notifications")
  }

  var ordered: [IslandActivity] {
    activities.sorted {
      $0.priority == $1.priority ? $0.order < $1.order : $0.priority > $1.priority
    }
  }

  var primary: IslandActivity? {
    ordered.first { activity in
      guard let group = activity.group else { return true }
      let member = front[group] ?? activities.first(where: { $0.group == group })?.id
      return activity.id == member
    }
  }

  @discardableResult
  func start(
    kind: ActivityKind, title: String, group: ActivityGroup? = nil,
    priority: Int = 10, cancel: (() -> Void)? = nil
  ) -> UUID {
    let id = UUID()
    activities.append(
      IslandActivity(
        id: id, kind: kind, group: group, order: nextOrder, title: title,
        priority: priority, canCancel: cancel != nil))
    nextOrder += 1
    cancelActions[id] = cancel
    return id
  }

  func update(_ id: UUID, progress: Double?, priority: Int? = nil, title: String? = nil, detail: String? = nil) {
    guard let index = activities.firstIndex(where: { $0.id == id }),
      activities[index].state == .running
    else { return }
    activities[index].progress = progress.flatMap { $0.isFinite ? min(1, max(0, $0)) : nil }
    if let priority { activities[index].priority = priority }
    if let title { activities[index].title = title }
    if let detail { activities[index].detail = detail }
  }

  func update(_ id: UUID, completedBytes: Int64, totalBytes: Int64) {
    let progress =
      totalBytes > 0 && completedBytes >= 0
      ? Double(completedBytes) / Double(totalBytes) : nil
    update(id, progress: progress)
  }

  func cancel(_ id: UUID) {
    guard let index = activities.firstIndex(where: { $0.id == id }),
      activities[index].state == .running, let action = cancelActions.removeValue(forKey: id)
    else { return }
    activities[index].state = .cancelling
    activities[index].detail = "Cancelling…"
    activities[index].canCancel = false
    action()
  }

  func finish(_ id: UUID, state: ActivityState, detail: String, now: Date = Date()) {
    guard state.isFinished, let index = activities.firstIndex(where: { $0.id == id }),
      !activities[index].state.isFinished
    else { return }
    let lifetime: TimeInterval = state == .failed ? 10 : 5
    activities[index].state = state
    activities[index].detail = detail
    activities[index].canCancel = false
    activities[index].progress = nil
    activities[index].priority = state == .failed ? 30 : 20
    activities[index].expires = now.addingTimeInterval(lifetime)
    if let group = activities[index].group { front[group] = id }
    cancelActions.removeValue(forKey: id)
    expiryTasks[id] = Task { [weak self] in
      try? await Task.sleep(for: .seconds(lifetime))
      guard !Task.isCancelled else { return }
      self?.removeExpiredAlerts()
    }
  }

  func bringForward(_ id: UUID) {
    guard let activity = activities.first(where: { $0.id == id }), let group = activity.group else {
      return
    }
    front[group] = id
    objectWillChange.send()
  }

  func dismiss(_ id: UUID) {
    guard let activity = activities.first(where: { $0.id == id }), activity.state.isFinished else {
      return
    }
    activities.removeAll { $0.id == id }
    expiryTasks.removeValue(forKey: id)?.cancel()
    if let group = activity.group, front[group] == id { front.removeValue(forKey: group) }
  }

  func removeExpiredAlerts(at now: Date = Date()) {
    let expired = activities.filter { $0.expires.map { $0 <= now } ?? false }.map(\.id)
    for id in expired { dismiss(id) }
  }

  deinit { for task in expiryTasks.values { task.cancel() } }
}
