import SwiftUI

func batteryColor(_ percent: Int) -> Color {
  percent <= 20 ? .red : (percent <= 40 ? .orange : .green)
}

struct BatteryRing: View {
  let percent: Int
  var body: some View {
    ZStack {
      Circle().stroke(.white.opacity(0.15), lineWidth: 3)
      Circle().trim(from: 0, to: CGFloat(percent) / 100)
        .stroke(batteryColor(percent), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        .rotationEffect(.degrees(-90))
    }.frame(width: 23, height: 23).accessibilityLabel("Battery \(percent) percent")
  }
}

struct MacBatteryIcon: View {
  let percent: Int
  var charging = false
  var lowPower = false
  private var color: Color {
    lowPower ? .yellow : (percent <= 20 ? .red : (charging ? .green : .white))
  }
  var body: some View {
    HStack(spacing: 1) {
      ZStack(alignment: .leading) {
        RoundedRectangle(cornerRadius: 3).strokeBorder(.white.opacity(0.65), lineWidth: 1)
        RoundedRectangle(cornerRadius: 1.3).fill(color)
          .frame(width: max(0, 17 * CGFloat(percent) / 100), height: 7).padding(.leading, 2)
        if charging {
          Image(systemName: "bolt.fill").font(.system(size: 8, weight: .black))
            .foregroundStyle(.black).frame(width: 21, height: 11)
        }
      }.frame(width: 21, height: 11)
      Capsule().fill(.white.opacity(0.65)).frame(width: 2, height: 4)
    }.accessibilityHidden(true)
  }
}

struct DevicesView: View {
  @ObservedObject var audio: AudioController
  var body: some View {
    VStack(spacing: 8) {
      ScrollView {
        LazyVStack(spacing: 4) {
          ForEach(audio.outputs) { output in
            Button {
              audio.select(output)
            } label: {
              HStack(spacing: 10) {
                Image(systemName: output.symbol).font(.system(size: 18)).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                  Text(output.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                  Text(output.connection).font(.system(size: 9)).foregroundStyle(
                    .white.opacity(0.5))
                }
                Spacer(minLength: 0)
                if let percent = output.battery {
                  Text("\(percent)%").font(.system(size: 10)).monospacedDigit()
                  MacBatteryIcon(percent: percent)
                } else if output.connection == "Bluetooth" {
                  Text("Battery unavailable").font(.system(size: 8)).foregroundStyle(
                    .white.opacity(0.45))
                }
                if output.id == audio.device {
                  Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                }
              }.padding(.horizontal, 8).frame(height: 34)
                .background(
                  output.id == audio.device ? .white.opacity(0.08) : .clear,
                  in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain).help("Use \(output.name) for audio")
          }
          ForEach(Array(audio.displays.enumerated()), id: \.offset) { _, name in
            HStack(spacing: 10) {
              Image(systemName: "display").font(.system(size: 17)).frame(width: 24)
              Text(name).font(.system(size: 11)).lineLimit(1)
              Spacer()
              Text("External display").font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
            }.padding(.horizontal, 8).frame(height: 28)
          }
        }
      }
      HStack(spacing: 8) {
        Image(systemName: "speaker.fill").font(.system(size: 9))
        Slider(
          value: Binding(get: { Double(audio.volume) }, set: { audio.setVolume(Float($0)) }),
          in: 0...1
        )
        .controlSize(.mini).tint(.white).disabled(!audio.canSetVolume).accessibilityLabel(
          "Output volume")
        Text(audio.canSetVolume ? "\(Int(audio.volume * 100))" : "System")
          .font(.system(size: 9)).monospacedDigit().frame(width: 30)
      }
    }
  }
}

struct WeatherBadge: View {
  @ObservedObject var weather: WeatherController
  var body: some View {
    Button {
      weather.refresh()
    } label: {
      HStack(spacing: 4) {
        Image(systemName: weather.symbol)
        Text(weather.temperature ?? (weather.busy ? "…" : "--°"))
      }.font(.system(size: 10, weight: .medium))
        .foregroundStyle(.white.opacity(0.8))
    }
    .buttonStyle(.plain).disabled(weather.busy)
    .accessibilityLabel(
      "Weather: \(weather.temperature ?? "not loaded"). \(weather.condition). Refresh at current location"
    )
    .help(weather.error ?? "\(weather.condition). Weather by Open-Meteo. Click to refresh.")
    .contextMenu {
      Text(weather.error ?? weather.condition)
      Button("Refresh Weather") { weather.refresh() }
      Link("Weather data by Open-Meteo", destination: URL(string: "https://open-meteo.com/")!)
    }
  }
}
