import K86Kit
import SwiftUI

struct LightsView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var model = model

    Form {
      Section("Main light") {
        ColorPicker("Colour", selection: colorBinding(for: \.mainColor), supportsOpacity: false)
        Picker("Effect", selection: $model.effect) {
          ForEach(LightEffect.allCases, id: \.self) { effect in
            Text(effect.rawValue.capitalized).tag(effect)
          }
        }
        if model.effect != .solid {
          Toggle("Rainbow colours", isOn: $model.rainbow)
        }
        Button("Apply") { model.applyMainLight() }
          .disabled(!model.isConnected)
      }

      Section("Side strips") {
        ColorPicker("Colour", selection: colorBinding(for: \.sideColor), supportsOpacity: false)
        Button("Apply") { model.applySideLight() }
          .disabled(!model.isConnected)
      }

      Section("Levels") {
        Slider(value: brightnessBinding, in: 0...4, step: 1) {
          Text("Brightness")
        } minimumValueLabel: {
          Image(systemName: "sun.min")
        } maximumValueLabel: {
          Image(systemName: "sun.max")
        }
        Slider(value: speedBinding, in: 0...5, step: 1) {
          Text("Effect speed")
        } minimumValueLabel: {
          Image(systemName: "tortoise")
        } maximumValueLabel: {
          Image(systemName: "hare")
        }
        HStack {
          Button("Lights off") { model.setLEDs(on: false) }
          Button("Lights on") { model.setLEDs(on: true) }
        }
        .disabled(!model.isConnected)
      }
    }
    .formStyle(.grouped)
    .disabled(!model.isConnected)
    .overlay {
      if !model.isConnected {
        DisconnectedOverlay()
      }
    }
  }

  // MARK: - Bindings

  private func colorBinding(for keyPath: ReferenceWritableKeyPath<AppModel, Color3>) -> Binding<Color> {
    Binding(
      get: {
        let value = model[keyPath: keyPath]
        return Color(red: value.r, green: value.g, blue: value.b)
      },
      set: { newValue in
        let resolved = NSColor(newValue).usingColorSpace(.sRGB) ?? .white
        var color = model[keyPath: keyPath]
        color.r = Double(resolved.redComponent)
        color.g = Double(resolved.greenComponent)
        color.b = Double(resolved.blueComponent)
        model[keyPath: keyPath] = color
      })
  }

  private var brightnessBinding: Binding<Double> {
    Binding(get: { Double(model.brightness) }, set: { model.brightness = Int($0) })
  }

  private var speedBinding: Binding<Double> {
    Binding(get: { Double(model.speed) }, set: { model.speed = Int($0) })
  }
}

struct DisconnectedOverlay: View {
  var body: some View {
    VStack(spacing: 8) {
      Image(systemName: "cable.connector.slash")
        .font(.largeTitle)
        .foregroundStyle(.secondary)
      Text("Connect the USB cable")
        .font(.headline)
      Text("Lighting and screen settings are written over USB. Set the switches on the back to Mac + USB.")
        .font(.callout)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 320)
    }
    .padding(28)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
  }
}
