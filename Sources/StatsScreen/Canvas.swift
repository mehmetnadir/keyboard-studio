import CoreGraphics
import CoreText
import Foundation
import K86Kit

/// Minimal drawing helpers for 128×128 screen cards.
///
/// Drawing happens in Core Graphics' native bottom-left coordinate space so
/// CoreText renders upright, but layout is expressed as `topY` — distance from
/// the top of the panel — because that is how these cards are designed.
enum Canvas {
  typealias Colour = (r: Double, g: Double, b: Double)

  enum Weight {
    case regular, medium, semibold

    var fontName: String {
      switch self {
      case .regular: "SFPro-Regular"
      case .medium: "SFPro-Medium"
      case .semibold: "SFPro-Semibold"
      }
    }
  }

  /// Runs `body` against a prepared bitmap context and returns the frame.
  static func draw(background: Colour, _ body: (CGContext) -> Void) -> ScreenFrame {
    let size = Screen.width
    guard let context = CGContext(
      data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return ScreenFrame(rgb: [UInt8](repeating: 0, count: size * size * 3)) }

    context.setFillColor(red: background.r, green: background.g, blue: background.b, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    body(context)
    return frame(from: context, size: size)
  }

  /// Draws one line of text. `topY` is measured from the top of the panel.
  static func text(
    _ string: String, in context: CGContext, topY: CGFloat, x: CGFloat = 10, size: CGFloat,
    color: Colour, alpha: Double = 1, weight: Weight = .regular, tracking: CGFloat = 0,
    centered: Bool = false
  ) {
    // CoreText attribute keys, not AppKit's — this target stays UI-framework free.
    let font = CTFontCreateWithName(weight.fontName as CFString, size, nil)
    var attributes: [CFString: Any] = [
      kCTFontAttributeName: font,
      kCTForegroundColorAttributeName: CGColor(
        red: color.r, green: color.g, blue: color.b, alpha: alpha),
    ]
    if tracking != 0 {
      attributes[kCTTrackingAttributeName] = tracking
    }
    guard let attributed = CFAttributedStringCreate(
      kCFAllocatorDefault, string as CFString, attributes as CFDictionary)
    else { return }
    let line = CTLineCreateWithAttributedString(attributed)

    let originX: CGFloat
    if centered {
      let width = CTLineGetTypographicBounds(line, nil, nil, nil)
      originX = (CGFloat(Screen.width) - CGFloat(width)) / 2
    } else {
      originX = x
    }
    // Cap height sits roughly 0.78 em above the baseline for these faces.
    context.textMatrix = .identity
    context.textPosition = CGPoint(
      x: originX, y: CGFloat(Screen.height) - topY - size * 0.78)
    CTLineDraw(line, context)
  }

  /// Copies the bitmap out as-is: a bitmap context's backing store is already
  /// top-down (first row = top of the image), which is what the panel wants,
  /// even though drawing coordinates have their origin at the bottom-left.
  static func frame(from context: CGContext, size: Int) -> ScreenFrame {
    guard let base = context.data else {
      return ScreenFrame(rgb: [UInt8](repeating: 0, count: size * size * 3))
    }
    let pixels = base.assumingMemoryBound(to: UInt8.self)
    var rgb = [UInt8](repeating: 0, count: size * size * 3)
    for index in 0..<(size * size) {
      rgb[index * 3] = pixels[index * 4]
      rgb[index * 3 + 1] = pixels[index * 4 + 1]
      rgb[index * 3 + 2] = pixels[index * 4 + 2]
    }
    return ScreenFrame(rgb: rgb)
  }
}
