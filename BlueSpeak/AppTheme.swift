import AppKit
import SwiftUI

enum AppTheme {
    // Monokrom blå palett (støvet bakgrunn + hvite kort + klar blå aksent)
    static let canvas = Color(nsColor: .bsDynamic(light: 0xEEF2F8, dark: 0xEEF2F8))
    static let sidebar = Color(nsColor: .bsDynamic(light: 0xFFFFFF, dark: 0xFFFFFF))
    static let surface = Color(nsColor: .bsDynamic(light: 0xFFFFFF, dark: 0xFFFFFF))
    static let surfaceMuted = Color(nsColor: .bsDynamic(light: 0xF8FAFC, dark: 0xF8FAFC))
    static let border = Color(nsColor: .bsDynamic(light: 0x0F172A, dark: 0x0F172A, alphaLight: 0.08, alphaDark: 0.08))
    static let fieldBorder = Color(nsColor: .bsDynamic(light: 0x0F172A, dark: 0x0F172A, alphaLight: 0.12, alphaDark: 0.12))
    static let primaryText = Color(nsColor: .bsDynamic(light: 0x0F172A, dark: 0x0F172A))
    static let secondaryText = Color(nsColor: .bsDynamic(light: 0x0F172A, dark: 0x0F172A, alphaLight: 0.45, alphaDark: 0.45))
    static let tertiaryText = Color(nsColor: .bsDynamic(light: 0x0F172A, dark: 0x0F172A, alphaLight: 0.32, alphaDark: 0.32))
    static let accent = Color(nsColor: .bs(0x2563EB))
    static let accentStrong = Color(nsColor: .bs(0x1D4ED8))
    static let accentSoft = Color(nsColor: .bsDynamic(light: 0x2563EB, dark: 0x2563EB, alphaLight: 0.12, alphaDark: 0.12))
    static let accentText = Color(nsColor: .bsDynamic(light: 0xFFFFFF, dark: 0xFFFFFF))
    static let success = accentStrong
    static let warning = accent
    static let destructive = Color(nsColor: .systemRed)
    static let shadow = Color.black.opacity(0.06)

    // Surfaces
    static let cardMaterial: Color = surface
    static let fieldMaterial: Color = surface
    static let sidebarMaterial: Color = sidebar
    static let sheetMaterial: Color = surface

    // Typography
    static func heading(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if NSFont(name: "DM Serif Display", size: size) != nil {
            return .custom("DM Serif Display", size: size)
        }
        return .system(size: size, weight: weight, design: .serif)
    }

    static func body(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if NSFont(name: "DM Sans", size: size) != nil {
            return .custom("DM Sans", size: size)
        }
        return .system(size: size, weight: weight)
    }

    static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if NSFont(name: "DM Mono", size: size) != nil {
            return .custom("DM Mono", size: size)
        }
        return .system(size: size, weight: weight, design: .monospaced)
    }
}

private struct AppCardModifier: ViewModifier {
    let fill: Color

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(AppTheme.border, lineWidth: 1)
                    )
                    .shadow(color: AppTheme.shadow, radius: 10, x: 0, y: 5)
            )
    }
}

private struct StoreFieldModifier: ViewModifier {
    let maxWidth: CGFloat
    let minHeight: CGFloat

    func body(content: Content) -> some View {
        content
            .font(AppTheme.body(size: 14, weight: .medium))
            .foregroundStyle(AppTheme.primaryText)
            .tint(AppTheme.primaryText)
            .padding(.horizontal, 12)
            .frame(maxWidth: maxWidth, minHeight: minHeight, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(AppTheme.surfaceMuted)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(AppTheme.fieldBorder, lineWidth: 1)
                    )
            )
    }
}

private struct StorePickerModifier: ViewModifier {
    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .pickerStyle(.menu)
            .labelsHidden()
            .foregroundStyle(AppTheme.primaryText)
            .tint(AppTheme.primaryText)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(AppTheme.surfaceMuted)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(AppTheme.fieldBorder, lineWidth: 1)
                    )
            )
    }
}

struct StoreGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            configuration.label
                .foregroundStyle(AppTheme.primaryText)

            configuration.content
        }
        .padding(18)
        .appCard()
    }
}

struct BrandMarkView: View {
    var size: CGFloat = 22

    private var barHeights: [CGFloat] {
        [0.30, 0.55, 0.86, 0.62, 0.38]
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: max(1, size * 0.08)) {
            ForEach(Array(barHeights.enumerated()), id: \.offset) { _, height in
                RoundedRectangle(cornerRadius: max(1, size * 0.05))
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.accent, AppTheme.accentStrong],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(
                        width: max(1.8, size * 0.12),
                        height: max(3, size * height)
                    )
            }
        }
        .frame(width: size, height: size, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

struct BrandWordmarkView: View {
    var size: CGFloat = 28

    private var wordmark: AttributedString {
        var value = AttributedString("BlueSpeak")
        value.foregroundColor = AppTheme.primaryText
        if let range = value.range(of: "Speak") {
            value[range].foregroundColor = AppTheme.accent
        }
        return value
    }

    var body: some View {
        Text(wordmark)
            .font(AppTheme.heading(size: size, weight: .regular))
    }
}

extension View {
    func appCard(fill: Color = AppTheme.surface) -> some View {
        modifier(AppCardModifier(fill: fill))
    }

    func storeField(maxWidth: CGFloat = .infinity, minHeight: CGFloat = 42) -> some View {
        modifier(StoreFieldModifier(maxWidth: maxWidth, minHeight: minHeight))
    }

    func storePicker(maxWidth: CGFloat = .infinity) -> some View {
        modifier(StorePickerModifier(maxWidth: maxWidth))
    }
}

private extension NSColor {
    static func bs(_ hex: UInt32, alpha: CGFloat = 1.0) -> NSColor {
        let red = CGFloat((hex >> 16) & 0xFF) / 255.0
        let green = CGFloat((hex >> 8) & 0xFF) / 255.0
        let blue = CGFloat(hex & 0xFF) / 255.0
        return NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }

    static func bsDynamic(
        light: UInt32,
        dark: UInt32,
        alphaLight: CGFloat = 1.0,
        alphaDark: CGFloat = 1.0
    ) -> NSColor {
        NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            if match == .darkAqua {
                return .bs(dark, alpha: alphaDark)
            }
            return .bs(light, alpha: alphaLight)
        }
    }
}
