import KeyboardKit
import SwiftUI

/// The rotary encoder's own page: what each of its three actions does.
struct KnobView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        header
        modeNote
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

  /// The single most useful thing to know about this knob, and it is in the
  /// manual rather than the protocol: turning it may walk the keyboard's own
  /// settings menu instead of doing what the slots below say. That is a
  /// firmware mode, and no command changes it — only Fn + press does. Someone
  /// looking at this page while their knob "does nothing" needs to read this
  /// before anything else on it makes sense.
  private var modeNote: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "info.circle.fill")
        .foregroundStyle(.tint)
      VStack(alignment: .leading, spacing: 3) {
        Text("knob.mode_note.title").font(.callout.weight(.medium))
        Text("knob.mode_note.detail")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer()
    }
    .padding(12)
    .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
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
        Section("knob.section.media") {
          ForEach(Knob.mediaOptions, id: \.code) { option in
            Text(option.name).tag(option.code)
          }
        }
        // Firmware actions are things the keyboard does to itself rather than
        // keystrokes it sends — including the only control anywhere over what
        // the encoder itself does.
        Section("knob.section.firmware") {
          ForEach(Knob.FirmwareAction.allCases, id: \.rawValue) { action in
            Text(action.label).tag(Self.firmwareTag + Int(action.rawValue))
          }
        }
      }
      .labelsHidden()
      .frame(width: 210)
      .disabled(!model.isConnected || model.knobBusy)

      if model.knobBusy {
        ProgressView().controlSize(.small)
      }
    }
    .padding(14)
    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 11))
  }

  /// Media codes are HID usage ids (0…255), so firmware actions are offset out
  /// of their range rather than sharing it.
  static let firmwareTag = 1000

  private var binding: Binding<Int> {
    Binding(
      get: {
        let current = (fn ? model.knobFnBindings[action] : model.knobBindings[action]) ?? .unassigned
        switch current {
        case .media(let code): return code
        case .firmware(let action): return Self.firmwareTag + Int(action.rawValue)
        default: return -1
        }
      },
      set: { tag in
        let binding: Knob.Binding
        if tag == -1 {
          binding = .unassigned
        } else if tag >= Self.firmwareTag,
          let action = Knob.FirmwareAction(rawValue: UInt8(tag - Self.firmwareTag))
        {
          binding = .firmware(action: action)
        } else {
          binding = .media(code: tag)
        }
        model.setKnob(action: action, binding: binding, fn: fn)
      })
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
