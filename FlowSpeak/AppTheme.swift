import SwiftUI

enum AppTheme {
    static let canvas = Color(red: 0.96, green: 0.97, blue: 0.99)
    static let sidebar = Color(red: 0.94, green: 0.96, blue: 0.99)
    static let surface = Color.white
    static let surfaceMuted = Color(red: 0.98, green: 0.99, blue: 1.00)
    static let border = Color(red: 0.86, green: 0.89, blue: 0.94)
    static let fieldBorder = Color(red: 0.78, green: 0.81, blue: 0.86)
    static let primaryText = Color(red: 0.11, green: 0.14, blue: 0.19)
    static let secondaryText = Color(red: 0.42, green: 0.47, blue: 0.56)
    static let accent = Color(red: 0.08, green: 0.47, blue: 0.96)
    static let accentSoft = Color(red: 0.90, green: 0.95, blue: 1.00)
    static let success = Color(red: 0.12, green: 0.63, blue: 0.34)
    static let warning = Color(red: 0.73, green: 0.43, blue: 0.10)
    static let shadow = Color.black.opacity(0.06)
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
            .environment(\.colorScheme, .light)
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
            .environment(\.colorScheme, .light)
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
            .foregroundStyle(.white)
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
