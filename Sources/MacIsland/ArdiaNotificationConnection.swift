import AppKit
import Foundation

// Reads only notification events from Ardia's local command-line stream.
final class ArdiaNotificationConnection {
  struct Event: Decodable {
    struct Data: Decodable {
      let origin: String
      let title: String
      let body: String
    }
    let event: String
    let time: Double
    let data: Data
  }

  private let process = Process()
  private let output = Pipe()
  private let queue = DispatchQueue(label: "MacIsland.ArdiaNotificationConnection")
  private var buffer = Data()
  private var discardingLine = false
  private var stopped = false
  private var terminationObserver: NSObjectProtocol?
  private let onEvent: (Event) -> Void
  private let onExit: (String) -> Void
  private let maximumLineBytes = 64 * 1024

  init(onEvent: @escaping (Event) -> Void, onExit: @escaping (String) -> Void) {
    self.onEvent = onEvent
    self.onExit = onExit
    terminationObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.willTerminateNotification, object: nil, queue: nil
    ) { [weak self] _ in self?.stop() }
  }

  func start() throws {
    process.executableURL = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".local/bin/ardia")
    process.arguments = ["events", "--json", "notification.shown"]
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    output.fileHandleForReading.readabilityHandler = { [weak self] handle in
      self?.queue.async { [weak self] in
        guard let self, !self.stopped else { return }
        self.consume(handle.availableData)
      }
    }
    process.terminationHandler = { [weak self] process in
      guard let self else { return }
      self.queue.async {
        guard !self.stopped else { return }
        self.output.fileHandleForReading.readabilityHandler = nil
        self.consume(self.output.fileHandleForReading.readDataToEndOfFile())
        self.stopped = true
        self.onExit("Ardia disconnected (exit \(process.terminationStatus)). Select Connect to try again.")
      }
    }
    do {
      try process.run()
    } catch {
      output.fileHandleForReading.readabilityHandler = nil
      throw error
    }
  }

  func stop() {
    queue.sync {
      stopped = true
      output.fileHandleForReading.readabilityHandler = nil
      if process.isRunning { process.terminate() }
    }
  }

  private func consume(_ data: Data) {
    guard !stopped else { return }
    for byte in data {
      if byte == 10 {
        if !discardingLine,
          let event = try? JSONDecoder().decode(Event.self, from: buffer),
          event.event == "notification.shown", event.time.isFinite,
          event.data.origin.utf8.count <= 2048,
          event.data.title.utf8.count <= 4096, event.data.body.utf8.count <= 16384
        { onEvent(event) }
        buffer.removeAll(keepingCapacity: true)
        discardingLine = false
      } else if !discardingLine {
        if buffer.count < maximumLineBytes { buffer.append(byte) }
        else { buffer.removeAll(keepingCapacity: true); discardingLine = true }
      }
    }
  }

  deinit {
    if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
    output.fileHandleForReading.readabilityHandler = nil
    if process.isRunning { process.terminate() }
  }
}
