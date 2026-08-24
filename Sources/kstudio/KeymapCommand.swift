import Foundation
import KeyboardKit
import StatsCore

/// `kstudio keymap` — read-only exploration of the keymap read opcode.
///
/// The knob's actions live in the keymap as extra slots beyond the physical
/// keys, so working out the slot layout is the prerequisite for configuring it.
/// This command only reads.
enum KeymapCommand {
  static func run(_ args: [String]) throws {
    let kb = try Keyboard()
    defer { kb.close() }

    guard try kb.verifyIdentity() else {
      errPrint("error: connected board does not match this profile — refusing to continue")
      exit(1)
    }
    print("\(kb.profile.displayName) — device id \((try kb.deviceID()).map(String.init) ?? "?")")
    print(String(repeating: "─", count: 66))

    // Sweep a few plausible parameter shapes; the firmware ignores what it
    // does not understand, so this is safe and tells us which shape it answers.
    if let map = try Keymap.discoverKnobSlots(on: kb) {
      print("Knob slots found:")
      let bindings = try Keymap.readKnob(map, on: kb)
      for action in Knob.Action.allCases {
        let index = map.slot(for: action)
        let described: String
        switch bindings[action] ?? .unassigned {
        case .media(let code):
          described = Knob.mediaName(code).map { "\($0) (0x\(String(code, radix: 16)))" }
            ?? "media 0x\(String(code, radix: 16))"
        case .key(let usage): described = "key \(KeyNames.name(for: usage))"
        case .raw(let bytes): described = bytes.map { String(format: "%02x", $0) }.joined()
        case .unassigned: described = "unassigned"
        }
        print(String(format: "  %-10@ slot %-3d  %@",
          action.rawValue as NSString, index, described as NSString))
      }
    } else {
      print("No knob slots found — this board may not have a knob.")
    }

    print("\nAll non-key slots (type != 0x00):")
    for page in 0..<8 {
      let slots = try Keymap.readPage(page, on: kb)
      for (index, bytes) in slots.enumerated() where bytes[0] != 0x00 || bytes[1] != 0x00 {
        let global = Keymap.globalSlot(page: page, index: index)
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        print(String(format: "  slot %-4d p%d i%-3d  %@", global, page, index, hex as NSString))
      }
    }

    print("\nFirst pages, decoded:")
    for page in 0..<3 {
      let slots = try Keymap.readPage(page, on: kb)
      let described = slots.prefix(8).map { bytes -> String in
        bytes[0] == 0x00 && bytes[2] != 0 ? KeyNames.name(for: Int(bytes[2]))
          : (bytes == [0, 0, 0, 0] ? "·" : "0x\(String(bytes[0], radix: 16)):\(bytes[2])")
      }
      print("  page \(page): \(described.joined(separator: " "))")
    }

    print(
      """

      Slots are 4 bytes: [type, ?, code, ?]. Types: 0x00 HID usage,
      0x03 consumer/media, 0x09 macro, 0x0A special. MEDIA entries are the
      interesting ones — a knob defaults to volume up/down.
      """)
  }
}
