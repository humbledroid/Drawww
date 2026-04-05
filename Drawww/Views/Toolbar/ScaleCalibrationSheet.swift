import SwiftUI

/// Sheet for calibrating the scale: "draw a line and tell me how long it is in real life"
/// This is the make-or-break UX for the measurement system.
struct ScaleCalibrationSheet: View {
    @Bindable var project: FloorPlanProject
    @Environment(\.dismiss) private var dismiss

    @State private var realWorldValue: String = ""
    @State private var referenceLength: Double = 200 // default reference line in points
    @State private var selectedPreset: ScalePreset?

    enum ScalePreset: String, CaseIterable, Identifiable {
        case oneFootPerInch = "1\" = 1'"
        case quarterInch = "1/4\" = 1'"
        case halfInch = "1/2\" = 1'"
        case oneCmPerMeter = "1 cm = 1 m"

        var id: String { rawValue }

        var pointsPerRealUnit: Double {
            switch self {
            case .oneFootPerInch: return 72.0    // 1 screen inch = 1 foot
            case .quarterInch: return 18.0       // 1/4 screen inch = 1 foot
            case .halfInch: return 36.0          // 1/2 screen inch = 1 foot
            case .oneCmPerMeter: return 28.35    // 1 screen cm = 1 meter
            }
        }

        var description: String {
            switch self {
            case .oneFootPerInch: return "Full size on screen"
            case .quarterInch: return "Architectural quarter-inch"
            case .halfInch: return "Architectural half-inch"
            case .oneCmPerMeter: return "Metric standard"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Set the scale so that measurements on the canvas correspond to real-world dimensions.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Quick Presets") {
                    ForEach(ScalePreset.allCases) { preset in
                        Button(action: {
                            selectedPreset = preset
                            project.pointsPerRealUnit = preset.pointsPerRealUnit
                        }) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(preset.rawValue)
                                        .font(.body)
                                    Text(preset.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selectedPreset == preset {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.accentColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("Custom Scale") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("The reference line on canvas is \(Int(referenceLength)) points long.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Slider(value: $referenceLength, in: 50...500, step: 10) {
                            Text("Reference length")
                        }

                        HStack {
                            Text("This line represents:")
                            TextField(
                                project.unitSystem == .imperial ? "e.g. 10" : "e.g. 3",
                                text: $realWorldValue
                            )
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)

                            Text(project.unitSystem == .imperial ? "feet" : "meters")
                                .foregroundStyle(.secondary)
                        }

                        Button("Apply Custom Scale") {
                            if let value = Double(realWorldValue), value > 0 {
                                project.pointsPerRealUnit = referenceLength / value
                                selectedPreset = nil
                            }
                        }
                        .disabled(Double(realWorldValue) == nil || Double(realWorldValue)! <= 0)
                    }
                }

                Section {
                    HStack {
                        Text("Current scale:")
                        Spacer()
                        Text(String(format: "%.1f pts = 1 %@",
                                    project.pointsPerRealUnit,
                                    project.unitSystem == .imperial ? "ft" : "m"))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.accentColor)
                    }
                }
            }
            .navigationTitle("Scale Calibration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
