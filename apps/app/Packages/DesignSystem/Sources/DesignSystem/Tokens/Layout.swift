import SwiftUI

// MARK: - Spacing (spec §B2: 4/8/12/16/20/24/32)

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

public enum Radius {
    /// Cards and rows.
    public static let card: CGFloat = 10
    /// Sheets and popovers.
    public static let sheet: CGFloat = 16
    /// Buttons and inputs.
    public static let control: CGFloat = 8
    /// Chips and tags.
    public static let chip: CGFloat = 6
}

// MARK: - Row heights

public enum RowHeight {
    /// List rows on iPhone.
    public static let iPhone: CGFloat = 44
    /// List rows on Mac.
    public static let mac: CGFloat = 36

    /// Platform-appropriate default row height.
    public static var standard: CGFloat {
        #if os(macOS)
        mac
        #else
        iPhone
        #endif
    }
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
    }
    .padding()
    .background(Color.bgCanvas)
}
