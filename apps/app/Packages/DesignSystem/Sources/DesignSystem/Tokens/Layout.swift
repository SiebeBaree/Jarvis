import SwiftUI

// MARK: - Spacing

public enum Space {
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 20
    public static let xxl: CGFloat = 24
    public static let xxxl: CGFloat = 32
}

// MARK: - Corner radii
//
// Rounder than the old scale across the board. A 10 pt radius on a 64 pt card
// reads as "a box with the corners taken off"; 16 reads as a designed object.

public enum Radius {
    /// Cards and grouped containers.
    public static let card: CGFloat = 16
    /// Rows inside a card, and standalone list rows.
    public static let row: CGFloat = 12
    /// Sheets and popovers.
    public static let sheet: CGFloat = 24
    /// Buttons and inputs.
    public static let control: CGFloat = 10
    /// Chips and tags.
    public static let chip: CGFloat = 8
    /// Icon tiles.
    public static let tile: CGFloat = 11
}

// MARK: - Row heights
//
// Taller than before. The old 44 pt row could not hold a title, a meta line
// and a control without feeling cramped, and a tap target you have to aim at
// is the single most "cheap app" thing a tracker can do.

public enum RowHeight {
    public static let iPhone: CGFloat = 56
    public static let mac: CGFloat = 44

    public static var standard: CGFloat {
        #if os(macOS)
        mac
        #else
        iPhone
        #endif
    }

    /// Minimum hit target for any bare control (Apple's guidance is 44).
    public static let tapTarget: CGFloat = 44
}

// MARK: - Icon tile sizes

public enum TileSize {
    /// Rows.
    public static let row: CGFloat = 38
    /// Detail headers.
    public static let large: CGFloat = 52
    /// Dense contexts (chips, inline).
    public static let small: CGFloat = 26
}

// MARK: - Page margins

public enum PageMargin {
    public static let iPhone: CGFloat = 16
    public static let mac: CGFloat = 24

    public static var standard: CGFloat {
        #if os(macOS)
        mac
        #else
        iPhone
        #endif
    }

    /// Content column cap on Mac — a 1400 pt-wide window should not stretch a
    /// task list to 1400 pt.
    public static let contentMaxWidth: CGFloat = 780
}

#Preview("Layout") {
    VStack(alignment: .leading, spacing: Space.md) {
        ForEach(
            [("xs", Space.xs), ("sm", Space.sm), ("md", Space.md), ("lg", Space.lg),
             ("xl", Space.xl), ("xxl", Space.xxl), ("xxxl", Space.xxxl)],
            id: \.0
        ) { name, value in
            HStack(spacing: Space.sm) {
                Text(name).font(.monoJ).frame(width: 40, alignment: .leading)
                Rectangle().fill(Color.accentPrimary).frame(width: value, height: 12)
            }
        }
        ForEach(
            [("chip", Radius.chip), ("control", Radius.control), ("row", Radius.row),
             ("card", Radius.card), ("sheet", Radius.sheet)],
            id: \.0
        ) { name, value in
            HStack(spacing: Space.sm) {
                Text(name).font(.monoJ).frame(width: 60, alignment: .leading)
                RoundedRectangle(cornerRadius: value, style: .continuous)
                    .fill(Color.bgSurface)
                    .frame(width: 90, height: 44)
                    .jarvisShadow()
            }
        }
    }
    .foregroundStyle(Color.textPrimary)
    .padding()
    .background(Color.bgCanvas)
}
