import KeyboardKit
import SwiftUI
import UniformTypeIdentifiers

/// SwiftUI ships its own `ContentMode`, so the screen one is spelled out.
private typealias ScreenFit = KeyboardKit.ContentMode

struct ScreenView: View {
  @Environment(AppModel.self) private var model
  @State private var preview: NSImage?
  @State private var status: String?
  @State private var isTargeted = false
  @State private var mode: ScreenFit = .fill

  var body: some View {
    @Bindable var model = model

    VStack(spacing: 16) {
      dropTarget
      HStack {
        Button("screen.choose_file") { chooseFile() }
        Picker("", selection: $mode) {
          Text("screen.mode.crop").tag(ScreenFit.fill)
          Text("screen.mode.fit").tag(ScreenFit.fit)
          Text("screen.mode.stretch").tag(ScreenFit.stretch)
        }
        .pickerStyle(.segmented)
        .frame(width: 190)
        .labelsHidden()
      }
      .disabled(!model.isConnected)

      if model.isUploading {
        HStack(spacing: 8) {
          ProgressView().controlSize(.small)
          Text("screen.uploading")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
      } else if let status {
        Text(status)
          .font(.callout)
          .foregroundStyle(.secondary)
      }

      Divider()

      VStack(alignment: .leading, spacing: 6) {
        Toggle("screen.show_stats", isOn: $model.screenShowsStats)
        Text("screen.show_stats.detail")
          .font(.caption)
          .foregroundStyle(.tertiary)
        if let screenStatus = model.screenStatus {
          Text(screenStatus)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Text("The panel is 128×128 and shows 65 536 colours. GIFs upload up to 30 frames.")
        .font(.caption)
        .foregroundStyle(.tertiary)
      Spacer()
    }
    .padding(20)
    .overlay {
      if !model.isConnected {
        DisconnectedOverlay()
      }
    }
  }

  private var dropTarget: some View {
    RoundedRectangle(cornerRadius: 14)
      .strokeBorder(
        isTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary),
        style: StrokeStyle(lineWidth: 2, dash: preview == nil ? [7, 5] : []))
      .background(
        Group {
          if let preview {
            Image(nsImage: preview)
              .resizable()
              .interpolation(.high)
              .scaledToFill()
          } else {
            Color.clear
          }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
      )
      .overlay {
        if preview == nil {
          VStack(spacing: 6) {
            Image(systemName: "photo.badge.arrow.down")
              .font(.largeTitle)
              .foregroundStyle(.secondary)
            Text("screen.drop_here")
              .foregroundStyle(.secondary)
          }
        }
      }
      .frame(width: 220, height: 220)
      .dropDestination(for: URL.self) { urls, _ in
        guard let url = urls.first else {
          status = "screen.unreadable".localized
          return false
        }
        Task { await upload(url) }
        return true
      } isTargeted: { isTargeted = $0 }
  }

  private func chooseFile() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.png, .jpeg, .gif, .image]
    panel.allowsMultipleSelection = false
    if panel.runModal() == .OK, let url = panel.url {
      Task { await upload(url) }
    }
  }

  private func upload(_ url: URL) async {
    preview = NSImage(contentsOf: url)
    status = "Uploading…"
    await model.uploadScreen(url: url, mode: mode)
    status = model.deviceError ?? "screen.uploaded".localized
  }
}
