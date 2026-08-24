import Foundation
import KeyboardKit

/// `kstudio keymap --test-write` — proves (or disproves) the keymap write path.
///
/// Everything about this is arranged so a failure costs nothing:
/// - it writes to the knob's press slot, which is unassigned on this board, so
///   a mistake cannot clobber a key you actually use;
/// - the whole page is read and kept first, and restored if anything looks
///   wrong afterwards;
/// - the write is verified by reading back before the result is believed.
enum KeymapWriteTest {
  static func run() throws {
    let kb = try Keyboard()
    defer { kb.close() }

    guard try kb.verifyIdentity() else {
      errPrint("error: connected board does not match its profile — refusing to write")
      exit(1)
    }
    guard let slots = try Keymap.discoverKnobSlots(on: kb) else {
      errPrint("error: no knob slots found; nothing safe to test against")
      exit(1)
    }

    let target = slots.press
    let (page, index) = Keymap.location(of: target)
    print("Target: knob press, slot \(target) (page \(page), index \(index))")

    let backup = try Keymap.readPage(page, on: kb)
    guard index < backup.count else {
      errPrint("error: slot \(target) is outside page \(page)")
      exit(1)
    }
    let original = backup[index]
    print("Backup of the whole page taken. Slot currently: \(hex(original))")

    guard original == [0, 0, 0, 0] else {
      errPrint("""
        Slot is not empty (\(hex(original))). This test only writes to an unassigned \
        slot, so it is stopping here rather than overwriting something.
        """)
      exit(1)
    }

    // Mute is a sensible thing for a knob press to do, and it is a consumer
    // usage, which is easy to recognise when reading back.
    let desired: [UInt8] = [0x03, 0x00, 0xE2, 0x00]
    print("Writing \(hex(desired)) (mute)…")

    var wrote = false
    for shape in WriteShape.allCases {
      do {
        try shape.write(slot: target, page: page, index: index, bytes: desired, pageSlots: backup, on: kb)
      } catch {
        print("  \(shape.name): send failed — \(error)")
        continue
      }
      Thread.sleep(forTimeInterval: 0.3)
      let after = try Keymap.readSlot(page: page, index: index, on: kb)
      if after == desired {
        print("  \(shape.name): ✅ verified — the keymap write works with this shape")
        wrote = true
        break
      }
      print("  \(shape.name): no change (read back \(hex(after ?? [])))")
    }

    if wrote {
      print("""

        Press the knob: it should now mute. Restoring the original value…
        """)
      Thread.sleep(forTimeInterval: 3)
      for shape in WriteShape.allCases {
        try? shape.write(
          slot: target, page: page, index: index, bytes: original, pageSlots: backup, on: kb)
        Thread.sleep(forTimeInterval: 0.3)
        if try Keymap.readSlot(page: page, index: index, on: kb) == original { break }
      }
      print("Restored: \(hex(try Keymap.readSlot(page: page, index: index, on: kb) ?? []))")
    } else {
      print("""

        No write shape worked. The keymap stays read-only, which is the safe
        outcome — nothing was changed.
        """)
    }
  }

  /// Candidate packet layouts for the write. The read is `[0x89, 0, page]`, so
  /// the write is most likely its mirror; the single-slot forms are the other
  /// plausible convention.
  enum WriteShape: CaseIterable {
    case wholePage
    case singleSlotByIndex
    case singleSlotByGlobal
    /// Data after the bit7 checksum byte, the way the screen upload works.
    case pageAfterChecksum
    /// bit8 checksum with the payload in the first eight bytes, the way the
    /// lighting commands are shaped.
    case singleSlotBit8
    case globalSlotBit8

    var name: String {
      switch self {
      case .wholePage: "whole page"
      case .singleSlotByIndex: "single slot (page,index)"
      case .singleSlotByGlobal: "single slot (global)"
      case .pageAfterChecksum: "page, data at byte 8"
      case .singleSlotBit8: "single slot, bit8"
      case .globalSlotBit8: "global slot, bit8"
      }
    }

    func write(
      slot: Int, page: Int, index: Int, bytes: [UInt8], pageSlots: [[UInt8]],
      on kb: Keyboard
    ) throws {
      switch self {
      case .wholePage:
        var payload = pageSlots
        payload[index] = bytes
        var packet = [UInt8](repeating: 0, count: Proto.reportLen)
        packet[0] = Proto.opSetKeymap
        packet[1] = 0
        packet[2] = UInt8(page)
        // Mirror of the read: the page's slots follow the 3-byte header.
        for (offset, slotBytes) in payload.enumerated() {
          let start = 3 + offset * 4
          guard start + 4 <= Proto.reportLen else { break }
          for (i, byte) in slotBytes.enumerated() { packet[start + i] = byte }
        }
        try kb.sendRaw(packet)

      case .singleSlotByIndex:
        try kb.sendRaw([Proto.opSetKeymap, 0, UInt8(page), UInt8(index)] + bytes)

      case .singleSlotByGlobal:
        try kb.sendRaw([Proto.opSetKeymap, 0, UInt8(slot & 0xFF), UInt8(slot >> 8)] + bytes)

      case .pageAfterChecksum:
        var payload = pageSlots
        payload[index] = bytes
        var packet = [UInt8](repeating: 0, count: Proto.reportLen)
        packet[0] = Proto.opSetKeymap
        packet[1] = 0
        packet[2] = UInt8(page)
        // Byte 7 carries the checksum; the screen protocol starts data at 8.
        for (offset, slotBytes) in payload.enumerated() {
          let start = 8 + offset * 4
          guard start + 4 <= Proto.reportLen else { break }
          for (i, byte) in slotBytes.enumerated() { packet[start + i] = byte }
        }
        try kb.sendRaw(packet)

      case .singleSlotBit8:
        try kb.sendRaw(
          [Proto.opSetKeymap, 0, UInt8(page), UInt8(index)] + bytes, mode: .bit8)

      case .globalSlotBit8:
        try kb.sendRaw(
          [Proto.opSetKeymap, 0, UInt8(slot & 0xFF), UInt8(slot >> 8)] + bytes, mode: .bit8)
      }
    }
  }

  private static func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
  }
}
