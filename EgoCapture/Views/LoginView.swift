import SwiftUI

// MARK: - Login view

/// Auth screen backed by the KGeN `auth-mobile` Edge Function. The visual
/// treatment stays aligned with the original ambient glass mock, but actions
/// now call email/password, signup and forgot-password.
struct LoginView: View {
    @ObservedObject var auth: AuthViewModel

    @State private var email = ""
    @State private var password = ""
    @State private var fullName = ""
    @State private var country = ""
    @State private var city = ""
    @State private var referralCode = ""
    @State private var mode: Mode = .login
    @State private var isWorking = false
    @FocusState private var focus: Field?

    private enum Mode { case login, signup }
    private enum Field { case email, password }

    var body: some View {
        ZStack {
            AmbientImageBackdrop()

            // Ambient orbs — positioned relative to the center of a 402×874
            // portrait frame so the layout matches the handoff on-device.
            Circle()
                .fill(KE.accentBlue.opacity(0.30))
                .frame(width: 240, height: 240)
                .blur(radius: 40)
                .offset(x: -170, y: -230)

            Circle()
                .fill(KE.accentGreen.opacity(0.25))
                .frame(width: 220, height: 220)
                .blur(radius: 40)
                .offset(x: 170, y: -100)

            AmbientImageBackdrop()
                .blur(radius: 12)
                .mask(
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .padding(EdgeInsets(top: 24, leading: 22, bottom: 28, trailing: 22))
                )
                .allowsHitTesting(false)

            GlassPane {
                VStack(spacing: 0) {
                    Spacer().frame(height: 62)
                    BrandLockup()

                    Spacer(minLength: 32)

                    VStack(spacing: 10) {
                        GlassField(
                            placeholder: "Email",
                            text: $email,
                            contentType: .emailAddress,
                            keyboardType: .emailAddress,
                            isSecure: false
                        )
                        .focused($focus, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }

                        GlassField(
                            placeholder: "Password",
                            text: $password,
                            contentType: .password,
                            keyboardType: .default,
                            isSecure: true
                        )
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit(submit)

                        if mode == .signup {
                            GlassField(
                                placeholder: "Full name",
                                text: $fullName,
                                contentType: .name,
                                keyboardType: .default,
                                isSecure: false
                            )
                            GlassField(
                                placeholder: "Country (BR)",
                                text: $country,
                                contentType: .countryName,
                                keyboardType: .default,
                                isSecure: false
                            )
                            GlassField(
                                placeholder: "City",
                                text: $city,
                                contentType: .addressCity,
                                keyboardType: .default,
                                isSecure: false
                            )
                            GlassField(
                                placeholder: "Referral code (optional)",
                                text: $referralCode,
                                contentType: nil,
                                keyboardType: .default,
                                isSecure: false
                            )
                        }
                    }

                    if let error = auth.errorMessage {
                        Text(error)
                            .font(.system(size: 13, weight: .medium))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(KE.accentRed)
                            .padding(.top, 10)
                    }

                    LoginButton(
                        title: mode == .login ? "Log in" : "Create account",
                        isWorking: isWorking,
                        action: submit
                    )
                        .padding(.top, 14)

                    Button("Forgot my password") {
                        forgotPassword()
                    }
                    .buttonStyle(ForgotLinkStyle())
                    .padding(.top, 18)

                    Button(mode == .login ? "Need an account? Sign up" : "Already have an account? Log in") {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            mode = mode == .login ? .signup : .login
                        }
                    }
                    .buttonStyle(ForgotLinkStyle())
                    .padding(.top, 10)

                    Spacer(minLength: 24)

                    Image("kgen-logo")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36)
                        .foregroundStyle(KE.accentBlue)
                        .opacity(0.85)

                    Spacer().frame(height: 20)
                }
                .padding(.horizontal, 44)
            }
        }
        .preferredColorScheme(.light)
        .onTapGesture { focus = nil }
    }

    private func submit() {
        focus = nil
        guard !isWorking else { return }
        isWorking = true
        Task {
            if mode == .login {
                await auth.login(email: email, password: password)
            } else {
                await auth.signup(
                    email: email,
                    password: password,
                    fullName: fullName.nilIfBlank,
                    country: country.nilIfBlank,
                    city: city.nilIfBlank,
                    referralCode: referralCode.nilIfBlank
                )
            }
            isWorking = false
        }
    }

    private func forgotPassword() {
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            auth.errorMessage = "Enter your email first."
            return
        }
        Task { await auth.forgotPassword(email: email) }
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

// MARK: - Glass input field

private struct GlassField: View {
    let placeholder: LocalizedStringKey
    @Binding var text: String
    let contentType: UITextContentType?
    let keyboardType: UIKeyboardType
    let isSecure: Bool

    var body: some View {
        Group {
            if isSecure {
                SecureField("", text: $text, prompt: placeholderText)
            } else {
                TextField("", text: $text, prompt: placeholderText)
            }
        }
        .textFieldStyle(.plain)
        .font(.system(size: 15))
        .foregroundStyle(KE.ink1)
        .textContentType(contentType)
        .keyboardType(keyboardType)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled(true)
        .padding(.horizontal, 18)
        .frame(height: 52)
        .background(Color.white.opacity(0.45))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.60), lineWidth: 1)
        )
        .shadow(
            color: Color(red: 30/255, green: 45/255, blue: 65/255).opacity(0.08),
            radius: 4, x: 0, y: 2
        )
    }

    private var placeholderText: Text {
        Text(placeholder)
            .foregroundStyle(KE.ink2.opacity(0.85))
    }
}

// MARK: - Primary login button

private struct LoginButton: View {
    let title: String
    let isWorking: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(isWorking ? "Please wait..." : title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(KE.ink1)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(
                    LinearGradient(
                        colors: [
                            KE.accentGreen.opacity(0.65),
                            KE.accentGreen.opacity(0.38)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(KE.accentGreen.opacity(0.60), lineWidth: 1.5)
                )
                .shadow(color: KE.accentGreen.opacity(0.45), radius: 13, x: 0, y: 0)
                .shadow(color: Color(red: 30/255, green: 40/255, blue: 55/255).opacity(0.20),
                        radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
    }
}

// MARK: - Forgot password link style

private struct ForgotLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .tracking(0.2)
            .foregroundStyle(Color(red: 210/255, green: 245/255, blue: 90/255))
            .shadow(
                color: Color(red: 210/255, green: 245/255, blue: 90/255).opacity(0.55),
                radius: 5
            )
            .shadow(
                color: Color(red: 20/255, green: 40/255, blue: 20/255).opacity(0.5),
                radius: 1, y: 1
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

#Preview {
    LoginView(auth: AuthViewModel())
}
