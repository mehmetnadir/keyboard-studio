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

  /// Finds a model's knob slots by looking for the consumer-control entries the
  /// firmware ships with — a knob defaults to volume down/up.
  ///
  /// Discovery beats hard-coding: slot numbers differ between models even
  /// within this protocol family.
  public static func discoverKnobSlots(on kb: Keyboard, pages: Int = 32) throws -> Knob.SlotMap? {
    for page in 0..<pages {
      let slots = try readPage(page, on: kb)
      let media = slots.enumerated().filter { $0.element.first == 0x03 }
      // A knob contributes a pair of consumer entries sitting next to each
      // other; anything else on the board would be a lone media key.
      guard media.count >= 2 else { continue }
      let down = media.first { $0.element[2] == 0xEA }
      let up = media.first { $0.element[2] == 0xE9 }
      guard let down, let up else { continue }
      // The press slot is the one directly after the pair.
      let press = max(down.offset, up.offset) + 1
      return Knob.SlotMap(
        page: page, turnLeft: down.offset, turnRight: up.offset, press: press)
    }
    return nil
  }

  /// Current bindings for the three knob actions.
  public static func readKnob(_ map: Knob.SlotMap, on kb: Keyboard) throws
    -> [Knob.Action: Knob.Binding]
  {
    let slots = try readPage(map.page, on: kb)
    var result: [Knob.Action: Knob.Binding] = [:]
    for action in Knob.Action.allCases {
      let index = map.index(for: action)
      result[action] = index < slots.count
        ? Knob.Binding(slotBytes: slots[index]) : .unassigned
    }
    return result
  }
}
