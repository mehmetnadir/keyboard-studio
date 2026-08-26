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
  @AppStorage("hideGlobeNote") private var hideGlobeNote = false

  private var layout: KeyboardLayout { model.layout ?? .placeholder }

  /// Why the keyboard's Fn is not macOS's Globe key, and what to do about it.
  ///
  /// Two separate facts, and people usually only know the second:
  ///
  ///  * The keyboard's Fn never reaches the Mac. It switches layers inside the
  ///    firmware, so no code goes out over USB — nothing can be assigned to it
  ///    here, and macOS cannot see it at all.
  ///  * Apple's Globe key is not a standard HID code. It belongs to Apple's own
  ///    device protocol, so no third-party keyboard can send it. This is not a
  ///    limitation of this board.
  ///
  /// The way through is to send an ordinary modifier and let macOS translate
  /// it: assign a key here to Right Option, then set Right Option to Globe in
  /// Keyboard Settings → Modifier Keys.
  @ViewBuilder private var globeNote: some View {
    if !hideGlobeNote {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: "globe")
          .foregroundStyle(.tint)
        VStack(alignment: .leading, spacing: 4) {
          Text("shortcuts.globe.title").font(.callout.weight(.medium))
          Text("shortcuts.globe.detail")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          HStack(spacing: 12) {
            // Right Control by default: Right Option is often still needed for
            // typing accented characters, so taking it away by default would
            // cost more than it gives. Any key works — select one first.
            Button("shortcuts.globe.assign") {
              if let entry = MacShortcuts.all.first(where: { $0.id == "right-control" }) {
                model.assignShortcut(entry.shortcut, toKeyIDs: selection, in: layout)
              }
            }
            .disabled(selection.isEmpty || !model.isConnected)
            .font(.caption)

            Button("shortcuts.globe.open_settings") {
              if let url = URL(
                string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
              {
                NSWorkspace.shared.open(url)
              }
            }
            .buttonStyle(.link)
            .font(.caption)
          }
          if selection.isEmpty {
            Text("shortcuts.globe.pick_first")
              .font(.caption2)
              .foregroundStyle(.tertiary)
          }
        }
        Spacer()
        Button {
          hideGlobeNote = true
        } label: {
          Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
      }
      .padding(12)
      .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
      .padding([.horizontal, .top], 12)
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      globeNote
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
      .disabled(model.shortcutBusy)

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
    HStack(spacing: 10) {
      if model.shortcutBusy {
        ProgressView().controlSize(.small)
        Text("shortcuts.writing").font(.callout).foregroundStyle(.secondary)
      } else if let status = model.shortcutStatus {
        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        Text(status).font(.callout).foregroundStyle(.secondary)
      } else {
        Image(systemName: "info.circle").foregroundStyle(.secondary)
        Text("shortcuts.storage").font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      if !selection.isEmpty && !model.shortcutBusy {
        Button("shortcuts.clear_key") {
          model.clearShortcut(keyIDs: selection, in: layout)
        }
        .buttonStyle(.link)
      }
    }
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
