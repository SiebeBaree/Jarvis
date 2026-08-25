import DesignSystem
import SwiftUI

/// A big-target numeric control: minus, value, plus. Built rather than using
/// `Stepper` because at the gym this needs a 44 pt hit area and a value you
/// can read from arm's length, and because tapping the number opens a keypad
/// for the jump that stepping would take twenty taps to reach.
///
/// The buttons ask `advance` where to land rather than adding a fixed step.
/// Weight walks the exercise's ladder, which is not a constant: a cable stack
/// goes 2.3, 4.5, 6.8, and dumbbells change gap at 10 kg.
struct NumberStepper<UnitLabel: View>: View {
    @Binding var value: Double
    /// The value one rung away, given where you are and which button was hit
    /// (+1 or -1). Must move, or holding the button does nothing.
    let advance: (Double, Int) -> Double
    let range: ClosedRange<Double>
    /// Spoken, not drawn. The drawn label is `unit`.
    let accessibilityUnit: String
    let format: (Double) -> String
    @ViewBuilder let unit: () -> UnitLabel

    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            stepButton("minus") {
                value = min(range.upperBound, max(range.lowerBound, advance(value, -1)))
            }

            Group {
                if isEditing {
                    TextField("", text: $draft)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.center)
                        .font(.numeralJ)
                        .focused($fieldFocused)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .onSubmit(commit)
                        .onChange(of: fieldFocused) { _, focused in
                            if !focused { commit() }
                        }
                } else {
                    VStack(spacing: -2) {
                        Text(format(value))
                            .font(.numeralJ)
                            .foregroundStyle(Color.textPrimary)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                draft = format(value)
                                isEditing = true
                                fieldFocused = true
                            }
                        unit()
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: RowHeight.tapTarget)

            stepButton("plus") {
                value = min(range.upperBound, max(range.lowerBound, advance(value, 1)))
            }
        }
        .background(Color.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .frame(maxWidth: .infinity)
    }

    private func commit() {
        let cleaned = draft.replacingOccurrences(of: ",", with: ".")
        if let parsed = Double(cleaned) {
            value = min(range.upperBound, max(range.lowerBound, parsed))
        }
        isEditing = false
        fieldFocused = false
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            Haptics.play(.light)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.textSecondary)
                .frame(width: RowHeight.tapTarget, height: RowHeight.tapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "plus" ? "Increase \(accessibilityUnit)" : "Decrease \(accessibilityUnit)")
    }
}
