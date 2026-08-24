import Foundation
import KeyboardKit

/// `kstudio keymap --restore-knob` — puts the knob's factory bindings back.
///
/// Exists because the write experiment left two slots changed: verification
/// was reading a cached reply, so a successful write looked like a failure and
/// the restore was judged wrong. Every check here re-opens the device first.
enum KeymapRestore {
  /// Factory values for this board, read from the device before any writing.
  static let knobTurnLeft: [UInt8] = [0x03, 0x00, 0xEA, 0x00]   // volume down
  static let knobTurnRight: [UInt8] = [0x03, 0x00, 0xE9, 0x00]  // volume up

  static func run() throws {
    print("Restoring knob bindings and clearing test writes…")

    try set(slot: 96, to: knobTurnLeft, label: "knob turn-left → volume down")
    try set(slot: 97, to: knobTurnRight, label: "knob turn-right → volume up")
    try set(slot: 11, to: [0, 0, 0, 0], label: "slot 11 → unassigned")

    print("\nFinal state:")
    let kb = try Keyboard()
    defer { kb.close() }
    for slot in [11, 96, 97] {
      let (page, index) = Keymap.location(of: slot)
      let bytes = try Keymap.readSlot(page: page, index: index, on: kb) ?? []
      print("  slot \(slot): \(bytes.map { String(format: "%02x", $0) }.joined())")
    }
  }

  /// Writes a slot, then re-opens the device to read it back.
  ///
  /// The re-open is the whole point: a read on the same connection returns a
  /// cached reply, so it will happily show the old value after a successful
  /// write.
  private static func set(slot: Int, to bytes: [UInt8], label: String) throws {
    do {
      let kb = try Keyboard()
      try Keymap.writeSlot(slot, bytes: bytes, on: kb)
      kb.close()
    }
    Thread.sleep(forTimeInterval: 0.4)

    let verify = try Keyboard()
    defer { verify.close() }
    let (page, index) = Keymap.location(of: slot)
    let after = try Keymap.readSlot(page: page, index: index, on: verify)
    let ok = after == bytes
    print("  \(ok ? "✅" : "⚠️ ") \(label)")
  }
}
