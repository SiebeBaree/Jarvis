import DesignSystem
import SwiftUI

/// Progress: the one place that answers "how is this going".
///
/// Goals, Trends, Body metrics and the improvement-area check-ins used to be
/// four separate destinations — two sidebar rows nobody clicked and two
/// unlabelled glyphs in Today's toolbar. They are all the same question asked
/// over different horizons, so they are now segments of one surface.
struct ProgressHubView: View {
    enum Segment: String, CaseIterable, Hashable {
        case trends
        case goals
        case body
        case improve

        var title: String {
            switch self {
            case .trends: "Trends"
            case .goals: "Goals"
            case .body: "Body"
            case .improve: "Improve"
            }
        }
    }

    @State private var segment: Segment = .trends

    var body: some View {
        content
            .background(Color.bgCanvas)
            .navigationTitle("Progress")
            #if os(iOS)
            // Inline: the segment chips directly below already name the page,
            // and a large title left an empty band above them.
            .navigationBarTitleDisplayMode(.inline)
            #endif
            // The picker lives in the window toolbar on macOS and in a top
            // safe-area inset on iOS. Both keep it visible in *every* load
            // state — passing it into each child as a first scrolling row
            // meant it vanished behind a spinner, stranding you in a segment
            // you could not leave.
            #if os(macOS)
            .toolbar {
                ToolbarItem(placement: .principal) { picker }
            }
            #else
            .safeAreaInset(edge: .top, spacing: 0) {
                picker
                    .padding(.horizontal, PageMargin.standard)
                    .padding(.top, Space.xs)
                    .padding(.bottom, Space.sm)
                    .background(Color.bgCanvas)
            }
            #endif
    }

    @ViewBuilder
    private var content: some View {
        switch segment {
        case .trends: TrendsView()
        case .goals: GoalsView()
        case .body: MetricsView()
        case .improve: ImproveView()
        }
    }

    private var picker: some View {
        ChipPicker(Segment.allCases, selection: $segment, fillsWidth: fillsWidth) { $0.title }
    }

    private var fillsWidth: Bool {
        #if os(macOS)
        false
        #else
        true
        #endif
    }
}
