import CoreGraphics
import Foundation
import ImageIO

/// One 128×128 frame for the K86's TFT screen.
public struct ScreenFrame: Sendable {
  /// Row-major RGB bytes, `(y * width + x) * 3`.
  public var rgb: [UInt8]
  /// GIF frame delay in ~10 ms units (0 for static images).
  public var delayByte: UInt8

  public init(rgb: [UInt8], delayByte: UInt8 = 0) {
    self.rgb = rgb
    self.delayByte = delayByte
  }
}

/// TFT screen upload: RGB565 encode (column-major, big-endian), a write
/// handshake, then the pixel stream in 56-byte chunks.
public enum Screen {
  public static let width = 128
  public static let height = 128

  static let opCanWrite: UInt8 = 165  // FEA_CMD_GETTFTLCDDATA (RGB565 mode)
  static let opData: UInt8 = 37       // FEA_CMD_SETTFTLCDDATA
  static let chunkSize = 56

  // MARK: - Upload

  public static func writeImage(_ frame: ScreenFrame, layer: UInt8 = 0, on kb: K86) throws {
    try validate(frame)
    let bytes = encode565(frame.rgb)
    guard try canWrite(
      kb, byteLength: bytes.count, frameIndex: layer, allFrames: 1, delay: 0, layer: layer)
    else { throw K86Error.screenHandshakeFailed }
    try sendChunks(kb, bytes, frameIndex: layer, allFrames: 1, delay: 0)
  }

  public static func writeAnimation(_ frames: [ScreenFrame], on kb: K86) throws {
    guard (1...255).contains(frames.count) else {
      throw K86Error.invalidFrame("animation needs 1...255 frames, got \(frames.count)")
    }
    for frame in frames { try validate(frame) }
    let first = frames[0]
    let firstBytes = encode565(first.rgb)
    guard try canWrite(
      kb, byteLength: firstBytes.count, frameIndex: 0,
      allFrames: UInt8(frames.count), delay: first.delayByte, layer: 0)
    else { throw K86Error.screenHandshakeFailed }
    for (index, frame) in frames.enumerated() {
      try sendChunks(
        kb, encode565(frame.rgb), frameIndex: UInt8(index),
        allFrames: UInt8(frames.count), delay: frame.delayByte)
    }
  }

  private static func validate(_ frame: ScreenFrame) throws {
    let expected = width * height * 3
    guard frame.rgb.count == expected else {
      throw K86Error.invalidFrame(
        "expected \(width)×\(height) RGB (\(expected) bytes), got \(frame.rgb.count)")
    }
  }

  // MARK: - Protocol

  private static func canWrite(
    _ kb: K86, byteLength: Int, frameIndex: UInt8, allFrames: UInt8,
    delay: UInt8, layer: UInt8
  ) throws -> Bool {
    var s = [UInt8](repeating: 0, count: Proto.reportLen)
    s[0] = opCanWrite
    s[1] = frameIndex
    s[2] = allFrames
    s[3] = delay
    s[4] = UInt8(byteLength & 0xFF)
    s[5] = UInt8((byteLength >> 8) & 0xFF)
    // Target rectangle (full frame): left, top, right, bottom — low then high bytes.
    s[8] = 0
    s[9] = 0
    s[10] = UInt8(width & 0xFF)
    s[11] = UInt8(height & 0xFF)
    s[12] = 0
    s[13] = 0
    s[14] = UInt8(width >> 8)
    s[15] = UInt8(height >> 8)
    s[16] = UInt8((byteLength >> 16) & 0xFF)
    s[17] = UInt8((byteLength >> 24) & 0xFF)
    s[18] = layer
    for _ in 0..<10 {
      // try? — a transient transport error must consume one retry, not abort
      // the whole handshake loop; the opcode echo guards against stale reports.
      if let f = try? kb.query(s, mode: .bit7, wait: 0.1),
        f.count > 1, f[0] == opCanWrite, f[1] == 1 {
        return true
      }
      Thread.sleep(forTimeInterval: 0.05)
    }
    return false
  }

