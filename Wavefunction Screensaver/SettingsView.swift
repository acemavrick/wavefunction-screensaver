//
//  SettingsView.swift
//  Wavefunction Screensaver
//
//  Created by acemavrick on 6/29/25.
//

import SwiftUI

struct SettingsView: View {
  var onDismiss: () -> Void
  var onSave: (Float, Float, Float, Float, Int, Int, Int, Int, Float, Float, Float, Float) -> Void

  // Default values passed from WaveView
  let defaultC: Float
  let defaultDx: Float
  let defaultDt: Float
  let defaultDamper: Float
  let defaultDisturbanceCooldownMin: Int
  let defaultDisturbanceCooldownMax: Int
  let defaultDisturbanceDensityMin: Int
  let defaultDisturbanceDensityMax: Int
  let defaultDisturbanceRadiusMin: Float
  let defaultDisturbanceRadiusMax: Float
  let defaultDisturbanceStrengthMin: Float
  let defaultDisturbanceStrengthMax: Float

  @State var c: Float
  @State var dx: Float
  @State var dt: Float
  @State var damper: Float
  @State var disturbanceCooldownMin: Int
  @State var disturbanceCooldownMax: Int
  @State var disturbanceDensityMin: Int
  @State var disturbanceDensityMax: Int
  @State var disturbanceRadiusMin: Float
  @State var disturbanceRadiusMax: Float
  @State var disturbanceStrengthMin: Float
  @State var disturbanceStrengthMax: Float

  var floatFormatter: Formatter {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 6
    return formatter
  }

  var intFormatter: Formatter {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 0
    return formatter
  }

  init(
    initialC: Float,
    initialDx: Float,
    initialDt: Float,
    initialDamper: Float,
    initialDisturbanceCooldownMin: Int,
    initialDisturbanceCooldownMax: Int,
    initialDisturbanceDensityMin: Int,
    initialDisturbanceDensityMax: Int,
    initialDisturbanceRadiusMin: Float,
    initialDisturbanceRadiusMax: Float,
    initialDisturbanceStrengthMin: Float,
    initialDisturbanceStrengthMax: Float,
    onSave: @escaping (Float, Float, Float, Float, Int, Int, Int, Int, Float, Float, Float, Float)
      -> Void,
    onDismiss: @escaping () -> Void
  ) {
    self.defaultC = initialC
    self.defaultDx = initialDx
    self.defaultDt = initialDt
    self.defaultDamper = initialDamper
    self.defaultDisturbanceCooldownMin = initialDisturbanceCooldownMin
    self.defaultDisturbanceCooldownMax = initialDisturbanceCooldownMax
    self.defaultDisturbanceDensityMin = initialDisturbanceDensityMin
    self.defaultDisturbanceDensityMax = initialDisturbanceDensityMax
    self.defaultDisturbanceRadiusMin = initialDisturbanceRadiusMin
    self.defaultDisturbanceRadiusMax = initialDisturbanceRadiusMax
    self.defaultDisturbanceStrengthMin = initialDisturbanceStrengthMin
    self.defaultDisturbanceStrengthMax = initialDisturbanceStrengthMax

    self._c = State(initialValue: initialC)
    self._dx = State(initialValue: initialDx)
    self._dt = State(initialValue: initialDt)
    self._damper = State(initialValue: initialDamper)
    self._disturbanceCooldownMin = State(initialValue: initialDisturbanceCooldownMin)
    self._disturbanceCooldownMax = State(initialValue: initialDisturbanceCooldownMax)
    self._disturbanceDensityMin = State(initialValue: initialDisturbanceDensityMin)
    self._disturbanceDensityMax = State(initialValue: initialDisturbanceDensityMax)
    self._disturbanceRadiusMin = State(initialValue: initialDisturbanceRadiusMin)
    self._disturbanceRadiusMax = State(initialValue: initialDisturbanceRadiusMax)
    self._disturbanceStrengthMin = State(initialValue: initialDisturbanceStrengthMin)
    self._disturbanceStrengthMax = State(initialValue: initialDisturbanceStrengthMax)
    self.onSave = onSave
    self.onDismiss = onDismiss
  }

  var body: some View {
    VStack {
      Text("Simulation Parameters").font(.headline)
      Divider()
      simulationParametersGrid

      Text("Disturbance Parameters").font(.headline).padding(.top)
      Divider()
      disturbanceParameters

      Divider().padding(.vertical)

      actionButtons
    }
    .padding([.horizontal, .top])
    .frame(minWidth: 420)
  }

