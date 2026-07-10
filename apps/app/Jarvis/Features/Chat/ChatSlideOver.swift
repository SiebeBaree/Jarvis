import DesignSystem
import SwiftUI

// macOS chat slide-over (⇧⌘J): a 360 pt trailing panel with a compact chat
// that keeps its own conversation, independent from the Chat tab. No-op on iOS.

#if os(macOS)

extension View {
    /// Attaches the ⇧⌘J chat slide-over panel to this view hierarchy.
    func chatSlideOver() -> some View {
        modifier(ChatSlideOverModifier())
    }
}

private struct ChatSlideOverModifier: ViewModifier {
    @State private var isOpen = false
    @State private var showHistory = false
    @State private var store = ChatStore()

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .trailing) {
                if isOpen {
                    panel
                        .transition(.move(edge: .trailing))
                }
            }
            .animation(.easeOut(duration: 0.22), value: isOpen)
            .background(
                // Hidden toggle carrying the global keyboard shortcut.
                Button("Toggle chat panel") {
                    isOpen.toggle()
                }
                .keyboardShortcut("j", modifiers: [.command, .shift])
                .hidden(),
            )
    }

    private var panel: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .overlay(Color.borderHairline)
            ChatView(store: store)
        }
        .frame(width: 360)
        .frame(maxHeight: .infinity)
        .background(Color.bgSurface)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.borderHairline)
                .frame(width: 0.5)
        }
    }

    private var header: some View {
        HStack(spacing: Space.sm) {
            Circle()
                .fill(Color.accentPrimary)
                .frame(width: 14, height: 14)
            Text("Jarvis")
                .font(.headlineJ)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            Button {
                store.newConversation()
            } label: {
                Image(systemName: "square.and.pencil")
                    .foregroundStyle(Color.textSecondary)
            }
            .buttonStyle(.plain)
            .help("New conversation")
            .accessibilityLabel("New conversation")
            Button {
                showHistory = true
            } label: {
                Image(systemName: "clock")
                    .foregroundStyle(Color.textSecondary)
            }
            .buttonStyle(.plain)
            .help("History")
            .accessibilityLabel("Conversation history")
            .sheet(isPresented: $showHistory) {
                ConversationListView { id in
                    Task { await store.loadConversation(id: id) }
                }
                .frame(minWidth: 420, minHeight: 460)
            }
            Button {
                isOpen = false
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(Color.textSecondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close (⇧⌘J)")
            .accessibilityLabel("Close chat panel")
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
    }
}

#else

extension View {
    /// The chat slide-over is macOS-only; on iOS this is a no-op.
    func chatSlideOver() -> some View {
        self
    }
}

#endif
