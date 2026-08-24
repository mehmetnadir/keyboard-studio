import KeyboardKit
import SwiftUI

/// Painting colours onto individual keys.
///
/// It works like a brush: pick a colour, then drag across the keys. There is no
/// select-then-apply step — the colour lands as the pointer passes, which is
/// what people expect from anything called painting.
///
/// The board stores the result in its own flash and shows it as a lighting
/// mode, so this is compose-then-send rather than a live canvas.
struct PaintView: View {
  @Environment(AppModel.self) private var model
  @State private var selection: Set<String> = []
  @State private var brush = Color(red: 0.61, green: 0.35, blue: 0.71)
  @State private var erasing = false

  private var layout: KeyboardLayout { model.layout ?? .placeholder }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      toolbar
      Divider()

      ScrollView([.horizontal, .vertical]) {
        KeyboardCanvas(
          layout: layout,
          selection: $selection,
          interaction: .paint,
          onPaint: { key in paint(key) },
          tint: { key in model.paintedColor(for: key) ?? Color.clear })
          .padding(16)
      }

      Divider()
      footer
    }
    .overlay {
      if !model.isConnected { DisconnectedOverlay() }
    }
  }

  // MARK: - Toolbar

  /// Everything needed while painting sits in one row above the keyboard, so
  /// the pointer never has to travel far from the keys.
  private var toolbar: some View {
    HStack(spacing: 14) {
      HStack(spacing: 6) {
        ForEach(Self.palette, id: \.description) { color in
          swatch(color)
        }
        ColorPicker("", selection: $brush, supportsOpacity: false)
          .labelsHidden()
          .frame(width: 44)
          .onChange(of: brush) { _, _ in erasing = false }
      }

      Divider().frame(height: 22)

      Toggle(isOn: $erasing) {
        Label("paint.eraser", systemImage: "eraser.fill")
      }
      .toggleStyle(.button)

      Menu {
        ForEach(KeyGroup.allCases, id: \.self) { group in
          Button(group.title) { paintGroup(group) }
        }
        Divider()
        Button("paint.select_all") { paintEverything() }
      } label: {
        Label("paint.fill_group", systemImage: "square.grid.2x2")
      }
      .frame(width: 150)

      Spacer()

      Button("paint.clear_all") { model.clearPainting() }
        .disabled(model.paintedKeys.isEmpty)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
  }

  private func swatch(_ color: Color) -> some View {
    let isActive = !erasing && color.description == brush.description
    return Button {
      brush = color
      erasing = false
    } label: {
      RoundedRectangle(cornerRadius: 6)
        .fill(color)
        .frame(width: 26, height: 26)
        .overlay(
          RoundedRectangle(cornerRadius: 6)
            .strokeBorder(isActive ? Color.primary : Color.white.opacity(0.2),
              lineWidth: isActive ? 2 : 1))
    }
    .buttonStyle(.plain)
  }

  // MARK: - Footer

  private var footer: some View {
    HStack(spacing: 12) {
      Button("paint.send") {
        Task { await model.sendPainting(layout: layout) }
      }
      .buttonStyle(.borderedProminent)
      .disabled(!model.isConnected || model.isUploading || model.paintedKeys.isEmpty)

      if model.isUploading { ProgressView().controlSize(.small) }
      if let wait = model.paintCooldown, wait > 0 {
        Text("paint.cooldown \(Int(wait.rounded(.up)))")
          .font(.callout)
          .foregroundStyle(.secondary)
      } else if let status = model.paintStatus {
        Text(status).font(.callout).foregroundStyle(.secondary)
      } else {
        Text("paint.hint").font(.callout).foregroundStyle(.tertiary)
      }
      Spacer()
      Text("paint.painted_count \(model.paintedKeys.count)")
        .font(.caption)
        .foregroundStyle(.tertiary)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
  }

  // MARK: - Painting

  private func paint(_ key: KeyboardLayout.Key) {
    model.paint(keyIDs: [key.id], color: erasing ? nil : brush, in: layout)
  }

  private func paintGroup(_ group: KeyGroup) {
    model.paint(keyIDs: group.keyIDs(in: layout), color: erasing ? nil : brush, in: layout)
  }

  private func paintEverything() {
    model.paint(
      keyIDs: Set(layout.keys.map(\.id)), color: erasing ? nil : brush, in: layout)
  }

  private static let palette: [Color] = [
    Color(red: 0.95, green: 0.26, blue: 0.26), Color(red: 1, green: 0.6, blue: 0.15),
    Color(red: 1, green: 0.9, blue: 0.25), Color(red: 0.3, green: 0.85, blue: 0.4),
    Color(red: 0.2, green: 0.75, blue: 0.9), Color(red: 0.35, green: 0.45, blue: 1),
    Color(red: 0.75, green: 0.35, blue: 0.9), Color.white,
  ]

  /// Key groups people actually think in, filled in one click.
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
