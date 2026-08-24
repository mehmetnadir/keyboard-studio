import KeyboardKit
import SwiftUI

/// An interactive drawing of the connected keyboard.
///
/// One component serves every page that needs keys: assigning shortcuts,
/// painting colours, showing a heatmap. Selection follows the conventions a Mac
/// user already has — click replaces, ⇧ adds, ⌥ removes, ⌘ toggles, drag makes
/// a marquee — so nothing here has to be learned.
struct KeyboardCanvas: View {
  /// How the pointer behaves over the keys.
  enum Interaction {
    /// Build a selection, then act on it — used where an action needs a target
    /// chosen first, like assigning a shortcut.
    case select
    /// Act on each key the pointer touches, straight away — a brush.
    case paint
  }

  let layout: KeyboardLayout
  @Binding var selection: Set<String>
  var interaction: Interaction = .select
  /// Called for every key the brush touches, once per key per stroke.
  var onPaint: ((KeyboardLayout.Key) -> Void)?
  /// Colour for a key, when the page wants to tint them (painting, heatmap).
  var tint: ((KeyboardLayout.Key) -> Color?)?
  /// Small caption under a key's label, e.g. its assigned shortcut.
  var caption: ((KeyboardLayout.Key) -> String?)?
  var onDoubleClick: ((KeyboardLayout.Key) -> Void)?

  @State private var dragStart: CGPoint?
  @State private var dragCurrent: CGPoint?
  @State private var selectionAtDragStart: Set<String> = []
  /// Keys already painted in the current stroke, so dragging across one does
  /// not repaint it on every pointer sample.
  @State private var strokeTouched: Set<String> = []

  private let unit: CGFloat = 44
  private let gap: CGFloat = 3

  var body: some View {
    let width = CGFloat(layout.columns) * unit
    let height = CGFloat(layout.rows) * unit

    ZStack(alignment: .topLeading) {
      ForEach(layout.keys, id: \.id) { key in
        keyView(key)
      }
      if let rect = marqueeRect {
        Rectangle()
          .fill(.tint.opacity(0.12))
          .overlay(Rectangle().strokeBorder(.tint, lineWidth: 1))
          .frame(width: rect.width, height: rect.height)
          .offset(x: rect.minX, y: rect.minY)
          .allowsHitTesting(false)
      }
    }
    .frame(width: width, height: height, alignment: .topLeading)
    .contentShape(Rectangle())
    .gesture(brushGesture, isEnabled: interaction == .paint)
    .gesture(marqueeGesture, isEnabled: interaction == .select)
    .padding(8)
    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
  }

  // MARK: - Keys

  private func keyView(_ key: KeyboardLayout.Key) -> some View {
    let rect = frame(for: key)
    let isSelected = selection.contains(key.id)

    return VStack(spacing: 1) {
      Text(key.label)
        .font(.system(size: key.label.count > 3 ? 9 : 12, weight: .medium))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
      if let caption = caption?(key), !caption.isEmpty {
        Text(caption)
          .font(.system(size: 8))
          .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
      }
    }
    .padding(.horizontal, 2)
    .frame(width: rect.width, height: rect.height)
    .background(background(for: key, selected: isSelected))
    .overlay(
      RoundedRectangle(cornerRadius: key.isKnob ? rect.width / 2 : 6)
        .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 2)
    )
    .clipShape(RoundedRectangle(cornerRadius: key.isKnob ? rect.width / 2 : 6))
    .foregroundStyle(isSelected ? .white : .primary)
    .offset(x: rect.minX, y: rect.minY)
    .onTapGesture(count: 2) { onDoubleClick?(key) }
    .onTapGesture {
      if interaction == .paint {
        onPaint?(key)
      } else {
        toggle(key)
      }
    }
  }

  private func background(for key: KeyboardLayout.Key, selected: Bool) -> AnyShapeStyle {
    if selected { return AnyShapeStyle(.tint) }
    if let painted = tint?(key), painted != .clear { return AnyShapeStyle(painted) }
    return AnyShapeStyle(Color.secondary.opacity(key.isKnob ? 0.28 : 0.16))
  }

  private func frame(for key: KeyboardLayout.Key) -> CGRect {
    CGRect(
      x: key.x * unit + gap / 2, y: key.y * unit + gap / 2,
      width: key.width * unit - gap, height: key.height * unit - gap)
  }

  // MARK: - Selection

  /// Click semantics follow AppKit: plain replaces, ⇧ adds, ⌥ removes,
  /// ⌘ toggles. Modelling all four is what makes irregular groups quick.
  private func toggle(_ key: KeyboardLayout.Key) {
    let flags = NSEvent.modifierFlags
    if flags.contains(.shift) {
      selection.insert(key.id)
    } else if flags.contains(.option) {
      selection.remove(key.id)
    } else if flags.contains(.command) {
      if selection.contains(key.id) { selection.remove(key.id) } else { selection.insert(key.id) }
    } else {
      selection = [key.id]
    }
  }

  private var marqueeRect: CGRect? {
    guard let start = dragStart, let current = dragCurrent else { return nil }
    return CGRect(
      x: min(start.x, current.x), y: min(start.y, current.y),
      width: abs(current.x - start.x), height: abs(current.y - start.y))
  }

  /// Paints continuously while the pointer is down, like dragging a brush.
  /// `minimumDistance: 0` makes a plain press paint immediately rather than
  /// waiting to see whether it becomes a drag.
  private var brushGesture: some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        guard let key = key(at: value.location), !strokeTouched.contains(key.id) else { return }
        strokeTouched.insert(key.id)
        onPaint?(key)
      }
      .onEnded { _ in strokeTouched.removeAll() }
  }

  private func key(at point: CGPoint) -> KeyboardLayout.Key? {
    layout.keys.first { frame(for: $0).contains(point) }
  }

  private var marqueeGesture: some Gesture {
    DragGesture(minimumDistance: 4)
      .onChanged { value in
        if dragStart == nil {
          dragStart = value.startLocation
          selectionAtDragStart = selection
        }
        dragCurrent = value.location
        updateMarqueeSelection()
      }
      .onEnded { _ in
        dragStart = nil
        dragCurrent = nil
        selectionAtDragStart = []
      }
  }

  private func updateMarqueeSelection() {
    guard let rect = marqueeRect else { return }
    let inside = layout.keys.filter { frame(for: $0).intersects(rect) }.map(\.id)
    let flags = NSEvent.modifierFlags
    if flags.contains(.shift) {
      selection = selectionAtDragStart.union(inside)
    } else if flags.contains(.option) {
      selection = selectionAtDragStart.subtracting(inside)
    } else {
      selection = Set(inside)
    }
  }
}