  private static func sendChunks(
    _ kb: K86, _ bytes: [UInt8], frameIndex: UInt8, allFrames: UInt8, delay: UInt8
  ) throws {
    let total = (bytes.count + chunkSize - 1) / chunkSize
    for chunk in 0..<total {
      let start = chunk * chunkSize
      let end = min(start + chunkSize, bytes.count)
      var data = Array(bytes[start..<end])
      let payloadLength = data.count
      if data.count < chunkSize {
        data.append(contentsOf: [UInt8](repeating: 0, count: chunkSize - data.count))
      }
      var pkt = [UInt8](repeating: 0, count: Proto.reportLen)
      pkt[0] = opData
      pkt[1] = frameIndex
      pkt[2] = allFrames
      pkt[3] = delay
      pkt[4] = UInt8(chunk & 0xFF)
      pkt[5] = UInt8((chunk >> 8) & 0xFF)
      pkt[6] = UInt8(payloadLength)
      // pkt[7] carries the Bit7 checksum; pixel data starts at byte 8.
      for (i, byte) in data.enumerated() { pkt[8 + i] = byte }
      try kb.sendFeature(pkt, mode: .bit7)
      Thread.sleep(forTimeInterval: 0.001)
    }
  }

  /// Row-major RGB → column-major RGB565 big-endian (panel's native order).
  static func encode565(_ rgb: [UInt8]) -> [UInt8] {
    var out = [UInt8]()
    out.reserveCapacity(width * height * 2)
    for x in 0..<width {
      for y in 0..<height {
        let i = (y * width + x) * 3
        let value =
          (UInt16(rgb[i] >> 3) << 11) | (UInt16(rgb[i + 1] >> 2) << 5) | UInt16(rgb[i + 2] >> 3)
        out.append(UInt8(value >> 8))
        out.append(UInt8(value & 0xFF))
      }
    }
    return out
  }

  // MARK: - Image loading (ImageIO — animated GIF supported)

  public static func loadFrames(url: URL, maxFrames: Int = 30) throws -> [ScreenFrame] {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      CGImageSourceGetCount(source) > 0
    else {
      throw CocoaError(.fileReadCorruptFile)
    }
    let count = min(CGImageSourceGetCount(source), maxFrames)
    var frames: [ScreenFrame] = []
    for index in 0..<count {
      guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else {
        throw K86Error.imageDecodeFailed
      }
      frames.append(
        ScreenFrame(rgb: try rasterize(image), delayByte: delayByte(source, index)))
    }
    return frames
  }

  private static func rasterize(_ image: CGImage) throws -> [UInt8] {
    guard let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8,
      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { throw K86Error.imageDecodeFailed }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let base = context.data else { throw K86Error.imageDecodeFailed }
    let rgba = base.assumingMemoryBound(to: UInt8.self)
    var rgb = [UInt8](repeating: 0, count: width * height * 3)
    for pixel in 0..<(width * height) {
      rgb[pixel * 3] = rgba[pixel * 4]
      rgb[pixel * 3 + 1] = rgba[pixel * 4 + 1]
      rgb[pixel * 3 + 2] = rgba[pixel * 4 + 2]
    }
    return rgb
  }

  private static func delayByte(_ source: CGImageSource, _ index: Int) -> UInt8 {
    // Non-GIF multi-frame containers (APNG, TIFF) carry no GIF dictionary;
    // fall back to 100 ms like the reference implementation.
    guard
      let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
      let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any]
    else { return 10 }
    let seconds =
      (gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
      ?? (gif[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
    let units = (seconds * 100).rounded()
    return UInt8(min(255.0, max(1.0, units.isFinite ? units : 10)))
  }

  /// Red / green / blue / white quadrants — device test without an image file.
  public static func testPattern() -> ScreenFrame {
    var rgb = [UInt8](repeating: 0, count: width * height * 3)
    for y in 0..<height {
      for x in 0..<width {
        let color: (UInt8, UInt8, UInt8) = switch (x < width / 2, y < height / 2) {
        case (true, true): (255, 0, 0)
        case (false, true): (0, 255, 0)
        case (true, false): (0, 0, 255)
        case (false, false): (255, 255, 255)
        }
        let i = (y * width + x) * 3
        (rgb[i], rgb[i + 1], rgb[i + 2]) = color
      }
    }
    return ScreenFrame(rgb: rgb)
  }
}
