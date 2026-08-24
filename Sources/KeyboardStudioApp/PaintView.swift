import KeyboardKit
import SwiftUI

/// Painting a colour onto individual keys.
///
/// The board stores this as a pattern in its own flash and shows it as a light
/// effect, so it is a picture you compose and then send — not a live canvas.
/// The UI leans into that: paint freely, then press Send once.
struct PaintView: View {
  @Environment(AppModel.self) private var model
  @State private var selection: Set<String> = []
  @State private var brush = Color(red: 0.61, green: 0.35, blue: 0.71)

  private var layout: KeyboardLayout { model.layout ?? .placeholder }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ScrollView([.horizontal, .vertical]) {
        KeyboardCanvas(
          layout: layout,
          selection: $selection,
          tint: { key in model.paintedColor(for: key) ?? Color.clear })
          .padding(16)
      }
      .frame(maxHeight: 300)

      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          brushRow
          paletteRow
          groupsRow
          sendRow
          Text("paint.explainer")
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(18)
      }
    }
    .overlay {
      if !model.isConnected { DisconnectedOverlay() }
    }
  }

  // MARK: - Controls

  private var brushRow: some View {
    HStack(spacing: 12) {
      ColorPicker("paint.colour", selection: $brush, supportsOpacity: false)
        .frame(width: 150)
      Button("paint.apply_to_selection") {
        model.paint(keyIDs: selection, color: brush, in: layout)
      }
      .buttonStyle(.borderedProminent)
      .disabled(selection.isEmpty)
      Button("paint.clear_selection") {
        model.paint(keyIDs: selection, color: nil, in: layout)
      }
      .disabled(selection.isEmpty)
      Spacer()
      Button("paint.clear_all") { model.clearPainting() }
        .disabled(model.paintedKeys.isEmpty)
    }
  }

  private var paletteRow: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("paint.palette").font(.headline)
      HStack(spacing: 8) {
        ForEach(Self.palette, id: \.description) { color in
          Button {
            brush = color
            if !selection.isEmpty {
              model.paint(keyIDs: selection, color: color, in: layout)
            }
          } label: {
            RoundedRectangle(cornerRadius: 6)
              .fill(color)
              .frame(width: 30, height: 24)
              .overlay(
                RoundedRectangle(cornerRadius: 6)
                  .strokeBorder(.white.opacity(0.25), lineWidth: 1))
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  /// Selecting by role is faster than dragging over the same keys every time.
  private var groupsRow: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("paint.groups").font(.headline)
      HStack(spacing: 8) {
        ForEach(KeyGroup.allCases, id: \.self) { group in
          Button(group.title) { selection = group.keyIDs(in: layout) }
            .buttonStyle(.bordered)
        }
        Button("paint.select_all") { selection = Set(layout.keys.map(\.id)) }
          .buttonStyle(.bordered)
      }
    }
  }

  private var sendRow: some View {
    HStack(spacing: 12) {
      Button("paint.send") {
        Task { await model.sendPainting(layout: layout) }
      }
      .buttonStyle(.borderedProminent)
      .disabled(!model.isConnected || model.isUploading || model.paintedKeys.isEmpty)

      if model.isUploading {
        ProgressView().controlSize(.small)
      }
      if let wait = model.paintCooldown, wait > 0 {
        Text("paint.cooldown \(Int(wait.rounded(.up)))")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      if let status = model.paintStatus {
        Text(status).font(.callout).foregroundStyle(.secondary)
      }
      Spacer()
    }
  }

  private static let palette: [Color] = [
    Color(red: 0.95, green: 0.26, blue: 0.26), Color(red: 1, green: 0.6, blue: 0.15),
    Color(red: 1, green: 0.9, blue: 0.25), Color(red: 0.3, green: 0.85, blue: 0.4),
    Color(red: 0.2, green: 0.75, blue: 0.9), Color(red: 0.35, green: 0.45, blue: 1),
    Color(red: 0.75, green: 0.35, blue: 0.9), Color.white,
  ]

  /// Key groups people actually think in.
  enum KeyGroup: String, CaseIterable {
    case wasd, arrows, functionRow, numberRow, modifiers

    var title: LocalizedStringKey {
      switch self {
      case .wasd: "paint.group.wasd"
      case .arrows: "paint.group.arrows"
      case .functionRow: "paint.group.function"
      case .numberRow: "paint.group.numbers"
      case .modifiers: "paint.group.modifiers"
      }
    }

    func keyIDs(in layout: KeyboardLayout) -> Set<String> {
      let usages: Set<Int>
      switch self {
      case .wasd: usages = [0x1A, 0x04, 0x16, 0x07]
      case .arrows: usages = [0x4F, 0x50, 0x51, 0x52]
      case .functionRow: usages = Set(0x3A...0x45)
      case .numberRow: usages = Set(0x1E...0x27)
      case .modifiers: usages = Set(0xE0...0xE7)
      }
      return Set(layout.keys.filter { key in key.usage.map(usages.contains) ?? false }.map(\.id))
    }
  }
}
