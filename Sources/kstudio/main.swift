import Foundation
import KeyboardKit
import StatsCore
import StatsScreen

let namedColors: [String: RGB] = [
  "red": RGB(255, 0, 0), "green": RGB(0, 255, 0), "blue": RGB(0, 0, 255),
  "white": RGB(255, 255, 255), "purple": RGB(155, 89, 182), "orange": RGB(255, 120, 0),
  "cyan": RGB(0, 220, 220), "magenta": RGB(255, 0, 255), "pink": RGB(255, 105, 180),
  "yellow": RGB(255, 220, 0), "teal": RGB(0, 128, 128), "lime": RGB(160, 255, 0),
]

func errPrint(_ text: String) {
  FileHandle.standardError.write(Data((text + "\n").utf8))
}

func fail(_ message: String) -> Never {
  errPrint("error: \(message)")
  exit(64)
}

func parseColor(_ text: String) -> RGB? {
  namedColors[text.lowercased()] ?? RGB(hex: text)
}

func option(_ name: String, _ args: [String]) -> String? {
  guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
  return args[i + 1]
}

func intOption(_ name: String, _ args: [String], default value: Int, range: ClosedRange<Int>) -> Int {
  guard let raw = option(name, args) else { return value }
  guard let parsed = Int(raw), range.contains(parsed) else {
    fail("invalid value for \(name): \(raw) (expected \(range.lowerBound)-\(range.upperBound))")
  }
  return parsed
}

