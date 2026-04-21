import SwiftUI

// MARK: - Login view

/// Dummy auth screen. Both `Log in` and `Continue with Google` trigger the
/// same `onAuthenticated` callback; the root view then swaps in
/// `KGenEyeHomeView`. No validation / Google SDK / backend is wired yet —
/// that work lands together with the real auth provider.
struct LoginView: View {
    let onAuthenticated: () -> Void

    @State private var email = ""
    @State private var password = ""
    @FocusState private var focus: Field?

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
                        .onSubmit(authenticate)
                    }

                    LoginButton(action: authenticate)
                        .padding(.top, 14)

                    GoogleButton(action: authenticate)
                        .padding(.top, 10)

                    Button("Forgot my password") {
                        // Dummy: spec calls for a modal sheet but auth isn't
                        // wired yet. Keeping as a no-op placeholder.
                    }
                    .buttonStyle(ForgotLinkStyle())
                    .padding(.top, 18)

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

    private func authenticate() {
        focus = nil
        withAnimation(.easeInOut(duration: 0.35)) {
            onAuthenticated()
        }
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Log in")
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
    }
}

// MARK: - Google button (placeholder glyph)

private struct GoogleButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                GoogleGlyph()
                    .frame(width: 20, height: 20)

                Text("Continue with Google")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(KE.ink1)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.55),
                        Color(red: 240/255, green: 245/255, blue: 252/255).opacity(0.32)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.55), lineWidth: 1.5)
            )
            .shadow(
                color: Color(red: 30/255, green: 45/255, blue: 65/255).opacity(0.10),
                radius: 10, x: 0, y: 4
            )
        }
        .buttonStyle(.plain)
    }
}

/// Placeholder Google mark — single-color "G" in Google Blue over a white
/// disc. Swap to the official multi-color SDK asset once the GoogleSignIn
/// integration lands.
private struct GoogleGlyph: View {
    var body: some View {
        ZStack {
            Circle().fill(Color.white)
            Text("G")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 66/255, green: 133/255, blue: 244/255))
        }
        .overlay(Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 1.5, y: 0.5)
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
    LoginView(onAuthenticated: {})
}
