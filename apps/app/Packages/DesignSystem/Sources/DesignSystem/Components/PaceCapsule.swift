import SwiftUI

// MARK: - Weekly habit pace indicator
//
// n segments (the weekly target) filling left-to-right in the habit's colour,
// with a thin tick at "where you should be by tonight". Status reads On pace ·
// N behind · Week done · Out of reach.
//
// NEVER red. Missing a planned day is not a failure in this app — only the
// weekly total counts, and the whole point of the indicator is to say "you can
// still make it", not "you blew it".

public enum PaceDisplayStatus: Equatable, Sendable {
    case onPace
    case behind(Int)
    case weekDone
    case outOfReach
}

public struct PaceCapsule: View {
    private let target: Int
    private let done: Int
    private let expectedByTonight: Double
    private let status: PaceDisplayStatus
    private let tint: Color

    public init(
        target: Int,
        done: Int,
        expectedByTonight: Double,
        status: PaceDisplayStatus,
        tint: Color = .success
    ) {
        self.target = max(target, 1)
        self.done = min(max(done, 0), max(target, 1))
        self.expectedByTonight = min(max(expectedByTonight, 0), Double(max(target, 1)))
        self.status = status
        self.tint = tint
    }

    private let segmentHeight: CGFloat = 6
    private let segmentSpacing: CGFloat = 3

    private func segmentColor(at index: Int) -> Color {
        if index < done { return tint }
        if case .behind = status, Double(index) < expectedByTonight {
            return .warning.opacity(0.28)
        }
        return .bgSubtle
    }

    private var showsTick: Bool {
        status != .weekDone && expectedByTonight > 0 && expectedByTonight < Double(target)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            segments
            statusLine
        }
        .jarvisAnimation(Motion.gauge, value: done)
    }

    private var segments: some View {
        HStack(spacing: segmentSpacing) {
            ForEach(0..<target, id: \.self) { index in
                Capsule()
                    .fill(segmentColor(at: index))
                    .frame(height: segmentHeight)
            }
        }
        .overlay {
            if showsTick {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.textTertiary)
                        .frame(width: 2, height: segmentHeight + 5)
                        .position(
                            x: proxy.size.width * expectedByTonight / Double(target),
                            y: proxy.size.height / 2
                        )
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(done) of \(target) this week"))
    }

    @ViewBuilder
    private var statusLine: some View {
        HStack(spacing: Space.xs) {
            Text("\(done)/\(target)")
                .font(.microJ)
                .monospacedDigit()
                .foregroundStyle(Color.textSecondary)
            Text("·").font(.microJ).foregroundStyle(Color.textTertiary)
            switch status {
            case .onPace:
                Text("On pace").font(.microJ).foregroundStyle(tint)
            case .behind(let n):
                Text("\(n) behind").font(.microJ).foregroundStyle(Color.warning)
            case .weekDone:
                Text("Week done").font(.microJ).foregroundStyle(tint)
            case .outOfReach:
                Text("Out of reach").font(.microJ).foregroundStyle(Color.textTertiary)
            }
        }
    }
}

#Preview("PaceCapsule") {
    VStack(alignment: .leading, spacing: Space.xl) {
        PaceCapsule(target: 5, done: 3, expectedByTonight: 2.9, status: .onPace, tint: ItemColor.green.color)
        PaceCapsule(target: 5, done: 1, expectedByTonight: 3, status: .behind(2), tint: ItemColor.blue.color)
        PaceCapsule(target: 5, done: 5, expectedByTonight: 4, status: .weekDone, tint: ItemColor.violet.color)
        PaceCapsule(target: 6, done: 1, expectedByTonight: 5, status: .outOfReach)
        PaceCapsule(target: 3, done: 2, expectedByTonight: 1.7, status: .onPace, tint: ItemColor.orange.color)
    }
    .padding()
    .frame(width: 240)
    .background(Color.bgCanvas)
}
