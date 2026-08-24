import SwiftUI
import UniformTypeIdentifiers

struct ScreenView: View {
  @Environment(AppModel.self) private var model
  @State private var preview: NSImage?
  @State private var status: String?
  @State private var isTargeted = false

  var body: some View {
    VStack(spacing: 18) {
      dropTarget
      HStack {
        Button("Choose image or GIF…") { chooseFile() }
        if preview != nil {
          Button("Clear") {
            preview = nil
            status = nil
          }
        }
      }
      .disabled(!model.isConnected)

      if let status {
        Text(status)
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      Text("The screen is 128×128. Images are resized; GIFs upload up to 30 frames.")
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
    model.uploadScreen(url: url)
    status = model.deviceError ?? "Uploaded to the keyboard."
  }
}
