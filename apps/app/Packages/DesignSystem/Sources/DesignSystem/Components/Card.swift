import SwiftUI

// MARK: - Card
//
// Surface + generous radius + a soft shadow. The old card was a hairline
// rectangle with shadows explicitly banned; that reads as a form, not an app.
// The border survives only in dark mode, where a shadow alone cannot separate
// a #1A1A1F card from a #0E0E11 canvas.

public struct JarvisCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let padding: CGFloat
    let radius: CGFloat
    let elevation: Elevation

    public init(padding: CGFloat = Space.lg, radius: CGFloat = Radius.card, elevation: Elevation = .card) {
        self.padding = padding
        self.radius = radius
        self.elevation = elevation
    }

    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.borderHairline, lineWidth: colorScheme == .dark ? 1 : 0)
            )
            .jarvisShadow(elevation)
    }
}

public extension View {
    /// The standard card: surface, radius 16, soft shadow.
    func jarvisCard(
        padding: CGFloat = Space.lg,
        radius: CGFloat = Radius.card,
        elevation: Elevation = .card
    ) -> some View {
        modifier(JarvisCardModifier(padding: padding, radius: radius, elevation: elevation))
    }

    /// A row-shaped card — tighter padding and radius, for list rows that each
    /// stand on their own rather than living inside a grouped container.
    func jarvisRow(padding: CGFloat = Space.md) -> some View {
        modifier(JarvisCardModifier(padding: padding, radius: Radius.row, elevation: .card))
    }

    /// A flat container: the card shape without the lift. For sections that
    /// group rows which already carry their own emphasis.
    func jarvisWell(padding inset: CGFloat = Space.lg, radius: CGFloat = Radius.card) -> some View {
        padding(inset)
            .background(Color.bgSubtle, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
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

        Text("Row card").font(.bodyJ).foregroundStyle(Color.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .jarvisRow()

        Text("Well").font(.bodyJ).foregroundStyle(Color.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .jarvisWell()
    }
    .padding()
    .background(Color.bgCanvas)
}
