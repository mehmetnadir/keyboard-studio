import KeyboardKit
import SwiftUI

/// The rotary encoder's own page: what each of its three actions does.
struct KnobView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        header
        if model.profile?.capabilities.knob == false {
          Text("knob.absent")
            .foregroundStyle(.secondary)
        } else if let slots = model.knobSlots {
          ForEach(Knob.Action.allCases) { action in
            KnobActionRow(action: action, slotIndex: slots.slot(for: action), fn: false)
          }

          Text("knob.fn_section")
            .font(.headline)
            .padding(.top, 6)
          Text("knob.fn_detail")
            .font(.caption)
            .foregroundStyle(.secondary)
          ForEach(Knob.Action.allCases) { action in
            KnobActionRow(action: action, slotIndex: slots.slot(for: action), fn: true)
          }

          footnote
        } else if model.isConnected {
          ProgressView().controlSize(.small)
          Text("knob.searching").font(.callout).foregroundStyle(.secondary)
        }
        if let error = model.knobError {
          Text(error).font(.caption).foregroundStyle(.red)
        }
      }
      .padding(20)
    }
    .overlay {
      if !model.isConnected { DisconnectedOverlay() }
    }
    .task { model.loadKnob() }
  }

  private var header: some View {
    HStack(spacing: 14) {
      // A knob, drawn rather than iconified: it is the thing this page is about.
      ZStack {
        Circle().strokeBorder(.secondary.opacity(0.5), lineWidth: 2)
        Circle().fill(.tint.opacity(0.15))
        Capsule()
          .fill(.tint)
          .frame(width: 3, height: 14)
          .offset(y: -9)
      }
      .frame(width: 46, height: 46)

      VStack(alignment: .leading, spacing: 3) {
        Text("knob.title").font(.title3.weight(.semibold))
        Text("knob.subtitle").font(.callout).foregroundStyle(.secondary)
      }
      Spacer()
    }
  }

  private var footnote: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("knob.storage")
        .font(.caption)
        .foregroundStyle(.tertiary)
      if let slots = model.knobSlots {
        Text("knob.slots_detail \(slots.turnLeft) \(slots.turnRight) \(slots.press)")
          .font(.caption2.monospaced())
          .foregroundStyle(.tertiary)
      }
    }
  }
}

private struct KnobActionRow: View {
  @Environment(AppModel.self) private var model
  let action: Knob.Action
  let slotIndex: Int
  let fn: Bool

  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: symbol)
        .font(.title2)
        .foregroundStyle(.tint)
        .frame(width: 34)

      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.headline)
        Text(describe((fn ? model.knobFnBindings[action] : model.knobBindings[action]) ?? .unassigned))
          .font(.callout)
          .foregroundStyle(.secondary)
      }

      Spacer()

      Picker("", selection: binding) {
        Text("knob.unassigned").tag(-1)
        ForEach(Knob.mediaOptions, id: \.code) { option in
          Text(option.name).tag(option.code)
        }
      }
      .labelsHidden()
      .frame(width: 190)
      .disabled(!model.isConnected || model.knobBusy)

      if model.knobBusy {
        ProgressView().controlSize(.small)
      }
    }
    .padding(14)
    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 11))
  }

  private var binding: Binding<Int> {
    Binding(
      get: {
        let current = (fn ? model.knobFnBindings[action] : model.knobBindings[action]) ?? .unassigned
        if case .media(let code) = current { return code }
        return -1
      },
      set: { model.setKnob(action: action, mediaCode: $0 == -1 ? nil : $0, fn: fn) })
  }

  private var title: LocalizedStringKey {
    switch (action, fn) {
    case (.turnLeft, false): "knob.turn_left"
    case (.turnRight, false): "knob.turn_right"
    case (.press, false): "knob.press"
    case (.turnLeft, true): "knob.fn_turn_left"
    case (.turnRight, true): "knob.fn_turn_right"
    case (.press, true): "knob.fn_press"
    }
  }

  private var symbol: String {
    switch action {
    case .turnLeft: "arrow.counterclockwise"
    case .turnRight: "arrow.clockwise"
    case .press: "hand.point.up.left.fill"
    }
  }

  private func describe(_ binding: Knob.Binding) -> String {
    switch binding {
    case .media(let code):
      Knob.mediaName(code) ?? String(format: "media 0x%02x", code)
    case .key(let usage):
      KeyNamesBridge.name(for: usage)
    case .firmware(let action):
      action.label
    case .raw(let bytes):
      bytes.map { String(format: "%02x", $0) }.joined()
    case .unassigned:
      "knob.unassigned".localized
    }
  }
}

/// Keeps the view free of a StatsCore import just for key labels.
enum KeyNamesBridge {
  static func name(for usage: Int) -> String {
    StatsKeyNames.name(for: usage)
  }
}
