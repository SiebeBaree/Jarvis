import SwiftUI

// MARK: - Shared press behaviour
//
// Every button style scales slightly under the finger. Uniform across the app
// so a button always confirms the touch before the action lands — which is
// what makes a slow network feel fast.

private struct PressScale: ViewModifier {
    let isPressed: Bool
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? scale : 1)
            .jarvisAnimation(Motion.quick, value: isPressed)
    }
}

// MARK: - Primary (accent fill)

public struct PrimaryButtonStyle: ButtonStyle {
    private let isProminent: Bool

    public init(prominent: Bool = false) {
        self.isProminent = prominent
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headlineJ)
            .foregroundStyle(.white)
            .padding(.horizontal, Space.xl)
            .frame(minHeight: 46)
            .frame(maxWidth: isProminent ? .infinity : nil)
            .background(
                Color.accentPrimary,
                in: RoundedRectangle(cornerRadius: Radius.control + 2, style: .continuous)
            )
            .jarvisShadow(configuration.isPressed ? .card : .raised)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .modifier(PressScale(isPressed: configuration.isPressed, scale: 0.97))
    }
}

// MARK: - Secondary (surface + border)

public struct SecondaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headlineJ)
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, Space.xl)
            .frame(minHeight: 46)
            .background(
                configuration.isPressed ? Color.bgHover : Color.bgSurface,
                in: RoundedRectangle(cornerRadius: Radius.control + 2, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control + 2, style: .continuous)
                    .strokeBorder(Color.borderHairline, lineWidth: 1)
            )
            .modifier(PressScale(isPressed: configuration.isPressed, scale: 0.97))
    }
}

// MARK: - Ghost (no chrome, accent text)

public struct GhostButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headlineJ)
            .foregroundStyle(Color.accentPrimary)
            .padding(.horizontal, Space.md)
            .frame(minHeight: 38)
            .background(
                configuration.isPressed ? Color.accentSubtle : Color.clear,
                in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            )
            .modifier(PressScale(isPressed: configuration.isPressed, scale: 0.97))
    }
}

// MARK: - Soft (tinted fill, no border) — the "secondary action inside a card"

public struct SoftButtonStyle: ButtonStyle {
    private let tint: Color

    public init(tint: Color = .accentPrimary) {
        self.tint = tint
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadStrongJ)
            .foregroundStyle(tint)
            .padding(.horizontal, Space.md)
            .frame(minHeight: 32)
            .background(
                tint.opacity(configuration.isPressed ? 0.24 : 0.14),
                in: Capsule()
            )
            .modifier(PressScale(isPressed: configuration.isPressed, scale: 0.95))
    }
}

// MARK: - Icon button — toolbar-weight control that keeps a 44 pt target

public struct IconButtonStyle: ButtonStyle {
    private let tint: Color
    private let filled: Bool

    public init(tint: Color = .textSecondary, filled: Bool = false) {
        self.tint = tint
        self.filled = filled
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 36, height: 36)
            .background(
                filled || configuration.isPressed ? Color.bgSubtle : Color.clear,
                in: Circle()
            )
            .frame(width: RowHeight.tapTarget, height: RowHeight.tapTarget)
            .contentShape(Circle())
            .modifier(PressScale(isPressed: configuration.isPressed, scale: 0.92))
    }
}

// MARK: - Dot-syntax conveniences

public extension ButtonStyle where Self == PrimaryButtonStyle {
    static var jarvisPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
    /// Full-width — pinned footers, empty-state CTAs.
    static var jarvisProminent: PrimaryButtonStyle { PrimaryButtonStyle(prominent: true) }
}

public extension ButtonStyle where Self == SecondaryButtonStyle {
    static var jarvisSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

public extension ButtonStyle where Self == GhostButtonStyle {
    static var jarvisGhost: GhostButtonStyle { GhostButtonStyle() }
}

public extension ButtonStyle where Self == SoftButtonStyle {
    static var jarvisSoft: SoftButtonStyle { SoftButtonStyle() }
    static func jarvisSoft(_ tint: Color) -> SoftButtonStyle { SoftButtonStyle(tint: tint) }
}

public extension ButtonStyle where Self == IconButtonStyle {
    static var jarvisIcon: IconButtonStyle { IconButtonStyle() }
    static func jarvisIcon(tint: Color = .textSecondary, filled: Bool = false) -> IconButtonStyle {
        IconButtonStyle(tint: tint, filled: filled)
    }
}

#Preview("Buttons") {
    VStack(spacing: Space.lg) {
        Button("Create habit") {}.buttonStyle(.jarvisPrimary)
        Button("Save changes") {}.buttonStyle(.jarvisProminent)
        Button("Cancel") {}.buttonStyle(.jarvisSecondary)
        Button("Add task") {}.buttonStyle(.jarvisGhost)
        HStack {
            Button("Undo") {}.buttonStyle(.jarvisSoft)
            Button("Skip") {}.buttonStyle(.jarvisSoft(ItemColor.amber.color))
        }
        HStack {
            Button { } label: { Image(systemName: "gearshape") }.buttonStyle(.jarvisIcon)
            Button { } label: { Image(systemName: "plus") }.buttonStyle(.jarvisIcon(tint: .accentPrimary, filled: true))
        }
    }
    .padding()
    .background(Color.bgCanvas)
}
