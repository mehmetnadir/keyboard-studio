import Foundation

/// The rotary encoder in the top-right corner — the knob.
///
/// The firmware stores its three actions as ordinary keymap slots that sit just
/// past the physical keys, so configuring it is a keymap write rather than a
/// dedicated command. Slot positions are read from the device rather than
/// assumed: they differ between models in this family.
public enum Knob {
  public enum Action: String, CaseIterable, Sendable, Identifiable {
    case turnLeft, turnRight, press
    public var id: String { rawValue }
  }

  /// What a knob action does.
  public enum Binding: Equatable, Sendable {
    /// Consumer-control usage (volume, media transport, brightness…).
    case media(code: Int)
    /// Ordinary key, by HID usage id from page 0x07.
    case key(usage: Int)
    /// Something this app does not model yet; kept verbatim so writing one
    /// action never silently rewrites another.
    case raw(bytes: [UInt8])
    case unassigned

    /// The 4-byte slot encoding: [type, modifier, code, 0].
    public var slotBytes: [UInt8] {
      switch self {
      case .media(let code):
        [0x03, 0x00, UInt8(clamping: code), 0x00]
      case .key(let usage):
        [0x00, 0x00, UInt8(clamping: usage), 0x00]
      case .raw(let bytes):
        bytes
      case .unassigned:
        [0x00, 0x00, 0x00, 0x00]
      }
    }

    public init(slotBytes bytes: [UInt8]) {
      guard bytes.count == 4 else {
        self = .raw(bytes: bytes)
        return
      }
      switch bytes[0] {
      case 0x00 where bytes[2] == 0: self = .unassigned
      case 0x00: self = .key(usage: Int(bytes[2]))
      case 0x03: self = .media(code: Int(bytes[2]))
      default: self = .raw(bytes: bytes)
      }
    }
  }

  /// Consumer-control usages worth offering. Values are HID Consumer Page
  /// (0x0C) usage ids, which is what the firmware stores for `0x03` slots.
  public static let mediaOptions: [(code: Int, name: String)] = [
    (0xE9, "Volume up"), (0xEA, "Volume down"), (0xE2, "Mute"),
    (0xCD, "Play / Pause"), (0xB5, "Next track"), (0xB6, "Previous track"),
    (0xB7, "Stop"), (0x6F, "Brightness up"), (0x70, "Brightness down"),
    (0x221, "Search"), (0x192, "Calculator"), (0x196, "Browser"),
  ]

  public static func mediaName(_ code: Int) -> String? {
    mediaOptions.first { $0.code == code }?.name
  }

  /// Where a model keeps its knob actions, as global keymap slot numbers.
  ///
  /// Global rather than page-relative because the three actions need not share
  /// a page: on the K86 the turns sit at 96/97, at the end of the matrix, while
  /// mute is at 78.
  public struct SlotMap: Sendable, Equatable {
    public var turnLeft: Int
    public var turnRight: Int
    public var press: Int

    public init(turnLeft: Int, turnRight: Int, press: Int) {
      self.turnLeft = turnLeft
      self.turnRight = turnRight
      self.press = press
    }

    public func slot(for action: Action) -> Int {
      switch action {
      case .turnLeft: turnLeft
      case .turnRight: turnRight
      case .press: press
      }
    }
  }
}
