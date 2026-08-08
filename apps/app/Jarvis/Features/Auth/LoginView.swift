import DesignSystem
import SwiftUI

/// Sign in / create account.
///
/// With the account wiped this is the app's first impression, and it used to
/// be a wordmark over three gray boxes. It now carries the same mark as the
/// launch screen and the same field, button and motion language as everything
/// behind it.
struct LoginView: View {
    @Environment(AppModel.self) private var model

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isRegistering = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    @FocusState private var focus: Field?
    private enum Field { case email, password, confirm }

    private var canSubmit: Bool {
        !isSubmitting && !email.isEmpty && !password.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Space.xxl) {
                header
                form
                toggle
            }
            .frame(maxWidth: 380)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, PageMargin.standard)
            .padding(.vertical, Space.xxxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color.bgCanvas)
        .jarvisAnimation(Motion.smooth, value: isRegistering)
        .jarvisAnimation(Motion.standard, value: errorMessage)
    }

    private var header: some View {
        VStack(spacing: Space.lg) {
            Circle()
                .stroke(AngularGradient.scoreArc, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .frame(width: 62, height: 62)

            VStack(spacing: Space.xs) {
                Text("Jarvis")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.textPrimary)
                Text(isRegistering
                    ? "Create your account to start tracking."
                    : "Welcome back.")
                    .font(.bodyJ)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
            }
        }
        .padding(.top, Space.xxl)
    }

    private var form: some View {
        VStack(spacing: Space.md) {
            field {
                TextField("Email", text: $email)
                    .focused($focus, equals: .email)
                    .onSubmit { focus = .password }
                    #if os(iOS)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()
                    #endif
            }

            field {
                SecureField("Password", text: $password)
                    .focused($focus, equals: .password)
                    .onSubmit { isRegistering ? (focus = .confirm) : submit() }
                    #if os(iOS)
                    .textContentType(isRegistering ? .newPassword : .password)
                    #endif
            }

            if isRegistering {
                field {
                    SecureField("Confirm password", text: $confirmPassword)
                        .focused($focus, equals: .confirm)
                        .onSubmit { submit() }
                        #if os(iOS)
                        .textContentType(.newPassword)
                        #endif
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Button(action: submit) {
                if isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                } else {
                    Text(isRegistering ? "Create account" : "Sign in")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.jarvisProminent)
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1 : 0.55)
            .padding(.top, Space.xs)

            if let errorMessage {
                HStack(spacing: Space.sm) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text(errorMessage)
                        .font(.subheadJ)
                        .multilineTextAlignment(.leading)
                }
                .foregroundStyle(Color.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.md)
                .background(Color.dangerSubtle, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
    }

    private func field(@ViewBuilder content: () -> some View) -> some View {
        content()
            .textFieldStyle(.plain)
            .font(.bodyJ)
            .padding(.horizontal, Space.lg)
            .frame(height: 50)
            .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: Radius.control + 2, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control + 2, style: .continuous)
                    .strokeBorder(Color.borderHairline, lineWidth: 1),
            )
    }

    private var toggle: some View {
        Button(isRegistering ? "I already have an account" : "Create an account") {
            withJarvisAnimation(Motion.smooth) {
                isRegistering.toggle()
                errorMessage = nil
            }
        }
        .buttonStyle(.jarvisGhost)
    }

    private func submit() {
        guard canSubmit else { return }
        if isRegistering, password != confirmPassword {
            Haptics.play(.warning)
            errorMessage = "Those passwords don't match."
            return
        }
        isSubmitting = true
        errorMessage = nil
        Task {
            defer { isSubmitting = false }
            do {
                try await model.signIn(email: email, password: password, register: isRegistering)
            } catch {
                Haptics.play(.warning)
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    LoginView().environment(AppModel())
}
