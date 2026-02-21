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
    let browserURL: String?  // NY: aktiv URL i nettleser
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
        let desc = focused.flatMap { copyStringAttr($0, kAXDescriptionAttribute) }
        let help = focused.flatMap { copyStringAttr($0, kAXHelpAttribute) }
        let title = focused.flatMap { copyStringAttr($0, kAXTitleAttribute) }
        let placeholder = focused.flatMap { copyStringAttr($0, kAXPlaceholderValueAttribute) }
        let valuePreview = focused.flatMap { copyValuePreview($0) }

        // NY: hent URL fra nettleser
        let browserURL = isBrowser(bundleId: bundleId) ? fetchBrowserURL(bundleId: bundleId) : nil

        return FieldContext(
            bundleId: bundleId,
            appName: appName,
            axRole: role,
            axSubrole: subrole,
            axDescription: desc,
            axHelp: help,
            axTitle: title,
            axPlaceholder: placeholder,
            axValuePreview: valuePreview,
            browserURL: browserURL
        )
    }

    func draftMode(for ctx: FieldContext) -> DraftMode {
        // Native apps
        switch ctx.bundleId {
        case "com.openai.chatgpt":
            return .chatMessage
        case "com.tinyspeck.slackmacgap":
            return .chatMessage
        case "com.microsoft.teams", "com.microsoft.teams2":
            return .chatMessage
        case "com.apple.Notes", "notion.id":
            return .note
        case "com.apple.mail":
            return subjectOrBody(ctx)
        case "com.microsoft.Outlook":
            return subjectOrBody(ctx)
        case "com.readdle.smartemail", "com.sparrowmailapp.sparrow3":
            return subjectOrBody(ctx)
        default:
            break
        }

        // Nettleser – bruk URL først, fall tilbake på AX-heuristikk
        if isBrowser(bundleId: ctx.bundleId) {
            if let url = ctx.browserURL {
                // Gmail
                if url.contains("mail.google.com") {
                    if looksLikeEmailSubject(ctx) { return .emailSubject }
                    return .emailBody
                }
                // Chat-apper
                if url.contains("chat.openai.com") || url.contains("chatgpt.com") { return .chatMessage }
                if url.contains("claude.ai") { return .chatMessage }
                if url.contains("slack.com") { return .chatMessage }
                if url.contains("teams.microsoft.com") { return .chatMessage }
                if url.contains("discord.com") { return .chatMessage }
                if url.contains("web.whatsapp.com") { return .chatMessage }
                if url.contains("messenger.com") { return .chatMessage }
                if url.contains("telegram.org") { return .chatMessage }

                // Notater/skriving
                if url.contains("notion.so") { return .note }
                if url.contains("docs.google.com") { return .note }
                if url.contains("linear.app") { return .note }

                // Mail-klienter i nettleser
                if url.contains("outlook.live.com") || url.contains("outlook.office.com") {
                    if looksLikeEmailSubject(ctx) { return .emailSubject }
                    return .emailBody
                }
            }

            // Fallback: AX-heuristikk
            if looksLikeEmailSubject(ctx) { return .emailSubject }
            if looksLikeEmailBody(ctx) { return .emailBody }
            if ctx.axRole == "AXTextArea" { return .chatMessage }

            return .generic
        }

        return .generic
    }

    // MARK: - Browser URL

    private func fetchBrowserURL(bundleId: String) -> String? {
        let appRef = AXUIElementCreateApplication(
            NSWorkspace.shared.frontmostApplication!.processIdentifier
        )

        // Finn aktiv vindu -> aktiv tab -> URL
        var windowVal: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowVal) == .success,
              let window = windowVal as! AXUIElement? else { return nil }

        // Chrome/Edge: AXTextField med title "Address and search bar"
        // Safari: AXTextField med identifier "WEB_BROWSER_ADDRESS_AND_SEARCH_FIELD"
        // Arc: ligner Chrome

        if let url = findURLField(in: window) {
            return url
        }

        return nil
    }

    private func findURLField(in element: AXUIElement, depth: Int = 0) -> String? {
        guard depth < 8 else { return nil }

        // Sjekk om dette elementet er adressefeltet
        let role = copyStringAttr(element, kAXRoleAttribute) ?? ""
        let desc = copyStringAttr(element, kAXDescriptionAttribute) ?? ""
        let identifier = copyStringAttr(element, "AXIdentifier") ?? ""
        let title = copyStringAttr(element, kAXTitleAttribute) ?? ""

        let isAddressBar = role == "AXTextField" && (
            desc.lowercased().contains("address") ||
            desc.lowercased().contains("search bar") ||
            desc.lowercased().contains("url") ||
            identifier.contains("ADDRESS") ||
            identifier.contains("WEB_BROWSER") ||
            title.lowercased().contains("address")
        )

        if isAddressBar {
            if let val = copyStringAttr(element, kAXValueAttribute), val.contains(".") {
                return val
            }
        }

        // Rekursivt søk i children
        var childrenVal: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenVal) == .success,
              let children = childrenVal as? [AXUIElement] else { return nil }

        for child in children {
            if let found = findURLField(in: child, depth: depth + 1) {
                return found
            }
        }

        return nil
    }

    // MARK: - Helpers

    private func subjectOrBody(_ ctx: FieldContext) -> DraftMode {
        return looksLikeEmailSubject(ctx) ? .emailSubject : .emailBody
    }

    private func isBrowser(bundleId: String) -> Bool {
        return bundleId == "com.google.Chrome"
            || bundleId == "com.apple.Safari"
            || bundleId == "com.microsoft.edgemac"
            || bundleId == "company.thebrowser.Browser"  // Arc
            || bundleId == "org.mozilla.firefox"
            || bundleId == "com.brave.Browser"
            || bundleId == "com.operasoftware.Opera"
    }

    private func looksLikeEmailSubject(_ ctx: FieldContext) -> Bool {
        guard ctx.axRole == "AXTextField" else { return false }
        let blob = normalize([ctx.axDescription, ctx.axHelp, ctx.axTitle, ctx.axPlaceholder])
        let keys = ["subject", "emne", "tema", "tittel", "re:", "fwd:"]
        return keys.contains { blob.contains($0) }
    }

    private func looksLikeEmailBody(_ ctx: FieldContext) -> Bool {
        let blob = normalize([ctx.axDescription, ctx.axHelp, ctx.axTitle, ctx.axPlaceholder])
        let bodyKeys = ["message body", "melding", "compose", "skriv", "mail", "e-post", "email", "innhold"]
        let hasBodyHint = bodyKeys.contains { blob.contains($0) }

        let role = ctx.axRole ?? ""
        let isBigField = (role == "AXTextArea" || role == "AXWebArea" || role == "AXGroup" || role == "AXScrollArea")

        if isBigField && !looksLikeEmailSubject(ctx) { return true }
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
        if let s = value as? String { return String(s.prefix(60)) }
        return nil
    }
}
