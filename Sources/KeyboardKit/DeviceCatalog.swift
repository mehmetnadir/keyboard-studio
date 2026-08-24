import Foundation
import IOKit.hid

/// Loads device profiles and matches them against what is plugged in.
public enum DeviceCatalog {
  /// Profiles bundled with the app, plus anything the user dropped into
  /// `~/Library/Application Support/KeyboardStudio/Devices/` — so a board can
  /// be added without rebuilding.
  public static func all() -> [DeviceProfile] {
    (bundled() + userSupplied()).sorted { $0.id < $1.id }
  }

  public static func profile(id: String) -> DeviceProfile? {
    all().first { $0.id == id }
  }

  /// Profiles for keyboards currently attached.
  public static func connected() -> [DeviceProfile] {
    let attached = attachedDevices()
    return all().filter { profile in
      attached.contains { profile.matches(vendorID: $0.vendor, productID: $0.product) }
    }
  }

  /// First connected keyboard, if any — what the CLI and the app open by default.
  public static func firstConnected() -> DeviceProfile? {
    connected().first
  }

  // MARK: - Loading

  private static func bundled() -> [DeviceProfile] {
    guard let urls = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "Devices")
    else { return [] }
    return urls.compactMap(decode)
  }

  public static var userDirectory: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first ?? FileManager.default.homeDirectoryForCurrentUser
    return base.appendingPathComponent("KeyboardStudio/Devices", isDirectory: true)
  }

  private static func userSupplied() -> [DeviceProfile] {
    guard let entries = try? FileManager.default.contentsOfDirectory(
      at: userDirectory, includingPropertiesForKeys: nil)
    else { return [] }
    return entries.filter { $0.pathExtension == "json" }.compactMap(decode)
  }

  private static func decode(_ url: URL) -> DeviceProfile? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(DeviceProfile.self, from: data)
  }

  // MARK: - USB enumeration

  struct AttachedDevice {
    let vendor: Int
    let product: Int
  }

  /// Every HID device currently present, as (vendor, product) pairs.
  static func attachedDevices() -> [AttachedDevice] {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(manager, nil)
    IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
    guard let raw = IOHIDManagerCopyDevices(manager) else { return [] }
    return (raw as NSSet).compactMap { entry in
      let device = entry as! IOHIDDevice
      guard let vendor = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int,
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int
      else { return nil }
      return AttachedDevice(vendor: vendor, product: product)
    }
  }
}
