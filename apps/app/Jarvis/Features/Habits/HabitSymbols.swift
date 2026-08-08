import DesignSystem
import SwiftUI

/// The curated SF Symbol set habits pick from, grouped so the grid can be
/// browsed rather than scanned. Grouping matters more than it sounds: a flat
/// 44-glyph wall is a puzzle, and picking an icon is supposed to take a
/// second.
enum HabitSymbols {
    static let defaultSymbol = "circle.dashed"

    struct Group: Identifiable {
        let id: String
        let symbols: [String]
    }

    static let groups: [Group] = [
        Group(id: "Movement", symbols: [
            "figure.run", "figure.walk", "figure.strengthtraining.traditional",
            "dumbbell.fill", "figure.mind.and.body", "figure.flexibility",
            "figure.pool.swim", "bicycle", "figure.hiking", "sportscourt.fill",
        ]),
        Group(id: "Food & body", symbols: [
            "drop.fill", "fork.knife", "carrot.fill", "cup.and.saucer.fill",
            "pills.fill", "cross.case.fill", "leaf.fill", "flame.fill",
            "scalemass.fill", "mouth.fill",
        ]),
        Group(id: "Rest", symbols: [
            "bed.double.fill", "alarm.fill", "moon.fill", "moon.stars.fill",
            "sun.max.fill", "sunrise.fill", "shower.fill", "comb.fill",
        ]),
        Group(id: "Mind", symbols: [
            "book.fill", "books.vertical.fill", "graduationcap.fill",
            "brain.head.profile", "pencil", "text.book.closed.fill",
            "lightbulb.fill", "headphones",
        ]),
        Group(id: "Work", symbols: [
            "laptopcomputer", "briefcase.fill", "chart.line.uptrend.xyaxis",
            "dollarsign.circle.fill", "checklist", "calendar", "hammer.fill",
            "envelope.fill",
        ]),
        Group(id: "People & play", symbols: [
            "phone.fill", "message.fill", "person.2.fill", "heart.fill",
            "face.smiling", "hands.and.sparkles.fill", "music.note",
            "camera.fill", "paintbrush.fill", "gamecontroller.fill",
        ]),
    ]

    static let all: [String] = groups.flatMap(\.symbols)
}

/// Icon picker. Shared by quick-add and the full editor so the two never
/// drift apart.
struct SymbolPickerSheet: View {
    @Binding var selection: String
    var tint: ItemColor = .indigo

    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Space.sm), count: 5)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    ForEach(HabitSymbols.groups) { group in
                        VStack(alignment: .leading, spacing: Space.sm) {
                            CaptionLabel(group.id)
                            LazyVGrid(columns: columns, spacing: Space.sm) {
                                ForEach(group.symbols, id: \.self) { symbol in
                                    cell(symbol)
                                }
                            }
                        }
                    }
                }
                .padding(PageMargin.standard)
            }
            .background(Color.bgCanvas)
            .navigationTitle("Icon")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 480)
        #endif
    }

    private func cell(_ symbol: String) -> some View {
        let isSelected = symbol == selection
        return Button {
            Haptics.play(.light)
            selection = symbol
            dismiss()
        } label: {
            IconTile(symbol: symbol, color: tint, size: 52, isMuted: !isSelected)
                .overlay {
                    RoundedRectangle(cornerRadius: 52 * 0.29, style: .continuous)
                        .strokeBorder(tint.color, lineWidth: isSelected ? 2 : 0)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Twelve-swatch colour row. Habits had no colour picker at all before, so
/// every habit rendered in the same indigo and a list of them was unreadable
/// at a glance.
struct ColorPickerRow: View {
    @Binding var selection: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.md) {
                ForEach(ItemColor.palette) { item in
                    let isSelected = item.hexString.caseInsensitiveCompare(selection) == .orderedSame
                    Button {
                        Haptics.play(.light)
                        withJarvisAnimation(Motion.quick) { selection = item.hexString }
                    } label: {
                        Circle()
                            .fill(item.color)
                            .frame(width: 30, height: 30)
                            .overlay {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                                    .opacity(isSelected ? 1 : 0)
                            }
                            .overlay {
                                Circle()
                                    .strokeBorder(item.color.opacity(0.35), lineWidth: 3)
                                    .padding(-4)
                                    .opacity(isSelected ? 1 : 0)
                            }
                            .scaleEffect(isSelected ? 1.05 : 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.displayName)
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.vertical, Space.xs)
            .padding(.horizontal, 4)
        }
    }
}
