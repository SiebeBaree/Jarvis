import DesignSystem
import SwiftUI

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

    var body: some View {
        VStack(spacing: Space.xl) {
            Spacer()

            Text("JARVIS")
                .font(.title1J)
                .tracking(4)
                .foregroundStyle(Color.textPrimary)

            VStack(spacing: Space.md) {
                TextField("Email", text: $email)
                    .textFieldStyle(.plain)
                    .padding(Space.md)
                    .background(Color.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.control))
                    .focused($focus, equals: .email)
                    .onSubmit { focus = .password }
                    #if os(iOS)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif

                SecureField("Password", text: $password)
                    .textFieldStyle(.plain)
                    .padding(Space.md)
                    .background(Color.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.control))
                    .focused($focus, equals: .password)
                    .onSubmit { isRegistering ? (focus = .confirm) : submit() }

                if isRegistering {
                    SecureField("Confirm password", text: $confirmPassword)
                        .textFieldStyle(.plain)
                        .padding(Space.md)
                        .background(Color.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.control))
                        .focused($focus, equals: .confirm)
                        .onSubmit { submit() }
                }

                Button {
                    submit()
                } label: {
                    if isSubmitting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(isRegistering ? "Create account" : "Sign in")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.jarvisPrimary)
                .disabled(isSubmitting || email.isEmpty || password.isEmpty)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.subheadJ)
                        .foregroundStyle(Color.danger)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: 360)

            Button(isRegistering ? "I already have an account" : "Create account") {
                isRegistering.toggle()
                errorMessage = nil
            }
            .buttonStyle(.jarvisGhost)

            Spacer()
            Spacer()
        }
        .padding(PageMargin.standard)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgCanvas)
    }

    private func submit() {
        guard !isSubmitting, !email.isEmpty, !password.isEmpty else { return }
        if isRegistering, password != confirmPassword {
            errorMessage = "Passwords don't match."
            return
        }
        isSubmitting = true
        errorMessage = nil
        Task {
            defer { isSubmitting = false }
            do {
                try await model.signIn(email: email, password: password, register: isRegistering)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    LoginView().environment(AppModel())
}
