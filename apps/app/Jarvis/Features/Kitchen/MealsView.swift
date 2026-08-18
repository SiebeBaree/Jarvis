import DesignSystem
import JarvisAPI
import SwiftUI

private struct MealRoute: Hashable, Identifiable {
    let mealId: String
    var id: String { mealId }
}

/// The meal prep cookbook. A grid rather than a list because the photo is the
/// point: you scroll this to remember what a batch actually looked like, and a
/// 40 pt thumbnail on a list row cannot do that.
struct MealsView: View {
    @Environment(AppModel.self) private var model

    let store: MealsStore
    let shopping: ShoppingStore

    @State private var showEditor = false
    @State private var route: MealRoute?

    private var columns: [GridItem] {
        #if os(macOS)
        [GridItem(.adaptive(minimum: 240, maximum: 340), spacing: Space.lg)]
        #else
        [GridItem(.flexible(), spacing: Space.md), GridItem(.flexible(), spacing: Space.md)]
        #endif
    }

    var body: some View {
        Group {
            if store.meals.isEmpty {
                switch store.state {
                case .loading, .idle:
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let message):
                    failure(message)
                case .loaded:
                    emptyState
                }
            } else {
                grid
            }
        }
        .background(Color.bgCanvas)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showEditor = true
                } label: {
                    Label("New meal prep", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            MealPrepEditorView(store: store)
        }
        .navigationDestination(item: $route) { route in
            MealPrepDetailView(mealId: route.mealId, store: store, shopping: shopping)
        }
        .task {
            store.bind(model)
            shopping.bind(model)
            await store.load()
        }
        .onChange(of: model.dataRevision) {
            Task { await store.load() }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Space.md) {
                ForEach(store.meals) { meal in
                    MealCard(meal: meal)
                        .pressable { route = MealRoute(mealId: meal.id) }
                }
            }
            .padding(.horizontal, PageMargin.standard)
            .padding(.vertical, Space.md)
            #if os(macOS)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
            #endif
        }
        .refreshable { await store.load(force: true) }
    }

    private var emptyState: some View {
        EmptyState(
            symbol: "fork.knife",
            title: "No meal preps yet",
            message: "Save a batch that worked: what goes in it, how you make it, and the macros. Next time you only have to cook it.",
            tint: ItemColor.orange.color,
        ) {
            Button("Add your first meal prep") { showEditor = true }
                .buttonStyle(.jarvisPrimary)
        }
        .frame(maxHeight: .infinity)
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: Space.lg) {
            Text(message)
                .font(.bodyJ)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await store.load(force: true) } }
                .buttonStyle(.jarvisSecondary)
        }
        .padding(Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Card

struct MealCard: View {
    let meal: MealPrepDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MealPhoto(url: meal.photoUrl, height: 118, cornerRadius: 0)

            VStack(alignment: .leading, spacing: Space.xs) {
                Text(meal.name)
                    .font(.headlineJ)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: Space.sm) {
                    if let minutes = meal.prepMinutes {
                        TagChip("\(minutes) min", symbol: "clock")
                    }
                    TagChip("\(meal.portions)×", symbol: "square.grid.2x2")
                }

                if let calories = meal.perPortion.calories {
                    Text("\(Int(calories.rounded())) kcal · \(macroLine)")
                        .font(.microJ)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.borderHairline, lineWidth: 0.5),
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .jarvisShadow(.card)
    }

    /// Protein first — it is the number the user actually tracks.
    private var macroLine: String {
        guard let protein = meal.perPortion.proteinG else { return "per portion" }
        return "\(Int(protein.rounded())) g protein"
    }
}

/// The photo, or a tinted placeholder that still looks deliberate.
///
/// The height is taken here rather than applied by the caller: `scaledToFill`
/// overflows its frame, so the clip has to come *after* the size is known.
/// Constraining it from outside clipped the natural (much taller) image and
/// let it paint over whatever followed.
struct MealPhoto: View {
    let url: String?
    let height: CGFloat
    var cornerRadius: CGFloat = Radius.card

    var body: some View {
        Group {
            if let url, let parsed = URL(string: url) {
                AsyncImage(url: parsed) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholder(symbol: "photo")
                    default:
                        placeholder(symbol: nil).overlay(ProgressView().controlSize(.small))
                    }
                }
            } else {
                placeholder(symbol: "fork.knife")
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private func placeholder(symbol: String?) -> some View {
        ItemColor.orange.soft.overlay {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(ItemColor.orange.color.opacity(0.7))
            }
        }
    }
}
