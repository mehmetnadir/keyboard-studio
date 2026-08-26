import CoreGraphics
import Foundation
import ImageIO

/// One frame for the K86's TFT screen.
///
/// Carries its own dimensions: the panel's real resolution is not something the
/// protocol reports (the firmware accepts a write handshake for any size), so
/// it must stay configurable rather than baked in as a constant.
public struct ScreenFrame: Sendable {
  /// Row-major RGB bytes, `(y * width + x) * 3`.
  public var rgb: [UInt8]
  public var width: Int
  public var height: Int
  /// GIF frame delay in ~10 ms units (0 for static images).
  public var delayByte: UInt8

  public init(
    rgb: [UInt8], width: Int = Screen.width, height: Int = Screen.height, delayByte: UInt8 = 0
  ) {
    self.rgb = rgb
    self.width = width
    self.height = height
    self.delayByte = delayByte
  }
}

/// How a source image is mapped onto the square panel.
public enum ContentMode: String, Sendable, CaseIterable {
  /// Fill the panel, cropping the long edge — no distortion. The default,
  /// because most photos and GIFs read better cropped than squashed.
  case fill
  /// Fit the whole image inside the panel, padding the short edge.
  case fit
  /// Stretch to 128×128, distorting non-square sources.
  case stretch
}

/// TFT screen upload: RGB565 encode (column-major, big-endian), a write
/// handshake, then the pixel stream in 56-byte chunks.
///
/// Panel facts worth knowing before preparing artwork:
/// - Geometry comes from the device profile, never from a constant here: the
///   firmware answers "ready" to a handshake for any frame size, so a panel's
///   real resolution has to be recorded per model and confirmed by eye.
/// - RGB565, 65 536 colours — fine gradients band.
/// - Animations: up to `maxFrames` frames per upload; the firmware indexes
///   frames in a single byte, so 255 is the hard ceiling.
/// - Frame delay comes from the GIF itself, quantised to 10 ms units and
///   clamped to 10 ms … 2.55 s.
public enum Screen {
  /// Fallback geometry for callers with no profile at hand (previews, tests).
  /// Real uploads take the size from `Keyboard.screen`.
  public static let width = 128
  public static let height = 128
  /// Default animation frame budget. Higher values upload slowly (each frame
  /// is 32 KB of pixel data sent in 56-byte chunks) and can exhaust device
  /// memory; 255 is the protocol maximum.
  public static let maxFrames = 30

  /// How many stored image slots the panel has.
  ///
  /// Images are written into a numbered slot and stay there. There is no
  /// command to display a given slot — that choice is made from the keyboard's
  /// own on-screen menu, which is what the knob opens.
  public static let imageSlots = 5

  /// Geometry for a connected keyboard, falling back to the defaults above.
  public static func geometry(for keyboard: Keyboard) -> (width: Int, height: Int, maxFrames: Int) {
    guard let screen = keyboard.screen else { return (width, height, maxFrames) }
    return (screen.width, screen.height, screen.maxFrames)
  }

  static let opCanWrite: UInt8 = 165  // FEA_CMD_GETTFTLCDDATA (RGB565 mode)
  static let opData: UInt8 = 37       // FEA_CMD_SETTFTLCDDATA
  static let chunkSize = 56

  // MARK: - Upload

  /// Uploads a frame, optionally at an offset inside the panel.
  ///
  /// The protocol's target rectangle is what makes panel measurement possible:
  /// drawing a known-good tile at increasing offsets shows where the panel ends.
  public static func writeImage(
    _ frame: ScreenFrame, at origin: (x: Int, y: Int) = (0, 0), layer: UInt8 = 0, on kb: Keyboard
  ) throws {
    try validate(frame)
    let bytes = encode565(frame.rgb, width: frame.width, height: frame.height)
    guard try canWrite(
      kb, byteLength: bytes.count, frameIndex: layer, allFrames: 1, delay: 0, layer: layer,
      left: origin.x, top: origin.y,
      right: origin.x + frame.width, bottom: origin.y + frame.height)
    else { throw DeviceError.screenHandshakeFailed }
    try sendChunks(kb, bytes, frameIndex: layer, allFrames: 1, delay: 0)
  }

