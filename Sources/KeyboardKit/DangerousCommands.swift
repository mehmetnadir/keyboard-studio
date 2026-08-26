import Foundation

/// Commands that must never be sent by exploration code.
///
/// The protocol puts destructive operations at innocuous-looking opcodes, right
/// next to harmless ones: a factory reset is `0x02`, and a full flash erase is
/// `0xAC` — which sits inside the 0x80+ range that otherwise contains only
/// reads. A sweep that assumed "high opcodes are safe" would wipe the screen's
/// storage and block for the best part of a minute.
public enum DangerousCommands {
  /// Opcodes that destroy state, take the device offline, or enter bootloader.
  public static let blocked: Set<UInt8> = [
    0xAC,  // flash chip erase — wipes stored screen images, blocks ~55 s
    0x02,  // factory reset (this protocol lineage)
    0x01,  // factory reset (the other lineage — a low, harmless-looking opcode)
    0x43, 0x44, 0xC3, 0xC4,  // Nordic bootloader entry and start
    0x30, 0x31, 0x40, 0x41,  // further reported bootloader entries, unconfirmed
    0x1C, 0x1E,  // magnetic-switch travel calibration — destroys calibration
  ]

  /// Opcodes that write to flash. Safe to send deliberately, never to sweep:
  /// flash has a limited number of write cycles.
  public static let flashWriting: Set<UInt8> = [
    0x0C,  // per-key colour pattern
    0x18, 0x19,  // animated per-key light
    0x25, 0x29,  // screen image, 16-bit and 24-bit
    0x22, 0x27, 0x28,  // screen host stats, language, clock
  ]

  public static func isBlocked(_ opcode: UInt8) -> Bool {
    blocked.contains(opcode)
  }

  /// Read-only opcodes confirmed safe to probe on this protocol family.
  public static let safeToProbe: [UInt8] = [
    // 0x0E asks the panel for its own resolution and 0x36 for the image slot
    // addresses; both are reads in the vendor's own client.
    0x0E, 0x36,
    0x80, 0x81, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89,
    0x8B, 0x8C, 0x8F, 0x90, 0x92, 0x97, 0xAD, 0xAE, 0xF0,
  ]
}
