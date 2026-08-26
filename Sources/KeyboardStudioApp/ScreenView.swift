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
  @State private var gallery: [GalleryItem] = []

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
        Picker("screen.mode", selection: $model.screenMode) {
          Text("screen.mode.off").tag(AppModel.ScreenMode.off)
          Text("screen.mode.stats").tag(AppModel.ScreenMode.stats)
          Text("screen.mode.now_playing").tag(AppModel.ScreenMode.nowPlaying)
        }
        .pickerStyle(.segmented)
        Text(
          model.screenMode == .nowPlaying
            ? "screen.now_playing.detail" : "screen.show_stats.detail")
          .font(.caption)
          .foregroundStyle(.tertiary)
        if model.screenMode == .nowPlaying {
          Divider().padding(.vertical, 2)
          Toggle("screen.light_follows_music", isOn: $model.lightFollowsMusic)
          if model.lightFollowsMusic {
            musicLightOptions
          }
          Text("screen.light_follows_music.detail")
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        if let screenStatus = model.screenStatus {
          Text(screenStatus)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      // The size has to come from the profile, not a literal — this panel is
      // not 128×128, and a hardcoded number here quietly contradicts the
      // Settings tab where the user just corrected it.
      Divider()
      gallerySection

      Text("\(model.screenWidthText)×\(model.screenHeightText) · " + "screen.panel_info".localized)
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

  /// Where the colour comes from, and which effect carries it. Shown together
  /// because the source is not a setting — it depends on the player — while the
  /// effect is entirely the user's choice.
  @ViewBuilder private var musicLightOptions: some View {
    @Bindable var model = model

    HStack(spacing: 8) {
      Text("screen.music_effect")
        .foregroundStyle(.secondary)
      Picker("", selection: $model.musicEffect) {
        ForEach(musicEffects, id: \.self) { effect in
          Text(effect.rawValue.capitalized).tag(effect)
        }
      }
      .labelsHidden()
      .frame(width: 150)
      Spacer()
      if let playing = model.nowPlaying {
        Label(
          model.musicColorFromArtwork
            ? "screen.color_from_artwork" : "screen.color_from_title",
          systemImage: model.musicColorFromArtwork ? "photo.fill" : "textformat")
          .font(.caption)
          .foregroundStyle(.secondary)
          .help(Text(playing.source.rawValue))
      }
    }

    if let playing = model.nowPlaying, !model.artworkAvailable {
      Text("screen.artwork_unavailable \(playing.source.rawValue)")
        .font(.caption)
        .foregroundStyle(.tertiary)
    }
  }

  /// Effects that read well as a single track colour. Rainbow-driven ones are
  /// left out: they would override the colour the track chose.
  private var musicEffects: [KeyboardKit.LightEffect] {
    [.solid, .breath, .press, .ripple, .raindrop, .sine]
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

  private var gallerySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("screen.gallery").font(.headline)
        Spacer()
        if !gallery.isEmpty {
          Button("screen.gallery.reveal") {
            NSWorkspace.shared.selectFile(
              gallery.first?.url.path, inFileViewerRootedAtPath: (try? ScreenGallery.directory())?.path ?? "")
          }
          .buttonStyle(.link)
          .font(.caption)
        }
      }

      if gallery.isEmpty {
        Text("screen.gallery.empty")
          .font(.caption)
          .foregroundStyle(.tertiary)
      } else {
        ScrollView(.vertical) {
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 10)], spacing: 10) {
            ForEach(gallery) { item in
              galleryTile(item)
            }
          }
          .padding(.vertical, 2)
        }
        .frame(maxHeight: 240)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .task { gallery = ScreenGallery.items() }
  }

  private func galleryTile(_ item: GalleryItem) -> some View {
    let width = Int(model.screenWidthText) ?? 235
    let height = Int(model.screenHeightText) ?? 128
    // Tiles are drawn at the panel's shape, so the grid previews what the
    // keyboard will show rather than what the file looks like.
    let tileWidth: CGFloat = 104
    let tileHeight = tileWidth * CGFloat(height) / CGFloat(max(width, 1))

    return VStack(spacing: 4) {
      ZStack {
        if let image = ScreenGallery.thumbnail(for: item, width: width, height: height) {
          Image(nsImage: image)
            .resizable()
            .interpolation(.medium)
            .aspectRatio(contentMode: .fill)
        } else {
          Color.black
        }
        if item.isAnimated {
          Text("GIF")
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 3))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(3)
        }
      }
      .frame(width: tileWidth, height: tileHeight)
      .clipShape(RoundedRectangle(cornerRadius: 5))
      .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.08)))

      Text(item.title)
        .font(.caption2)
        .lineLimit(1)
        .truncationMode(.middle)
        .foregroundStyle(.secondary)
        .frame(width: tileWidth)
    }
    .onTapGesture { Task { await upload(item.url, remember: false) } }
    .contextMenu {
      Button("screen.gallery.send") { Task { await upload(item.url, remember: false) } }
      Button("screen.gallery.finder") {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
      }
      Divider()
      Button("screen.gallery.remove", role: .destructive) {
        try? ScreenGallery.remove(item)
        gallery = ScreenGallery.items()
      }
    }
    .help(item.title)
  }

  private func chooseFile() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.png, .jpeg, .gif, .image]
    panel.allowsMultipleSelection = false
    if panel.runModal() == .OK, let url = panel.url {
      Task { await upload(url) }
    }
  }

  /// `remember` is false when sending something already in the gallery — the
  /// point of the copy is to keep what came from outside, not to duplicate what
  /// is already kept.
  private func upload(_ url: URL, remember: Bool = true) async {
    preview = NSImage(contentsOf: url)
    status = "screen.uploading".localized
    await model.uploadScreen(url: url, mode: mode)
    status = model.deviceError ?? "screen.uploaded".localized

    if remember, model.deviceError == nil {
      // Failure to keep a copy must not read as a failed upload: the picture is
      // already on the keyboard by this point.
      if (try? ScreenGallery.add(url)) != nil {
        gallery = ScreenGallery.items()
      }
    }
  }
}
