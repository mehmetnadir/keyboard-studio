import SwiftUI

@main
struct KeyboardStudioApp: App {
  @State private var model = AppModel()

  var body: some Scene {
    Window("Keyboard Studio", id: "main") {
      MainView()
        .environment(model)
        .frame(minWidth: 640, minHeight: 520)
        .onAppear { model.onAppear() }
    }
    .windowResizability(.contentMinSize)

    MenuBarExtra("Keyboard Studio", systemImage: "keyboard") {
      MenuBarView()
        .environment(model)
    }
    .menuBarExtraStyle(.window)
  }
}

struct MainView: View {
  @Environment(AppModel.self) private var model
  @State private var tab = Tab.stats

  enum Tab: String, CaseIterable {
    case stats = "Statistics"
    case lights = "Lights"
    case screen = "Screen"

    var icon: String {
      switch self {
      case .stats: "chart.bar.fill"
      case .lights: "lightbulb.fill"
      case .screen: "photo.fill"
      }
    }
  }

  var body: some View {
    TabView(selection: $tab) {
      ForEach(Tab.allCases, id: \.self) { item in
        Group {
          switch item {
          case .stats: StatsView()
          case .lights: LightsView()
          case .screen: ScreenView()
          }
        }
        .tabItem { Label(item.rawValue, systemImage: item.icon) }
        .tag(item)
      }
    }
    .padding(.top, 6)
    .toolbar {
      ToolbarItem(placement: .status) {
        ConnectionBadge()
      }
    }
  }
}

struct ConnectionBadge: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    HStack(spacing: 5) {
      Circle()
        .fill(model.isConnected ? .green : .secondary)
        .frame(width: 7, height: 7)
      Text(model.isConnected ? "K86 connected" : "Not connected")
        .font(.caption)
        .foregroundStyle(.secondary)
      if let firmware = model.firmware {
        Text(firmware)
          .font(.caption.monospaced())
          .foregroundStyle(.tertiary)
      }
    }
  }
}

struct MenuBarView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text(model.today?.presses ?? 0, format: .number)
          .font(.system(size: 26, weight: .semibold, design: .rounded))
        Text("presses today")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Divider()
      ConnectionBadge()
      if model.isConnected {
        HStack(spacing: 6) {
          ForEach(quickColors, id: \.name) { quick in
            Button {
              model.mainColor = quick.color
              model.effect = .solid
              model.applyMainLight()
            } label: {
              Circle()
                .fill(Color(red: quick.color.r, green: quick.color.g, blue: quick.color.b))
                .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help(quick.name)
          }
        }
      }
      Divider()
      Button("Open Keyboard Studio") {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
      }
      Button("Quit") {
        model.shutDown()  // flush pending counts before the process goes away
        NSApp.terminate(nil)
      }
    }
    .padding(14)
    .frame(width: 240)
    .onAppear { model.refreshStats() }
  }

  private var quickColors: [(name: String, color: Color3)] {
    [
      ("Purple", Color3(155, 89, 182)), ("Cyan", Color3(0, 220, 220)),
      ("Orange", Color3(255, 120, 0)), ("Green", Color3(0, 220, 120)),
      ("White", Color3(255, 255, 255)),
    ]
  }
}
