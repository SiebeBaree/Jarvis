import DesignSystem
import JarvisAPI
import SwiftUI

extension Color {
    /// Parses "#RRGGBB" / "#RRGGBBAA" strings (the API's colorHex format).
    init?(hexString: String?) {
        guard let hexString else { return nil }
        var hex = hexString.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else { return nil }
        if hex.count == 6 {
            self.init(
                red: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255,
            )
        } else {
            self.init(
                red: Double((value >> 24) & 0xFF) / 255,
                green: Double((value >> 16) & 0xFF) / 255,
                blue: Double((value >> 8) & 0xFF) / 255,
                opacity: Double(value & 0xFF) / 255,
            )
        }
    }
}

/// Rotating palette for auto-assigning a colour to newly created categories.
/// Drawn from the design system's item palette so a category dot, a habit
/// tile and a chart series are all the same set of colours.
enum CategoryPalette {
    static let hexes = ItemColor.palette.map(\.hexString)

    static func next(after count: Int) -> String {
        hexes[count % hexes.count]
    }
}

/// Small colored-dot chip for a task category (TickTick-style list tag).
struct CategoryChip: View {
    let category: TaskCategoryDTO

    var body: some View {
        HStack(spacing: Space.xs) {
            if let emoji = category.emoji, !emoji.isEmpty {
                Text(emoji)
                    .font(.system(size: 9))
            } else {
                Circle()
                    .fill(Color(hexString: category.colorHex) ?? Color.textTertiary)
                    .frame(width: 6, height: 6)
            }
            Text(category.name)
                .font(.captionJ)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, 2)
        .background(Color.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                .strokeBorder(Color.borderHairline, lineWidth: 0.5),
        )
    }
}
