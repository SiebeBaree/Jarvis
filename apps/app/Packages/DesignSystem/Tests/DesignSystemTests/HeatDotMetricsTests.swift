import CoreGraphics
import Testing
@testable import DesignSystem

/// The habit-consistency rows used a fixed 8pt dot, which left a dead gap at
/// the trailing edge on iPhone and used barely half the card on Mac. These
/// pin the derived sizing so that regresses loudly.
struct HeatDotMetricsTests {
    /// iPhone 402pt wide, less the 16pt page margin and 16pt card padding.
    private let phoneWidth: CGFloat = 402 - 2 * 16 - 2 * 16 // 338
    /// Mac content caps at 760pt, less the 24pt page margin and 16pt padding.
    private let macWidth: CGFloat = 760 - 2 * 24 - 2 * 16 // 680

    @Test func aMonthFillsTheRowWithoutOverflowing() {
        for (width, maxSize) in [(phoneWidth, CGFloat(13)), (macWidth, CGFloat(22))] {
            for days in [28, 29, 30, 31] {
                let size = HeatDotMetrics.size(width: width, dayCount: days, maxSize: maxSize)
                let row = HeatDotMetrics.rowWidth(dotSize: size, dayCount: days)
                #expect(row <= width + 0.01, "overflows at \(width)pt / \(days) days")
                // Either it fills the width exactly, or the dots hit the cap.
                #expect(
                    row >= width - 0.01 || size == maxSize,
                    "leaves a gap at \(width)pt / \(days) days (row \(row) of \(width))",
                )
            }
        }
    }

    @Test func desktopDotsAreMuchLargerThanTheOldFixedEight() {
        let mac = HeatDotMetrics.size(width: macWidth, dayCount: 31, maxSize: 22)
        let phone = HeatDotMetrics.size(width: phoneWidth, dayCount: 31, maxSize: 13)
        #expect(mac > 15, "expected chunky desktop dots, got \(mac)")
        #expect(mac > phone * 1.8, "desktop should dwarf phone, got \(mac) vs \(phone)")
        // A phone can only ever win a little here: 31 dots in 338pt is tight.
        #expect(phone > 8, "should still beat the old fixed 8pt, got \(phone)")
    }

    @Test func degenerateInputsFallBackToTheMinimum() {
        #expect(HeatDotMetrics.size(width: 0, dayCount: 31) == HeatDotMetrics.minSize)
        #expect(HeatDotMetrics.size(width: 300, dayCount: 0) == HeatDotMetrics.minSize)
    }
}
