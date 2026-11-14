import Foundation

// Run through scripts/check-activities.sh. No XCTest installation is needed.
@main
@MainActor
struct ActivityStoreChecks {
  struct Failure: Error { let message: String }

  static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw Failure(message: message) }
  }

  static func main() throws {
    try priorityChangesKeepEqualPriorityInStartOrder()
    try progressUsesOnlyKnownTotals()
    try groupsCanBringAWaitingJobForward()
    try cancelWaitsForTheAdapterAndRunsOnlyOnce()
    try resultsExpireWithoutRemovingRunningWork()
    try lateUpdatesCannotRestoreFinishedOrDismissedWork()
    try progressIsBoundedButDoesNotFinishTheJob()
    print("PASS: 7 activity behavior checks")
  }

  static func priorityChangesKeepEqualPriorityInStartOrder() throws {
    let store = ActivityStore()
    let first = store.start(kind: .upload, title: "First")
    let second = store.start(kind: .download, title: "Second")
    try require(store.primary?.id == first, "Equal priority must keep start order")
    store.update(second, progress: nil, priority: 20)
    try require(store.primary?.id == second, "Higher priority must come first")
    store.update(first, progress: nil, priority: 20)
    try require(store.primary?.id == first, "Priority ties must keep start order")
  }

  static func progressUsesOnlyKnownTotals() throws {
    let store = ActivityStore()
    let id = store.start(kind: .download, title: "Download")
    store.update(id, completedBytes: 25, totalBytes: 100)
    try require(store.primary?.progress == 0.25, "Progress must use actual byte totals")
    store.update(id, completedBytes: 25, totalBytes: -1)
    try require(store.primary?.progress == nil, "Unknown totals must stay unknown")
  }

  static func groupsCanBringAWaitingJobForward() throws {
    let store = ActivityStore()
    let first = store.start(kind: .upload, title: "First", group: .drive)
    let second = store.start(kind: .download, title: "Second", group: .drive, priority: 100)
    try require(store.primary?.id == first, "A group must keep its first job until brought forward")
    try require(store.ordered.count == 2, "Grouped jobs must remain available in the full list")
    store.bringForward(second)
    try require(
      store.primary?.id == second, "An explicit selection must bring a grouped job forward")
  }

  static func cancelWaitsForTheAdapterAndRunsOnlyOnce() throws {
    let store = ActivityStore()
    var requests = 0
    let id = store.start(kind: .upload, title: "Upload", cancel: { requests += 1 })
    store.cancel(id)
    store.cancel(id)
    try require(requests == 1, "A cancel action must run once")
    try require(store.primary?.state == .cancelling, "Cancel must wait for the adapter to stop")
    store.update(id, progress: 0.9)
    try require(store.primary?.progress == nil, "Late progress must not replace cancelling state")
    store.finish(id, state: .cancelled, detail: "Cancelled")
    try require(store.primary?.state == .cancelled, "The adapter must confirm cancellation")
    let hub = store.start(kind: .processing, title: "ZIP", priority: 50)
    store.cancel(hub)
    try require(store.primary?.state == .running, "Work without cancel support must remain running")
  }

  static func resultsExpireWithoutRemovingRunningWork() throws {
    let store = ActivityStore()
    let running = store.start(kind: .upload, title: "Running", group: .drive)
    let failed = store.start(kind: .download, title: "Failed", group: .drive)
    let success = store.start(kind: .processing, title: "Saved", group: .hub)
    let now = Date(timeIntervalSince1970: 1000)
    store.finish(failed, state: .failed, detail: "Server refused", now: now)
    store.finish(success, state: .succeeded, detail: "Saved", now: now)
    try require(store.primary?.id == failed, "Failure alerts must take priority over success")
    store.removeExpiredAlerts(at: now.addingTimeInterval(5))
    try require(store.ordered.count == 2, "Success must expire after five seconds")
    store.removeExpiredAlerts(at: now.addingTimeInterval(10))
    try require(store.primary?.id == running, "The running job must return after alert expiry")
    store.dismiss(running)
    try require(store.primary?.id == running, "Dismiss must not remove running work")
  }

  static func lateUpdatesCannotRestoreFinishedOrDismissedWork() throws {
    let store = ActivityStore()
    let id = store.start(kind: .processing, title: "PDF")
    store.finish(id, state: .failed, detail: "One file failed")
    store.update(id, progress: 1, priority: 100)
    store.finish(id, state: .succeeded, detail: "Late result")
    try require(store.primary?.state == .failed, "A late update must not replace the final result")
    store.dismiss(id)
    store.update(id, progress: 0.5)
    store.finish(id, state: .succeeded, detail: "Late result")
    try require(store.ordered.isEmpty, "Late callbacks must not restore a dismissed job")
  }

  static func progressIsBoundedButDoesNotFinishTheJob() throws {
    let store = ActivityStore()
    let id = store.start(kind: .upload, title: "Upload")
    store.update(id, progress: 1.5)
    try require(store.primary?.progress == 1, "Progress must not exceed one")
    try require(store.primary?.state == .running, "Only the adapter can confirm completion")
    store.update(id, progress: -1)
    try require(store.primary?.progress == 0, "Progress must not be negative")
    store.update(id, progress: .nan)
    try require(store.primary?.progress == nil, "Invalid totals must not make a percentage")
  }

}