  /// What the panel reports about itself.
  public struct Parameters: Sendable, Equatable {
    public var width: Int
    public var height: Int
    public var brightness: Int
  }

  /// Asks the panel for its own resolution instead of guessing it.
  ///
  /// The vendor's client never hardcodes a screen size either — it starts with
  /// `horizontal: 0, vertical: 0` and fills them in from this reply, which is
  /// why the same client drives boards with different panels. Layout of the
  /// response, from the vendor's own parser:
  ///
  ///     byte 2      brightness
  ///     bytes 17-18 width   (big-endian)
  ///     bytes 19-20 height  (big-endian)
  ///
  /// Reads on this protocol are cached — the first query after another command
  /// returns *that* command's reply — so this retries until the opcode echoes
  /// back, the same fix `deviceID()` needs.
  public static func readParameters(on kb: Keyboard) throws -> Parameters? {
    // Two transports, because the answer depends on how the board is wired.
    // The vendor's client sends this on its own numbered output report; boards
    // whose vendor interface exposes no output endpoint can only be asked over
    // the unnumbered feature report the rest of this project uses.
    let packet = Proto.displayPacket(Proto.opGetDisplayParam)
    for attempt in 0..<6 {
      let reply: [UInt8]? =
        (try? kb.queryDisplay(packet)) ?? (try? kb.probe(opcode: Proto.opGetDisplayParam))
      if let r = reply, r.count > 20, r[0] == Proto.opGetDisplayParam {
        let width = Int(r[17]) << 8 | Int(r[18])
        let height = Int(r[19]) << 8 | Int(r[20])
        // A panel this size does not exist; a zero means "not reported".
        if (8...1024).contains(width), (8...1024).contains(height) {
          return Parameters(width: width, height: height, brightness: Int(r[2]))
        }
      }
      if attempt < 5 { Thread.sleep(forTimeInterval: 0.1) }
    }
    return nil
  }

  /// A colour-coded ruler for reading the panel's width in one shot.
  ///
  /// Sweeping candidate sizes needs one look per candidate. This needs one look
  /// total: a frame deliberately wider than the panel, marked with coloured
  /// bars at known x positions. The device clips what does not fit, so the
  /// rightmost colour still visible names the last position the panel reaches —
  /// which is its width, to the spacing of the marks.
  ///
  /// Marks run in rainbow order so they can be reported by name without a
  /// legend on screen, and the left edge carries a white block so the reader
  /// can tell the image is not mirrored or offset.
  public static let rulerMarks: [(x: Int, name: String, color: (UInt8, UInt8, UInt8))] = [
    (204, "red", (230, 40, 40)),
    (208, "orange", (245, 140, 30)),
    (212, "yellow", (240, 225, 50)),
    (216, "green", (60, 200, 70)),
    (220, "cyan", (40, 210, 210)),
    (224, "blue", (60, 110, 245)),
    (228, "purple", (160, 70, 220)),
    (232, "pink", (245, 110, 190)),
    (236, "white", (255, 255, 255)),
    (240, "grey", (140, 140, 150)),
  ]

  public static func widthRuler(height: Int) -> ScreenFrame {
    let width = 248  // wider than every candidate, so the panel does the clipping
    var rgb = [UInt8](repeating: 0, count: width * height * 3)
    func fill(_ x0: Int, _ x1: Int, _ color: (UInt8, UInt8, UInt8)) {
      for y in 0..<height {
        for x in max(0, x0)..<min(width, x1) {
          let i = (y * width + x) * 3
          rgb[i] = color.0; rgb[i + 1] = color.1; rgb[i + 2] = color.2
        }
      }
    }
    // Orientation anchor: a white block hugging the left edge.
    fill(0, 8, (255, 255, 255))
    for mark in rulerMarks { fill(mark.x, mark.x + 3, mark.color) }
    return ScreenFrame(rgb: rgb, width: width, height: height)
  }

