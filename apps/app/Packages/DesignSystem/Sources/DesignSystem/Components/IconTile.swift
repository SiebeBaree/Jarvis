import SwiftUI

// MARK: - Icon tile
//
// A rounded square of the item's colour at 16% with the glyph on top in the
// full colour. This is the anchor of every row in the app — it is what lets
// you find "the blue one" in a list of fifteen without reading a word.

public struct IconTile: View {
    private let symbol: String
    private let color: ItemColor
    private let size: CGFloat
    private let isMuted: Bool

    public init(
        symbol: String,
        color: ItemColor,
        size: CGFloat = TileSize.row,
        isMuted: Bool = false
    ) {
        self.symbol = symbol
        self.color = color
        self.size = size
        self.isMuted = isMuted
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
            .fill(isMuted ? Color.bgSubtle : color.soft)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(isMuted ? Color.textTertiary : color.color)
            )
            .accessibilityHidden(true)
    }
}

#Preview("IconTile") {
    VStack(spacing: Space.lg) {
        HStack(spacing: Space.md) {
            IconTile(symbol: "drop.fill", color: .blue)
            IconTile(symbol: "book.fill", color: .amber)
            IconTile(symbol: "figure.run", color: .green)
            IconTile(symbol: "carrot.fill", color: .orange)
            IconTile(symbol: "moon.fill", color: .violet, isMuted: true)
        }
        HStack(spacing: Space.md) {
            IconTile(symbol: "drop.fill", color: .blue, size: TileSize.small)
            IconTile(symbol: "drop.fill", color: .blue, size: TileSize.row)
            IconTile(symbol: "drop.fill", color: .blue, size: TileSize.large)
        }
    }
    .padding()
    .background(Color.bgCanvas)
}
