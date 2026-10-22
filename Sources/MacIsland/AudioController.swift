import AppKit
import AudioToolbox
import CoreAudio
import IOKit

struct AudioOutput: Identifiable, Equatable {
  let id: AudioDeviceID
  let name: String
  let connection: String
  let symbol: String
  let battery: Int?
}

@MainActor
final class AudioController: ObservableObject {
  @Published private(set) var name = "Audio output"
  @Published private(set) var headphones = false
  @Published private(set) var battery: Int?
  @Published private(set) var volume: Float32 = 0
  @Published private(set) var canSetVolume = false
  @Published private(set) var outputs: [AudioOutput] = []
  @Published private(set) var displays: [String] = []
  @Published private(set) var device = AudioDeviceID(0)
  private var outputListener: AudioObjectPropertyListenerBlock?
  private var volumeListener: AudioObjectPropertyListenerBlock?
  private var volumeAddress = AudioObjectPropertyAddress(
    mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
    mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)

  init() {
    let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
      MainActor.assumeIsolated { self?.refresh() }
    }
    outputListener = listener
    for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDevices] {
      var address = Self.address(selector)
      AudioObjectAddPropertyListenerBlock(
        AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
    }
    refresh()
  }

  private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress
  {
    .init(
      mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
  }

  func refresh() {
    if let volumeListener, device != 0 {
      AudioObjectRemovePropertyListenerBlock(device, &volumeAddress, .main, volumeListener)
    }
    var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    _ = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
    outputs = readOutputs()
    displays = NSScreen.screens.filter {
      guard
        let id = ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
          .uint32Value
      else { return false }
      return CGDisplayIsBuiltin(id) == 0
    }.map(\.localizedName)
    if let current = outputs.first(where: { $0.id == device }) {
      if name != current.name { name = current.name }
      headphones = current.symbol == "headphones" || current.symbol.hasPrefix("airpods")
      battery = current.battery
    }
    readVolume()
    let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
      MainActor.assumeIsolated { self?.readVolume() }
    }
    volumeListener = listener
    if device != 0 { AudioObjectAddPropertyListenerBlock(device, &volumeAddress, .main, listener) }
  }

  private func readOutputs() -> [AudioOutput] {
    var address = Self.address(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    let system = AudioObjectID(kAudioObjectSystemObject)
    guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else {
      return []
    }
    var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else {
      return []
    }
    return devices.compactMap { id in
      var streams = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)
      var streamSize: UInt32 = 0
      guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize) == noErr,
        streamSize > 0
      else { return nil }
      var property = Self.address(kAudioObjectPropertyName)
      var label: Unmanaged<CFString>?
      var bytes = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
      guard AudioObjectGetPropertyData(id, &property, 0, nil, &bytes, &label) == noErr, let label
      else { return nil }
      let name = label.takeRetainedValue() as String
      property.mSelector = kAudioDevicePropertyTransportType
      var transport: UInt32 = 0
      bytes = UInt32(MemoryLayout<UInt32>.size)
      _ = AudioObjectGetPropertyData(id, &property, 0, nil, &bytes, &transport)
      guard
        transport != kAudioDeviceTransportTypeVirtual
          && transport != kAudioDeviceTransportTypeAggregate
      else { return nil }
      let connection: String
      let symbol: String
      switch transport {
      case kAudioDeviceTransportTypeHDMI: (connection, symbol) = ("HDMI", "display")
      case kAudioDeviceTransportTypeDisplayPort: (connection, symbol) = ("DisplayPort", "display")
      case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
        connection = "Bluetooth"
        symbol = name.localizedCaseInsensitiveContains("airpods") ? "airpodspro" : "headphones"
      case kAudioDeviceTransportTypeUSB: (connection, symbol) = ("USB", "headphones")
      default:
        (connection, symbol) = (
          "Built-in",
          name.localizedCaseInsensitiveContains("headphone") ? "headphones" : "speaker.wave.2"
        )
      }
      return AudioOutput(
        id: id, name: name, connection: connection, symbol: symbol,
        battery: readBattery(named: name))
    }
  }

  private func readVolume() {
    var size = UInt32(MemoryLayout<Float32>.size)
    var value: Float32 = 0
    var settable = DarwinBoolean(false)
    canSetVolume =
      AudioObjectGetPropertyData(device, &volumeAddress, 0, nil, &size, &value) == noErr
      && AudioObjectIsPropertySettable(device, &volumeAddress, &settable) == noErr
      && settable.boolValue
    if canSetVolume { volume = value }
  }

  func setVolume(_ value: Float32) {
    var next = min(1, max(0, value))
    if AudioObjectSetPropertyData(
      device, &volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &next) == noErr
    {
      volume = next
    }
  }

  func select(_ output: AudioOutput) {
    var next = output.id
    var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
    if AudioObjectSetPropertyData(
      AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
      UInt32(MemoryLayout<AudioDeviceID>.size), &next) == noErr
    {
      refresh()
    }
  }

  // Missing battery data stays unknown; it is never replaced with an example percentage.
  private func readBattery(named name: String) -> Int? {
    for service in ["AppleDeviceManagementHIDEventService", "AppleHSBluetoothDevice"] {
      var iterator: io_iterator_t = 0
      guard
        IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(service), &iterator)
          == KERN_SUCCESS
      else { continue }
      defer { IOObjectRelease(iterator) }
      var entry = IOIteratorNext(iterator)
      while entry != 0 {
        let current = entry
        defer { IOObjectRelease(current) }
        var properties: Unmanaged<CFMutableDictionary>?
        if IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0)
          == KERN_SUCCESS,
          let data = properties?.takeRetainedValue() as? [String: Any],
          let product = (data["Product"] ?? data["DeviceName"]) as? String,
          product.caseInsensitiveCompare(name) == .orderedSame
        {
          if let percent = data["BatteryPercent"] as? Int, (0...100).contains(percent) {
            return percent
          }
          let earbuds = [data["BatteryPercentLeft"] as? Int, data["BatteryPercentRight"] as? Int]
            .compactMap { $0 }.filter { (0...100).contains($0) }
          if let remaining = earbuds.min() { return remaining }
        }
        entry = IOIteratorNext(iterator)
      }
    }
    return nil
  }
}
