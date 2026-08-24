import Foundation
import K86Kit
import SwiftUI

/// Approximates what each firmware effect looks like, so the gallery can show
/// motion before anything is written to the keyboard.
///
/// These are visual stand-ins, not the firmware's own maths: the device runs
/// its animations internally and reports nothing back, so an exact replica is
/// not obtainable. The goal is that picking "ripple" over "meteor" from the
/// preview leads to the effect you expected.
enum EffectSimulator {
  /// Colour for one key at time `t` (seconds).
  static func color(
    effect: LightEffect, at position: (x: Double, y: Double), time t: Double,
    base: Color, rainbow: Bool, speed: Double = 1
  ) -> Color {
    let time = t * speed
    let (x, y) = position

    switch effect {
    case .off:
      return .black

    case .solid:
      return base

    case .breath:
      let phase = (sin(time * 2) + 1) / 2
      return base.opacity(0.15 + 0.85 * phase)

    case .neon, .dazzle:
      // Whole board cycles through hues together.
      return hue(time * 0.15, rainbow: true, base: base)

    case .wave:
      return hue(x * 0.7 - time * 0.25, rainbow: rainbow, base: base)

    case .linewave:
      let phase = (sin((x * 6) - time * 3) + 1) / 2
      return tint(base, rainbow: rainbow, hueShift: x, intensity: 0.2 + 0.8 * phase)

    case .sine:
      let band = abs(y - (0.5 + 0.35 * sin(x * 6 - time * 3)))
      return tint(base, rainbow: rainbow, hueShift: x, intensity: max(0, 1 - band * 6))

    case .ripple, .circlewave:
      let distance = hypot(x - 0.5, y - 0.5)
      let phase = (sin(distance * 14 - time * 4) + 1) / 2
      return tint(base, rainbow: rainbow, hueShift: distance, intensity: pow(phase, 2))

    case .converge:
      let distance = abs(x - 0.5)
      let front = (time * 0.4).truncatingRemainder(dividingBy: 1)
      let intensity = max(0, 1 - abs(distance - (0.5 - front)) * 8)
      return tint(base, rainbow: rainbow, hueShift: y, intensity: intensity)

    case .laser:
      let head = (time * 0.5).truncatingRemainder(dividingBy: 1.4) - 0.2
      return tint(base, rainbow: rainbow, hueShift: y, intensity: max(0, 1 - abs(x - head) * 9))

    case .meteor, .train:
      let head = (time * 0.45).truncatingRemainder(dividingBy: 1.6) - 0.3
      let tail = max(0, 1 - (head - x) * 3.5)
      let intensity = x <= head ? tail : 0
      return tint(base, rainbow: rainbow, hueShift: y, intensity: intensity)

    case .snake:
      // One lit key travelling row by row.
      let cells = 16.0
      let index = (time * 6).truncatingRemainder(dividingBy: cells * 6)
      let row = floor(index / cells)
      let column = index.truncatingRemainder(dividingBy: cells)
      let distance = hypot(x * cells - column, y * 6 - row)
      return tint(base, rainbow: rainbow, hueShift: index / 40, intensity: max(0, 1 - distance))

    case .kaleidoscope:
      let angle = atan2(y - 0.5, x - 0.5)
      return hue(angle / (2 * .pi) + time * 0.2, rainbow: rainbow, base: base)

    case .raindrop, .raindown:
      let column = floor(x * 16)
      let seed = pseudoRandom(column)
      let drop = (time * 0.6 + seed).truncatingRemainder(dividingBy: 1)
      let intensity = max(0, 1 - abs(y - drop) * 7)
      return tint(base, rainbow: rainbow, hueShift: seed, intensity: intensity)

    case .press:
      // Keys light on press: show a few keys fading at staggered times.
      let seed = pseudoRandom(floor(x * 16) + floor(y * 6) * 16)
      let phase = (time * 0.8 + seed * 4).truncatingRemainder(dividingBy: 3)
      return tint(base, rainbow: rainbow, hueShift: seed, intensity: max(0, 1 - phase * 2.5))

    case .fireworks:
      let burst = floor(time * 0.7)
      let seed = pseudoRandom(burst)
      let centre = (x: 0.2 + seed * 0.6, y: 0.25 + pseudoRandom(burst + 7) * 0.5)
      let age = (time * 0.7).truncatingRemainder(dividingBy: 1)
      let radius = age * 0.7
      let distance = hypot(x - centre.x, y - centre.y)
      let intensity = max(0, 1 - abs(distance - radius) * 10) * (1 - age)
      return tint(base, rainbow: rainbow, hueShift: seed, intensity: intensity)
    }
  }

  // MARK: - Helpers

  private static func tint(
    _ base: Color, rainbow: Bool, hueShift: Double, intensity: Double
  ) -> Color {
    let value = max(0, min(1, intensity))
    if rainbow {
      return hue(hueShift, rainbow: true, base: base).opacity(value)
    }
    return base.opacity(0.08 + 0.92 * value)
  }

  private static func hue(_ value: Double, rainbow: Bool, base: Color) -> Color {
    guard rainbow else { return base }
    let wrapped = value - floor(value)
    return Color(hue: wrapped, saturation: 0.85, brightness: 1)
  }

  /// Deterministic per-index jitter — no Random, so previews are reproducible.
  private static func pseudoRandom(_ index: Double) -> Double {
    let value = sin(index * 12.9898) * 43758.5453
    return value - floor(value)
  }
}
