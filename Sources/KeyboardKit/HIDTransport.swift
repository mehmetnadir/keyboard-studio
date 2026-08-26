import Foundation
import IOKit.hid

public enum DeviceError: Error, CustomStringConvertible {
  case deviceNotFound
  case openFailed(IOReturn)
  case reportFailed(IOReturn)
  case staleResponse
  case screenHandshakeFailed
  case invalidFrame(String)
  case imageDecodeFailed
  case identityMismatch
  case rateLimited(seconds: TimeInterval)
  case blockedCommand(opcode: UInt8)

  public var description: String {
    switch self {
    case .deviceNotFound:
      "No supported keyboard found. Connect it with the USB cable (switches on the back: Mac + USB)."
    case .openFailed(let code):
      "Could not open the keyboard's control interface (IOReturn \(Self.hex(code)))."
    case .reportFailed(let code):
      "HID feature report failed (IOReturn \(Self.hex(code)))."
    case .staleResponse:
      "Device returned a stale or mismatched report — unplug/replug and try again."
    case .screenHandshakeFailed:
      "Screen handshake failed — the device did not report ready."
    case .invalidFrame(let reason):
      "Invalid screen frame: \(reason)."
    case .imageDecodeFailed:
      "Could not decode the image."
    case .identityMismatch:
      "The connected keyboard is not the model this profile describes — refusing to write to it."
    case .blockedCommand(let opcode):
      """
      Refusing to send command \(String(format: "0x%02X", opcode)): it erases \
      stored data or enters the bootloader.
      """
    case .rateLimited(let seconds):
      """
      Too soon — per-key colour is written to the keyboard's flash, so uploads \
      are spaced out. Try again in \(Int(seconds.rounded(.up))) s.
      """
    }
  }

  private static func hex(_ code: IOReturn) -> String {
    String(format: "0x%08x", UInt32(bitPattern: code))
  }
}

/// Synchronous feature-report transport over the K86's vendor HID interface.
final class HIDTransport {
  private let device: IOHIDDevice
  private var isOpen = false

  static func findVendorInterface(_ profile: DeviceProfile) -> IOHIDDevice? {
    for productID in profile.productIDs {
      if let device = findVendorInterface(vendorID: profile.vendorID, productID: productID) {
        return device
      }
    }
    return nil
  }

  static func findVendorInterface(vendorID: Int, productID: Int) -> IOHIDDevice? {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    let matching: [String: Any] = [
      kIOHIDVendorIDKey: vendorID,
      kIOHIDProductIDKey: productID,
    ]
    IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
    IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
    guard let raw = IOHIDManagerCopyDevices(manager) else { return nil }
    // The set from IOHIDManagerCopyDevices only ever contains IOHIDDevice refs;
    // ARC retains them through the bridged array, so they outlive the manager.
    let devices = (raw as NSSet).map { $0 as! IOHIDDevice }

    func intProperty(_ device: IOHIDDevice, _ key: String) -> Int? {
      IOHIDDeviceGetProperty(device, key as CFString) as? Int
    }
    // Prefer the exact control channel (usage page 0xFFFF, usage 2), fall back
    // to any vendor-page interface — mirrors the reference implementation.
    if let exact = devices.first(where: {
      intProperty($0, kIOHIDPrimaryUsagePageKey) == Proto.vendorUsagePage
        && intProperty($0, kIOHIDPrimaryUsageKey) == Proto.vendorUsage
    }) {
      return exact
    }
    return devices.first {
      intProperty($0, kIOHIDPrimaryUsagePageKey) == Proto.vendorUsagePage
    }
  }

  init(profile: DeviceProfile) throws {
    guard let device = Self.findVendorInterface(profile) else { throw DeviceError.deviceNotFound }
    let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
    guard result == kIOReturnSuccess else { throw DeviceError.openFailed(result) }
    self.device = device
    self.isOpen = true
  }

  deinit {
    close()
  }

  /// Report id is 0 (unnumbered): the raw 64-byte payload goes on the wire.
  func sendFeature(_ payload: [UInt8]) throws {
    let result = payload.withUnsafeBufferPointer { buffer -> IOReturn in
      guard let base = buffer.baseAddress, !buffer.isEmpty else { return kIOReturnBadArgument }
      return IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 0, base, buffer.count)
    }
    guard result == kIOReturnSuccess else { throw DeviceError.reportFailed(result) }
  }

  func getFeature() throws -> [UInt8] {
    var data = [UInt8](repeating: 0, count: Proto.reportLen)
    var length = CFIndex(Proto.reportLen)
    let result = data.withUnsafeMutableBufferPointer { buffer in
      IOHIDDeviceGetReport(
        device, kIOHIDReportTypeFeature, 0, buffer.baseAddress!, &length)
    }
    guard result == kIOReturnSuccess else { throw DeviceError.reportFailed(result) }
    return Array(data.prefix(max(0, min(Int(length), Proto.reportLen))))
  }

  /// Sends on a numbered report id.
  ///
  /// The screen is a second command family: the vendor's client talks to the
  /// keyboard on report id 8 and to the display on report id 13, while every
  /// command this project sends goes out as an unnumbered feature report.
  /// Queries like "what resolution are you?" only answer on the numbered path.
  func send(reportType: IOHIDReportType, reportID: Int, _ payload: [UInt8]) throws {
    let result = payload.withUnsafeBufferPointer { buffer -> IOReturn in
      guard let base = buffer.baseAddress, !buffer.isEmpty else { return kIOReturnBadArgument }
      return IOHIDDeviceSetReport(device, reportType, CFIndex(reportID), base, buffer.count)
    }
    guard result == kIOReturnSuccess else { throw DeviceError.reportFailed(result) }
  }

  func read(reportType: IOHIDReportType, reportID: Int, length: Int) throws -> [UInt8] {
    var data = [UInt8](repeating: 0, count: length)
    var size = CFIndex(length)
    let result = data.withUnsafeMutableBufferPointer { buffer in
      IOHIDDeviceGetReport(device, reportType, CFIndex(reportID), buffer.baseAddress!, &size)
    }
    guard result == kIOReturnSuccess else { throw DeviceError.reportFailed(result) }
    return Array(data.prefix(max(0, min(Int(size), length))))
  }

  func close() {
    guard isOpen else { return }
    isOpen = false
    IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
  }
}
