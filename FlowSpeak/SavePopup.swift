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

    private let green = Color(red: 0.20, green: 0.78, blue: 0.35)

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
    @State private var isVisible = true

    var body: some View {
        SaveCheckmark(isVisible: $isVisible)
            .onAppear {
                isVisible = true
            }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var show = false

        var body: some View {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.08).ignoresSafeArea()

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
