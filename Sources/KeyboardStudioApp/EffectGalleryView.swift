import K86Kit
import SwiftUI

/// Effect library: each tile is a miniature keyboard that animates on hover.
struct EffectGalleryView: View {
  @Environment(AppModel.self) private var model
  @State private var hovered: LightEffect?

  private let columns = [GridItem(.adaptive(minimum: 190), spacing: 14)]

  var body: some View {
    LazyVGrid(columns: columns, spacing: 14) {
      ForEach(LightEffect.allCases.filter { $0 != .off }, id: \.self) { effect in
        EffectTile(
          effect: effect,
          isSelected: model.effect == effect,
          isAnimating: hovered == effect,
          base: Color(red: model.mainColor.r, green: model.mainColor.g, blue: model.mainColor.b),
          rainbow: model.rainbow
        )
        .onHover { hovering in
          hovered = hovering ? effect : (hovered == effect ? nil : hovered)
        }
        .onTapGesture {
          model.effect = effect
          model.applyMainLight()
        }
      }
    }
  }
}

private struct EffectTile: View {
  let effect: LightEffect
  let isSelected: Bool
  let isAnimating: Bool
  let base: Color
  let rainbow: Bool

  private let layout = KeyboardLayout.k86

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      preview
      HStack(spacing: 5) {
        Text(effect.rawValue.capitalized)
          .font(.callout)
        Spacer()
        if isSelected {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.tint)
            .font(.caption)
        }
      }
    }
    .padding(9)
    .background(
      RoundedRectangle(cornerRadius: 11)
        .fill(.quaternary.opacity(isSelected ? 0.75 : 0.35))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 11)
        .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 1.5)
    )
    .contentShape(Rectangle())
  }

  private var preview: some View {
    // A frozen frame when idle keeps 19 tiles from animating at once; hovering
    // starts the clock for just the one under the pointer.
    Group {
      if isAnimating {
        TimelineView(.animation) { timeline in
          canvas(at: timeline.date.timeIntervalSinceReferenceDate)
        }
      } else {
        canvas(at: 0.35)
      }
    }
    .frame(height: 66)
    .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 7))
  }

  private func canvas(at time: Double) -> some View {
    Canvas { context, size in
      let unit = size.width / layout.columns
      for key in layout.keys {
        let position = layout.normalised(key)
        let color = EffectSimulator.color(
          effect: effect, at: position, time: time, base: base, rainbow: rainbow)
        let rect = CGRect(
          x: key.x * unit + 0.5, y: key.y * unit + 0.5,
          width: key.width * unit - 1, height: key.height * unit - 1)
        context.fill(
          Path(roundedRect: rect, cornerRadius: max(1, unit * 0.16)), with: .color(color))
      }
    }
    .padding(3)
  }
}
