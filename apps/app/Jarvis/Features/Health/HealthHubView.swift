import DesignSystem
import SwiftUI

/// Health: the body-and-kitchen tab.
///
/// Three surfaces that belong together in practice — you train, you cook for
/// it, and you buy what the cooking needs — behind one picker, structured
/// exactly like the Progress hub so there is one way segments work in this app
/// rather than two. The stores live here rather than in the segment views so
/// switching segments does not throw away a loaded list, and so a meal prep
/// can push its ingredients straight onto the shopping list next door.
struct HealthHubView: View {
    enum Segment: String, CaseIterable, Hashable {
        case train
        case meals
        case shop

        var title: String {
            switch self {
            case .train: "Train"
            case .meals: "Meals"
            case .shop: "Shop"
            }
        }
    }

    @State private var segment: Segment = .train
    @State private var workouts = WorkoutsStore()
    @State private var meals = MealsStore()
    @State private var shopping = ShoppingStore()

    var body: some View {
        content
            .background(Color.bgCanvas)
            .navigationTitle("Health")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            // Same placement rule as Progress: in the window toolbar on macOS
            // (a fixed region under the title makes the toolbar paint its
            // permanent opaque band), a top safe-area inset on iOS. Both keep
            // the picker visible in every load state.
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
        case .train: TrainView(store: workouts)
        case .meals: MealsView(store: meals, shopping: shopping)
        case .shop: ShoppingListView(store: shopping)
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
