import Foundation
import IOKit.hid

/// Reports which of the keyboard's HID interfaces will actually open.
///
/// `IOHIDManagerOpen` opens every matching device at once and reports a single
/// result, so one interface refusing takes the whole thing down and says
/// nothing about which one it was. This opens them one at a time and prints the
/// verdict for each, which is the difference between "counting is broken" and
/// "this one interface is held by something else".
public enum HIDDiagnostics {
  /// Tries every keyboard on the machine, not just ours.
  ///
  /// If the built-in keyboard refuses too, nothing is "holding" this keyboard
  /// in particular — the refusal is system-wide and the cause is a filter
  /// driver or an OS policy, not another app fighting over one device.
  public static func runAllKeyboards() throws {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(manager, [
      kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
      kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard,
    ] as CFDictionary)
    guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
      print("No keyboards matched at all.")
      return
    }
    print("Every keyboard on this machine:\n")
    for device in devices {
      let name = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String)
        ?? "unnamed"
      let vendor = (IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? NSNumber)?
        .intValue ?? -1
      let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
      if result == kIOReturnSuccess {
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
      }
      print(String(format: "  %-34@ vendor 0x%04x  %@",
                   name as NSString, vendor,
                   (result == kIOReturnSuccess
                     ? "opens"
                     : String(format: "refused (0x%08x)", UInt32(bitPattern: result))) as NSString))
    }
  }

  public static func run() throws {
    let profile = DeviceCatalog.firstConnected() ?? DeviceCatalog.all().first
    guard let profile else {
      print("No device profile available.")
      return
    }
    let vendor = profile.vendorID
    print("Looking for vendor 0x\(String(vendor, radix: 16)) — \(profile.displayName)\n")

    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    // Deliberately matching on vendor alone: the point is to see every
    // interface the keyboard exposes, including the ones the monitor filters
    // out, and how each one responds to being opened.
    IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: vendor] as CFDictionary)

    guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !devices.isEmpty
    else {
      print("No devices matched. Is the keyboard connected by cable and switched to USB?")
      return
    }

    print(String(format: "%-6@ %-6@ %-5@ %-9@ %@",
                 "usage" as NSString, "page" as NSString, "prod" as NSString,
                 "open?" as NSString, "detail" as NSString))
    print(String(repeating: "─", count: 62))

    for device in devices {
      func number(_ key: String) -> Int {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? -1
      }
      let usagePage = number(kIOHIDPrimaryUsagePageKey)
      let usage = number(kIOHIDPrimaryUsageKey)
      let product = number(kIOHIDProductIDKey)

      let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
      let verdict: String
      switch result {
      case kIOReturnSuccess:
        verdict = "yes"
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
      case kIOReturnExclusiveAccess:
        verdict = "no"
      case kIOReturnNotPermitted:
        verdict = "no"
      default:
        verdict = "no"
      }
      let detail: String
      switch result {
      case kIOReturnSuccess: detail = "opened and closed cleanly"
      case kIOReturnExclusiveAccess: detail = "exclusive access — held by another process"
      case kIOReturnNotPermitted: detail = "not permitted — Input Monitoring not granted"
      default: detail = String(format: "IOReturn 0x%08x", UInt32(bitPattern: result))
      }

      print(String(format: "%-6d %-6d 0x%04x %-9@ %@",
                   usage, usagePage, product, verdict as NSString, detail as NSString))
    }

    print("""

      Counting needs usage 6 on page 1 (Generic Desktop / Keyboard). If that row
      says "not permitted", grant Input Monitoring to whichever binary you ran.
      If it says "exclusive access", another process has seized the keyboard —
      Karabiner-Elements is the usual one.
      """)
  }
}
