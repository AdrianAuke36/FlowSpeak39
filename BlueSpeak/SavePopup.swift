import SwiftUI

// MARK: - Usage
//
// @State private var showSaved = false
//
// ZStack {
//     ContentView()
//     SaveCheckmark(isVisible: $showSaved)
// }
//
// // Trigger:
// showSaved = true

// MARK: - Checkmark shape

struct CheckmarkPath: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: w * 0.18, y: h * 0.54))
        path.addLine(to: CGPoint(x: w * 0.42, y: h * 0.76))
        path.addLine(to: CGPoint(x: w * 0.82, y: h * 0.28))
        return path
    }
}

// MARK: - Popup view

struct SaveCheckmark: View {
    @Binding var isVisible: Bool

    @State private var circleScale: CGFloat = 0
    @State private var checkProgress: CGFloat = 0
    @State private var opacity: Double = 0
    @State private var offsetY: CGFloat = 6

    private let green = Color(nsColor: .systemGreen)

    var body: some View {
        VStack {
            Spacer()

            ZStack {
                // Circle
                Circle()
                    .fill(green.opacity(0.15))
                    .overlay(
                        Circle()
                            .strokeBorder(green.opacity(0.35), lineWidth: 1)
                    )
                    .shadow(color: green.opacity(0.15), radius: 8, x: 0, y: 0)
                    .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 2)
                    .scaleEffect(circleScale)

                // Checkmark
                CheckmarkPath(progress: checkProgress)
                    .trim(from: 0, to: checkProgress)
                    .stroke(
                        green,
                        style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: 14, height: 14)
            }
            .frame(width: 36, height: 36)
            .opacity(opacity)
            .offset(y: offsetY)
            .padding(.bottom, 36)
        }
        .allowsHitTesting(false)
        .onAppear {
            if isVisible {
                show()
            }
        }
        .onChange(of: isVisible) { _, newValue in
            if newValue { show() }
        }
    }

    private func show() {
        // Reset
        circleScale = 0
        checkProgress = 0
        opacity = 0
        offsetY = 6

        // Pop in
        withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
            opacity = 1
            offsetY = 0
            circleScale = 1
        }

        // Draw check
        withAnimation(.easeOut(duration: 0.24).delay(0.12)) {
            checkProgress = 1
        }

        // Auto hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeIn(duration: 0.18)) {
                opacity = 0
                offsetY = 4
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isVisible = false
                circleScale = 0
                checkProgress = 0
            }
        }
    }
}

struct SaveToastPanelView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var opacity: Double = 0
    @State private var scale: CGFloat = 0.94

    private func ui(_ norwegian: String, _ english: String) -> String {
        settings.ui(norwegian, english)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(nsColor: .systemGreen))
            Text(ui("Tekst lagret", "Text saved"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 4)
        )
        .opacity(opacity)
        .scaleEffect(scale)
        .onAppear {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                opacity = 1
                scale = 1
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.bottom, 4)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct SaveFailedToastPanelView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var opacity: Double = 0
    @State private var scale: CGFloat = 0.94

    private func ui(_ norwegian: String, _ english: String) -> String {
        settings.ui(norwegian, english)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(nsColor: .systemOrange))
            Text(ui("Ingen tekst markert", "No text selected"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 4)
        )
        .opacity(opacity)
        .scaleEffect(scale)
        .onAppear {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                opacity = 1
                scale = 1
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.bottom, 4)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

enum SaveToastKind {
    case saved
    case failed
}

@ViewBuilder
func saveToastContent(for kind: SaveToastKind) -> some View {
    switch kind {
    case .saved:
        SaveToastPanelView()
    case .failed:
        SaveFailedToastPanelView()
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var show = false

        var body: some View {
            ZStack {
                AppTheme.canvas.ignoresSafeArea()

                Button("Lagre") { show = true }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.white.opacity(0.75))
                    .font(.system(size: 13, weight: .medium))

                SaveCheckmark(isVisible: $show)
            }
        }
    }
    return PreviewWrapper()
}
