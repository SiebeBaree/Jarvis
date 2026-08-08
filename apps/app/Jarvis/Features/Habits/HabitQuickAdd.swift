import DesignSystem
import JarvisAPI
import SwiftUI

/// Inline habit composer, always present at the top of the Habits list.
///
/// Creating a habit used to mean: tap +, wait for a sheet, fill a grouped
/// `Form`, wait on a network round-trip, wait for the dismissal. Setting up
/// eight habits was eight of those. Now it is: type a name, press return.
/// Everything else has a sensible default and can be changed later — the
/// habit exists the instant you hit return, because the id is generated here
/// and the write goes to the outbox.
///
/// The chips are the escape hatch for the two decisions that actually change
/// what the habit *is*: how often, and how many.
struct HabitQuickAdd: View {
    let nextColorHex: String
    var onCreate: (HabitCreateRequest) -> Void
    /// "More…" — hands the half-typed draft to the full editor.
    var onOpenEditor: (HabitDraft) -> Void

    @FocusState private var isFocused: Bool
    @State private var name = ""
    @State private var type: HabitType = .daily
    @State private var timesPerDay = 2
    @State private var timesPerWeek = 3
    @State private var symbol = HabitSymbols.defaultSymbol
    @State private var showSymbolPicker = false

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var color: ItemColor { ItemColor.named(nextColorHex) }

    private var target: Int {
        switch type {
        case .daily: 1
        case .multiDaily: timesPerDay
        case .weeklyFrequency: timesPerWeek
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.md) {
                Button {
                    showSymbolPicker = true
                } label: {
                    IconTile(
                        symbol: symbol,
                        color: color,
                        isMuted: trimmed.isEmpty && !isFocused,
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Choose icon")

                TextField("Add a habit", text: $name)
                    .font(.headlineJ)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .submitLabel(.done)
                    .onSubmit(commit)
                    #if os(iOS)
                    .autocorrectionDisabled()
                    #endif

                if !trimmed.isEmpty {
                    Button(action: commit) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(Color.accentPrimary)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: [])
                    .accessibilityLabel("Create habit")
                }
            }

            // Only shown once there is something to configure — an idle
            // composer should look like one line, not a form.
            if isFocused || !trimmed.isEmpty {
                chips
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .jarvisShadow(isFocused ? .raised : .card)
        .jarvisAnimation(Motion.standard, value: isFocused)
        .jarvisAnimation(Motion.standard, value: trimmed.isEmpty)
        .sheet(isPresented: $showSymbolPicker) {
            SymbolPickerSheet(selection: $symbol, tint: color)
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.sm) {
                frequencyChip("Daily", isOn: type == .daily) { type = .daily }
                frequencyChip("\(timesPerDay)×/day", isOn: type == .multiDaily) {
                    if type == .multiDaily {
                        timesPerDay = timesPerDay >= 10 ? 2 : timesPerDay + 1
                    } else {
                        type = .multiDaily
                    }
                }
                frequencyChip("\(timesPerWeek)×/week", isOn: type == .weeklyFrequency) {
                    if type == .weeklyFrequency {
                        timesPerWeek = timesPerWeek >= 7 ? 1 : timesPerWeek + 1
                    } else {
                        type = .weeklyFrequency
                    }
                }

                Divider().frame(height: 18)

                Button("More…") {
                    onOpenEditor(
                        HabitDraft(
                            name: trimmed,
                            symbol: symbol,
                            colorHex: nextColorHex,
                            type: type,
                            targetReps: target,
                        ),
                    )
                    reset()
                }
                .buttonStyle(.jarvisGhost)
            }
            .padding(.leading, 1)
        }
    }

    /// Tapping the selected count chip again bumps the number — the fastest
    /// possible way to say "8 glasses" without opening a stepper.
    private func frequencyChip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.play(.light)
            withJarvisAnimation(Motion.quick) { action() }
        } label: {
            Text(title)
                .font(.microJ)
                .foregroundStyle(isOn ? color.color : Color.textSecondary)
                .padding(.horizontal, Space.md)
                .padding(.vertical, 6)
                .background(isOn ? color.soft : Color.bgSubtle, in: Capsule())
                .contentTransition(.numericText())
        }
        .buttonStyle(.plain)
    }

    private func commit() {
        guard !trimmed.isEmpty else { return }
        Haptics.play(.success)
        onCreate(
            HabitCreateRequest(
                name: trimmed,
                icon: symbol,
                colorHex: nextColorHex,
                type: type,
                targetReps: target,
                plannedDays: type == .weeklyFrequency ? [] : nil,
            ),
        )
        // Stay open with the frequency intact: setting up a tracker means
        // adding several habits in a row, and they are usually the same shape.
        name = ""
        symbol = HabitSymbols.defaultSymbol
        isFocused = true
    }

    private func reset() {
        name = ""
        symbol = HabitSymbols.defaultSymbol
        type = .daily
        isFocused = false
    }
}

/// What quick-add hands to the full editor when you outgrow one line.
struct HabitDraft: Identifiable {
    let id = UUID()
    var name: String = ""
    var symbol: String = HabitSymbols.defaultSymbol
    var colorHex: String = ItemColor.indigo.hexString
    var type: HabitType = .daily
    var targetReps: Int = 1
}
