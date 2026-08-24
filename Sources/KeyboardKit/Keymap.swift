import Foundation

/// Reading and writing individual keymap slots.
///
/// Slots are 4 bytes and are addressed by a page plus an index within the
/// page's 64-byte reply. Physical keys come first in column-major order (all
/// rows of column 0, then column 1…), and the knob's actions follow them.
public enum Keymap {
  public static let slotSize = 4
  public static var slotsPerPage: Int { Proto.reportLen / slotSize }

  /// Reads one page of slots.
  public static func readPage(_ page: Int, on kb: Keyboard) throws -> [[UInt8]] {
    let reply = try kb.probeRaw([Proto.opGetKeymap, 0, UInt8(clamping: page)])
    return stride(from: 0, to: reply.count - slotSize + 1, by: slotSize).map {
      Array(reply[$0..<($0 + slotSize)])
    }
  }

  public static func readSlot(page: Int, index: Int, on kb: Keyboard) throws -> [UInt8]? {
    let slots = try readPage(page, on: kb)
    guard index < slots.count else { return nil }
    return slots[index]
  }

  /// Global slot number from a page and an index within it.
  public static func globalSlot(page: Int, index: Int) -> Int {
    page * slotsPerPage + index
  }

  public static func location(of slot: Int) -> (page: Int, index: Int) {
    (slot / slotsPerPage, slot % slotsPerPage)
  }

  /// Finds a model's knob slots by looking for the consumer-control entries the
  /// firmware ships with: volume down, volume up and mute.
  ///
  /// Discovery beats hard-coding — slot numbers differ between models even
  /// within this protocol family, and the three actions do not have to sit
  /// next to each other. On the K86 the turn actions land at the very end of
  /// the matrix while mute sits back among the function keys.
  public static func discoverKnobSlots(on kb: Keyboard, pages: Int = 8) throws -> Knob.SlotMap? {
    var found: [Int: Int] = [:]  // consumer usage -> global slot
    for page in 0..<pages {
      let slots = try readPage(page, on: kb)
      for (index, bytes) in slots.enumerated() where bytes.first == 0x03 {
        let usage = Int(bytes[2])
        if found[usage] == nil {
          found[usage] = globalSlot(page: page, index: index)
        }
      }
    }
    guard let down = found[0xEA], let up = found[0xE9] else { return nil }
    // Mute is the knob's press on every board seen so far; if it is missing,
    // fall back to the slot after the turn pair rather than guessing wildly.
    let press = found[0xE2] ?? (max(down, up) + 1)
    return Knob.SlotMap(turnLeft: down, turnRight: up, press: press)
  }

  // MARK: - Writing

  /// Writes one keymap slot.
  ///
  /// Uses the single-slot command rather than the bulk one. The bulk write
  /// sends a fixed 504 bytes, which cannot even reach slots past 125 on this
  /// firmware, and rewriting the whole matrix to change one key is a poor
  /// trade when a targeted command exists.
  ///
  /// There is no unlock before and no commit after — the firmware just needs a
  /// moment to settle its flash write, hence the pause.
  public static func writeSlot(
    _ slot: Int, bytes: [UInt8], profile: Int = 0, on kb: Keyboard
  ) throws {
    guard bytes.count == slotSize else {
      throw DeviceError.invalidFrame("a keymap slot is \(slotSize) bytes")
    }
    guard try kb.verifyIdentity() else { throw DeviceError.identityMismatch }
    guard (0...255).contains(slot) else {
      throw DeviceError.invalidFrame("slot \(slot) is out of range")
    }

    var packet = [UInt8](repeating: 0, count: Proto.reportLen)
    packet[0] = Proto.opSetKeymapSlot
    packet[1] = UInt8(clamping: profile)
    packet[2] = UInt8(slot)
    // Bytes 3...6 stay zero; byte 7 receives the checksum; the slot's four
    // bytes sit at 8...11.
    for (offset, byte) in bytes.enumerated() { packet[8 + offset] = byte }
    try kb.sendRaw(packet)
    // The vendor blocks its own polling for ~100 ms after a write; give the
    // flash the same room before anything else is sent.
    Thread.sleep(forTimeInterval: 0.12)
  }

  /// Writes a slot and confirms it, re-opening the device to check.
  ///
  /// The re-open is not caution, it is required: after a write, a read on the
  /// same connection returns a cached reply showing the *old* value. Verifying
  /// without re-opening makes a successful write look like a failure — which
  /// is exactly what happened while this was being worked out.
  ///
  /// The passed-in keyboard is closed as part of this; callers get a fresh one
  /// back if they need to keep going.
  @discardableResult
  public static func writeSlotVerified(
    _ slot: Int, bytes: [UInt8], profile: Int = 0, on kb: Keyboard
  ) throws -> Bool {
    try writeSlot(slot, bytes: bytes, profile: profile, on: kb)
    kb.close()
    Thread.sleep(forTimeInterval: 0.4)

    let fresh = try Keyboard(profile: kb.profile)
    defer { fresh.close() }
    let (page, index) = location(of: slot)
    return try readSlot(page: page, index: index, on: fresh) == bytes
  }

  /// Selects which of the board's onboard profiles is active.
  public static func selectProfile(_ profile: Int, on kb: Keyboard) throws {
    guard (0...2).contains(profile) else {
      throw DeviceError.invalidFrame("profile \(profile) is out of range")
    }
    try kb.sendRaw([Proto.opSetProfile, UInt8(profile)])
  }

  /// Current bindings for the three knob actions.
  public static func readKnob(_ map: Knob.SlotMap, on kb: Keyboard) throws
    -> [Knob.Action: Knob.Binding]
  {
    var pageCache: [Int: [[UInt8]]] = [:]
    var result: [Knob.Action: Knob.Binding] = [:]
    for action in Knob.Action.allCases {
      let (page, index) = location(of: map.slot(for: action))
      let slots = try pageCache[page] ?? readPage(page, on: kb)
      pageCache[page] = slots
      result[action] = index < slots.count
        ? Knob.Binding(slotBytes: slots[index]) : .unassigned
    }
    return result
  }
}
