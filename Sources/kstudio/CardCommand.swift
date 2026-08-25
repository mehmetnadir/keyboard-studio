import CoreGraphics
import Foundation
import ImageIO
import KeyboardKit
import StatsCore
import StatsScreen
import UniformTypeIdentifiers

/// `kstudio card <out.png> [--demo]` — renders the keyboard screen card to a
/// file. Useful for previewing without the cable, and for documentation shots.
enum CardCommand {
  static func run(_ args: [String]) throws {
    guard args.count > 1 else {
      errPrint("usage: kstudio card <out.png> [--demo]")
      exit(64)
    }
    let output = URL(fileURLWithPath: args[1])

    // Use the connected keyboard's panel size when there is one, so a preview
    // matches what the screen will actually show.
    var width = Screen.width
    var height = Screen.height
    if let keyboard = try? Keyboard() {
      let panel = Screen.geometry(for: keyboard)
      (width, height) = (panel.width, panel.height)
      keyboard.close()
    }

    let frame: ScreenFrame
    if args.contains("--demo") {
      frame = StatsCard.render(
        presses: 18_432, activeMinutes: 214, streak: 12,
        sparkline: [8200, 14300, 5100, 19800, 12400, 16900, 18432],
        width: width, height: height)
    } else {
      let store = try StatsStore(path: StatsStore.defaultPath())
      defer { store.close() }
      frame = try StatsCard.today(store: store, width: width, height: height)
    }

    try writePNG(frame, to: output)
    print("Wrote \(output.path)")
  }

  static func writePNG(_ frame: ScreenFrame, to url: URL) throws {
    let (w, h) = (frame.width, frame.height)
    var rgba = [UInt8](repeating: 255, count: w * h * 4)
    for pixel in 0..<(w * h) {
      rgba[pixel * 4] = frame.rgb[pixel * 3]
      rgba[pixel * 4 + 1] = frame.rgb[pixel * 3 + 1]
      rgba[pixel * 4 + 2] = frame.rgb[pixel * 3 + 2]
    }
    guard let provider = CGDataProvider(data: Data(rgba) as CFData),
      let image = CGImage(
        width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
      let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else {
      throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw CocoaError(.fileWriteUnknown)
    }
  }
}
