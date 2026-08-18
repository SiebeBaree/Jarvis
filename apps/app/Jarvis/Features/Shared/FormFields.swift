import DesignSystem
import SwiftUI

// Form fields that behave the same on both platforms.
//
// The trap these exist to close: `TextField("Name", text:)` puts "Name" INSIDE
// the field on iOS and BESIDE it as a permanent label on macOS. Writing an
// iOS-style example placeholder ("Leg day, Chest & Back, …") therefore turned
// into a label on the Mac that ate the row, leaving a few characters of the
// actual value visible at the far right.
//
// Everything here goes through `prompt:` + `.labelsHidden()`, which puts the
// hint inside the field on both platforms and never generates a label. Any
// label that is wanted is drawn explicitly, so its width is known.

/// A text field whose hint stays inside the field on macOS and iOS alike.
struct PromptField: View {
    let prompt: String
    @Binding var text: String
    var axis: Axis = .horizontal
    var lineLimit: ClosedRange<Int>?

    var body: some View {
        Group {
            if axis == .vertical {
                TextField("", text: $text, prompt: Text(prompt), axis: .vertical)
                    .lineLimit(lineLimit ?? 1...4)
            } else {
                TextField("", text: $text, prompt: Text(prompt))
            }
        }
        .labelsHidden()
        .textFieldStyle(.plain)
        .font(.bodyJ)
        .foregroundStyle(Color.textPrimary)
    }
}

/// A short numeric entry with its caption *above* it.
///
/// Captions go above rather than beside because a 46 pt-wide inline label
/// wraps ("Se / ts") the moment the sheet is anything but wide. Stacked, the
/// caption has the whole column to itself and the number never moves.
struct CaptionedField: View {
    let caption: String
    let prompt: String
    @Binding var text: String
    var width: CGFloat = 62
    var suffix: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(caption)
                .font(.microJ)
                .foregroundStyle(Color.textTertiary)
                .lineLimit(1)
                .fixedSize()

            HStack(spacing: 4) {
                TextField("", text: $text, prompt: Text(prompt))
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .font(.numeralJ)
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: width)
                    .padding(.vertical, 6)
                    .background(
                        Color.bgSubtle,
                        in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous),
                    )
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif

                if let suffix {
                    Text(suffix)
                        .font(.microJ)
                        .foregroundStyle(Color.textTertiary)
                        .fixedSize()
                }
            }
        }
    }
}

/// A labelled row for grouped forms: explicit label on the left, field on the
/// right, with a unit after it. Replaces `TextField("Label", …)` so the label
/// width is ours and the value can never be squeezed to three characters.
struct LabeledField: View {
    let label: String
    let prompt: String
    @Binding var text: String
    var unit: String?
    var fieldWidth: CGFloat = 90

    var body: some View {
        HStack(spacing: Space.sm) {
            Text(label)
                .font(.bodyJ)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
            Spacer(minLength: Space.md)
            TextField("", text: $text, prompt: Text(prompt))
                .labelsHidden()
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .font(.bodyJ)
                .frame(width: fieldWidth)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
            if let unit {
                Text(unit)
                    .font(.subheadJ)
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 30, alignment: .leading)
            }
        }
    }
}

/// Full-width search box.
///
/// `.searchable()` on macOS collapses into a small fixed-width toolbar field
/// that truncates its own placeholder, which is useless for exercise names
/// like "Supine barbell bench press". This is just a field, so it is always as
/// wide as the sheet.
struct InlineSearchField: View {
    let prompt: String
    @Binding var text: String
    var onSubmit: (() -> Void)?

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.textTertiary)

            TextField("", text: $text, prompt: Text(prompt))
                .labelsHidden()
                .textFieldStyle(.plain)
                .font(.bodyJ)
                .foregroundStyle(Color.textPrimary)
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit { onSubmit?() }
                #if os(iOS)
                .autocorrectionDisabled()
                #endif

            if !text.isEmpty {
                Button {
                    text = ""
                    isFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Space.md)
        .frame(height: 38)
        .background(Color.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(
                    isFocused ? Color.accentPrimary.opacity(0.5) : Color.clear,
                    lineWidth: 1,
                ),
        )
        .jarvisAnimation(Motion.quick, value: isFocused)
    }
}

/// The item-colour picker.
///
/// The selection ring is drawn *inside* each swatch's own frame rather than as
/// negative padding around it. Drawn outside, the ring fell beyond the swatch's
/// bounds and the enclosing scroll view clipped it, so the selected colour lost
/// a slice of its border.
struct ColorSwatchPicker: View {
    @Binding var selection: ItemColor

    private let swatch: CGFloat = 24
    private let cell: CGFloat = 34

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(ItemColor.palette) { option in
                    let isSelected = option.id == selection.id
                    ZStack {
                        Circle()
                            .strokeBorder(
                                isSelected ? Color.textPrimary : Color.clear,
                                lineWidth: 2,
                            )
                            .frame(width: cell - 6, height: cell - 6)
                        Circle()
                            .fill(option.color)
                            .frame(width: swatch, height: swatch)
                    }
                    .frame(width: cell, height: cell)
                    .contentShape(Circle())
                    .pressable(haptic: .light) { selection = option }
                    .accessibilityLabel(option.displayName)
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: cell)
        .jarvisAnimation(Motion.quick, value: selection.id)
    }
}

#Preview("Form fields") {
    struct Demo: View {
        @State private var name = ""
        @State private var sets = "4"
        @State private var low = "6"
        @State private var high = "8"
        @State private var weight = "82.5"
        @State private var search = ""
        @State private var color: ItemColor = .rose

        var body: some View {
            VStack(alignment: .leading, spacing: Space.xl) {
                PromptField(prompt: "Name", text: $name)
                InlineSearchField(prompt: "Search or add an exercise", text: $search)
                ColorSwatchPicker(selection: $color)
                HStack(alignment: .bottom, spacing: Space.sm) {
                    CaptionedField(caption: "Sets", prompt: "3", text: $sets, width: 46)
                    CaptionedField(caption: "Reps", prompt: "8", text: $low, width: 46)
                    CaptionedField(caption: "to", prompt: "12", text: $high, width: 46)
                    CaptionedField(caption: "Weight", prompt: "0", text: $weight, suffix: "kg")
                }
                LabeledField(label: "Calories", prompt: "0", text: $weight, unit: "kcal")
            }
            .padding()
            .background(Color.bgCanvas)
        }
    }
    return Demo()
}
