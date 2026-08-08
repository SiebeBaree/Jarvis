import SwiftUI

// MARK: - Empty state
//
// Every list in the app has one, and on a brand-new account they are the
// *first* thing seen — so they are a designed screen, not a gray sentence.
// A tinted glyph, a plain-language title, one line of why, and exactly one
// action.

public struct EmptyState<Actions: View>: View {
    private let symbol: String
    private let title: String
    private let message: String?
    private let tint: Color
    private let actions: Actions

    public init(
        symbol: String,
        title: String,
        message: String? = nil,
        tint: Color = .accentPrimary,
        @ViewBuilder actions: () -> Actions
    ) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.tint = tint
        self.actions = actions()
    }

    public var body: some View {
        VStack(spacing: Space.lg) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(tint)
            }

            VStack(spacing: Space.xs) {
                Text(title)
                    .font(.title2J)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)
                if let message {
                    Text(message)
                        .font(.bodyJ)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            actions
        }
        .frame(maxWidth: 340)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Space.xl)
        .padding(.vertical, Space.xxxl)
        .accessibilityElement(children: .contain)
    }
}

public extension EmptyState where Actions == EmptyView {
    init(symbol: String, title: String, message: String? = nil, tint: Color = .accentPrimary) {
        self.init(symbol: symbol, title: title, message: message, tint: tint) { EmptyView() }
    }
}

#Preview("EmptyState") {
    VStack(spacing: Space.xxxl) {
        EmptyState(
            symbol: "repeat",
            title: "No habits yet",
            message: "Habits are the part of the score you control every single day.",
            tint: ItemColor.violet.color
        ) {
            Button("Add your first habit") {}
                .buttonStyle(.jarvisPrimary)
        }

        EmptyState(
            symbol: "checkmark.circle",
            title: "Nothing scheduled",
            message: "Your day is clear.",
            tint: ItemColor.green.color
        )
    }
    .background(Color.bgCanvas)
}
