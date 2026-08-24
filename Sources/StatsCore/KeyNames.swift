import AppKit
import Foundation
import IOKit.hid

public enum MonitorError: Error, CustomStringConvertible {
  case inputMonitoringDenied(IOReturn)

  /// True when the failure is the missing Input Monitoring grant, which the
  /// user can fix — as opposed to something they can only report.
  public var isPermissionDenied: Bool {
    if case .inputMonitoringDenied = self { return true }
    return false
  }

  /// Opens System Settings straight at Privacy & Security → Input Monitoring.
  @discardableResult
  public static func openInputMonitoringSettings() -> Bool {
    guard let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    else { return false }
    return NSWorkspace.shared.open(url)
  }

  public var description: String {
    switch self {
    case .inputMonitoringDenied(let code):
      """
      Could not open the keyboard for counting (IOReturn \
      \(String(format: "0x%08x", UInt32(bitPattern: code)))). \
      Grant Input Monitoring in System Settings → Privacy & Security, then try again.
      """
    }
  }
}

/// Display names for HID Keyboard/Keypad usage ids (usage page 0x07).
///
/// Names describe physical keys, not characters: the same usage is "A" on a
/// QWERTY layout and "Q" on AZERTY. Counting a usage says which key was struck,
/// never which character was produced.
public enum KeyNames {
  public static func name(for usage: Int) -> String {
    if let known = table[usage] { return known }
    if (0x04...0x1D).contains(usage) {  // A–Z
      return String(UnicodeScalar(UInt8(usage - 0x04 + 65)))
    }
    if (0x1E...0x26).contains(usage) {  // 1–9
      return String(usage - 0x1E + 1)
    }
    if (0x3A...0x45).contains(usage) {  // F1–F12
      return "F\(usage - 0x3A + 1)"
    }
    return "0x\(String(usage, radix: 16))"
  }

  /// Coarse grouping for dashboards ("you press modifiers 22% of the time").
  public enum Category: String, Sendable, CaseIterable {
    case letter, number, modifier, navigation, function, punctuation, keypad, other
  }

  public static func category(for usage: Int) -> Category {
    switch usage {
    case 0x04...0x1D: .letter
    case 0x1E...0x27: .number
    case 0xE0...0xE7: .modifier
    case 0x4F...0x52, 0x4A...0x4E, 0x29, 0x2B: .navigation
    case 0x3A...0x45, 0x68...0x73: .function
    case 0x2D...0x38: .punctuation
    case 0x53...0x63: .keypad
    default: .other
    }
  }

  private static let table: [Int: String] = [
    0x27: "0", 0x28: "Return", 0x29: "Escape", 0x2A: "Delete", 0x2B: "Tab",
    0x2C: "Space", 0x2D: "-", 0x2E: "=", 0x2F: "[", 0x30: "]", 0x31: "\\",
    0x33: ";", 0x34: "'", 0x35: "`", 0x36: ",", 0x37: ".", 0x38: "/",
    0x39: "Caps Lock", 0x46: "Print Screen", 0x47: "Scroll Lock", 0x48: "Pause",
    0x49: "Insert", 0x4A: "Home", 0x4B: "Page Up", 0x4C: "Forward Delete",
    0x4D: "End", 0x4E: "Page Down", 0x4F: "→", 0x50: "←", 0x51: "↓", 0x52: "↑",
    0x53: "Num Lock", 0x54: "Keypad /", 0x55: "Keypad *", 0x56: "Keypad -",
    0x57: "Keypad +", 0x58: "Keypad Enter", 0x62: "Keypad 0", 0x63: "Keypad .",
    0xE0: "Left Control", 0xE1: "Left Shift", 0xE2: "Left Option",
    0xE3: "Left Command", 0xE4: "Right Control", 0xE5: "Right Shift",
    0xE6: "Right Option", 0xE7: "Right Command",
  ]
}
