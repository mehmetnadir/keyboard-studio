import CoreGraphics
import Foundation
import ImageIO
import K86Kit
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

    let frame: ScreenFrame
    if args.contains("--demo") {
      frame = StatsCard.render(
        presses: 18_432, activeMinutes: 214, streak: 12,
        sparkline: [8200, 14300, 5100, 19800, 12400, 16900, 18432])
    } else {
      let store = try StatsStore(path: StatsStore.defaultPath())
      defer { store.close() }
      frame = try StatsCard.today(store: store)
    }

    try writePNG(frame, to: output)
    print("Wrote \(output.path)")
  }

  static func writePNG(_ frame: ScreenFrame, to url: URL) throws {
    let side = Screen.width
    var rgba = [UInt8](repeating: 255, count: side * side * 4)
    for pixel in 0..<(side * side) {
      rgba[pixel * 4] = frame.rgb[pixel * 3]
      rgba[pixel * 4 + 1] = frame.rgb[pixel * 3 + 1]
      rgba[pixel * 4 + 2] = frame.rgb[pixel * 3 + 2]
    }
    guard let provider = CGDataProvider(data: Data(rgba) as CFData),
      let image = CGImage(
        width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
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