  /// One step of a width sweep: a solid colour, white vertical stripes and a
  /// full border.
  ///
  /// Reading a wrong width produces a *shear* — every row starts a fixed number
  /// of pixels off from the one above, so straight vertical stripes lean. That
  /// makes stripes a far better probe than a picture: leaning means wrong,
  /// vertical means right, and no photograph or measurement is needed to tell
  /// them apart. The background colour identifies which candidate is on screen,
  /// so a whole list can be tried in one pass and reported back by colour.
  public static func widthProbe(width: Int, height: Int, tint: (UInt8, UInt8, UInt8))
    -> ScreenFrame
  {
    var rgb = [UInt8](repeating: 0, count: width * height * 3)
    for pixel in 0..<(width * height) {
      rgb[pixel * 3] = tint.0
      rgb[pixel * 3 + 1] = tint.1
      rgb[pixel * 3 + 2] = tint.2
    }
    func plot(_ x: Int, _ y: Int) {
      guard x >= 0, x < width, y >= 0, y < height else { return }
      let i = (y * width + x) * 3
      rgb[i] = 255; rgb[i + 1] = 255; rgb[i + 2] = 255
    }
    // Stripes every 20 px, 2 px wide: thin enough to show a small lean, far
    // enough apart to stay countable.
    for x in stride(from: 10, to: width, by: 20) {
      for y in 0..<height { plot(x, y); plot(x + 1, y) }
    }
    for x in 0..<width { plot(x, 0); plot(x, height - 1) }
    for y in 0..<height { plot(0, y); plot(width - 1, y) }
    return ScreenFrame(rgb: rgb, width: width, height: height)
  }

  /// Candidate panel sizes, in the order worth trying.
  ///
  /// The list is anchored on what the user found by trial: a width near 235 at
  /// a height of 128. It surrounds that with the resolutions actual 1.2-inch
  /// TFT modules ship with, since a panel is far more likely to be a catalogue
  /// part than an arbitrary number.
  public static let candidateSizes: [(width: Int, height: Int, name: String)] = [
    (240, 135, "red"),
    (240, 128, "green"),
    (235, 128, "blue"),
    (232, 128, "yellow"),
    (240, 140, "magenta"),
    (220, 128, "cyan"),
  ]

  public static let candidateTints: [(UInt8, UInt8, UInt8)] = [
    (200, 30, 30), (30, 180, 60), (40, 90, 230),
    (220, 180, 30), (200, 40, 200), (30, 190, 200),
  ]

  /// Corner-coded orientation test.
  ///
  /// A panel accepts any frame size without complaint, so a picture that
  /// merely "looks full" proves nothing. This pattern makes one photograph
  /// answer three questions at once:
  ///
  /// * **Is the width right?** The stripes run straight down. A wrong width
  ///   shears them into diagonals, because each column lands one row off from
  ///   the last.
  /// * **Is it rotated?** The four corners are different colours — red, green,
  ///   blue, yellow, clockwise from top-left — so a rotated or transposed
  ///   frame shows them in the wrong places.
  /// * **Is it cropped?** The white border touches all four edges and the top
  ///   bar is thicker than the left one. Missing corners or a missing bar mean
  ///   the device is discarding part of the frame.
  public static func orientationPattern(width: Int, height: Int) -> ScreenFrame {
    var rgb = [UInt8](repeating: 0, count: width * height * 3)
    func plot(_ x: Int, _ y: Int, _ color: (UInt8, UInt8, UInt8)) {
      guard x >= 0, x < width, y >= 0, y < height else { return }
      let i = (y * width + x) * 3
      (rgb[i], rgb[i + 1], rgb[i + 2]) = color
    }

    // Vertical stripes every 16 px: the shear detector.
    for x in stride(from: 0, to: width, by: 16) {
      for y in 0..<height { plot(x, y, (60, 60, 70)) }
    }

    let box = max(8, min(width, height) / 4)
    let corners: [((Int, Int), (UInt8, UInt8, UInt8))] = [
      ((0, 0), (255, 40, 40)),                       // top-left     red
      ((width - box, 0), (40, 220, 60)),             // top-right    green
      ((0, height - box), (60, 110, 255)),           // bottom-left  blue
      ((width - box, height - box), (255, 210, 40)),  // bottom-right yellow
    ]
    for ((originX, originY), color) in corners {
      for y in originY..<(originY + box) {
        for x in originX..<(originX + box) { plot(x, y, color) }
      }
    }

    // Asymmetric border: a 6 px top bar against a 2 px left bar tells top from
    // bottom even in a photograph taken at an angle.
    let white: (UInt8, UInt8, UInt8) = (255, 255, 255)
    for x in 0..<width {
      for y in 0..<6 { plot(x, y, white) }
      plot(x, height - 1, white)
    }
    for y in 0..<height {
      for x in 0..<2 { plot(x, y, white) }
      plot(width - 1, y, white)
    }
    return ScreenFrame(rgb: rgb, width: width, height: height)
  }

