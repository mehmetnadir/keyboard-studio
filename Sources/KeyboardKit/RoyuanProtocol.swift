import Foundation

/// ROYUAN vendor HID protocol constants for the Attack Shark K86.
///
/// Byte-level layout ported from the MIT-licensed reference implementation
/// (github.com/RaphaelCaputo2/shark-k86-mac), itself reverse-engineered from
/// the official WebHID driver.
///
/// Index mapping caveat: the Python reference reads feature reports through
/// hidapi, which prepends a report-id byte — its `r[i]` equals the raw device
/// byte `f[i-1]` used throughout this port.
public enum Proto {
  static let vid = 0x3151
  static let pid = 0x4015
  static let vendorUsagePage = 0xFFFF
  static let vendorUsage = 0x0002
  public static let reportLen = 64

  static let opGetRev: UInt8 = 0x80
  /// Whoami: replies with a little-endian u32 model id in bytes 1..4.
  static let opGetDeviceID: UInt8 = 0x8F
  /// Keymap read. Slots are 4 bytes; byte 0 is the action type.
  public static let opGetKeymap: UInt8 = 0x89
  /// Bulk keymap write: nine 56-byte chunks carrying the whole matrix.
  public static let opSetKeymap: UInt8 = 0x09
  /// Single-slot keymap write — what the vendor's own UI uses for a key edit,
  /// and far safer than rewriting the whole matrix to change one key.
  public static let opSetKeymapSlot: UInt8 = 0x13
  /// Selects the active onboard profile (the board holds three).
  public static let opSetProfile: UInt8 = 0x05
  public static let opGetProfile: UInt8 = 0x85
  /// Macro write; ids 0...49.
  public static let opSetMacro: UInt8 = 0x16
  public static let opGetMacro: UInt8 = 0x8B
  /// Fn-layer single-slot write.
  public static let opSetFnSlot: UInt8 = 0x15
  public static let opGetFn: UInt8 = 0x90
  static let opGetKBOption: UInt8 = 0x86
  static let opSetKBOption: UInt8 = 0x06
  static let opSetLEDParam: UInt8 = 0x07
  static let opSetSLEDParam: UInt8 = 0x08

  static let lightMaxSpeed = 5
  static let optCustomRGB: UInt8 = 0x07
  static let optRainbow: UInt8 = 0x08

  /// LED-off flag bits inside the kboption "main" byte.
  static let mainLEDOffBit: UInt8 = 0x10
  static let sideLEDOffBit: UInt8 = 0x20
}

enum ChecksumMode {
  case bit7   // checksum over bytes 0..<7, stored in byte 7
  case bit8   // checksum over bytes 0..<8, stored in byte 8
  case none
}

extension Proto {
  /// Build a 64-byte payload with the firmware's complement checksum.
  static func encode(_ cmd: [UInt8], mode: ChecksumMode) -> [UInt8] {
    precondition(cmd.count <= reportLen, "command exceeds the 64-byte report")
    var buf = [UInt8](repeating: 0, count: reportLen)
    for (i, byte) in cmd.enumerated() { buf[i] = byte }
    switch mode {
    case .bit7:
      let sum = buf[0..<7].reduce(0) { ($0 + Int($1)) & 0xFF }
      buf[7] = UInt8((255 - sum) & 0xFF)
    case .bit8:
      let sum = buf[0..<8].reduce(0) { ($0 + Int($1)) & 0xFF }
      buf[8] = UInt8((255 - sum) & 0xFF)
    case .none:
      break
    }
    return buf
  }
}

/// Main/side light effects supported by the K86 firmware.
public enum LightEffect: String, CaseIterable, Sendable {
  case off, solid, breath, neon, wave, ripple, raindrop, snake, press
  case converge, sine, kaleidoscope, linewave, laser, circlewave, dazzle
  case raindown, meteor, train, fireworks

  /// Firmware effect index (LIGHT_LIST order; 13 and 19–22 are unused slots).
  var index: UInt8 {
    switch self {
    case .off: 0
    case .solid: 1
    case .breath: 2
    case .neon: 3
    case .wave: 4
    case .ripple: 5
    case .raindrop: 6
    case .snake: 7
    case .press: 8
    case .converge: 9
    case .sine: 10
    case .kaleidoscope: 11
    case .linewave: 12
    case .laser: 14
    case .circlewave: 15
    case .dazzle: 16
    case .raindown: 17
    case .meteor: 18
    case .train: 23
    case .fireworks: 24
    }
  }
}

public struct RGB: Sendable, Equatable {
  public var r: UInt8
  public var g: UInt8
  public var b: UInt8

  public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) {
    self.r = r
    self.g = g
    self.b = b
  }

  /// Parse "#RRGGBB" / "RRGGBB".
  public init?(hex: String) {
    let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    // isHexDigit guard: UInt32(_:radix:) would also accept a "+" sign prefix.
    guard s.count == 6, s.allSatisfy(\.isHexDigit), let v = UInt32(s, radix: 16) else {
      return nil
    }
    self.init(UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF))
  }
}
