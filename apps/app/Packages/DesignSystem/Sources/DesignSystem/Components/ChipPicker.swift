import SwiftUI

/// Capsule-chip segment picker — the app's replacement for the system
/// segmented control, which reads as heavy "navbar" chrome. Selected chip is
/// accent-tinted; the rest stay quiet.
public struct ChipPicker<Option: Hashable>: View {
    private let options: [Option]
    private let label: (Option) -> String
    @Binding private var selection: Option

    public init(
        _ options: [Option],
        selection: Binding<Option>,
        label: @escaping (Option) -> String,
    ) {
        self.options = options
        self._selection = selection
        self.label = label
    }

    public var body: some View {
        HStack(spacing: Space.sm) {
            ForEach(options, id: \.self) { option in
                chip(option)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
    }

    private func chip(_ option: Option) -> some View {
        let isSelected = option == selection
        return Button {
            selection = option
        } label: {
            Text(label(option))
                .font(.subheadJ)
                .foregroundStyle(isSelected ? Color.accentPrimary : Color.textSecondary)
                .padding(.horizontal, Space.md)
                .padding(.vertical, 5)
                .background(isSelected ? Color.accentSubtle : Color.bgSubtle, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        isSelected ? Color.accentPrimary.opacity(0.35) : Color.borderHairline,
                        lineWidth: 0.5,
                    ),
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview("ChipPicker") {
    struct Demo: View {
        @State private var selection = "Today"
        var body: some View {
            ChipPicker(["Today", "Upcoming", "All", "Done"], selection: $selection) { $0 }
                .padding()
                .background(Color.bgCanvas)
        }
    }
    return Demo()
}
