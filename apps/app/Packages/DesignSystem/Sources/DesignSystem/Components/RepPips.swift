import SwiftUI

// MARK: - Multi-rep habit pips (spec §B5.2)
//
// Up to 10 8 pt circles filling left-to-right plus a mono fraction ("1/2").

public struct RepPips: View {
    private let done: Int
    private let target: Int

    public init(done: Int, target: Int) {
        self.target = max(target, 1)
        self.done = min(max(done, 0), max(target, 1))
    }

    private let pipSize: CGFloat = 8

    public var body: some View {
        HStack(spacing: Space.sm) {
            HStack(spacing: Space.xs) {
                ForEach(0..<min(target, 10), id: \.self) { index in
                    if index < done {
                        Circle()
                            .fill(Color.success)
                            .frame(width: pipSize, height: pipSize)
                    } else {
                        Circle()
                            .strokeBorder(Color.borderStrong, lineWidth: 1)
                            .frame(width: pipSize, height: pipSize)
                    }
                }
            }
            Text("\(done)/\(target)")
                .font(.monoJ)
                .foregroundStyle(Color.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(done) of \(target) today"))
    }
}

#Preview("RepPips") {
    VStack(alignment: .leading, spacing: Space.lg) {
        RepPips(done: 1, target: 2)
        RepPips(done: 0, target: 3)
        RepPips(done: 3, target: 3)
        RepPips(done: 6, target: 10)
    }
    .padding()
    .background(Color.bgCanvas)
}
