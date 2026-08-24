import Foundation

/// Which checksum variant a probe should use.
public enum ChecksumModeSelector: Sendable {
  case bit7, bit8
}

/// A connected keyboard, opened through its vendor control interface.
///
/// The profile decides which USB ids to look for, what the panel's geometry is
/// and which features exist — so supporting another board is a data change, not
/// a code change.
///
/// Configuration only works over the USB cable; settings persist in the
/// keyboard's own memory and survive switching back to Bluetooth/2.4GHz.
public final class Keyboard {
  private let transport: HIDTransport
  public let profile: DeviceProfile

  public init(profile: DeviceProfile) throws {
    self.profile = profile
    self.transport = try HIDTransport(profile: profile)
  }

  /// Opens whichever supported keyboard is attached.
  public convenience init() throws {
    guard let profile = DeviceCatalog.firstConnected() else { throw DeviceError.deviceNotFound }
    try self.init(profile: profile)
  }

  public static var isConnected: Bool {
    DeviceCatalog.firstConnected() != nil
  }

  /// The panel's geometry, or nil when this board has no screen.
  public var screen: DeviceProfile.ScreenSpec? { profile.capabilities.screen }

  public func close() {
    transport.close()
  }

  // MARK: - Transport

  func sendFeature(_ cmd: [UInt8], mode: ChecksumMode) throws {
    try transport.sendFeature(Proto.encode(cmd, mode: mode))
  }

  @discardableResult
  func query(_ cmd: [UInt8], mode: ChecksumMode = .bit7, wait: TimeInterval = 0.03) throws -> [UInt8] {
    try sendFeature(cmd, mode: mode)
    Thread.sleep(forTimeInterval: wait)
    return try transport.getFeature()
  }

  // MARK: - Info

  /// The model id the board reports to opcode 0x8F.
  ///
  /// This is the only reliable way to tell models apart in this family: one
  /// USB vendor/product pair is reused across dozens of keyboards.
  public func deviceID() throws -> Int? {
    let f = try query([Proto.opGetDeviceID])
    guard f.count > 4, f[0] == Proto.opGetDeviceID else { return nil }
    return Int(f[1]) | Int(f[2]) << 8 | Int(f[3]) << 16 | Int(f[4]) << 24
  }

  /// Confirms the board really is the model this profile describes.
  ///
  /// Returns true when the profile declares no `handshakeID` (nothing to check)
  /// or the board agrees. A mismatch means we are about to speak one model's
  /// protocol to another — the documented cause of bricked keyboards in this
  /// space — so callers should stop rather than continue.
  public func verifyIdentity() throws -> Bool {
    guard let expected = profile.handshakeID else { return true }
    guard let reported = try deviceID() else { return false }
    return reported == expected
  }

  /// Firmware revision word as reported by the device (e.g. 0x0113).
  public func firmwareVersion() throws -> Int? {
    let f = try query([Proto.opGetRev])
    guard f.count > 2, f[0] == Proto.opGetRev else { return nil }
    return (Int(f[2]) << 8) | Int(f[1])
  }

  // MARK: - Diagnostics

  /// Sends a bare read-only opcode and returns the raw reply. For exploring
  /// what a given firmware reports; callers interpret the bytes themselves.
  public func probe(opcode: UInt8) throws -> [UInt8] {
    try query([opcode])
  }

  /// Sends an arbitrary read command and returns the raw reply, for protocol
  /// exploration. Read-only by convention — callers must not pass write opcodes.
  public func probeRaw(_ cmd: [UInt8], mode: ChecksumModeSelector = .bit7) throws -> [UInt8] {
    try query(cmd, mode: mode == .bit7 ? .bit7 : .bit8)
  }

  /// Sends a raw command for protocol work that has not yet been wrapped in a
  /// typed API — currently the keymap write, which is still being proven.
  /// Ordinary features should not call this.
  public func sendRaw(_ cmd: [UInt8], mode: ChecksumModeSelector = .bit7) throws {
    try sendFeature(cmd, mode: mode == .bit7 ? .bit7 : .bit8)
  }

  /// Asks whether the panel would accept a frame of this size, without sending
  /// any pixels. Used to discover the real screen resolution rather than
  /// trusting a hard-coded constant.
  public func probeScreenGeometry(width: Int, height: Int) -> Bool {
    Screen.handshakeAccepts(width: width, height: height, on: self)
  }

  // MARK: - LED master switch

  /// (mainByte, sideByte, powerSave) from the kboption block.
  func readKBOption() throws -> (main: UInt8, side: UInt8, powerSave: UInt8) {
    // The opcode echo check matters: setLEDs read-modify-writes these bytes
    // into the keyboard's persistent memory, so a stale report must not pass.
    let f = try query([Proto.opGetKBOption, 0])
    guard f.count > 4, f[0] == Proto.opGetKBOption else { throw DeviceError.staleResponse }
    return (f[2], f[3], f[4])
  }

  /// Enable/disable BOTH main and side LEDs (also clears power-save).
  ///
  /// The firmware keeps LED-off bits that mute all lighting regardless of the
  /// stored colour — always call `setLEDs(on: true)` before setting colours.
  public func setLEDs(on: Bool) throws {
    let (main, side, _) = try readKBOption()
    let newMain = on
      ? main & ~Proto.mainLEDOffBit & ~Proto.sideLEDOffBit
      : main | Proto.mainLEDOffBit | Proto.sideLEDOffBit
    try sendFeature(
      [Proto.opSetKBOption, 0, newMain, side, on ? 0 : 1], mode: .bit7)
  }

  // MARK: - Lighting

  public func setMainColor(
    _ color: RGB, effect: LightEffect = .solid, brightness: Int = 4, speed: Int = 3
  ) throws {
    try setLight(
      op: Proto.opSetLEDParam, effect: effect, option: Proto.optCustomRGB,
      color: color, brightness: brightness, speed: speed)
  }

  public func setMainEffect(
    _ effect: LightEffect, brightness: Int = 4, speed: Int = 3,
    rainbow: Bool = true, color: RGB = RGB(255, 0, 0)
  ) throws {
    try setLight(
      op: Proto.opSetLEDParam, effect: effect,
      option: rainbow ? Proto.optRainbow : Proto.optCustomRGB,
      color: color, brightness: brightness, speed: speed)
  }

  public func setSideColor(
    _ color: RGB, effect: LightEffect = .solid, brightness: Int = 4, speed: Int = 3
  ) throws {
    // Firmware quirk: pure white on the side strip must be sent as (250,255,250).
    let side = color == RGB(255, 255, 255) ? RGB(250, 255, 250) : color
    try setLight(
      op: Proto.opSetSLEDParam, effect: effect, option: Proto.optCustomRGB,
      color: side, brightness: brightness, speed: speed)
  }

  private func setLight(
    op: UInt8, effect: LightEffect, option: UInt8, color: RGB, brightness: Int, speed: Int
  ) throws {
    let clampedSpeed = max(0, min(speed, Proto.lightMaxSpeed))
    let cmd: [UInt8] = [
      op, effect.index, UInt8(Proto.lightMaxSpeed - clampedSpeed),
      UInt8(max(0, min(brightness, 4))), option, color.r, color.g, color.b,
    ]
    try sendFeature(cmd, mode: .bit8)
  }
}
