import Foundation
import IOKit.hid

public enum K86Error: Error, CustomStringConvertible {
  case deviceNotFound
  case openFailed(IOReturn)
  case reportFailed(IOReturn)
  case staleResponse
  case screenHandshakeFailed
  case invalidFrame(String)
  case imageDecodeFailed

  public var description: String {
    switch self {
    case .deviceNotFound:
      "K86 not found. Connect it with the USB cable (back switches: Win/Mac + USB)."
    case .openFailed(let code):
      "Could not open the K86 control interface (IOReturn \(Self.hex(code)))."
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

  static func findVendorInterface() -> IOHIDDevice? {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    let matching: [String: Any] = [
      kIOHIDVendorIDKey: Proto.vid,
      kIOHIDProductIDKey: Proto.pid,
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

  init() throws {
    guard let device = Self.findVendorInterface() else { throw K86Error.deviceNotFound }
    let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
    guard result == kIOReturnSuccess else { throw K86Error.openFailed(result) }
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
    guard result == kIOReturnSuccess else { throw K86Error.reportFailed(result) }
  }

  func getFeature() throws -> [UInt8] {
    var data = [UInt8](repeating: 0, count: Proto.reportLen)
    var length = CFIndex(Proto.reportLen)
    let result = data.withUnsafeMutableBufferPointer { buffer in
      IOHIDDeviceGetReport(
        device, kIOHIDReportTypeFeature, 0, buffer.baseAddress!, &length)
    }
    guard result == kIOReturnSuccess else { throw K86Error.reportFailed(result) }
    return Array(data.prefix(max(0, min(Int(length), Proto.reportLen))))
  }

  func close() {
    guard isOpen else { return }
    isOpen = false
    IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
  }
}
