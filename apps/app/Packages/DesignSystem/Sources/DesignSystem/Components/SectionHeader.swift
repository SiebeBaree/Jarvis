import SwiftUI

// MARK: - Section header
//
// Title-case and bold, not uppercase-tracked caption. The all-caps header was
// doing two jobs badly: too loud to be a quiet label, too small to be a real
// heading. This is a heading.

public struct SectionHeader<Trailing: View>: View {
    private let title: String
    private let subtitle: String?
    private let trailing: Trailing

    public init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.title3J)
                    .foregroundStyle(Color.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadJ)
                        .foregroundStyle(Color.textTertiary)
                }
            }
            Spacer(minLength: Space.sm)
            trailing
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

public extension SectionHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: - Caption label
//
// What the old SectionHeader was actually good for: a quiet marker above a
// small group ("OVERDUE", "ALSO AVAILABLE"). Kept as its own thing so the two
// jobs stop competing.

public struct CaptionLabel: View {
    private let text: String
    private let color: Color

    public init(_ text: String, color: Color = .textTertiary) {
        self.text = text
        self.color = color
    }

    public var body: some View {
        Text(text.uppercased())
            .font(.microJ)
            .tracking(0.7)
            .foregroundStyle(color)
    }
}

#Preview("SectionHeader") {
    VStack(alignment: .leading, spacing: Space.xl) {
        SectionHeader("Tasks")
        SectionHeader("Habits", subtitle: "4 of 6 on pace") {
            Button("See all") {}
                .buttonStyle(.jarvisSoft)
        }
        CaptionLabel("Overdue", color: .warning)
        CaptionLabel("Also available")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
    .background(Color.bgCanvas)
}