  private var simulationParametersGrid: some View {
    VStack(spacing: 10) {
      HStack {
        parameterField(label: "C", value: $c, formatter: floatFormatter)
        parameterField(label: "dx", value: $dx, formatter: floatFormatter)
      }
      HStack {
        parameterField(label: "dt", value: $dt, formatter: floatFormatter)
        parameterField(label: "Damper", value: $damper, formatter: floatFormatter)
      }
    }
    .onChange(of: c) { _, _ in save() }
    .onChange(of: dx) { _, _ in save() }
    .onChange(of: dt) { _, _ in save() }
    .onChange(of: damper) { _, _ in save() }
  }

  private var disturbanceParameters: some View {
    VStack(spacing: 10) {
      rangeField(label: "Cooldown (frames)", min: $disturbanceCooldownMin, max: $disturbanceCooldownMax, formatter: intFormatter)
        .onChange(of: disturbanceCooldownMin) { _, newMin in
          if newMin > disturbanceCooldownMax { disturbanceCooldownMax = newMin }
          save()
        }
        .onChange(of: disturbanceCooldownMax) { _, newMax in
          if newMax < disturbanceCooldownMin { disturbanceCooldownMin = newMax }
          save()
        }

      rangeField(label: "Density", min: $disturbanceDensityMin, max: $disturbanceDensityMax, formatter: intFormatter)
        .onChange(of: disturbanceDensityMin) { _, newMin in
          if newMin > disturbanceDensityMax { disturbanceDensityMax = newMin }
          save()
        }
        .onChange(of: disturbanceDensityMax) { _, newMax in
          if newMax < disturbanceDensityMin { disturbanceDensityMin = newMax }
          save()
        }

      rangeField(label: "Radius", min: $disturbanceRadiusMin, max: $disturbanceRadiusMax, formatter: floatFormatter)
        .onChange(of: disturbanceRadiusMin) { _, newMin in
          if newMin > disturbanceRadiusMax { disturbanceRadiusMax = newMin }
          save()
        }
        .onChange(of: disturbanceRadiusMax) { _, newMax in
          if newMax < disturbanceRadiusMin { disturbanceRadiusMin = newMax }
          save()
        }

      rangeField(label: "Strength", min: $disturbanceStrengthMin, max: $disturbanceStrengthMax, formatter: floatFormatter)
        .onChange(of: disturbanceStrengthMin) { _, newMin in
          if newMin > disturbanceStrengthMax { disturbanceStrengthMax = newMin }
          save()
        }
        .onChange(of: disturbanceStrengthMax) { _, newMax in
          if newMax < disturbanceStrengthMin { disturbanceStrengthMin = newMax }
          save()
        }
    }
  }

  private var actionButtons: some View {
    HStack {
      Button("Reset") {
        c = defaultC
        dx = defaultDx
        dt = defaultDt
        damper = defaultDamper
        disturbanceCooldownMin = defaultDisturbanceCooldownMin
        disturbanceCooldownMax = defaultDisturbanceCooldownMax
        disturbanceDensityMin = defaultDisturbanceDensityMin
        disturbanceDensityMax = defaultDisturbanceDensityMax
        disturbanceRadiusMin = defaultDisturbanceRadiusMin
        disturbanceRadiusMax = defaultDisturbanceRadiusMax
        disturbanceStrengthMin = defaultDisturbanceStrengthMin
        disturbanceStrengthMax = defaultDisturbanceStrengthMax
      }
      .buttonStyle(.bordered)

      Spacer()

      Button("Done") {
        onDismiss()
      }
      .buttonStyle(.borderedProminent)
    }
    .padding()
  }

  private func save() {
    onSave(
      c, dx, dt, damper, disturbanceCooldownMin, disturbanceCooldownMax, disturbanceDensityMin,
      disturbanceDensityMax, disturbanceRadiusMin, disturbanceRadiusMax, disturbanceStrengthMin,
      disturbanceStrengthMax)
  }

  @ViewBuilder
  private func parameterField<V>(label: String, value: Binding<V>, formatter: Formatter)
    -> some View where V: CVarArg
  {
    HStack {
      Text(label)
      TextField(label, value: value, formatter: formatter)
        .textFieldStyle(RoundedBorderTextFieldStyle())
    }
  }

  @ViewBuilder
  private func rangeField<V>(label: String, min: Binding<V>, max: Binding<V>, formatter: Formatter) -> some View where V: CVarArg & Comparable {
    HStack {
      Text(label)
      Spacer()
      TextField("Min", value: min, formatter: formatter)
        .textFieldStyle(RoundedBorderTextFieldStyle())
        .frame(maxWidth: 90)

      Image(systemName: "arrow.right")
      
      TextField("Max", value: max, formatter: formatter)
        .textFieldStyle(RoundedBorderTextFieldStyle())
        .frame(maxWidth: 90)
    }
  }
}
