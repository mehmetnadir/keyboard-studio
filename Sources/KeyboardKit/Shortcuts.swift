import Foundation

/// Key combinations a slot can be bound to.
///
/// A keymap slot is `[type, modifiers, usage, 0]`, and the second byte is the
/// standard HID modifier mask — so a slot can hold ⌘Space just as easily as a
/// plain letter. That is what makes shortcuts possible without macros.
public struct Shortcut: Sendable, Equatable, Hashable {
  /// HID usage id from page 0x07.
  public var usage: Int
  public var modifiers: Modifiers

  public init(usage: Int, modifiers: Modifiers = []) {
    self.usage = usage
    self.modifiers = modifiers
  }

  public struct Modifiers: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let control = Modifiers(rawValue: 0x01)
    public static let shift = Modifiers(rawValue: 0x02)
    public static let option = Modifiers(rawValue: 0x04)
    public static let command = Modifiers(rawValue: 0x08)
    public static let rightControl = Modifiers(rawValue: 0x10)
    public static let rightShift = Modifiers(rawValue: 0x20)
    public static let rightOption = Modifiers(rawValue: 0x40)
    public static let rightCommand = Modifiers(rawValue: 0x80)

    /// Mac order, as the system writes it: ⌃⌥⇧⌘.
    public var symbols: String {
      var out = ""
      if contains(.control) || contains(.rightControl) { out += "⌃" }
      if contains(.option) || contains(.rightOption) { out += "⌥" }
      if contains(.shift) || contains(.rightShift) { out += "⇧" }
      if contains(.command) || contains(.rightCommand) { out += "⌘" }
      return out
    }
  }

  public var slotBytes: [UInt8] {
    [0x00, modifiers.rawValue, UInt8(clamping: usage), 0x00]
  }

  public init?(slotBytes bytes: [UInt8]) {
    guard bytes.count == 4, bytes[0] == 0x00, bytes[2] != 0 else { return nil }
    self.init(usage: Int(bytes[2]), modifiers: Modifiers(rawValue: bytes[1]))
  }
}

/// Ready-made macOS shortcuts, so someone who has never thought about HID
/// usages can bind something useful in two clicks.
///
/// These are the system's own defaults. A user who has changed a shortcut in
/// System Settings should use the custom option instead.
public enum MacShortcuts {
  public struct Entry: Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let category: Category
    public let shortcut: Shortcut

    public var display: String {
      shortcut.modifiers.symbols + KeyLabels.name(for: shortcut.usage)
    }
  }

  public enum Category: String, Sendable, CaseIterable, Identifiable {
    case system = "System"
    case screenshot = "Screenshots"
    case window = "Windows & Spaces"
    case text = "Editing"
    case media = "Media"
    public var id: String { rawValue }
  }

  public static let all: [Entry] = [
    // System
    entry("spotlight", "Spotlight search", .system, 0x2C, [.command]),
    entry("launchpad", "Launchpad", .system, 0x3D),
    entry("mission-control", "Mission Control", .system, 0x3C),
    entry("lock-screen", "Lock screen", .system, 0x14, [.control, .command]),
    entry("force-quit", "Force Quit menu", .system, 0x29, [.option, .command]),
    entry("finder", "New Finder window", .system, 0x11, [.command]),
    entry("emoji", "Emoji picker", .system, 0x2C, [.control, .command]),

    // Screenshots
    entry("shot-screen", "Screenshot: whole screen", .screenshot, 0x20, [.shift, .command]),
    entry("shot-area", "Screenshot: selection", .screenshot, 0x21, [.shift, .command]),
    entry("shot-tools", "Screenshot tools", .screenshot, 0x22, [.shift, .command]),
    entry("shot-clip", "Selection to clipboard", .screenshot, 0x21, [.control, .shift, .command]),

    // Windows & Spaces
    entry("app-switch", "Switch apps", .window, 0x2B, [.command]),
    entry("window-switch", "Switch windows in app", .window, 0x35, [.command]),
    entry("minimise", "Minimise window", .window, 0x10, [.command]),
    entry("hide", "Hide app", .window, 0x0B, [.command]),
    entry("close-window", "Close window", .window, 0x1B, [.command]),
    entry("fullscreen", "Full screen", .window, 0x09, [.control, .command]),
    entry("space-left", "Move a space left", .window, 0x50, [.control]),
    entry("space-right", "Move a space right", .window, 0x4F, [.control]),

    // Editing
    entry("copy", "Copy", .text, 0x06, [.command]),
    entry("paste", "Paste", .text, 0x19, [.command]),
    entry("paste-plain", "Paste as plain text", .text, 0x19, [.option, .shift, .command]),
    entry("cut", "Cut", .text, 0x1B, [.command]),
    entry("undo", "Undo", .text, 0x1D, [.command]),
    entry("redo", "Redo", .text, 0x1D, [.shift, .command]),
    entry("select-all", "Select all", .text, 0x04, [.command]),
    entry("find", "Find", .text, 0x09, [.command]),
    entry("save", "Save", .text, 0x16, [.command]),
  ]

  public static func entries(in category: Category) -> [Entry] {
    all.filter { $0.category == category }
  }

  private static func entry(
    _ id: String, _ name: String, _ category: Category, _ usage: Int,
    _ modifiers: Shortcut.Modifiers = []
  ) -> Entry {
    Entry(
      id: id, name: name, category: category,
      shortcut: Shortcut(usage: usage, modifiers: modifiers))
  }
}

/// Human labels for HID usages, used when describing a binding.
public enum KeyLabels {
  public static func name(for usage: Int) -> String {
    if let known = table[usage] { return known }
    if (0x04...0x1D).contains(usage) {
      return String(UnicodeScalar(UInt8(usage - 0x04 + 65)))
    }
    if (0x1E...0x26).contains(usage) { return String(usage - 0x1E + 1) }
    if (0x3A...0x45).contains(usage) { return "F\(usage - 0x3A + 1)" }
    return String(format: "0x%02X", usage)
  }

  private static let table: [Int: String] = [
    0x27: "0", 0x28: "↩", 0x29: "esc", 0x2A: "⌫", 0x2B: "⇥", 0x2C: "Space",
    0x2D: "-", 0x2E: "=", 0x2F: "[", 0x30: "]", 0x31: "\\", 0x33: ";", 0x34: "'",
    0x35: "`", 0x36: ",", 0x37: ".", 0x38: "/", 0x39: "⇪", 0x4A: "↖", 0x4B: "⇞",
    0x4C: "⌦", 0x4D: "↘", 0x4E: "⇟", 0x4F: "→", 0x50: "←", 0x51: "↓", 0x52: "↑",
  ]
}
