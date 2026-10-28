import AppKit

@main
struct MacIslandApp {
  @MainActor
  static func main() {
    let application = NSApplication.shared
    if reopenRunningCopy() { return }
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { application.run() }
  }

  @MainActor
  private static func reopenRunningCopy() -> Bool {
    let current = NSRunningApplication.current
    let bundleID = Bundle.main.bundleIdentifier ?? "local.macisland.app"
    let copies =
      NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
      .filter { !$0.isTerminated } + [current]
    // Keep the first copy, including when two copies start at the same time.
    let first = copies.min { left, right in
      if let leftDate = left.launchDate, let rightDate = right.launchDate,
        leftDate != rightDate
      {
        return leftDate < rightDate
      }
      return left.processIdentifier < right.processIdentifier
    }
    guard let first, first.processIdentifier != current.processIdentifier else { return false }
    // Opening the running bundle sends its normal reopen request and restores a hidden island.
    if let url = first.bundleURL { NSWorkspace.shared.open(url) }
    first.activate()
    return true
  }
}
