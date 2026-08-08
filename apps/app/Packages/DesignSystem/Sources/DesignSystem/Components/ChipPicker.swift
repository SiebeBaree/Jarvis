import SwiftUI

// MARK: - Segmented picker
//
// A pill track with a single selected capsule that *slides* between options
// via `matchedGeometryEffect`. The old version cross-faded two background
// colours, so switching segments read as a flicker; a moving indicator reads
// as one object being repositioned, which is both calmer and clearer about
// where you came from.

public struct ChipPicker<Option: Hashable>: View {
    private let options: [Option]
    private let label: (Option) -> String
    private let fillsWidth: Bool
    @Binding private var selection: Option
    @Namespace private var indicator

    public init(
        _ options: [Option],
        selection: Binding<Option>,
        fillsWidth: Bool = false,
        label: @escaping (Option) -> String,
    ) {
        self.options = options
        self._selection = selection
        self.fillsWidth = fillsWidth
        self.label = label
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                segment(option)
            }
        }
        .padding(3)
        .background(Color.bgSubtle, in: Capsule())
        .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
        .fixedSize(horizontal: !fillsWidth, vertical: true)
        .accessibilityElement(children: .contain)
    }

    private func segment(_ option: Option) -> some View {
        let isSelected = option == selection
        return Button {
            Haptics.play(.light)
            withJarvisAnimation(Motion.quick) { selection = option }
        } label: {
            Text(label(option))
                .font(.captionJ)
                .foregroundStyle(isSelected ? Color.textPrimary : Color.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, Space.md)
                .padding(.vertical, 7)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color.bgSurface)
                            .jarvisShadow(.card)
                            .matchedGeometryEffect(id: "selection", in: indicator)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview("ChipPicker") {
    struct Demo: View {
        @State private var selection = "Today"
        @State private var range = "31D"
        var body: some View {
            VStack(alignment: .leading, spacing: Space.xl) {
                ChipPicker(["Today", "Upcoming", "All", "Done"], selection: $selection) { $0 }
                ChipPicker(["7D", "31D", "26W", "12M"], selection: $range, fillsWidth: true) { $0 }
            }
            .padding()
            .background(Color.bgCanvas)
        }
    }
    return Demo()
}
