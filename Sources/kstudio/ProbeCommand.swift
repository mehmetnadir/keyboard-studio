import Foundation
import KeyboardKit

/// `kstudio probe` — asks the keyboard about itself instead of trusting
/// documentation. Read-only queries plus screen-geometry handshakes.
///
/// Handshakes announce an intent to write and are answered with ready/not-ready;
/// no pixel data follows, so the panel keeps whatever it is showing.
enum ProbeCommand {
  static func run() throws {
    let kb = try Keyboard()
    defer { kb.close() }

    print("Device queries (read-only opcodes known safe on this family)")
    print(String(repeating: "─", count: 62))
    for opcode in DangerousCommands.safeToProbe {
      guard let response = try? kb.probe(opcode: opcode) else {
        print(String(format: "  0x%02X  <no response>", opcode))
        continue
      }
      let echoed = response.first == opcode
      let bytes = response.prefix(12).map { String(format: "%02x", $0) }.joined(separator: " ")
      print(String(format: "  0x%02X  %@  %@", opcode, echoed ? "✓" : " ", bytes))
    }

    print("\nScreen geometry — which frame sizes does the panel accept?")
    print(String(repeating: "─", count: 62))
    for side in [64, 96, 128, 160, 192, 240, 256] {
      let accepted = kb.probeScreenGeometry(width: side, height: side)
      print("  \(side)×\(side)  \(accepted ? "accepted" : "rejected")")
    }
    print(
      """

      A size is "accepted" when the firmware reports ready for a frame of that
      many bytes. The largest accepted square is the panel's own resolution.
      """)
  }
}
