import SwiftUI

// MARK: - Usage
//
// @State private var showSignedOut = false
//
// ZStack {
//     ContentView()
//     SignedOutPopup(isVisible: $showSignedOut)
// }

struct SignedOutPopup: View {
    @Binding var isVisible: Bool

    @State private var opacity: Double = 0
    @State private var offsetY: CGFloat = 10

    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: 0) {
                // Header row
                HStack {
                    Spacer()
                    Text("Signed out")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.88))
                    Spacer()
                    Button(action: dismiss) {
                        Text("✕")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.25))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 6)

                // Body
                Text("Your session expired. Sign in to continue.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.38))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.bottom, 14)

                // Button
                Button(action: dismiss) {
                    Text("Sign in again")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.07))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .frame(width: 340)
            .background(
                RoundedRectangle(cornerRadius: 13)
                    .fill(Color(red: 0.086, green: 0.086, blue: 0.086))
                    .overlay(
                        RoundedRectangle(cornerRadius: 13)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.6), radius: 24, x: 0, y: 8)
                    .shadow(color: .white.opacity(0.04), radius: 0, x: 0, y: 1)
            )
            .opacity(opacity)
            .offset(y: offsetY)
            .padding(.bottom, 40)
        }
        .onAppear { show() }
    }

    private func show() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            opacity = 1
            offsetY = 0
        }
    }

    private func dismiss() {
        withAnimation(.easeIn(duration: 0.18)) {
            opacity = 0
            offsetY = 6
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isVisible = false
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var show = false

        var body: some View {
            ZStack {
                Color(red: 0.047, green: 0.047, blue: 0.047).ignoresSafeArea()

                Button("Vis popup") { show = true }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .font(.system(size: 12))

                if show {
                    SignedOutPopup(isVisible: $show)
                }
            }
        }
    }
    return PreviewWrapper()
}
