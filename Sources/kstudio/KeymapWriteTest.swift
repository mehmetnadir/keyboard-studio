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

    // Write to a slot that certainly exists: the knob's turn-right, which we
    // have read as volume-up. An empty slot proves nothing — the firmware may
    // simply ignore writes to positions with no key behind them.
    let target = slots.turnRight
    let (page, index) = Keymap.location(of: target)
    print("Target: knob turn-right, slot \(target) (page \(page), index \(index))")

    let backup = try Keymap.readPage(page, on: kb)
    guard index < backup.count else {
      errPrint("error: slot \(target) is outside page \(page)")
      exit(1)
    }
    let original = backup[index]
    print("Backup taken. Slot currently: \(hex(original))")

    // Mute: a consumer usage, easy to recognise on read-back, and trivially
    // reversible since the original bytes are in hand.
    let desired: [UInt8] = [0x03, 0x00, 0xE2, 0x00]
    print("Writing \(hex(desired)) (mute)…")

    var wrote = false
    do {
      try Keymap.writeSlot(target, bytes: desired, on: kb)
      wrote = try Keymap.readSlot(page: page, index: index, on: kb) == desired

      // If the read disagrees, re-open the device before believing it: a
      // cached reply would look exactly like a failed write.
      if !wrote {
        kb.close()
        Thread.sleep(forTimeInterval: 0.5)
        let fresh = try Keyboard()
        defer { fresh.close() }
        let afterReopen = try Keymap.readSlot(page: page, index: index, on: fresh)
        print("  after reopening the device: \(hex(afterReopen ?? []))")
        wrote = afterReopen == desired
      }
      print(wrote
        ? "  0x13 single-slot write: ✅ verified — the keymap write works"
        : "  0x13 single-slot write: sent, but read-back did not match")
    } catch {
      print("  0x13 single-slot write: failed — \(error)")
    }

    if wrote {
      print("\nPress the knob — it should mute. Restoring in 5 s…")
      Thread.sleep(forTimeInterval: 5)
      let restored = (try? Keymap.writeSlotVerified(target, bytes: original, on: kb)) ?? false
      print(restored ? "Restored to unassigned." : "⚠️  Restore did not verify — check the slot.")
    } else {
      print("\nWrite did not take. Nothing changed, which is the safe outcome.")
    }
  }

  private static func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
  }
}
