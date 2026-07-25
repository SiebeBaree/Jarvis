import CoreGraphics

/// Sizing for the habit-consistency dot rows.
///
/// A month has to fit on one line, so the dot size is derived from the width
/// actually available rather than fixed. The old fixed 8pt left a dead gap at
/// the trailing edge on iPhone and used barely half the row on Mac, where the
/// card is roughly twice as wide.
public enum HeatDotMetrics {
    /// Gap between dots, as a fraction of the dot itself, so the rhythm holds
    /// at every size. Deliberately tight: on a phone, 31 dots leave very
    /// little room, and spacing is the only place to win it back.
    public static let spacingRatio: CGFloat = 0.22

    public static let minSize: CGFloat = 7

    /// Only reachable for short months on a wide window — a 31-day month on a
    /// phone is bound by width long before it gets here.
    #if os(macOS)
    public static let maxSize: CGFloat = 22
    #else
    public static let maxSize: CGFloat = 13
    #endif

    /// Largest dot for which `dayCount` dots plus their gaps still fit in
    /// `width`, clamped to the platform bounds.
    public static func size(width: CGFloat, dayCount: Int, maxSize: CGFloat = HeatDotMetrics.maxSize) -> CGFloat {
        guard width > 0, dayCount > 0 else { return minSize }
        let count = CGFloat(dayCount)
        // width = count * size + (count - 1) * size * spacingRatio
        let raw = width / (count + (count - 1) * spacingRatio)
        return min(max(raw, minSize), maxSize)
    }

    /// Total width a row occupies at a given dot size — used to check the row
    /// fills its container rather than stopping short.
    public static func rowWidth(dotSize: CGFloat, dayCount: Int) -> CGFloat {
        guard dayCount > 0 else { return 0 }
        let count = CGFloat(dayCount)
        return count * dotSize + (count - 1) * dotSize * spacingRatio
    }
}
