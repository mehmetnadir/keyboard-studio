import K86Kit
import SwiftUI
import UniformTypeIdentifiers

/// SwiftUI ships its own `ContentMode`, so the screen one is spelled out.
private typealias ScreenFit = K86Kit.ContentMode

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
        Button("Choose image or GIF…") { chooseFile() }
        Picker("", selection: $mode) {
          Text("Crop").tag(ScreenFit.fill)
          Text("Fit").tag(ScreenFit.fit)
          Text("Stretch").tag(ScreenFit.stretch)
        }
        .pickerStyle(.segmented)
        .frame(width: 190)
        .labelsHidden()
      }
      .disabled(!model.isConnected)

      if let status {
        Text(status)
          .font(.callout)
          .foregroundStyle(.secondary)
      }

      Divider()

      VStack(alignment: .leading, spacing: 6) {
        Toggle("Show today's statistics on the keyboard", isOn: $model.screenShowsStats)
        Text("Refreshes every 5 minutes while the app is running.")
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
            Text("Drop an image or GIF here")
              .foregroundStyle(.secondary)
          }
        }
      }
      .frame(width: 220, height: 220)
      .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
          guard let url else { return }
          Task { @MainActor in upload(url) }
        }
        return true
      }
  }

  private func chooseFile() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.png, .jpeg, .gif, .image]
    panel.allowsMultipleSelection = false
    if panel.runModal() == .OK, let url = panel.url {
      upload(url)
    }
  }

  private func upload(_ url: URL) {
    preview = NSImage(contentsOf: url)
    status = "Uploading…"
    model.uploadScreen(url: url, mode: mode)
    status = model.deviceError ?? "Uploaded to the keyboard."
  }
}
