import Foundation

/// Per-key colour: a stored pattern, not a live canvas.
///
/// The firmware keeps one colour per keymap slot and shows it as light effect
/// 13. Uploading commits to the keyboard's flash, so this is deliberately not
/// a streaming path — see `Pacing` for why the timing here is not negotiable.
public enum PerKeyLighting {
  /// Slots in a pattern payload. Colours are indexed by keymap slot, the same
  /// numbering the keymap read uses, so a key's colour and its binding share
  /// one address.
  public static let slotCount = 128
  public static var payloadSize: Int { slotCount * 3 }

  static let opSetPattern: UInt8 = 0x0C
  static let chunkSize = 56
  /// Light effect index that displays the stored pattern.
  static let patternEffectIndex: UInt8 = 13

  /// Timing the firmware requires. These are not tuning knobs: sending pages
  /// faster wedges the control endpoint, and a wedged endpoint fails every
  /// subsequent report until the keyboard is physically re-plugged.
  public enum Pacing {
    /// Between the seven pages of one upload.
    public static let betweenPages: TimeInterval = 0.1
    /// After the last page, before anything else is sent.
    public static let settle: TimeInterval = 2.0
    /// Between two complete uploads. Also protects flash endurance — the cells
    /// are rated for something like ten thousand writes.
    public static let betweenUploads: TimeInterval = 10.0
  }

  /// A colour per slot; slots left out stay dark.
  public struct Pattern: Sendable, Equatable {
    public var colors: [Int: RGB]

    public init(colors: [Int: RGB] = [:]) {
      self.colors = colors
    }

    /// Row-major RGB payload, one triple per slot.
    public func payload() -> [UInt8] {
      var bytes = [UInt8](repeating: 0, count: PerKeyLighting.payloadSize)
      for (slot, color) in colors where slot >= 0 && slot < PerKeyLighting.slotCount {
        bytes[slot * 3] = color.r
        bytes[slot * 3 + 1] = color.g
        bytes[slot * 3 + 2] = color.b
      }
      return bytes
    }
  }

  /// Tracks when the last upload happened so the cadence can be enforced
  /// centrally rather than trusted to each caller.
  public final class Throttle: @unchecked Sendable {
    private let lock = NSLock()
    private var lastUpload: Date?

    public init() {}

    /// Seconds still to wait, or zero when an upload may proceed now.
    public func remainingWait(now: Date = Date()) -> TimeInterval {
      lock.withLock {
        guard let lastUpload else { return 0 }
        return max(0, Pacing.betweenUploads - now.timeIntervalSince(lastUpload))
      }
    }

    public func recordUpload(at date: Date = Date()) {
      lock.withLock { lastUpload = date }
    }
  }

  /// Writes a pattern into the keyboard and shows it.
  ///
  /// Blocks for roughly three seconds by design — pages are spaced and the
  /// firmware is given time to finish writing flash before the mode switch.
  /// Callers must run this off the main thread.
  public static func upload(
    _ pattern: Pattern, slot: UInt8 = 0, brightness: Int = 4, on kb: Keyboard,
    throttle: Throttle? = nil
  ) throws {
    if let throttle, throttle.remainingWait() > 0 {
      throw DeviceError.rateLimited(seconds: throttle.remainingWait())
    }
    guard try kb.verifyIdentity() else { throw DeviceError.identityMismatch }

    let bytes = pattern.payload()
    let pageCount = (bytes.count + chunkSize - 1) / chunkSize
    for page in 0..<pageCount {
      var packet = [UInt8](repeating: 0, count: Proto.reportLen)
      packet[0] = opSetPattern
      packet[1] = 0  // pattern slot; this lineage ignores it, kept explicit
      packet[2] = UInt8(bytes.count & 0xFF)
      packet[3] = UInt8((bytes.count >> 8) & 0xFF)
      packet[4] = UInt8(page)
      let start = page * chunkSize
      let end = min(start + chunkSize, bytes.count)
      for (offset, byte) in bytes[start..<end].enumerated() {
        packet[8 + offset] = byte
      }
      try kb.sendFeature(packet, mode: .bit7)
      if page < pageCount - 1 {
        Thread.sleep(forTimeInterval: Pacing.betweenPages)
      }
    }

    // Let the flash write finish before asking the board to do anything else.
    Thread.sleep(forTimeInterval: Pacing.settle)
    try showPattern(slot: slot, brightness: brightness, on: kb)
    throttle?.recordUpload()
  }

  /// Switches the main light to the stored pattern.
  ///
  /// The colour bytes are fixed at (0, 200, 200): the firmware ignores them in
  /// this mode, and sending anything else has no effect.
  public static func showPattern(
    slot: UInt8 = 0, brightness: Int = 4, speed: Int = 3, on kb: Keyboard
  ) throws {
    let clampedSpeed = max(0, min(speed, Proto.lightMaxSpeed))
    let command: [UInt8] = [
      Proto.opSetLEDParam, patternEffectIndex,
      UInt8(Proto.lightMaxSpeed - clampedSpeed), UInt8(max(0, min(brightness, 4))),
      slot << 4, 0, 200, 200,
    ]
    try kb.sendFeature(command, mode: .bit8)
  }
}
