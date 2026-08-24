import Foundation

/// Physical arrangement of a keyboard, loaded from JSON.
///
/// Field names follow QMK's `info.json` (`x`, `y`, `w`, `h`, `label`) so a
/// layout can be converted from QMK or keyboard-layout-editor with a small
/// script rather than redrawn by hand.
public struct KeyboardLayout: Codable, Sendable, Identifiable, Hashable {
  public struct Key: Codable, Sendable, Identifiable, Hashable {
    public var label: String
    /// HID usage id (page 0x07), so painting and statistics share a vocabulary.
    /// Absent for keys that emit no usage, like Fn or the knob.
    public var usage: Int?
    public var x: Double
    public var y: Double
    public var w: Double?
    public var h: Double?
    public var knob: Bool?

    public var width: Double { w ?? 1 }
    public var height: Double { h ?? 1 }
    public var isKnob: Bool { knob ?? false }
    /// Position is unique within a layout, so it makes a stable identity.
    public var id: String { "\(x)x\(y)" }
  }

  public let id: String
  public let name: String
  public let columns: Double
  public let rows: Double
  public let keys: [Key]

  /// Normalised 0…1 centre, so effect maths is independent of render size.
  public func normalised(_ key: Key) -> (x: Double, y: Double) {
    ((key.x + key.width / 2) / columns, (key.y + key.height / 2) / rows)
  }

  // MARK: - Loading

  public static func load(named name: String) -> KeyboardLayout? {
    let userFile = LayoutCatalog.userDirectory.appendingPathComponent("\(name).json")
    if let layout = decode(userFile) { return layout }
    guard let url = Bundle.module.url(
      forResource: name, withExtension: "json", subdirectory: "Layouts")
    else { return nil }
    return decode(url)
  }

  private static func decode(_ url: URL) -> KeyboardLayout? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(KeyboardLayout.self, from: data)
  }
}

public enum LayoutCatalog {
  /// User-supplied layouts, so a board can be drawn without rebuilding.
  public static var userDirectory: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first ?? FileManager.default.homeDirectoryForCurrentUser
    return base.appendingPathComponent("KeyboardStudio/Layouts", isDirectory: true)
  }

  public static func all() -> [KeyboardLayout] {
    var layouts: [String: KeyboardLayout] = [:]
    let bundled = Bundle.module.urls(
      forResourcesWithExtension: "json", subdirectory: "Layouts") ?? []
    let user = (try? FileManager.default.contentsOfDirectory(
      at: userDirectory, includingPropertiesForKeys: nil))?.filter { $0.pathExtension == "json" }
      ?? []
    for url in bundled + user {
      guard let data = try? Data(contentsOf: url),
        let layout = try? JSONDecoder().decode(KeyboardLayout.self, from: data)
      else { continue }
      layouts[layout.id] = layout  // user files win, they come last
    }
    return layouts.values.sorted { $0.id < $1.id }
  }
}

extension KeyboardLayout {
  /// Generic grid for boards with no layout file yet — effects still preview,
  /// they just do not show the real key shapes.
  public static let placeholder: KeyboardLayout = {
    var keys: [Key] = []
    for row in 0..<5 {
      for column in 0..<15 {
        keys.append(Key(label: "", usage: nil, x: Double(column), y: Double(row)))
      }
    }
    return KeyboardLayout(
      id: "placeholder", name: "Generic", columns: 15, rows: 5, keys: keys)
  }()
}