  /// Fills `width`×`height` with one colour — the tile used for measuring.
  public static func solid(_ color: (UInt8, UInt8, UInt8), width: Int, height: Int)
    -> ScreenFrame
  {
    var rgb = [UInt8](repeating: 0, count: width * height * 3)
    for pixel in 0..<(width * height) {
      rgb[pixel * 3] = color.0
      rgb[pixel * 3 + 1] = color.1
      rgb[pixel * 3 + 2] = color.2
    }
    return ScreenFrame(rgb: rgb, width: width, height: height)
  }

  public static func writeAnimation(_ frames: [ScreenFrame], on kb: Keyboard) throws {
    guard (1...255).contains(frames.count) else {
      throw DeviceError.invalidFrame("animation needs 1...255 frames, got \(frames.count)")
    }
    for frame in frames { try validate(frame) }
    let first = frames[0]
    // The frame's own size, not the default: passing no size here encoded every
    // animation frame as 128x128 regardless of the panel, which produced a
    // half-filled, striped image on any non-square screen. Static images always
    // passed their size, so only GIFs were affected.
    let firstBytes = encode565(first.rgb, width: first.width, height: first.height)
    // The target rectangle must describe the frame, not the 128x128 default.
    // Announcing a 128-wide window and then sending 235-wide rows makes each
    // row overflow into the next, which reads on the panel as an image that
    // slides sideways a little more with every line.
    guard try canWrite(
      kb, byteLength: firstBytes.count, frameIndex: 0,
      allFrames: UInt8(frames.count), delay: first.delayByte, layer: 0,
      right: first.width, bottom: first.height)
    else { throw DeviceError.screenHandshakeFailed }
    for (index, frame) in frames.enumerated() {
      try sendChunks(
        kb, encode565(frame.rgb, width: frame.width, height: frame.height),
        frameIndex: UInt8(index),
        allFrames: UInt8(frames.count), delay: frame.delayByte)
    }
  }

  private static func validate(_ frame: ScreenFrame) throws {
    let expected = frame.width * frame.height * 3
    guard frame.rgb.count == expected else {
      throw DeviceError.invalidFrame(
        "expected \(frame.width)×\(frame.height) RGB (\(expected) bytes), got \(frame.rgb.count)")
    }
  }

  // MARK: - Diagnostics

  /// Runs only the write handshake for a frame of the given size. No pixel data
  /// follows, so the panel keeps its current contents.
  static func handshakeAccepts(width: Int, height: Int, on kb: Keyboard) -> Bool {
    let byteLength = width * height * 2  // RGB565
    return (try? canWrite(
      kb, byteLength: byteLength, frameIndex: 0, allFrames: 1, delay: 0, layer: 0,
      right: width, bottom: height, retries: 3)) ?? false
  }

  // MARK: - Protocol

