import SwiftUI

struct SaveToastPanelView: View {
    @State private var circleScale: CGFloat = 0
    @State private var circleOpacity: Double = 0
    @State private var checkProgress: CGFloat = 0
    @State private var pillOffset: CGFloat = 14
    @State private var pillOpacity: Double = 0
    @State private var glowOpacity: Double = 0.4

    private let green = Color(red: 0.20, green: 0.78, blue: 0.35)

    var body: some View {
        ZStack {
            Capsule()
                .stroke(green.opacity(glowOpacity), lineWidth: 1)
                .blur(radius: 6)
                .padding(-4)
                .allowsHitTesting(false)

            HStack(spacing: 12) {
                CheckCircleView(
                    green: green,
                    circleScale: circleScale,
                    circleOpacity: circleOpacity,
                    checkProgress: checkProgress
                )

                Text("Tekst lagret")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
            }
            .padding(.leading, 14)
            .padding(.trailing, 20)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.22),
                                        green.opacity(0.25),
                                        .white.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 4)
                    .shadow(color: green.opacity(0.15), radius: 10, x: 0, y: 0)
            )
        }
        .offset(y: pillOffset)
        .opacity(pillOpacity)
        .allowsHitTesting(false)
        .onAppear {
            showPopup()
        }
    }

    private func showPopup() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
            pillOffset = 0
            pillOpacity = 1
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.65).delay(0.05)) {
            circleScale = 1
            circleOpacity = 1
        }

        withAnimation(.easeOut(duration: 0.28).delay(0.22)) {
            checkProgress = 1
        }

        withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
            glowOpacity = 0.75
        }
    }
}

private struct CheckCircleView: View {
    let green: Color
    let circleScale: CGFloat
    let circleOpacity: Double
    let checkProgress: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(green.opacity(0.15))
                .overlay(
                    Circle()
                        .strokeBorder(green.opacity(0.5), lineWidth: 1.5)
                )
                .shadow(color: green.opacity(0.25), radius: 6, x: 0, y: 0)
                .scaleEffect(circleScale)
                .opacity(circleOpacity)

            CheckmarkShape(progress: checkProgress)
                .trim(from: 0, to: checkProgress)
                .stroke(
                    green,
                    style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 14, height: 14)
        }
        .frame(width: 34, height: 34)
    }
}

private struct CheckmarkShape: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        path.move(to: CGPoint(x: width * 0.18, y: height * 0.52))
        path.addLine(to: CGPoint(x: width * 0.42, y: height * 0.76))
        path.addLine(to: CGPoint(x: width * 0.82, y: height * 0.28))
        return path
    }
}
