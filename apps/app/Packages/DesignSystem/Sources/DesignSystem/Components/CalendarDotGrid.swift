import SwiftUI

// MARK: - Month calendar dot grid (spec §B5.3)
//
// Monday-first grid of 10 pt dots: solid green = full, pie-fill by exact
// fraction = partial, hairline outline = missed (neutral, never red),
// blank = not applicable. Today gets an accent ring. Weekly habits can show
// a trailing per-week result column (✓ / — / live fraction).

public enum DotState: Equatable, Sendable {
    case full
    case partial(Double)
    case missed
    case notApplicable
}

public struct CalendarDay: Equatable, Sendable {
    public let day: Int
    public let state: DotState
    public let isToday: Bool

    public init(day: Int, state: DotState, isToday: Bool = false) {
        self.day = day
        self.state = state
        self.isToday = isToday
    }
}

public enum WeekResult: Equatable, Sendable {
    case met
    case missed
    case live(done: Int, target: Int)
}

public struct CalendarDotGrid: View {
    private let year: Int
    private let month: Int
    private let days: [Int: CalendarDay]
    private let weekResults: [WeekResult]?
    private let tint: Color

    public init(
        year: Int,
        month: Int,
        days: [CalendarDay],
        weekResults: [WeekResult]? = nil,
        tint: Color = .success
    ) {
        self.year = year
        self.month = month
        self.days = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        self.weekResults = weekResults
        self.tint = tint
    }

    /// Convenience init from any date within the month.
    public init(
        monthAnchor: Date,
        days: [CalendarDay],
        weekResults: [WeekResult]? = nil,
        tint: Color = .success,
        calendar: Calendar = .current
    ) {
        let components = calendar.dateComponents([.year, .month], from: monthAnchor)
        self.init(
            year: components.year ?? 2000,
            month: components.month ?? 1,
            days: days,
            weekResults: weekResults,
            tint: tint
        )
    }

    private let dotSize: CGFloat = 13
    private let cellHeight: CGFloat = 24
    private let weekdaySymbols = ["M", "T", "W", "T", "F", "S", "S"]

    /// Weeks as rows of optional day numbers (nil = outside the month).
    private var weeks: [[Int?]] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2 // Monday

        guard let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let dayRange = calendar.range(of: .day, in: .month, for: firstOfMonth)
        else { return [] }

        // Monday-first index of day 1 (0 = Monday … 6 = Sunday).
        let weekday = calendar.component(.weekday, from: firstOfMonth) // 1 = Sunday
        let leadingBlanks = (weekday + 5) % 7

        var cells: [Int?] = Array(repeating: nil, count: leadingBlanks)
        cells.append(contentsOf: dayRange.map { Optional($0) })
        while cells.count % 7 != 0 { cells.append(nil) }

        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<($0 + 7)]) }
    }

    public var body: some View {
        VStack(spacing: Space.sm) {
            // Weekday header
            gridRow(
                cells: { column in
                    Text(weekdaySymbols[column])
                        .font(.captionJ)
                        .foregroundStyle(Color.textTertiary)
                },
                trailing: { EmptyView() }
            )

            ForEach(Array(weeks.enumerated()), id: \.offset) { weekIndex, week in
                gridRow(
                    cells: { column in
                        if let dayNumber = week[column] {
                            DayDot(
                                day: days[dayNumber] ?? CalendarDay(day: dayNumber, state: .notApplicable),
                                dotSize: dotSize,
                                tint: tint
                            )
                        } else {
                            Color.clear.frame(width: dotSize, height: dotSize)
                        }
                    },
                    trailing: {
                        if let weekResults, weekIndex < weekResults.count {
                            WeekResultCell(result: weekResults[weekIndex])
                        }
                    }
                )
            }

            legend
                .padding(.top, Space.xs)
        }
    }

    private func gridRow(
        @ViewBuilder cells: @escaping (Int) -> some View,
        @ViewBuilder trailing: () -> some View
    ) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { column in
                cells(column)
                    .frame(maxWidth: .infinity)
                    .frame(height: cellHeight)
            }
            if weekResults != nil {
                trailing()
                    .frame(width: 36, height: cellHeight)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: Space.md) {
            legendItem(label: "Complete") {
                Circle().fill(tint)
            }
            legendItem(label: "Partial") {
                ZStack {
                    Circle().strokeBorder(Color.borderStrong, lineWidth: 1)
                    PieSlice(fraction: 0.5).fill(tint)
                }
            }
            legendItem(label: "Missed") {
                Circle().strokeBorder(Color.borderStrong, lineWidth: 1)
            }
            Spacer()
        }
    }

    private func legendItem(label: String, @ViewBuilder dot: () -> some View) -> some View {
        HStack(spacing: Space.xs) {
            dot().frame(width: 8, height: 8)
            Text(label)
                .font(.captionJ)
                .foregroundStyle(Color.textSecondary)
        }
    }
}

// MARK: - Single day dot

private struct DayDot: View {
    let day: CalendarDay
    let dotSize: CGFloat
    let tint: Color

    var body: some View {
        ZStack {
            switch day.state {
            case .full:
                Circle().fill(tint)
            case .partial(let fraction):
                Circle().strokeBorder(Color.borderStrong, lineWidth: 1)
                PieSlice(fraction: min(max(fraction, 0), 1)).fill(tint)
            case .missed:
                Circle().strokeBorder(Color.borderStrong, lineWidth: 1)
            case .notApplicable:
                Color.clear
            }
        }
        .frame(width: dotSize, height: dotSize)
        .overlay {
            if day.isToday {
                Circle()
                    .strokeBorder(Color.accentPrimary, lineWidth: 1.5)
                    .frame(width: dotSize + 6, height: dotSize + 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Day \(day.day)"))
    }
}

// MARK: - Weekly result cell

private struct WeekResultCell: View {
    let result: WeekResult

    var body: some View {
        switch result {
        case .met:
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.success)
        case .missed:
            Circle()
                .strokeBorder(Color.borderStrong, lineWidth: 1)
                .frame(width: 9, height: 9)
        case .live(let done, let target):
            Text("\(done)/\(target)")
                .font(.monoJ)
                .foregroundStyle(Color.textSecondary)
        }
    }
}

// MARK: - Pie sector shape (exact-fraction partial fill)

struct PieSlice: Shape {
    var fraction: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard fraction > 0 else { return path }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * min(fraction, 1)),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

#Preview("CalendarDotGrid: daily habit") {
    CalendarDotGrid(
        year: 2026,
        month: 7,
        days: (1...31).map { day in
            let state: DotState = switch day % 5 {
            case 0: .missed
            case 1, 2: .full
            case 3: .partial(0.5)
            default: day > 10 ? .full : .notApplicable
            }
            return CalendarDay(day: day, state: day > 10 ? state : .notApplicable, isToday: day == 10)
        }
    )
    .padding()
    .frame(width: 320)
    .background(Color.bgSurface)
}

#Preview("CalendarDotGrid: weekly habit") {
    CalendarDotGrid(
        year: 2026,
        month: 7,
        days: [
            CalendarDay(day: 1, state: .full), CalendarDay(day: 3, state: .full),
            CalendarDay(day: 6, state: .full), CalendarDay(day: 8, state: .full),
            CalendarDay(day: 9, state: .full), CalendarDay(day: 10, state: .full, isToday: true),
        ],
        weekResults: [.met, .live(done: 3, target: 5), .missed, .missed, .missed]
    )
    .padding()
    .frame(width: 340)
    .background(Color.bgSurface)
}
