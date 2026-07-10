import SwiftUI

// MARK: - Section header (caption style: uppercase, +0.6 tracking, textSecondary)

public struct SectionHeader<Trailing: View>: View {
    private let title: String
    private let trailing: Trailing

    public init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.captionJ)
                .tracking(0.6)
                .foregroundStyle(Color.textSecondary)
            Spacer(minLength: Space.sm)
            trailing
        }
    }
}

public extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

#Preview("SectionHeader") {
    VStack(spacing: Space.xl) {
        SectionHeader("Tasks")
        SectionHeader("Habits") {
            Button("See all") {}
                .font(.captionJ)
                .foregroundStyle(Color.accentPrimary)
                .buttonStyle(.plain)
        }
        SectionHeader("Overdue")
    }
    .padding()
    .background(Color.bgCanvas)
}
