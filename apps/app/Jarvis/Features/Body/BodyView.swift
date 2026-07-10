import DesignSystem
import SwiftUI

/// Body (§B3): segmented Metrics · Photos.
struct BodyView: View {
    private enum Tab: String, CaseIterable {
        case metrics = "Metrics"
        case photos = "Photos"
    }

    @State private var tab: Tab = .metrics

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, PageMargin.standard)
            .padding(.vertical, Space.sm)

            switch tab {
            case .metrics:
                MetricsView()
            case .photos:
                PhotosView()
            }
        }
        .background(Color.bgCanvas)
        .navigationTitle("Body")
    }
}
