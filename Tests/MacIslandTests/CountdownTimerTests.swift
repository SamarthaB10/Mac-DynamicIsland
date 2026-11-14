import Foundation

@main
struct CountdownTimerTests {
  @MainActor static func main() {
    var now = Date(timeIntervalSince1970: 0)
    let timer = CountdownTimer(now: { now }, automaticallyUpdates: false)
    timer.start(seconds: 60)
    now = now.addingTimeInterval(10)
    timer.update()
    precondition(timer.remaining == 50 && timer.state == .running, "start uses a deadline")
    timer.pause()
    now = now.addingTimeInterval(100)
    timer.update()
    precondition(timer.state == .paused && timer.remaining == 50, "pause holds remaining time")
    timer.resume()
    now = now.addingTimeInterval(20)
    timer.update()
    precondition(timer.state == .running && timer.remaining == 30, "resume uses remaining time")
    timer.cancel()
    now = now.addingTimeInterval(100)
    timer.update()
    precondition(timer.state == .idle && timer.remaining == 0, "cancel stops the timer")
    var expiries = 0
    timer.onExpiry = { expiries += 1 }
    timer.start(seconds: 5)
    now = now.addingTimeInterval(6)
    timer.update()
    timer.update()
    precondition(timer.state == .expired && timer.remaining == 0 && expiries == 1, "expiry fires once")
    timer.start(seconds: 2)
    now = now.addingTimeInterval(3)
    timer.pause()
    precondition(timer.state == .expired && expiries == 2, "pause after deadline expires")
    print("Countdown timer checks passed")
  }
}
