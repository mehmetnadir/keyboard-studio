import Foundation

/// Physical layout of the K86 — a 75% board with a knob in the top right.
///
/// Positions are in key units (1u = one alphanumeric key). Rendering multiplies
/// by a pixel scale, so the same model drives the effect previews and, later,
/// the per-key painting canvas.
struct KeyboardLayout {
  struct Key: Identifiable, Hashable {
    let id: Int
    /// HID usage id (page 0x07), so painting and statistics speak the same
    /// language. `nil` for the knob, which is not a keyboard usage.
    let usage: Int?
    let label: String
    let x: Double
    let y: Double
    var width: Double = 1
    var height: Double = 1
    var isKnob: Bool = false
  }

  let keys: [Key]
  let columns: Double
  let rows: Double

  static let k86: KeyboardLayout = {
    var keys: [Key] = []
    var id = 0
    func add(_ label: String, _ usage: Int?, _ x: Double, _ y: Double, _ w: Double = 1) {
      keys.append(Key(id: id, usage: usage, label: label, x: x, y: y, width: w))
      id += 1
    }

    // Row 0 — Esc, function row, knob at the far right.
    add("Esc", 0x29, 0, 0)
    let functionUsages = [0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F, 0x40, 0x41, 0x42, 0x43, 0x44, 0x45]
    for (index, usage) in functionUsages.enumerated() {
      add("F\(index + 1)", usage, 1.5 + Double(index), 0)
    }
    add("Del", 0x4C, 14, 0)
    keys.append(
      Key(id: id, usage: nil, label: "Knob", x: 15.25, y: 0, width: 1, height: 1, isKnob: true))
    id += 1

    // Row 1 — number row.
    let numberRow: [(String, Int)] = [
      ("`", 0x35), ("1", 0x1E), ("2", 0x1F), ("3", 0x20), ("4", 0x21), ("5", 0x22),
      ("6", 0x23), ("7", 0x24), ("8", 0x25), ("9", 0x26), ("0", 0x27), ("-", 0x2D),
      ("=", 0x2E),
    ]
    for (index, key) in numberRow.enumerated() {
      add(key.0, key.1, Double(index), 1.25)
    }
    add("⌫", 0x2A, 13, 1.25, 2)
    add("PgUp", 0x4B, 15.25, 1.25)

    // Row 2 — QWERTY.
    add("Tab", 0x2B, 0, 2.25, 1.5)
    let topRow: [(String, Int)] = [
      ("Q", 0x14), ("W", 0x1A), ("E", 0x08), ("R", 0x15), ("T", 0x17), ("Y", 0x1C),
      ("U", 0x18), ("I", 0x0C), ("O", 0x12), ("P", 0x13), ("[", 0x2F), ("]", 0x30),
    ]
    for (index, key) in topRow.enumerated() {
      add(key.0, key.1, 1.5 + Double(index), 2.25)
    }
    add("\\", 0x31, 13.5, 2.25, 1.5)
    add("PgDn", 0x4E, 15.25, 2.25)

    // Row 3 — home row.
    add("Caps", 0x39, 0, 3.25, 1.75)
    let homeRow: [(String, Int)] = [
      ("A", 0x04), ("S", 0x16), ("D", 0x07), ("F", 0x09), ("G", 0x0A), ("H", 0x0B),
      ("J", 0x0D), ("K", 0x0E), ("L", 0x0F), (";", 0x33), ("'", 0x34),
    ]
    for (index, key) in homeRow.enumerated() {
      add(key.0, key.1, 1.75 + Double(index), 3.25)
    }
    add("Enter", 0x28, 12.75, 3.25, 2.25)
    add("Home", 0x4A, 15.25, 3.25)

    // Row 4 — bottom letter row.
    add("Shift", 0xE1, 0, 4.25, 2.25)
    let bottomRow: [(String, Int)] = [
      ("Z", 0x1D), ("X", 0x1B), ("C", 0x06), ("V", 0x19), ("B", 0x05), ("N", 0x11),
      ("M", 0x10), (",", 0x36), (".", 0x37), ("/", 0x38),
    ]
    for (index, key) in bottomRow.enumerated() {
      add(key.0, key.1, 2.25 + Double(index), 4.25)
    }
    add("Shift", 0xE5, 12.25, 4.25, 1.75)
    add("↑", 0x52, 14.25, 4.25)
    add("End", 0x4D, 15.25, 4.25)

    // Row 5 — modifiers and space.
    add("Ctrl", 0xE0, 0, 5.25, 1.25)
    add("⌥", 0xE2, 1.25, 5.25, 1.25)
    add("⌘", 0xE3, 2.5, 5.25, 1.25)
    add("Space", 0x2C, 3.75, 5.25, 6.25)
    add("⌘", 0xE7, 10, 5.25)
    add("⌥", 0xE6, 11, 5.25)
    add("Fn", nil, 12, 5.25)
    add("←", 0x50, 13.25, 5.25)
    add("↓", 0x51, 14.25, 5.25)
    add("→", 0x4F, 15.25, 5.25)

    return KeyboardLayout(keys: keys, columns: 16.25, rows: 6.25)
  }()

  /// Normalised 0…1 position, used by effect maths so an effect looks the same
  /// whatever the render size.
  func normalised(_ key: Key) -> (x: Double, y: Double) {
    ((key.x + key.width / 2) / columns, (key.y + key.height / 2) / rows)
  }
}
