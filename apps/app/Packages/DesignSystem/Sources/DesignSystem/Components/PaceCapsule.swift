import SwiftUI

// MARK: - Weekly habit pace indicator (spec §B5.2)
//
// n segments (weekly target) filling green left-to-right, with a thin
// vertical pace tick at expected/target ("where you should be by tonight").
// Status chip: On pace (success) · N behind (warning) · Week ✓ (solid) ·
// Out of reach (gray). NEVER red.

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

    public init(target: Int, done: Int, expectedByTonight: Double, status: PaceDisplayStatus) {
        self.target = max(target, 1)
        self.done = min(max(done, 0), max(target, 1))
        self.expectedByTonight = min(max(expectedByTonight, 0), Double(max(target, 1)))
        self.status = status
    }

    private let segmentHeight: CGFloat = 8
    private let segmentSpacing: CGFloat = 2

    private func segmentColor(at index: Int) -> Color {
        if index < done {
            return .success
        }
        // When behind, tint the missing segments up to the pace tick with warning.
        if case .behind = status, Double(index) < expectedByTonight {
            return .warning.opacity(0.3)
        }
        return .bgSubtle
    }

    private var showsTick: Bool {
        status != .weekDone && expectedByTonight > 0 && expectedByTonight < Double(target)
    }

    public var body: some View {
        HStack(spacing: Space.md) {
            segments
            statusChip
        }
    }

    private var segments: some View {
        HStack(spacing: segmentSpacing) {
            ForEach(0..<target, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(segmentColor(at: index))
                    .frame(height: segmentHeight)
            }
        }
        .clipShape(Capsule())
        .overlay {
            if showsTick {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(Color.borderStrong)
                        .frame(width: 1.5, height: segmentHeight + 6)
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
    private var statusChip: some View {
        switch status {
        case .onPace:
            Text("On pace")
                .font(.captionJ)
                .foregroundStyle(Color.success)
        case .behind(let n):
            Text("\(n) behind")
                .font(.captionJ)
                .foregroundStyle(Color.warning)
        case .weekDone:
            Text("Week ✓")
                .font(.captionJ)
                .foregroundStyle(.white)
                .padding(.horizontal, Space.sm)
                .padding(.vertical, 2)
                .background(Color.success, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
        case .outOfReach:
            Text("Out of reach")
                .font(.captionJ)
                .foregroundStyle(Color.textSecondary)
        }
    }
}

#Preview("PaceCapsule") {
    VStack(alignment: .leading, spacing: Space.xl) {
        PaceCapsule(target: 5, done: 3, expectedByTonight: 2.9, status: .onPace)
        PaceCapsule(target: 5, done: 1, expectedByTonight: 3, status: .behind(2))
        PaceCapsule(target: 5, done: 5, expectedByTonight: 4, status: .weekDone)
        PaceCapsule(target: 6, done: 1, expectedByTonight: 5, status: .outOfReach)
        PaceCapsule(target: 3, done: 2, expectedByTonight: 1.7, status: .onPace)
    }
    .padding()
    .frame(width: 320)
    .background(Color.bgCanvas)
}
