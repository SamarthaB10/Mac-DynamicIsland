import SwiftUI

struct CountdownTimerView: View {
  @ObservedObject var timer: CountdownTimer
  @State private var minutes = ""
  @State private var seconds = ""

  private var duration: TimeInterval {
    guard (minutes.isEmpty || Int(minutes) != nil),
      (seconds.isEmpty || Int(seconds) != nil) else { return 0 }
    let m = Int(minutes) ?? 0
    let s = Int(seconds) ?? 0
    guard m >= 0, s >= 0, m <= 9999, s <= 59 else { return 0 }
    return TimeInterval(m * 60 + s)
  }

  private var timeText: String {
    let value = Int(ceil(timer.remaining))
    return String(format: "%02d:%02d", value / 60, value % 60)
  }

  var body: some View {
    VStack(spacing: 12) {
      if timer.state == .running || timer.state == .paused {
        Text(timeText)
          .font(.system(size: 28, weight: .medium, design: .rounded).monospacedDigit())
          .accessibilityLabel("Time remaining \(timeText)")
        HStack(spacing: 16) {
          if timer.state == .running {
            Button { timer.pause() } label: { Label("Pause", systemImage: "pause.fill") }
          } else {
            Button { timer.resume() } label: { Label("Resume", systemImage: "play.fill") }
          }
          Button { timer.cancel() } label: { Label("Cancel", systemImage: "stop.fill") }
        }
      } else {
        if timer.state == .expired {
          Text("Timer finished").font(.system(size: 13, weight: .medium))
        }
        HStack {
          TextField("Minutes", text: $minutes)
            .accessibilityLabel("Minutes")
          TextField("Seconds", text: $seconds)
            .accessibilityLabel("Seconds")
        }
        .textFieldStyle(.roundedBorder)
        Button { timer.start(seconds: duration) } label: {
          Label("Start timer", systemImage: "timer")
        }
        .disabled(duration <= 0)
      }
    }
    .padding(12)
  }
}
