import Foundation
import AppKit
import ApplicationServices

struct FieldContext {
    let bundleId: String
    let appName: String
    let axRole: String?
    let axSubrole: String?
    let axDescription: String?
    let axHelp: String?
    let axTitle: String?
    let axPlaceholder: String?
    let axValuePreview: String?
}

enum DraftMode: String {
    case chatMessage  = "chat_message"
    case emailBody    = "email_body"
    case emailSubject = "email_subject"
    case note         = "note"
    case generic      = "generic"
}

final class ContextResolver {

    func resolve() -> FieldContext? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let bundleId = app.bundleIdentifier ?? "unknown"
        let appName = app.localizedName ?? bundleId

        let focused = focusedElement()
        let role = focused.flatMap { copyStringAttr($0, kAXRoleAttribute) }
        let subrole = focused.flatMap { copyStringAttr($0, kAXSubroleAttribute) }

        // Disse kan være nil i webviews, men når de finnes er de gull
        let desc = focused.flatMap { copyStringAttr($0, kAXDescriptionAttribute) }
        let help = focused.flatMap { copyStringAttr($0, kAXHelpAttribute) }
        let title = focused.flatMap { copyStringAttr($0, kAXTitleAttribute) }
        let placeholder = focused.flatMap { copyStringAttr($0, kAXPlaceholderValueAttribute) }

        // Value kan være stor/ikke-string; vi tar en liten preview
        let valuePreview = focused.flatMap { copyValuePreview($0) }

        return FieldContext(
            bundleId: bundleId,
            appName: appName,
            axRole: role,
            axSubrole: subrole,
            axDescription: desc,
            axHelp: help,
            axTitle: title,
            axPlaceholder: placeholder,
            axValuePreview: valuePreview
        )
    }

    func draftMode(for ctx: FieldContext) -> DraftMode {
        // Native apps (stabilt)
        switch ctx.bundleId {
        case "com.openai.chatgpt":
            return .chatMessage
        case "com.tinyspeck.slackmacgap":
            return .chatMessage
        case "com.microsoft.teams", "com.microsoft.teams2":
            return .chatMessage
        case "com.apple.Notes", "notion.id":
            return .note
        default:
            break
        }

        // Browsere (Chrome/Arc/Safari/Edge) – kun AX heuristikk
        if isBrowser(bundleId: ctx.bundleId) {
            // 1) Gmail subject/body heuristikk
            // Subject er ofte single-line (AXTextField) og har label/desc/placeholder som "Subject"/"Emne"
            if looksLikeEmailSubject(ctx) { return .emailSubject }

            // 2) Hvis det ser ut som "stor tekstflate"/rich editor => email body eller chat
            // I Gmail body er det ofte AXWebArea/AXTextArea eller rich editor med tekstområde.
            if looksLikeEmailBody(ctx) { return .emailBody }

            // 3) Fallback: textarea -> chat message (for web chat apps)
            if ctx.axRole == "AXTextArea" { return .chatMessage }

            return .generic
        }

        return .generic
    }

    // MARK: - Heuristics

    private func isBrowser(bundleId: String) -> Bool {
        return bundleId == "com.google.Chrome"
            || bundleId == "com.apple.Safari"
            || bundleId == "com.microsoft.edgemac"
            || bundleId == "company.thebrowser.Browser"   // Arc (ofte dette; varierer litt)
    }

    private func looksLikeEmailSubject(_ ctx: FieldContext) -> Bool {
        // Subject er typisk single-line.
        guard ctx.axRole == "AXTextField" else { return false }

        let blob = normalize([
            ctx.axDescription,
            ctx.axHelp,
            ctx.axTitle,
            ctx.axPlaceholder
        ])

        // Nøkkelord vi ofte ser i Gmail/andre mail-klienter
        let keys = ["subject", "emne", "tema", "tittel"]
        return keys.contains { blob.contains($0) }
    }

    private func looksLikeEmailBody(_ ctx: FieldContext) -> Bool {
        let blob = normalize([
            ctx.axDescription,
            ctx.axHelp,
            ctx.axTitle,
            ctx.axPlaceholder
        ])

        // Gmail body/compose kan ha hints som "Message Body" / "Meldingstekst"
        let bodyKeys = ["message body", "melding", "compose", "skriv", "mail", "e-post", "email", "innhold"]
        let hasBodyHint = bodyKeys.contains { blob.contains($0) }

        // Role: body er ofte større område enn AXTextField
        let role = ctx.axRole ?? ""
        let isBigField = (role == "AXTextArea" || role == "AXWebArea" || role == "AXGroup" || role == "AXScrollArea")

        // Hvis det ikke er subject og det er stor tekstflate, er email body en god guess
        if isBigField && !looksLikeEmailSubject(ctx) {
            return true
        }

        return hasBodyHint
    }

    private func normalize(_ parts: [String?]) -> String {
        parts.compactMap { $0 }
            .joined(separator: " | ")
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Accessibility helpers

    private func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused)
        guard err == .success, let el = focused else { return nil }
        return (el as! AXUIElement)
    }

    private func copyStringAttr(_ el: AXUIElement, _ attr: String) -> String? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(el, attr as CFString, &value)
        guard err == .success else { return nil }
        return value as? String
    }

    private func copyValuePreview(_ el: AXUIElement) -> String? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &value)
        guard err == .success else { return nil }

        if let s = value as? String {
            return String(s.prefix(60))
        }

        // Noen webfelt returnerer attributed string eller annet – vi ignorerer
        return nil
    }
}
