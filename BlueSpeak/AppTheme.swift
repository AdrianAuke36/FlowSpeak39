import AppKit
import SwiftUI

enum AppTheme {
    // Apple-native semantic colors
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let sidebar = Color(nsColor: .underPageBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let surfaceMuted = Color(nsColor: .textBackgroundColor)
    static let border = Color(nsColor: .separatorColor)
    static let fieldBorder = Color(nsColor: .quaternaryLabelColor)
    static let primaryText = Color(nsColor: .labelColor)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    static let tertiaryText = Color(nsColor: .tertiaryLabelColor)
    static let accent = Color.accentColor
    static let accentText = Color.white
    static let accentSoft = Color.accentColor.opacity(0.14)
    static let success = Color(nsColor: .systemGreen)
    static let warning = Color(nsColor: .systemOrange)
    static let destructive = Color(nsColor: .systemRed)
    static let shadow = Color.black.opacity(0.12)

    // Apple-native materials
    static let cardMaterial: Material = .regularMaterial
    static let fieldMaterial: Material = .thinMaterial
    static let sidebarMaterial: Material = .regularMaterial
    static let sheetMaterial: Material = .thickMaterial
}

private struct AppCardModifier: ViewModifier {
    let fill: Color

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.cardMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(fill.opacity(0.2))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(AppTheme.border, lineWidth: 1)
                    )
                    .shadow(color: AppTheme.shadow, radius: 8, x: 0, y: 4)
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
                    .fill(AppTheme.fieldMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(AppTheme.surface.opacity(0.28))
                    )
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
                    .fill(AppTheme.fieldMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(AppTheme.surface.opacity(0.28))
                    )
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
