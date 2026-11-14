import Combine
import Foundation

@MainActor
final class CountdownTimer: ObservableObject {
  enum State { case idle, running, paused, expired }

  @Published private(set) var state: State = .idle
  @Published private(set) var remaining: TimeInterval = 0
  private(set) var duration: TimeInterval = 0
  private let now: () -> Date
  private let automaticallyUpdates: Bool
  private var deadline: Date?
  private var task: Task<Void, Never>?
  var onExpiry: (() -> Void)?
  var onChange: (() -> Void)?

  var remainingText: String {
    let value = Int(ceil(remaining))
    return String(format: "%02d:%02d", value / 60, value % 60)
  }

  init(now: @escaping () -> Date = Date.init, automaticallyUpdates: Bool = true) {
    self.now = now
    self.automaticallyUpdates = automaticallyUpdates
  }

  func start(seconds: TimeInterval) {
    guard seconds.isFinite, seconds > 0, seconds <= 599_999 else { return }
    task?.cancel()
    duration = seconds
    remaining = seconds
    deadline = now().addingTimeInterval(seconds)
    state = .running
    scheduleUpdates()
    onChange?()
  }

  func update() {
    guard state == .running, let deadline else { return }
    remaining = max(0, deadline.timeIntervalSince(now()))
    if remaining == 0 {
      self.deadline = nil
      state = .expired
      task?.cancel()
      task = nil
      onChange?()
      onExpiry?()
    } else {
      onChange?()
    }
  }

  func pause() {
    update()
    guard state == .running else { return }
    deadline = nil
    state = .paused
    task?.cancel()
    task = nil
    onChange?()
  }

  func resume() {
    guard state == .paused else { return }
    deadline = now().addingTimeInterval(remaining)
    state = .running
    scheduleUpdates()
    onChange?()
  }

  func cancel() {
    task?.cancel()
    task = nil
    deadline = nil
    remaining = 0
    duration = 0
    state = .idle
    onChange?()
  }

  private func scheduleUpdates() {
    guard automaticallyUpdates else { return }
    task = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled, let self else { return }
        self.update()
      }
    }
  }

  deinit { task?.cancel() }
}