  private static func canWrite(
    _ kb: Keyboard, byteLength: Int, frameIndex: UInt8, allFrames: UInt8,
    delay: UInt8, layer: UInt8, left: Int = 0, top: Int = 0,
    right: Int = Screen.width, bottom: Int = Screen.height, retries: Int = 10
  ) throws -> Bool {
    var s = [UInt8](repeating: 0, count: Proto.reportLen)
    s[0] = opCanWrite
    s[1] = frameIndex
    s[2] = allFrames
    s[3] = delay
    s[4] = UInt8(byteLength & 0xFF)
    s[5] = UInt8((byteLength >> 8) & 0xFF)
    // Target rectangle: left, top, right, bottom — low bytes then high bytes.
    s[8] = UInt8(left & 0xFF)
    s[9] = UInt8(top & 0xFF)
    s[10] = UInt8(right & 0xFF)
    s[11] = UInt8(bottom & 0xFF)
    s[12] = UInt8(left >> 8)
    s[13] = UInt8(top >> 8)
    s[14] = UInt8(right >> 8)
    s[15] = UInt8(bottom >> 8)
    s[16] = UInt8((byteLength >> 16) & 0xFF)
    s[17] = UInt8((byteLength >> 24) & 0xFF)
    s[18] = layer
    for _ in 0..<retries {
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
    _ kb: Keyboard, _ bytes: [UInt8], frameIndex: UInt8, allFrames: UInt8, delay: UInt8
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

  /// How pixels are ordered on the wire.
  ///
  /// Two conventions exist and they are indistinguishable on a square panel —
  /// which is exactly why this went unnoticed: the encoder was verified at
  /// 128×128, where the two differ only by a transpose that a symmetric test
  /// pattern hides. On a 235×128 panel they produce completely different
  /// images.
  public enum PixelOrder: String, Sendable, CaseIterable {
    /// Column-major, big-endian. What this project shipped with.
    case column
    /// Row-major, little-endian — what the vendor's own client emits:
    /// `for row { for column { push(low); push(high) } }`.
    case row
  }

  /// Row-major RGB → RGB565 in the panel's wire order.
  static func encode565(
    _ rgb: [UInt8], width: Int = Screen.width, height: Int = Screen.height,
    order: PixelOrder = .column
  ) -> [UInt8] {
    var out = [UInt8]()
    out.reserveCapacity(width * height * 2)

    func pack(_ i: Int) -> UInt16 {
      (UInt16(rgb[i] >> 3) << 11) | (UInt16(rgb[i + 1] >> 2) << 5) | UInt16(rgb[i + 2] >> 3)
    }

    switch order {
    case .column:
      for x in 0..<width {
        for y in 0..<height {
          let value = pack((y * width + x) * 3)
          out.append(UInt8(value >> 8))
          out.append(UInt8(value & 0xFF))
        }
      }
    case .row:
      for y in 0..<height {
        for x in 0..<width {
          let value = pack((y * width + x) * 3)
          out.append(UInt8(value & 0xFF))
          out.append(UInt8(value >> 8))
        }
      }
    }
    return out
  }

  // MARK: - Image loading (ImageIO — animated GIF supported)

  /// Decodes an image or GIF, scaled to the panel `keyboard` actually has.
  public static func loadFrames(
    url: URL, for keyboard: Keyboard, mode: ContentMode = .fill
  ) throws -> [ScreenFrame] {
    let panel = geometry(for: keyboard)
    return try loadFrames(
      url: url, mode: mode, maxFrames: panel.maxFrames,
      width: panel.width, height: panel.height)
  }

  public static func loadFrames(
    url: URL, mode: ContentMode = .fill, maxFrames: Int = Screen.maxFrames,
    width: Int = Screen.width, height: Int = Screen.height
  ) throws -> [ScreenFrame] {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      CGImageSourceGetCount(source) > 0
    else {
      throw CocoaError(.fileReadCorruptFile)
    }
    let count = min(CGImageSourceGetCount(source), max(1, min(maxFrames, 255)))
    var frames: [ScreenFrame] = []
    for index in 0..<count {
      guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else {
        throw DeviceError.imageDecodeFailed
      }
      frames.append(
        ScreenFrame(
          rgb: try rasterize(image, mode: mode, width: width, height: height),
          width: width, height: height, delayByte: delayByte(source, index)))
    }
    return frames
  }

  private static func rasterize(
    _ image: CGImage, mode: ContentMode, width: Int = Screen.width, height: Int = Screen.height
  ) throws -> [UInt8] {
    guard let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8,
      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { throw DeviceError.imageDecodeFailed }
    context.interpolationQuality = .high
    context.setFillColor(gray: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.draw(
      image, in: destinationRect(for: image, mode: mode, width: width, height: height))
    guard let base = context.data else { throw DeviceError.imageDecodeFailed }
    let rgba = base.assumingMemoryBound(to: UInt8.self)
    var rgb = [UInt8](repeating: 0, count: width * height * 3)
    for pixel in 0..<(width * height) {
      rgb[pixel * 3] = rgba[pixel * 4]
      rgb[pixel * 3 + 1] = rgba[pixel * 4 + 1]
      rgb[pixel * 3 + 2] = rgba[pixel * 4 + 2]
    }
    return rgb
  }

  /// Where to draw the source so the panel is filled, fitted or stretched.
  /// Returned in the panel's coordinate space; may extend past the edges for
  /// `.fill`, which is what produces the centre crop.
  static func destinationRect(
    for image: CGImage, mode: ContentMode, width: Int = Screen.width,
    height: Int = Screen.height
  ) -> CGRect {
    let panel = CGRect(x: 0, y: 0, width: width, height: height)
    let sourceWidth = CGFloat(image.width)
    let sourceHeight = CGFloat(image.height)
    guard mode != .stretch, sourceWidth > 0, sourceHeight > 0 else { return panel }

    let scale: CGFloat = switch mode {
    case .fill: max(panel.width / sourceWidth, panel.height / sourceHeight)
    case .fit: min(panel.width / sourceWidth, panel.height / sourceHeight)
    case .stretch: 1
    }
    let drawnWidth = sourceWidth * scale
    let drawnHeight = sourceHeight * scale
    return CGRect(
      x: (panel.width - drawnWidth) / 2, y: (panel.height - drawnHeight) / 2,
      width: drawnWidth, height: drawnHeight)
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

  /// Calibration pattern: a 2 px border hugging the very edge of the frame,
  /// corner blocks, and centre crosshairs.
  ///
  /// It answers a question the protocol cannot: the firmware accepts a write
  /// handshake for any frame size, so the only way to confirm the panel's real
  /// resolution is to send a frame whose edges are visible and look at it. If
  /// the border touches all four edges, the assumed size is correct; if the
  /// image sits in a corner with dead space around it, the panel is larger.
  public static func rulerPattern(width: Int = Screen.width, height: Int = Screen.height)
    -> ScreenFrame
  {
    var rgb = [UInt8](repeating: 0, count: width * height * 3)
    func set(_ x: Int, _ y: Int, _ color: (UInt8, UInt8, UInt8)) {
      guard x >= 0, x < width, y >= 0, y < height else { return }
      let i = (y * width + x) * 3
      (rgb[i], rgb[i + 1], rgb[i + 2]) = color
    }

    for y in 0..<height {
      for x in 0..<width {
        let onBorder = x < 2 || y < 2 || x >= width - 2 || y >= height - 2
        if onBorder { set(x, y, (255, 255, 255)) }
        // Centre crosshairs.
        if abs(x - width / 2) < 1 || abs(y - height / 2) < 1 { set(x, y, (70, 70, 80)) }
      }
    }
    // Corner blocks, 10 px, inset by the border.
    for y in 0..<10 {
      for x in 0..<10 {
        set(2 + x, 2 + y, (255, 60, 60))
        set(width - 12 + x, 2 + y, (60, 255, 60))
        set(2 + x, height - 12 + y, (60, 120, 255))
        set(width - 12 + x, height - 12 + y, (255, 220, 0))
      }
    }
    return ScreenFrame(rgb: rgb, width: width, height: height)
  }

  /// Colour bands every `step` pixels: count the bands you can see and multiply
  /// by `step` to get the panel's real width and height. The top row runs left
  /// to right, the left column runs top to bottom, in the same colour order.
  public static func bandPattern(
    width: Int = Screen.width, height: Int = Screen.height, step: Int = 32
  ) -> ScreenFrame {
    let palette: [(UInt8, UInt8, UInt8)] = [
      (255, 60, 60), (255, 170, 40), (255, 240, 60), (70, 220, 90),
      (60, 190, 235), (90, 110, 255), (200, 90, 230), (255, 255, 255),
    ]
    var rgb = [UInt8](repeating: 0, count: width * height * 3)
    for y in 0..<height {
      for x in 0..<width {
        let band: (UInt8, UInt8, UInt8)
        if y < step {
          band = palette[(x / step) % palette.count]  // horizontal ruler
        } else if x < step {
          band = palette[(y / step) % palette.count]  // vertical ruler
        } else {
          // Faint checkerboard so wrapping errors show up as a skew.
          let dark = ((x / step) + (y / step)) % 2 == 0
          band = dark ? (18, 18, 22) : (34, 34, 42)
        }
        let i = (y * width + x) * 3
        (rgb[i], rgb[i + 1], rgb[i + 2]) = band
      }
    }
    return ScreenFrame(rgb: rgb, width: width, height: height)
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
