import DesignSystem
import JarvisAPI
import SwiftUI

/// The consent card (§B3): every AI-proposed mutation renders as a card the
/// user must confirm. Pending = full card with badge + summary + buttons;
/// resolved states compress to a single line.
struct ActionCardView: View {
    let action: ProposedActionDTO
    let isBusy: Bool
    let errorText: String?
    let onConfirm: () -> Void
    let onReject: () -> Void

    var body: some View {
        switch action.status {
        case "executed":
            resolvedLine(
                icon: "checkmark",
                text: action.summary,
                color: .success,
            )
        case "rejected":
            resolvedLine(text: "Dismissed · \(action.summary)", color: .textTertiary)
        case "expired":
            resolvedLine(text: "Expired · \(action.summary)", color: .textTertiary)
        default:
            pendingCard
        }
    }

    // MARK: - Pending

    private var pendingCard: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text(ChatDisplay.badgeLabel(for: action.toolName).uppercased())
                .font(.captionJ)
                .tracking(0.6)
                .foregroundStyle(Color.accentPrimary)
                .padding(.horizontal, Space.sm)
                .padding(.vertical, 3)
                .background(Color.accentSubtle, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))

            Text(action.summary)
                .font(.bodyJ)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let errorText {
                Text(errorText)
                    .font(.captionJ)
                    .foregroundStyle(Color.danger)
            }

            HStack(spacing: Space.sm) {
                Button {
                    onConfirm()
                } label: {
                    HStack(spacing: Space.xs) {
                        if isBusy {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        }
                        Text("Confirm")
                    }
                }
                .buttonStyle(.jarvisPrimary)
                .disabled(isBusy)

                Button("Dismiss", action: onReject)
                    .buttonStyle(.jarvisGhost)
                    .disabled(isBusy)
            }
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.borderHairline, lineWidth: 0.5),
        )
        // Soft shadow only while pending — the one card that may cast one.
        .shadow(color: .black.opacity(0.07), radius: 10, y: 3)
    }

    // MARK: - Resolved

    private func resolvedLine(icon: String? = nil, text: String, color: Color) -> some View {
        HStack(spacing: Space.sm) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(text)
                .font(.subheadJ)
                .foregroundStyle(color)
                .lineLimit(2)
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgSubtle.opacity(0.6), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}
