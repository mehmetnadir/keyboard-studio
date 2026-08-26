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
    /// A firmware action — something the keyboard does to itself rather than
    /// a keystroke it sends. Slot type 0x0A, with the action in byte 1.
    case firmware(action: FirmwareAction)
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
      case .firmware(let action):
        [0x0A, action.rawValue, 0x00, 0x00]
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
      case 0x0A where FirmwareAction(rawValue: bytes[1]) != nil:
        self = .firmware(action: FirmwareAction(rawValue: bytes[1])!)
      default: self = .raw(bytes: bytes)
      }
    }
  }

  /// Actions the firmware performs on itself, rather than keystrokes it sends.
  ///
  /// These are slot type `0x0A` with the action id in byte 1, taken from the
  /// vendor client's own action table. They matter here because the knob's
  /// behaviour is firmware state, not a key binding: on this board turning the
  /// knob opens the keyboard's settings menu no matter what the knob's slots
  /// say, and no command exists to switch that menu off.
  ///
  /// `wheelSwap` is the one lead worth trying. The vendor names it "Wheel
  /// Swap" on one board and "volume <-> keyboard brightness" on another, which
  /// says it changes *what the encoder controls* — the only knob-mode control
  /// found anywhere in either vendor client.
  public enum FirmwareAction: UInt8, CaseIterable, Sendable {
    case officeGaming = 6
    case keyboardLock = 7
    case checkBattery = 8
    case ledOnOff = 9
    case wasdChange = 10
    case fnKeyMatrixChange = 11
    case powerSaves = 12
    case fnLock = 13
    case wheelSwap = 14
    case capsSwap = 15
    case sleepToggle = 16
    case capsLedSwap = 17
    case powerDown = 18
    case fnKeySwap = 19
    case altTab = 20
    case languageSwitch = 21

    public var label: String {
      switch self {
      case .officeGaming: "Office/Gaming"
      case .keyboardLock: "Keyboard lock"
      case .checkBattery: "Check battery"
      case .ledOnOff: "LED on/off"
      case .wasdChange: "WASD swap"
      case .fnKeyMatrixChange: "Fn key matrix"
      case .powerSaves: "Power saving"
      case .fnLock: "Fn lock"
      case .wheelSwap: "Wheel mode swap"
      case .capsSwap: "Caps swap"
      case .sleepToggle: "Sleep toggle"
      case .capsLedSwap: "Caps LED swap"
      case .powerDown: "Power down"
      case .fnKeySwap: "Fn key swap"
      case .altTab: "Alt-Tab"
      case .languageSwitch: "Language switch"
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
