import SwiftUI

/// Sheet for calibrating the scale: "draw a line and tell me how long it is in real life"
/// This is the make-or-break UX for the measurement system.
struct ScaleCalibrationSheet: View {
    @Bindable var project: FloorPlanProject
    @Environment(\.dismiss) private var dismiss

    @State private var realWorldValue: String = ""
    @State private var referenceLength: Double = 200
    @State private var selectedPreset: ScalePreset?

    var body: some View {
        NavigationStack {
            Form {
                descriptionSection
                presetsSection
                customScaleSection
                currentScaleSection
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

    // MARK: - Sections

    private var descriptionSection: some View {
        Section {
            Text("Set the scale so that measurements on the canvas correspond to real-world dimensions.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var presetsSection: some View {
        Section("Quick Presets") {
            ForEach(ScalePreset.allCases) { preset in
                presetRow(preset)
            }
        }
    }

    private func presetRow(_ preset: ScalePreset) -> some View {
        Button {
            selectedPreset = preset
            project.pointsPerRealUnit = preset.pointsPerRealUnit
        } label: {
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
                        .foregroundColor(.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var customScaleSection: some View {
        Section("Custom Scale") {
            VStack(alignment: .leading, spacing: 12) {
                Text("The reference line on canvas is \(Int(referenceLength)) points long.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Slider(value: $referenceLength, in: 50...500, step: 10) {
                    Text("Reference length")
                }

                customScaleInput

                applyButton
            }
        }
    }

    private var customScaleInput: some View {
        HStack {
            Text("This line represents:")
            TextField(unitPlaceholder, text: $realWorldValue)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
            Text(unitLabel)
                .foregroundStyle(.secondary)
        }
    }

    private var applyButton: some View {
        Button("Apply Custom Scale") {
            if let value = Double(realWorldValue), value > 0 {
                project.pointsPerRealUnit = referenceLength / value
                selectedPreset = nil
            }
        }
        .disabled(!isValidCustomValue)
    }

    private var currentScaleSection: some View {
        Section {
            HStack {
                Text("Current scale:")
                Spacer()
                Text(currentScaleText)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.accentColor)
            }
        }
    }

    // MARK: - Computed Helpers

    private var unitPlaceholder: String {
        project.unitSystem == .imperial ? "e.g. 10" : "e.g. 3"
    }

    private var unitLabel: String {
        project.unitSystem == .imperial ? "feet" : "meters"
    }

    private var isValidCustomValue: Bool {
        guard let value = Double(realWorldValue) else { return false }
        return value > 0
    }

    private var currentScaleText: String {
        let suffix = project.unitSystem == .imperial ? "ft" : "m"
        return String(format: "%.1f pts = 1 %@", project.pointsPerRealUnit, suffix)
    }
}

// MARK: - Scale Preset

enum ScalePreset: String, CaseIterable, Identifiable {
    case oneFootPerInch = "1\" = 1'"
    case quarterInch = "1/4\" = 1'"
    case halfInch = "1/2\" = 1'"
    case oneCmPerMeter = "1 cm = 1 m"

    var id: String { rawValue }

    var pointsPerRealUnit: Double {
        switch self {
        case .oneFootPerInch: return 72.0
        case .quarterInch: return 18.0
        case .halfInch: return 36.0
        case .oneCmPerMeter: return 28.35
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
