import CoreLocation
import Foundation

@MainActor
final class WeatherController: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate
{
  @Published private(set) var temperature: String?
  @Published private(set) var condition = "Weather at your location"
  @Published private(set) var symbol = "cloud.sun"
  @Published private(set) var busy = false
  @Published private(set) var error: String?
  private let location = CLLocationManager()
  private var timeout: Task<Void, Never>?
  private var request: Task<Void, Never>?
  private var lastFetch: Date?

  override init() {
    super.init()
    location.delegate = self
    location.desiredAccuracy = kCLLocationAccuracyBest
  }

  func refresh() {
    guard !busy else { return }
    busy = true
    error = nil
    guard CLLocationManager.locationServicesEnabled() else {
      busy = false
      error = "Turn on Location Services in System Settings."
      return
    }
    timeout?.cancel()
    timeout = Task { [weak self] in
      try? await Task.sleep(for: .seconds(25))
      guard !Task.isCancelled, let self, self.busy else { return }
      self.location.stopUpdatingLocation()
      self.busy = false
      self.error = "Location did not respond. Check Location Services, then try again."
    }
    if location.authorizationStatus == .notDetermined {
      location.requestWhenInUseAuthorization()
      location.requestLocation()
    } else {
      requestLocation()
    }
  }

  private func requestLocation() {
    switch location.authorizationStatus {
    case .authorizedAlways: location.requestLocation()
    case .denied, .restricted:
      busy = false
      error = "Allow Location Services for Mac Island in System Settings."
    default: break
    }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    if busy {
      requestLocation()
    } else if manager.authorizationStatus == .authorizedAlways {
      refreshIfNeeded()
    }
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    timeout?.cancel()
    busy = false
    self.error = "Location is not available. Check Location Services and Wi-Fi."
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let fix = locations.last, fix.horizontalAccuracy >= 0 else { return }
    timeout?.cancel()
    request?.cancel()
    request = Task {
      do {
        var url = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        url.queryItems = [
          .init(name: "latitude", value: String(fix.coordinate.latitude)),
          .init(name: "longitude", value: String(fix.coordinate.longitude)),
          .init(name: "current", value: "temperature_2m,weather_code,is_day"),
        ]
        var query = URLRequest(url: url.url!)
        query.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: query)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
          throw URLError(.badServerResponse)
        }
        let result = try JSONDecoder().decode(WeatherResponse.self, from: data).current
        guard !Task.isCancelled else { return }
        temperature = Measurement(value: result.temperature_2m, unit: UnitTemperature.celsius)
          .formatted(
            .measurement(
              width: .narrow, usage: .weather,
              numberFormatStyle: .number.precision(.fractionLength(0))))
        (condition, symbol) = Self.describe(result.weather_code, day: result.is_day != 0)
        busy = false
        lastFetch = Date()
      } catch {
        guard !Task.isCancelled else { return }
        busy = false
        self.error = "Weather could not load. Select Refresh to try again."
      }
    }
  }

  func refreshIfNeeded() {
    guard location.authorizationStatus == .authorizedAlways,
      lastFetch.map({ Date().timeIntervalSince($0) > 900 }) ?? true
    else { return }
    refresh()
  }

  private static func describe(_ code: Int, day: Bool) -> (String, String) {
    switch code {
    case 0: return ("Clear", day ? "sun.max" : "moon")
    case 1...3: return ("Cloudy", day ? "cloud.sun" : "cloud.moon")
    case 45, 48: return ("Fog", "cloud.fog")
    case 51...67, 80...82: return ("Rain", "cloud.rain")
    case 71...77, 85, 86: return ("Snow", "cloud.snow")
    case 95...99: return ("Thunderstorms", "cloud.bolt.rain")
    default: return ("Current weather", "cloud")
    }
  }
}

private struct WeatherResponse: Decodable {
  struct Current: Decodable {
    let temperature_2m: Double
    let weather_code: Int
    let is_day: Int
  }
  let current: Current
}
