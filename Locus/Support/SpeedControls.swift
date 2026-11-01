import SwiftUI

/// Shared by the map tray and the route sheet.
struct SpeedControls: View {
    @EnvironmentObject private var session: SpoofSession
    @State private var showEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ForEach(TravelMode.allCases) { mode in
                    let selected = session.travelMode == mode
                    Button {
                        if mode == .custom {
                            showEditor = true
                        } else {
                            session.travelMode = mode
                        }
                    } label: {
                        Image(systemName: mode.icon)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(selected ? .black : .primary)
                            .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
                            .background(Capsule().fill(selected ? LocusTheme.accent : Color.primary.opacity(0.08)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(mode.title)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            HStack(spacing: 6) {
                Text(session.travelMode.title)
                Text((session.baseSpeed * 3.6).formatted(.number.precision(.fractionLength(1))) + " km/h")
                    .monospacedDigit()
                Spacer(minLength: 0)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showEditor) {
            NumericValueSheet(
                title: String(localized: "Custom speed"),
                unit: "km/h", value: $session.motionSettings.customSpeedKPH,
                range: 0.1...300, step: 0.1,
                help: String(localized: "Shared by joystick and routes. Changes apply while moving.")
            ) {
                session.travelMode = .custom
            }
        }
    }
}

struct NumericSettingRow: View {
    var title: String
    var unit: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var help: String
    var prefix = ""
    @State private var showEditor = false

    var body: some View {
        Button { showEditor = true } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                Text(prefix + value.formatted(.number.precision(.fractionLength(0...1))) + " " + unit)
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .sheet(isPresented: $showEditor) {
            NumericValueSheet(title: title, unit: unit, value: $value,
                              range: range, step: step, help: help)
        }
    }
}

/// Draft input prevents an invalid edit from changing an active movement session.
struct NumericValueSheet: View {
    var title: String
    var unit: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var help: String
    var onSave: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    private var parsed: Double? {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        formatter.isLenient = false
        // Reject partial parses (e.g. pasted letters or grouping separators).
        let decimal = Locale.current.decimalSeparator ?? "."
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.allSatisfy({ $0.isASCII && ($0.isNumber || String($0) == decimal) }),
              trimmed.components(separatedBy: decimal).count <= 2,
              let number = formatter.number(from: trimmed)?.doubleValue,
              number.isFinite, range.contains(number) else { return nil }
        return number
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField(title, text: $text)
                            .keyboardType(.decimalPad)
                            .font(.title2.monospacedDigit())
                            .accessibilityLabel(title)
                        Text(unit).foregroundStyle(.secondary)
                    }
                    Stepper(String(localized: "Fine adjustment"), value: Binding(
                        get: { parsed ?? min(range.upperBound, max(range.lowerBound, value)) },
                        set: { text = $0.formatted(.number.grouping(.never).precision(.fractionLength(1))) }
                    ), in: range, step: step)
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(help)
                        Text(String(format: String(localized: "Allowed range: %@–%@ %@"),
                                    range.lowerBound.formatted(), range.upperBound.formatted(), unit))
                        if parsed == nil {
                            Text(String(localized: "Enter a number within the allowed range."))
                                .foregroundStyle(LocusTheme.danger)
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        guard let parsed else { return }
                        value = (parsed * 10).rounded() / 10
                        onSave()
                        dismiss()
                    }
                    .disabled(parsed == nil)
                }
            }
        }
        .tint(LocusTheme.accent)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { text = value.formatted(.number.grouping(.never).precision(.fractionLength(0...1))) }
    }
}
