import SwiftUI

// MARK: - Jarvis card (spec §B2: surface + 1 px hairline, NO shadow)

public struct JarvisCardModifier: ViewModifier {
    let padding: CGFloat

    public init(padding: CGFloat = Space.lg) {
        self.padding = padding
    }

    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.borderHairline, lineWidth: 0.5)
            )
    }
}

public extension View {
    /// Attio-style card: bgSurface, radius 10, hairline border, no shadow.
    func jarvisCard(padding: CGFloat = Space.lg) -> some View {
        modifier(JarvisCardModifier(padding: padding))
    }
}

#Preview("Card") {
    VStack(spacing: Space.lg) {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("This week").font(.headlineJ).foregroundStyle(Color.textPrimary)
            Text("4 of 6 habits on pace").font(.subheadJ).foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()

        Text("Compact card").font(.bodyJ).foregroundStyle(Color.textPrimary)
            .jarvisCard(padding: Space.md)
    }
    .padding()
    .background(Color.bgCanvas)
}
