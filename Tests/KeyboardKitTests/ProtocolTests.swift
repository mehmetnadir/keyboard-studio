import CoreGraphics
import Foundation
import Testing

@testable import KeyboardKit

@Suite struct ProtocolTests {
  @Test func bit7ChecksumComplementsFirstSevenBytes() {
    let buf = Proto.encode([Proto.opGetRev], mode: .bit7)
    #expect(buf.count == 64)
    #expect(buf[0] == 0x80)
    #expect(buf[7] == 127)  // 255 - 0x80
    #expect(buf[8] == 0)
  }

  @Test func bit8ChecksumCoversEightBytes() {
    let cmd: [UInt8] = [7, 1, 2, 4, 0x07, 255, 0, 0]
    let buf = Proto.encode(cmd, mode: .bit8)
    let sum = buf[0..<8].reduce(0) { ($0 + Int($1)) & 0xFF }
    #expect(buf[8] == UInt8((255 - sum) & 0xFF))
    #expect(buf[7] == 0)  // bit8 mode must not touch byte 7
  }

  @Test func effectIndicesMatchFirmwareTable() {
    #expect(LightEffect.off.index == 0)
    #expect(LightEffect.solid.index == 1)
    #expect(LightEffect.linewave.index == 12)
    #expect(LightEffect.laser.index == 14)  // 13 is an unused firmware slot
    #expect(LightEffect.train.index == 23)
    #expect(LightEffect.fireworks.index == 24)
  }

  @Test func hexColorParsing() {
    #expect(RGB(hex: "#9B59B6") == RGB(155, 89, 182))
    #expect(RGB(hex: "ff0000") == RGB(255, 0, 0))
    #expect(RGB(hex: "nope") == nil)
    #expect(RGB(hex: "#fff") == nil)
  }

  @Test func rgb565EncodesWhiteAndRed() {
    var rgb = [UInt8](repeating: 0, count: 128 * 128 * 3)
    (rgb[0], rgb[1], rgb[2]) = (255, 255, 255)  // (x=0, y=0)
    let out = Screen.encode565(rgb)
    #expect(out.count == 128 * 128 * 2)
    #expect(out[0] == 0xFF && out[1] == 0xFF)

    var red = [UInt8](repeating: 0, count: 128 * 128 * 3)
    (red[0], red[1], red[2]) = (255, 0, 0)
    let redOut = Screen.encode565(red)
    #expect(redOut[0] == 0xF8 && redOut[1] == 0x00)
  }

  @Test func rgb565IsColumnMajor() {
    var rgb = [UInt8](repeating: 0, count: 128 * 128 * 3)
    let i = (0 * 128 + 1) * 3  // row-major pixel (x=1, y=0)
    (rgb[i], rgb[i + 1], rgb[i + 2]) = (255, 0, 0)
    let out = Screen.encode565(rgb)
    let pos = (1 * 128 + 0) * 2  // column-major slot for (x=1, y=0)
    #expect(out[pos] == 0xF8 && out[pos + 1] == 0x00)
    #expect(out[0] == 0 && out[1] == 0)
  }

  @Test func contentModeMapsWideSourceCorrectly() {
    // A 256×128 source: twice as wide as the square panel.
    let wide = CGImage(
      width: 256, height: 128, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 256 * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
      provider: CGDataProvider(data: Data(count: 256 * 128 * 4) as CFData)!, decode: nil,
      shouldInterpolate: false, intent: .defaultIntent)!

    let fill = Screen.destinationRect(for: wide, mode: .fill)
    #expect(fill.height == 128)  // short edge matches
    #expect(fill.width == 256)  // long edge overflows and is cropped
    #expect(fill.origin.x == -64)  // centred

    let fit = Screen.destinationRect(for: wide, mode: .fit)
    #expect(fit.width == 128)  // whole image fits
    #expect(fit.height == 64)
    #expect(fit.origin.y == 32)  // letterboxed

    let stretch = Screen.destinationRect(for: wide, mode: .stretch)
    #expect(stretch == CGRect(x: 0, y: 0, width: 128, height: 128))
  }

  @Test func testPatternQuadrants() {
    let frame = Screen.testPattern()
    func pixel(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8) {
      let i = (y * 128 + x) * 3
      return (frame.rgb[i], frame.rgb[i + 1], frame.rgb[i + 2])
    }
    #expect(pixel(0, 0) == (255, 0, 0))
    #expect(pixel(127, 0) == (0, 255, 0))
    #expect(pixel(0, 127) == (0, 0, 255))
    #expect(pixel(127, 127) == (255, 255, 255))
  }
}

@Suite struct SafetyTests {
  @Test func destructiveOpcodesAreBlocked() {
    // The two that would actually cost the user something.
    #expect(DangerousCommands.isBlocked(0xAC))  // flash erase, ~55 s
    #expect(DangerousCommands.isBlocked(0x02))  // factory reset
    #expect(DangerousCommands.isBlocked(0x01))  // factory reset, other lineage
    #expect(DangerousCommands.isBlocked(0x43))  // bootloader
  }

  @Test func ordinaryCommandsAreNotBlocked() {
    #expect(!DangerousCommands.isBlocked(0x07))  // lighting
    #expect(!DangerousCommands.isBlocked(0x13))  // single-slot keymap write
    #expect(!DangerousCommands.isBlocked(0x89))  // keymap read
  }

  @Test func probeSetContainsNoBlockedOpcode() {
    for opcode in DangerousCommands.safeToProbe {
      #expect(!DangerousCommands.isBlocked(opcode))
    }
  }

  @Test func flashWritersAreFlaggedButNotBlocked() {
    // These are legitimate features; they just must never be swept.
    #expect(DangerousCommands.flashWriting.contains(0x0C))
    #expect(!DangerousCommands.isBlocked(0x0C))
  }
}
