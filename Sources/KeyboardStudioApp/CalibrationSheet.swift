import KeyboardKit
import SwiftUI

/// Measures the panel's real resolution without asking anyone to count pixels.
///
/// The panel accepts any frame size without complaint, so "it looks full" is
/// not evidence and a size typed by hand is a guess. This walks the same
/// procedure the command line tools do, in the order that gets an answer with
/// the least effort:
///
///  1. Ask the device. Some boards report their resolution and the rest of the
///     wizard is unnecessary.
///  2. Otherwise show a ruler — a frame deliberately larger than the panel,
///     marked with coloured bars at known positions. The device clips what does
///     not fit, so the last colour still visible names the size. One look per
///     axis, no measuring.
///
/// Width and height need separate passes because this encoder is column-major:
/// a wrong height slides columns sideways without tilting a vertical line, so
/// vertical stripes can measure width but never height.
struct CalibrationSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  private enum Step {
    case asking
    case width
    case height
    case done
  }

  @State private var step: Step = .asking
  @State private var measuredWidth: Int?
  @State private var measuredHeight: Int?
  @State private var error: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      header

      switch step {
      case .asking:
        askingStep
      case .width:
        rulerStep(
          title: "calibrate.width.title",
          detail: "calibrate.width.detail",
          swatches: Screen.rulerMarks.map { ($0.name, $0.x, $0.color) },
          onPick: { value in
            measuredWidth = value
            Task { await beginHeight() }
          })
      case .height:
        rulerStep(
          title: "calibrate.height.title",
          detail: "calibrate.height.detail",
          swatches: Screen.heightMarks.map { ($0.name, $0.y, $0.color) },
          onPick: { value in
            measuredHeight = value
            step = .done
          })
      case .done:
        doneStep
      }

      if let error {
        Text(error)
          .font(.caption)
          .foregroundStyle(.red)
          .textSelection(.enabled)
      }

      Spacer(minLength: 0)
      footer
    }
    .padding(20)
    .frame(width: 460, height: 420)
    .task { await askDevice() }
  }

  // MARK: - Steps

  private var header: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("calibrate.title").font(.title3.weight(.semibold))
      Text("calibrate.subtitle")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var askingStep: some View {
    HStack(spacing: 10) {
      ProgressView().controlSize(.small)
      Text("calibrate.asking")
        .font(.callout)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func rulerStep(
    title: String, detail: String,
    swatches: [(name: String, value: Int, color: (UInt8, UInt8, UInt8))],
    onPick: @escaping (Int) -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title.localized).font(.headline)
      Text(detail.localized)
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      if model.isUploading {
        HStack(spacing: 8) {
          ProgressView().controlSize(.small)
          Text("calibrate.sending").font(.caption).foregroundStyle(.secondary)
        }
      }

      LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 8)], spacing: 8) {
        ForEach(swatches, id: \.name) { swatch in
          Button {
            onPick(swatch.value)
          } label: {
            HStack(spacing: 6) {
              RoundedRectangle(cornerRadius: 3)
                .fill(
                  Color(
                    red: Double(swatch.color.0) / 255, green: Double(swatch.color.1) / 255,
                    blue: Double(swatch.color.2) / 255)
                )
                .frame(width: 16, height: 16)
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.white.opacity(0.2)))
              Text("\(swatch.value)")
                .font(.callout.monospacedDigit())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 3)
          }
          .buttonStyle(.bordered)
        }
      }
      .disabled(model.isUploading)

      Text("calibrate.none_visible")
        .font(.caption)
        .foregroundStyle(.tertiary)
    }
  }

  private var doneStep: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("calibrate.done.title").font(.headline)
      if let width = measuredWidth, let height = measuredHeight {
        Text(verbatim: "\(width) × \(height)")
          .font(.system(size: 32, weight: .semibold, design: .rounded))
        Text("calibrate.done.detail")
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var footer: some View {
    HStack {
      if step == .width || step == .height {
        Button("calibrate.restart") {
          measuredWidth = nil
          measuredHeight = nil
          Task { await beginWidth() }
        }
        .buttonStyle(.link)
      }
      Spacer()
      Button("calibrate.cancel") { dismiss() }
        .keyboardShortcut(.cancelAction)
      if step == .done, let width = measuredWidth, let height = measuredHeight {
        Button("calibrate.save") {
          model.applyCalibration(width: width, height: height)
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
      }
    }
  }

  // MARK: - Flow

  private func askDevice() async {
    if let reported = await model.queryPanelSize() {
      measuredWidth = reported.width
      measuredHeight = reported.height
      step = .done
      return
    }
    await beginWidth()
  }

  private func beginWidth() async {
    step = .width
    error = await model.sendRuler(.width)
  }

  private func beginHeight() async {
    step = .height
    // The height ruler is drawn at the width just measured, so the bars span
    // the panel rather than stopping short of it.
    error = await model.sendRuler(.height, width: measuredWidth ?? 235)
  }
}
