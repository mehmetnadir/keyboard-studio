import AppKit
import Foundation

/// Everything the user has sent to the screen, kept so it can be sent again.
///
/// Files are copied rather than referenced. A gallery of aliases would rot the
/// first time something is moved out of Downloads, and half of what goes here
/// is found on the web and saved once — the copy is the point.
///
/// The layout is deliberately plain: one flat directory of ordinary image
/// files plus a JSON sidecar of titles. Nothing here needs this app to be
/// readable, which is what makes a collection shareable later — a folder can
/// be zipped, published, or dropped into someone else's gallery directory
/// without an export step.
struct GalleryItem: Identifiable, Hashable, Sendable {
  let id: String
  let url: URL
  let addedAt: Date
  var title: String

  var isAnimated: Bool { url.pathExtension.lowercased() == "gif" }
}

enum ScreenGallery {
  /// `~/Library/Application Support/KeyboardStudio/Gallery/`
  static func directory() throws -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("KeyboardStudio", isDirectory: true)
      .appendingPathComponent("Gallery", isDirectory: true)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return base
  }

  private static func titlesFile() throws -> URL {
    try directory().appendingPathComponent("titles.json")
  }

  private static func titles() -> [String: String] {
    guard let url = try? titlesFile(), let data = try? Data(contentsOf: url),
      let map = try? JSONDecoder().decode([String: String].self, from: data)
    else { return [:] }
    return map
  }

  private static func writeTitles(_ map: [String: String]) {
    guard let url = try? titlesFile(),
      let data = try? JSONEncoder().encode(map)
    else { return }
    try? data.write(to: url, options: .atomic)
  }

  /// Copies a file in, returning the stored item.
  ///
  /// A name already in use gets a numeric suffix instead of overwriting: two
  /// unrelated downloads are very often both called `tenor.gif`, and silently
  /// replacing the first one would lose it.
  @discardableResult
  static func add(_ source: URL) throws -> GalleryItem {
    let folder = try directory()
    let base = source.deletingPathExtension().lastPathComponent
    let ext = source.pathExtension
    var name = "\(base).\(ext)"
    var counter = 2
    while FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path) {
      name = "\(base)-\(counter).\(ext)"
      counter += 1
    }
    let destination = folder.appendingPathComponent(name)
    try FileManager.default.copyItem(at: source, to: destination)

    var map = titles()
    map[name] = base
    writeTitles(map)
    return GalleryItem(id: name, url: destination, addedAt: Date(), title: base)
  }

  /// Newest first, so the thing just added is where the eye already is.
  static func items() -> [GalleryItem] {
    guard let folder = try? directory(),
      let names = try? FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: [.contentModificationDateKey])
    else { return [] }

    let map = titles()
    let allowed: Set<String> = ["gif", "png", "jpg", "jpeg", "heic", "webp", "bmp", "tiff"]
    return names
      .filter { allowed.contains($0.pathExtension.lowercased()) }
      .map { url in
        let added =
          (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
          .contentModificationDate ?? Date.distantPast
        let name = url.lastPathComponent
        return GalleryItem(
          id: name, url: url, addedAt: added,
          title: map[name] ?? url.deletingPathExtension().lastPathComponent)
      }
      .sorted { $0.addedAt > $1.addedAt }
  }

  static func remove(_ item: GalleryItem) throws {
    try FileManager.default.removeItem(at: item.url)
    var map = titles()
    map[item.id] = nil
    writeTitles(map)
  }

  static func rename(_ item: GalleryItem, to title: String) {
    var map = titles()
    map[item.id] = title
    writeTitles(map)
  }

  /// A still frame for the grid.
  ///
  /// Drawn at the panel's aspect ratio rather than the source's, so the tile
  /// previews what the keyboard will actually show — a 320×240 GIF on a
  /// 235×128 screen loses its top and bottom, and the grid should say so
  /// before the upload does.
  static func thumbnail(for item: GalleryItem, width: Int, height: Int) -> NSImage? {
    guard let source = NSImage(contentsOf: item.url) else { return nil }
    let target = NSSize(width: width, height: height)
    let image = NSImage(size: target)
    image.lockFocus()
    NSColor.black.setFill()
    NSRect(origin: .zero, size: target).fill()

    let sourceSize = source.size
    guard sourceSize.width > 0, sourceSize.height > 0 else {
      image.unlockFocus()
      return image
    }
    let scale = max(target.width / sourceSize.width, target.height / sourceSize.height)
    let scaled = NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
    let origin = NSPoint(
      x: (target.width - scaled.width) / 2, y: (target.height - scaled.height) / 2)
    source.draw(
      in: NSRect(origin: origin, size: scaled), from: .zero, operation: .sourceOver, fraction: 1)
    image.unlockFocus()
    return image
  }
}
