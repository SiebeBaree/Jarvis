import DesignSystem
import JarvisAPI
import SwiftUI

/// The active interview round: 1–3 questions, each with option rows / scale /
/// free text plus the always-available "✎ Write my own" row (§B6).
struct QuestionCardView: View {
    let round: InterviewRoundDTO
    let store: OnboardingStore

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxxl) {
            ForEach(round.questions) { question in
                QuestionView(question: question, draft: binding(for: question.id))
            }
        }
    }

    private func binding(for id: String) -> Binding<OnboardingStore.AnswerDraft> {
        Binding(
            get: { store.drafts[id] ?? OnboardingStore.AnswerDraft() },
            set: { store.drafts[id] = $0 },
        )
    }
}

// MARK: - Single question

private struct QuestionView: View {
    let question: InterviewQuestionDTO
    @Binding var draft: OnboardingStore.AnswerDraft
    @FocusState private var freeTextFocused: Bool

    private var isSingle: Bool { question.type == "single_choice" || question.type == "scale" }
    private var isMulti: Bool { question.type == "multi_choice" }
    private var isFreeTextOnly: Bool { question.type == "free_text" }
    private var options: [String] { question.options ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            header
            if draft.skipped {
                skippedRow
            } else {
                inputs
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            if question.isFollowUp {
                Text("FOLLOW-UP")
                    .font(.captionJ)
                    .tracking(0.6)
                    .foregroundStyle(Color.accentPrimary)
                    .padding(.horizontal, Space.sm)
                    .padding(.vertical, 2)
                    .background(Color.accentSubtle, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
            }
            Text(question.question)
                .font(.title2J)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let rationale = question.rationale, !rationale.isEmpty {
                Text(rationale)
                    .font(.subheadJ)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if isMulti {
                Text("Select all that apply")
                    .font(.captionJ)
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }

    // MARK: Inputs

    @ViewBuilder
    private var inputs: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            if question.type == "scale" {
                scaleRow
            } else if !isFreeTextOnly {
                ForEach(options, id: \.self) { option in
                    optionRow(option)
                }
            }
            if isFreeTextOnly {
                freeTextEditor
            } else {
                writeMyOwnRow
            }
            if question.skippable {
                Button("Skip") {
                    withAnimation(.easeOut(duration: 0.25)) {
                        draft.skipped = true
                        freeTextFocused = false
                    }
                }
                .buttonStyle(.plain)
                .font(.subheadJ)
                .foregroundStyle(Color.textTertiary)
                .padding(.top, Space.xs)
            }
        }
    }

    private var skippedRow: some View {
        HStack(spacing: Space.sm) {
            Text("Skipped")
                .font(.subheadJ)
                .foregroundStyle(Color.textTertiary)
            Button("Answer instead") {
                withAnimation(.easeOut(duration: 0.25)) {
                    draft.skipped = false
                }
            }
            .buttonStyle(.plain)
            .font(.subheadJ)
            .foregroundStyle(Color.accentPrimary)
        }
        .padding(.vertical, Space.xs)
    }

    // MARK: Choice rows

    private func optionRow(_ option: String) -> some View {
        let selected = draft.selected.contains(option)
        return Button {
            select(option)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Space.md) {
                Image(systemName: indicatorSymbol(selected: selected))
                    .font(.system(size: 16))
                    .foregroundStyle(selected ? Color.accentPrimary : Color.textTertiary)
                Text(option)
                    .font(.bodyJ)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(selected ? Color.accentPrimary : Color.borderHairline, lineWidth: selected ? 1 : 0.5)
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func indicatorSymbol(selected: Bool) -> String {
        if isMulti {
            selected ? "checkmark.square.fill" : "square"
        } else {
            selected ? "checkmark.circle.fill" : "circle"
        }
    }

    /// Scale options render as one horizontal segmented row.
    private var scaleRow: some View {
        HStack(spacing: Space.xs) {
            ForEach(options, id: \.self) { option in
                let selected = draft.selected.contains(option)
                Button {
                    select(option)
                } label: {
                    Text(option)
                        .font(.subheadJ)
                        .foregroundStyle(selected ? .white : Color.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    selected ? Color.accentPrimary : Color.bgSurface,
                    in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous),
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .strokeBorder(selected ? Color.accentPrimary : Color.borderHairline, lineWidth: 0.5)
                )
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private func select(_ option: String) {
        withAnimation(.easeOut(duration: 0.15)) {
            if isMulti {
                if let index = draft.selected.firstIndex(of: option) {
                    draft.selected.remove(at: index)
                } else {
                    draft.selected.append(option)
                }
            } else {
                // Single choice / scale: picking an option clears free text.
                draft.selected = [option]
                draft.freeTextActive = false
                draft.freeText = ""
                freeTextFocused = false
            }
        }
    }

    // MARK: Write my own

    private var writeMyOwnRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    if draft.freeTextActive {
                        draft.freeTextActive = false
                        draft.freeText = ""
                        freeTextFocused = false
                    } else {
                        draft.freeTextActive = true
                        if isSingle {
                            // Free text clears the selection for single choice.
                            draft.selected = []
                        }
                        freeTextFocused = true
                    }
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: Space.md) {
                    Image(systemName: "pencil")
                        .font(.system(size: 15))
                        .foregroundStyle(draft.freeTextActive ? Color.accentPrimary : Color.textTertiary)
                    Text("Write my own")
                        .font(.bodyJ)
                        .foregroundStyle(Color.textPrimary)
                    Spacer(minLength: 0)
                }
                .padding(Space.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if draft.freeTextActive {
                freeTextField
                    .padding(.horizontal, Space.md)
                    .padding(.bottom, Space.md)
            }
        }
        .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(
                    draft.freeTextActive ? Color.accentPrimary : Color.borderHairline,
                    lineWidth: draft.freeTextActive ? 1 : 0.5,
                )
        )
    }

    /// free_text questions show the editor directly, no toggle row.
    private var freeTextEditor: some View {
        freeTextField
            .padding(Space.md)
            .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(freeTextFocused ? Color.accentPrimary : Color.borderHairline, lineWidth: freeTextFocused ? 1 : 0.5)
            )
    }

    private var freeTextField: some View {
        TextField("Your answer…", text: $draft.freeText, axis: .vertical)
            .font(.bodyJ)
            .foregroundStyle(Color.textPrimary)
            .lineLimit(3...8)
            .textFieldStyle(.plain)
            .focused($freeTextFocused)
    }
}
