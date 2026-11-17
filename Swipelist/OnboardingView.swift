import SwiftUI

/// The landing page: sign in to a Swipelist account.
///
/// Music services aren't linked here — that happens in Profile, so a listener can
/// swap service without ever signing out of their account.
struct OnboardingView: View {
    @ObservedObject var account: SupabaseAuth

    @State private var showEmailForm = false
    @State private var email = ""
    @State private var password = ""
    @State private var isSigningUp = false

    // The blurred artwork wall behind the title, from the design.
    private static let wall: [Art] = [
        (0x6F9FE8, 0x12203C, 40.0, 40.0), (0xD66FD0, 0x2C0E28, 60, 30), (0x86D92A, 0x16280A, 50, 60),
        (0xF0A952, 0x301806, 30, 50), (0x3FC9B8, 0x0C2422, 55, 45), (0xB06FF0, 0x1E0E3A, 45, 35),
        (0x8A9BB8, 0x171C26, 65, 55), (0xFF7A59, 0x33100A, 35, 65), (0x5C7BA6, 0x101827, 50, 40),
        (0x86D92A, 0x182B0B, 60, 60), (0xD0D0D5, 0x202024, 40, 30), (0x6F9FE8, 0x101D33, 30, 55),
        (0xD66FD0, 0x290D26, 55, 50), (0x3FC9B8, 0x0B201E, 45, 60), (0xF0A952, 0x2C1605, 65, 35),
        (0xB06FF0, 0x1B0D33, 50, 50), (0x8A9BB8, 0x14181F, 35, 40), (0x86D92A, 0x14260A, 60, 65),
        (0xFF7A59, 0x2E0F08, 40, 50), (0x5C7BA6, 0x0E1524, 55, 35), (0x6F9FE8, 0x0F1C31, 45, 45),
        (0xD66FD0, 0x260C23, 50, 55), (0x3FC9B8, 0x0A1E1C, 35, 35), (0xF0A952, 0x291404, 60, 45),
    ].map { Art([($0.0, 0), ($0.1, 1)], center: ($0.2, $0.3)) }

    var body: some View {
        ZStack {
            Color.swBackground.ignoresSafeArea()
            artworkWall
            dimOverlay

            VStack(spacing: 0) {
                Spacer()
                SwipelistAppIcon(size: 84)
                    .padding(.bottom, 20)
                Text("Swipelist")
                    .font(.system(size: 44, weight: .heavy))
                    .tracking(-1)
                    .foregroundStyle(Color.swTextPrimary)
                Text("Swipe. Build. Listen.")
                    .font(.system(size: 17))
                    .multilineTextAlignment(.center)
                    .tracking(0.2)
                    .foregroundStyle(Color.swTextSecondary)
                    .padding(.top, 12)
                Spacer()

                Group {
                    if showEmailForm { emailForm } else { signInButtons }
                }
                .padding(.horizontal, 20)

                if let error = account.errorMessage {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.swDestructive)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                        .padding(.top, 12)
                }

                legalText
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
                    .padding(.top, 18)
            }
            .padding(.bottom, 14)
        }
        .animation(.easeInOut(duration: 0.2), value: showEmailForm)
    }

    private var signInButtons: some View {
        VStack(spacing: 10) {
            Button {
                Task { await account.signInWithGoogle() }
            } label: {
                HStack(spacing: 8) {
                    if account.isWorking {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: "g.circle.fill").font(.system(size: 19))
                        Text("Continue with Google").font(.system(size: 18, weight: .semibold))
                    }
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(.white, in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(account.isWorking)

            Button {
                account.errorMessage = nil
                showEmailForm = true
            } label: {
                Text("Continue with email")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.swTextSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
            }
            .buttonStyle(.plain)
        }
    }

    private var emailForm: some View {
        VStack(spacing: 10) {
            TextField("", text: $email, prompt: Text("Email").foregroundStyle(Color.swTextTertiary))
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .modifier(FieldStyle())

            SecureField("", text: $password, prompt: Text("Password").foregroundStyle(Color.swTextTertiary))
                .textContentType(isSigningUp ? .newPassword : .password)
                .modifier(FieldStyle())

            Button {
                Task {
                    if isSigningUp {
                        await account.signUp(email: email, password: password)
                    } else {
                        await account.signIn(email: email, password: password)
                    }
                }
            } label: {
                Group {
                    if account.isWorking {
                        ProgressView().tint(Color.swOnAccent)
                    } else {
                        Text(isSigningUp ? "Create account" : "Sign in").font(.swHeadline)
                    }
                }
                .foregroundStyle(Color.swOnAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.swAccent, in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(account.isWorking || email.isEmpty || password.count < 6)
            .opacity(email.isEmpty || password.count < 6 ? 0.4 : 1)

            HStack {
                Button(isSigningUp ? "Have an account?" : "Create an account") {
                    account.errorMessage = nil
                    isSigningUp.toggle()
                }
                Spacer()
                Button("Back") {
                    account.errorMessage = nil
                    showEmailForm = false
                }
            }
            .font(.system(size: 15))
            .foregroundStyle(Color.swTextSecondary)
            .padding(.top, 2)
        }
    }

    private struct FieldStyle: ViewModifier {
        func body(content: Content) -> some View {
            content
                .font(.system(size: 17))
                .foregroundStyle(Color.swTextPrimary)
                .tint(Color.swAccent)
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
        }
    }

    private var legalText: Text {
        Text("By signing in, you agree to our ").foregroundStyle(Color.swTextTertiary)
            + Text("Terms of Service").underline().foregroundStyle(Color.swTextSecondary)
            + Text(" and ").foregroundStyle(Color.swTextTertiary)
            + Text("Privacy Policy").underline().foregroundStyle(Color.swTextSecondary)
            + Text(".").foregroundStyle(Color.swTextTertiary)
    }

    private var artworkWall: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4),
            spacing: 6
        ) {
            ForEach(Self.wall.indices, id: \.self) { i in
                ArtworkView(art: Self.wall[i])
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .overlay(Color.black.opacity(0.55))
        .blur(radius: 3)
        .saturation(0.7)
        .padding(-20)
        .frame(maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }

    private var dimOverlay: some View {
        RadialGradient(
            stops: [
                .init(color: Color.swBackground.opacity(0.55), location: 0),
                .init(color: Color.swBackground.opacity(0.88), location: 0.7),
                .init(color: Color.swBackground, location: 1),
            ],
            center: UnitPoint(x: 0.5, y: 0.42),
            startRadius: 0,
            endRadius: 560
        )
        .ignoresSafeArea()
    }
}

#Preview {
    OnboardingView(account: SupabaseAuth.shared)
        .preferredColorScheme(.dark)
}
