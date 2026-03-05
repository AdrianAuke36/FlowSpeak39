import AppKit
import SwiftUI

enum AppTheme {
    // Obsidian theme: neutral monochrome palette for maximum focus.
    static let canvas = dynamic(light: rgb(242, 242, 240), dark: rgb(12, 12, 12))
    static let sidebar = dynamic(light: rgb(235, 235, 233), dark: rgb(18, 18, 18))
    static let surface = dynamic(light: rgb(250, 250, 250), dark: rgb(22, 22, 22))
    static let surfaceMuted = dynamic(light: rgb(244, 244, 242), dark: rgb(28, 28, 28))
    static let border = dynamic(light: rgb(214, 214, 212), dark: rgb(48, 48, 48))
    static let fieldBorder = dynamic(light: rgb(192, 192, 190), dark: rgb(66, 66, 66))
    static let primaryText = dynamic(light: rgb(17, 17, 17), dark: rgb(245, 245, 245))
    static let secondaryText = dynamic(light: rgb(94, 94, 94), dark: rgb(176, 176, 176))
    static let accent = dynamic(light: rgb(17, 17, 17), dark: rgb(245, 245, 245))
    static let accentText = dynamic(light: rgb(245, 245, 245), dark: rgb(17, 17, 17))
    static let accentSoft = dynamic(light: rgb(229, 229, 227), dark: rgb(34, 34, 34))
    static let success = dynamic(light: rgb(17, 17, 17), dark: rgb(245, 245, 245))
    static let warning = dynamic(light: rgb(70, 70, 70), dark: rgb(198, 198, 198))
    static let shadow = dynamic(light: rgb(0, 0, 0, alpha: 0.08), dark: rgb(0, 0, 0, alpha: 0.4))

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let match = appearance.bestMatch(from: [.darkAqua, .aqua])
                return match == .darkAqua ? dark : light
            }
        )
    }

    private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, alpha: CGFloat = 1.0) -> NSColor {
        NSColor(
            calibratedRed: red / 255.0,
            green: green / 255.0,
            blue: blue / 255.0,
            alpha: alpha
        )
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
                    .shadow(color: AppTheme.shadow, radius: 10, x: 0, y: 6)
            )
    }
}

private struct StoreFieldModifier: ViewModifier {
    let maxWidth: CGFloat
    let minHeight: CGFloat

    func body(content: Content) -> some View {
        content
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(AppTheme.primaryText)
            .tint(AppTheme.primaryText)
            .padding(.horizontal, 12)
            .frame(maxWidth: maxWidth, minHeight: minHeight, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(AppTheme.surface)
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
                    .fill(AppTheme.surface)
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

struct StorePrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isEnabled ? AppTheme.accent : AppTheme.border)
                    .shadow(color: AppTheme.shadow, radius: 8, x: 0, y: 4)
            )
            .foregroundStyle(AppTheme.accentText)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct StoreSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(AppTheme.surfaceMuted)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(isEnabled ? AppTheme.border : AppTheme.border.opacity(0.6), lineWidth: 1)
                    )
            )
            .foregroundStyle(isEnabled ? AppTheme.primaryText : AppTheme.secondaryText)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