func usage() -> Never {
  errPrint(
    """
    kstudio — Keyboard Studio CLI (Attack Shark K86 and other ROYUAN boards)

    USAGE:
      kstudio info                          firmware + connection status
      kstudio leds on|off                   LED master switch
      kstudio color <hex|name> [opts]       main light solid color
      kstudio effect <name> [opts]          main light effect (rainbow by default)
      kstudio side <hex|name> [opts]        side strip color
      kstudio screen <image|gif>            upload to the 128x128 TFT screen
      kstudio screen --test                 upload RGBW test pattern
      kstudio screen --stats                show today's typing stats on the keyboard
      kstudio effects                       list effect names
      kstudio probe                         ask the device about itself (read-only)
      kstudio measure                       find the panel's real resolution
      kstudio keymap                        read the keymap layout (read-only)
      kstudio stats                         typing statistics summary
      kstudio watch [seconds]               count presses live (needs Input Monitoring)
      kstudio card <out.png> [--demo]       preview the keyboard screen card as PNG

    OPTIONS:
      --bright 0-4   brightness (default 4)
      --speed 0-5    effect speed (default 3)
      --color <hex>  fixed color for `effect` (disables rainbow)

    SCREEN OPTIONS (the panel is 128x128; sources are centre-cropped by default):
      --fit          fit the whole image, padding the short edge
      --stretch      stretch to the square, distorting non-square sources

    The keyboard must be connected by USB cable (back switches: Mac + USB).
    Settings persist on the keyboard after you switch back to Bluetooth.
    """)
  exit(64)
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { usage() }

do {
  switch command {
  case "effects":
    print(LightEffect.allCases.map(\.rawValue).joined(separator: " "))

  case "stats", "watch":
    try StatsCommands.run(args)

  case "card":
    try CardCommand.run(args)

  case "probe":
    try ProbeCommand.run()

  case "measure":
    try MeasureCommand.run(args)

  case "keymap":
    try KeymapCommand.run(args)

  case "info":
    let kb = try Keyboard()
    defer { kb.close() }
    if let version = try kb.firmwareVersion() {
      print("\(kb.profile.displayName) — firmware \(String(format: "0x%04x", version))")
    } else {
      print("Connected — firmware query returned no data")
    }

  case "leds":
    guard args.count > 1, ["on", "off"].contains(args[1]) else { usage() }
    let kb = try Keyboard()
    defer { kb.close() }
    try kb.setLEDs(on: args[1] == "on")
    print("LEDs \(args[1])")

  case "color", "side":
    guard args.count > 1 else { usage() }
    guard let color = parseColor(args[1]) else {
      fail("unknown color: \(args[1]) (use #RRGGBB or one of: \(namedColors.keys.sorted().joined(separator: " ")))")
    }
    if option("--color", args) != nil {
      fail("--color only applies to `effect`; pass the color directly to \(command)")
    }
    let kb = try Keyboard()
    defer { kb.close() }
    try kb.setLEDs(on: true)
    let brightness = intOption("--bright", args, default: 4, range: 0...4)
    let speed = intOption("--speed", args, default: 3, range: 0...5)
    if command == "color" {
      try kb.setMainColor(color, brightness: brightness, speed: speed)
    } else {
      try kb.setSideColor(color, brightness: brightness, speed: speed)
    }
    print("\(command == "color" ? "Main" : "Side") light set to \(args[1])")

  case "effect":
    guard args.count > 1 else { usage() }
    guard let effect = LightEffect(rawValue: args[1].lowercased()) else {
      fail("unknown effect: \(args[1]) — run `kstudio effects` for the list")
    }
    var fixed: RGB?
    if let raw = option("--color", args) {
      guard let parsed = parseColor(raw) else { fail("unknown color: \(raw)") }
      fixed = parsed
    }
    let kb = try Keyboard()
    defer { kb.close() }
    try kb.setLEDs(on: true)
    try kb.setMainEffect(
      effect, brightness: intOption("--bright", args, default: 4, range: 0...4),
      speed: intOption("--speed", args, default: 3, range: 0...5),
      rainbow: fixed == nil, color: fixed ?? RGB(255, 0, 0))
    print("Effect: \(effect.rawValue)\(fixed == nil ? " (rainbow)" : "")")

  case "screen":
    guard args.count > 1 else { usage() }
    let kb = try Keyboard()
    defer { kb.close() }
    if args[1] == "--test" {
      try Screen.writeImage(Screen.testPattern(), on: kb)
      print("Test pattern uploaded.")
    } else if args[1] == "--ruler" || args[1] == "--bands" {
      // Optional WxH so the real panel size can be discovered by trying sizes.
      let panel = Screen.geometry(for: kb)
      var frameWidth = panel.width
      var frameHeight = panel.height
      if let size = option("--size", args) {
        let parts = size.lowercased().split(separator: "x").compactMap { Int($0) }
        guard parts.count == 2, parts.allSatisfy({ (8...512).contains($0) }) else {
          fail("--size expects WxH, e.g. 160x128")
        }
        (frameWidth, frameHeight) = (parts[0], parts[1])
      }
      let frame = args[1] == "--bands"
        ? Screen.bandPattern(width: frameWidth, height: frameHeight)
        : Screen.rulerPattern(width: frameWidth, height: frameHeight)
      try Screen.writeImage(frame, on: kb)
      if args[1] == "--bands" {
        print(
          """
          Colour bands uploaded at \(frameWidth)×\(frameHeight), 32 px per band.
          Count the bands along the top edge and down the left edge:
            width  = bands across × 32
            height = bands down × 32
          Skewed or wrapped bands mean the height guess is wrong.
          """)
      } else {
        print(
          """
          Calibration pattern uploaded at \(frameWidth)×\(frameHeight).
          Look at the keyboard:
            • white border touching all four edges  → the size is correct
            • image in one corner with dead space   → the panel is larger
            • edges cut off                          → the panel is smaller
          """)
      }
    } else if args[1] == "--stats" {
      let store = try StatsStore(path: StatsStore.defaultPath())
      defer { store.close() }
      try Screen.writeImage(try StatsCard.today(store: store), on: kb)
      print("Today's statistics uploaded to the keyboard screen.")
    } else {
      let mode: ContentMode =
        args.contains("--fit") ? .fit : (args.contains("--stretch") ? .stretch : .fill)
      let frames = try Screen.loadFrames(
        url: URL(fileURLWithPath: args[1]), for: kb, mode: mode)
      if frames.count == 1 {
        try Screen.writeImage(frames[0], on: kb)
        print("Image uploaded.")
      } else {
        try Screen.writeAnimation(frames, on: kb)
        print("Animation uploaded (\(frames.count) frames).")
      }
    }

  default:
    usage()
  }
} catch {
  errPrint("error: \(error)")
  exit(1)
}
