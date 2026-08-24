import Foundation

/// Everything the app needs to know about one keyboard model.
///
/// This is data, not code: adding a keyboard should mean adding a profile (and
/// a layout file), never editing the transport or the UI. Profiles ship as JSON
/// so contributors can add a board without writing Swift.
public struct DeviceProfile: Codable, Sendable, Identifiable, Hashable {
  /// Stable slug, e.g. "attackshark-k86". Also names the layout file.
  public let id: String
  public let vendor: String
  public let model: String
  /// USB vendor id, e.g. 0x3151 for ROYUAN.
  ///
  /// Note this identifies a *family*, not a model. Across this manufacturer's
  /// catalogue a single vendor/product pair is shared by dozens of different
  /// keyboards, so USB ids can only narrow the search.
  public let vendorID: Int
  /// Product ids this profile matches. Tri-mode boards often enumerate under a
  /// different id per connection, so this is a list rather than one value.
  public let productIDs: [Int]
  /// The device id the board reports to opcode 0x8F — the actual model key.
  /// Where USB ids collide across models, this is what tells them apart, so it
  /// is checked before anything is written.
  public let handshakeID: Int?
  /// How much the entries here are trusted. `guess` means nobody has run the
  /// board; it should not be written to without the user opting in.
  public var confidence: Confidence?

  public enum Confidence: String, Codable, Sendable {
    case confirmed, probable, guess
  }
  /// Which wire protocol drives it. Boards from one manufacturer share a family.
  public let family: ProtocolFamily
  public let capabilities: Capabilities
  /// Layout file name under Layouts/, without the extension. Nil means the
  /// board has no drawn layout yet — lighting and screen still work.
  public let layout: String?

  public enum ProtocolFamily: String, Codable, Sendable {
    /// ROYUAN vendor HID: 64-byte feature reports with a complement checksum.
    /// Sold as Attack Shark, Epomaker, Akko, Hator, ikbc, NOPPOO, MEETION.
    case royuan
  }

  public struct Capabilities: Codable, Sendable, Hashable {
    /// Main backlight: how finely it can be addressed.
    public var lighting: LightingSupport
    /// Separate side light strips.
    public var sideLighting: Bool
    /// Screen description, absent when the board has none.
    public var screen: ScreenSpec?
    /// Rotary encoder in the top right.
    public var knob: Bool
    /// Firmware effect ids this board actually implements. Absent means "the
    /// family's full set" — an override for boards missing some effects.
    public var effects: [String]?

    public init(
      lighting: LightingSupport = .whole, sideLighting: Bool = false,
      screen: ScreenSpec? = nil, knob: Bool = false, effects: [String]? = nil
    ) {
      self.lighting = lighting
      self.sideLighting = sideLighting
      self.screen = screen
      self.knob = knob
      self.effects = effects
    }
  }

  public enum LightingSupport: String, Codable, Sendable {
    /// One colour plus a firmware effect for the whole board.
    case whole
    /// Addressable zones.
    case zones
    /// Every key individually addressable.
    case perKey
    case none
  }

  /// A panel's real geometry. Deliberately per-profile: the ROYUAN protocol
  /// reports "ready" for any frame size, so the resolution cannot be discovered
  /// from the device and must be recorded per model.
  public struct ScreenSpec: Codable, Sendable, Hashable {
    public var width: Int
    public var height: Int
    /// Pixel format on the wire; only rgb565 exists in this family so far.
    public var pixelFormat: String
    /// Maximum animation frames per upload.
    public var maxFrames: Int
    /// Set when the resolution has been confirmed on real hardware rather than
    /// taken from a datasheet or another project's constant.
    public var verified: Bool

    public init(
      width: Int, height: Int, pixelFormat: String = "rgb565", maxFrames: Int = 30,
      verified: Bool = false
    ) {
      self.width = width
      self.height = height
      self.pixelFormat = pixelFormat
      self.maxFrames = maxFrames
      self.verified = verified
    }
  }

  public init(
    id: String, vendor: String, model: String, vendorID: Int, productIDs: [Int],
    family: ProtocolFamily, capabilities: Capabilities, layout: String? = nil,
    handshakeID: Int? = nil, confidence: Confidence? = nil
  ) {
    self.id = id
    self.vendor = vendor
    self.model = model
    self.vendorID = vendorID
    self.productIDs = productIDs
    self.handshakeID = handshakeID
    self.confidence = confidence
    self.family = family
    self.capabilities = capabilities
    self.layout = layout
  }

  public var displayName: String { "\(vendor) \(model)" }

  /// USB-level match. Only narrows candidates — see `handshakeID`.
  public func matches(vendorID: Int, productID: Int) -> Bool {
    self.vendorID == vendorID && productIDs.contains(productID)
  }
}
