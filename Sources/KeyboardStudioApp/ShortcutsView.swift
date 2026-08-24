import KeyboardKit
import SwiftUI

/// Assigning shortcuts to keys, on a drawing of the actual keyboard.
///
/// Pick a key, pick what it should do. Ready-made macOS shortcuts come first so
/// nothing has to be known about HID usages; a custom combination is there for
/// anyone who wants one.
struct ShortcutsView: View {
  @Environment(AppModel.self) private var model
  @State private var selection: Set<String> = []
  @State private var category: MacShortcuts.Category = .system
  @State private var customUsage = ""
  @State private var customModifiers: Shortcut.Modifiers = [.command]

  private var layout: KeyboardLayout { model.layout ?? .placeholder }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ScrollView([.horizontal, .vertical]) {
        KeyboardCanvas(
          layout: layout,
          selection: $selection,
          caption: { key in model.assignedShortcutLabel(for: key) })
          .padding(16)
      }
      .frame(maxHeight: 320)

      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          selectionSummary
          if !selection.isEmpty {
            readyMade
            customCombination
          }
          notice
        }
        .padding(18)
      }
    }
    .overlay {
      if !model.isConnected { DisconnectedOverlay() }
    }
    .task { model.loadKeymap() }
  }

  // MARK: - Sections

  private var selectionSummary: some View {
    HStack(spacing: 8) {
      Image(systemName: "cursorarrow.rays")
        .foregroundStyle(.secondary)
      if selection.isEmpty {
        Text("shortcuts.pick_a_key").foregroundStyle(.secondary)
      } else {
        Text("shortcuts.selected \(selectedLabels)")
          .font(.callout.weight(.medium))
        Spacer()
        Button("shortcuts.clear_selection") { selection = [] }
          .buttonStyle(.link)
      }
      Spacer()
    }
  }

  private var readyMade: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("shortcuts.ready_made").font(.headline)
      Picker("", selection: $category) {
        ForEach(MacShortcuts.Category.allCases) { item in
          Text(item.rawValue).tag(item)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()

      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 210), spacing: 8)], spacing: 8
      ) {
        ForEach(MacShortcuts.entries(in: category)) { entry in
          Button {
            model.assignShortcut(entry.shortcut, toKeyIDs: selection, in: layout)
          } label: {
            HStack(spacing: 8) {
              Text(entry.name)
                .lineLimit(1)
              Spacer()
              Text(entry.display)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  private var customCombination: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("shortcuts.custom").font(.headline)
      HStack(spacing: 10) {
        ForEach(modifierChoices, id: \.label) { choice in
          Toggle(choice.label, isOn: modifierBinding(choice.modifier))
            .toggleStyle(.button)
      }
        TextField("shortcuts.key_placeholder", text: $customUsage)
          .frame(width: 90)
          .textFieldStyle(.roundedBorder)
        Button("shortcuts.assign") {
          if let usage = parsedCustomUsage {
            model.assignShortcut(
              Shortcut(usage: usage, modifiers: customModifiers),
              toKeyIDs: selection, in: layout)
          }
        }
        .disabled(parsedCustomUsage == nil)
      }
      Text("shortcuts.custom_hint")
        .font(.caption)
        .foregroundStyle(.tertiary)
    }
  }

  private var notice: some View {
    Label("shortcuts.write_pending", systemImage: "info.circle")
      .font(.caption)
      .foregroundStyle(.secondary)
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
  }

  // MARK: - Helpers

  private var selectedLabels: String {
    let labels = layout.keys.filter { selection.contains($0.id) }.map(\.label)
    return labels.count <= 4
      ? labels.joined(separator: " ")
      : labels.prefix(4).joined(separator: " ") + " +\(labels.count - 4)"
  }

  private var modifierChoices: [(label: String, modifier: Shortcut.Modifiers)] {
    [("⌃", .control), ("⌥", .option), ("⇧", .shift), ("⌘", .command)]
  }

  private func modifierBinding(_ modifier: Shortcut.Modifiers) -> Binding<Bool> {
    Binding(
      get: { customModifiers.contains(modifier) },
      set: { on in
        if on { customModifiers.insert(modifier) } else { customModifiers.remove(modifier) }
      })
  }

  /// Accepts a single letter, a digit, or a raw 0x usage.
  private var parsedCustomUsage: Int? {
    let text = customUsage.trimmingCharacters(in: .whitespaces)
    guard !text.isEmpty else { return nil }
    if text.lowercased().hasPrefix("0x") {
      return Int(text.dropFirst(2), radix: 16)
    }
    if text.count == 1, let scalar = text.uppercased().unicodeScalars.first {
      if scalar.value >= 65, scalar.value <= 90 { return Int(scalar.value) - 65 + 0x04 }
      if scalar.value >= 49, scalar.value <= 57 { return Int(scalar.value) - 49 + 0x1E }
      if scalar.value == 48 { return 0x27 }
    }
    return nil
  }
}
