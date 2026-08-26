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
      let bytes = response.prefix(22).map { String(format: "%02x", $0) }.joined(separator: " ")
      print(String(format: "  0x%02X  %@  %@", opcode, echoed ? "✓" : " ", bytes))
    }

    print("\nScreen geometry — which frame sizes does the panel accept?")
    print(String(repeating: "─", count: 62))
    // Includes deliberately impossible sizes: if even 2048x2048 is accepted
    // the handshake performs no bounds check at all, and cannot be used to
    // discover the real panel size.
    for (w, h) in [(64, 64), (128, 128), (235, 128), (240, 135), (240, 240),
                   (320, 240), (512, 512), (1024, 1024), (2048, 2048)] {
      let accepted = kb.probeScreenGeometry(width: w, height: h)
      print("  \(w)×\(h)  \(accepted ? "accepted" : "rejected")")
    }
    print(
      """

      A size is "accepted" when the firmware reports ready for a frame of that
      many bytes. Note that 2048x2048 is accepted too: this firmware does no
      bounds checking, so acceptance says nothing about the real panel size.
      Ask the panel instead with `kstudio screen --query`, or check a size by
      eye with `kstudio screen --orient --size WxH`.
      """)
  }
}
