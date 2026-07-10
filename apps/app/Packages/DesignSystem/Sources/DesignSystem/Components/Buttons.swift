import SwiftUI

// MARK: - Primary (accent fill, white text, 36 pt, radius 8)

public struct PrimaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headlineJ)
            .foregroundStyle(.white)
            .padding(.horizontal, Space.lg)
            .frame(minHeight: 36)
            .background(
                Color.accentPrimary,
                in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Secondary (surface + hairline border)

public struct SecondaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headlineJ)
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, Space.lg)
            .frame(minHeight: 36)
            .background(
                configuration.isPressed ? Color.bgHover : Color.bgSurface,
                in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(Color.borderHairline, lineWidth: 0.5)
            )
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
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
            .frame(minHeight: 36)
            .background(
                configuration.isPressed ? Color.bgHover : Color.clear,
                in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            )
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Dot-syntax conveniences

public extension ButtonStyle where Self == PrimaryButtonStyle {
    static var jarvisPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

public extension ButtonStyle where Self == SecondaryButtonStyle {
    static var jarvisSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

public extension ButtonStyle where Self == GhostButtonStyle {
    static var jarvisGhost: GhostButtonStyle { GhostButtonStyle() }
}

#Preview("Buttons") {
    VStack(spacing: Space.lg) {
        Button("Approve plan") {}.buttonStyle(.jarvisPrimary)
        Button("Save & exit") {}.buttonStyle(.jarvisSecondary)
        Button("+ Add task") {}.buttonStyle(.jarvisGhost)
    }
    .padding()
    .background(Color.bgCanvas)
}
