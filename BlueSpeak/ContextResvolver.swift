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
    let axValuePreview: String?  // Opptil 500 tegn bakover
    let browserURL: String?
    let emailRecipientHint: String?
}

enum DraftMode: String {
    case chatMessage  = "chat_message"
    case emailBody    = "email_body"
    case emailSubject = "email_subject"
    case note         = "note"
    case generic      = "generic"
}

final class ContextResolver {
    private enum Heuristics {
        static let browserBundleIDs: Set<String> = [
            "com.google.Chrome",
            "com.apple.Safari",
            "com.microsoft.edgemac",
            "company.thebrowser.Browser",
            "org.mozilla.firefox"
        ]

        static let subjectKeys = ["subject", "emne", "tema", "tittel", "betreff"]
        static let emailBodyKeys = ["message body", "message", "melding", "skriv e-post", "skriv en e-post", "e-post", "email", "innhold", "body"]
        static let composeHints = ["compose", "ny melding", "new message", "skriv e-post", "skriv en e-post"]
        static let emailHints = ["e-post", "email", "subject", "emne", "recipient", "mottaker", "to", "cc", "bcc"]

        static let chatURLHints = [
            "chat.openai.com", "chatgpt.com", "claude.ai", "slack.com", "teams.microsoft.com",
            "discord.com", "web.whatsapp.com", "messenger.com"
        ]
        static let noteURLHints = ["notion.so", "docs.google.com", "linear.app", "github.com"]
    }

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

        // Opptil 500 tegn bakover for bedre kontekst
        let valuePreview = focused.flatMap { copyValuePreview($0, maxLength: 500) }

        let browserURL = isBrowser(bundleId: bundleId) ? fetchBrowserURL(bundleId: bundleId) : nil
        let emailRecipientHint = focused.flatMap {
            inferEmailRecipientHint(from: $0, bundleId: bundleId, browserURL: browserURL)
        }

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
            browserURL: browserURL,
            emailRecipientHint: emailRecipientHint
        )
    }

    func draftMode(for ctx: FieldContext) -> DraftMode {
        switch ctx.bundleId {
        case "com.openai.chatgpt":          return .chatMessage
        case "com.tinyspeck.slackmacgap":   return .chatMessage
        case "com.microsoft.teams",
             "com.microsoft.teams2":        return .chatMessage
        case "com.apple.Notes",
             "notion.id":                   return .note
        case "com.apple.mail":              return subjectOrBody(ctx)
        case "com.microsoft.Outlook":       return subjectOrBody(ctx)
        default: break
        }

        if isBrowser(bundleId: ctx.bundleId) {
            if let url = ctx.browserURL, let mode = modeFromURL(url, ctx: ctx) {
                return mode
            }
            if looksLikeGmailCompose(ctx) {
                return looksLikeEmailSubject(ctx) ? .emailSubject : .emailBody
            }
            if looksLikeEmailSubject(ctx) { return .emailSubject }
            if looksLikeEmailBody(ctx) { return .emailBody }
            if ctx.axRole == "AXTextArea" { return .chatMessage }
            return .generic
        }

        return .generic
    }

    // MARK: - URL-basert mode

    private func modeFromURL(_ url: String, ctx: FieldContext) -> DraftMode? {
        let lower = url.lowercased()

        if lower.contains("mail.google.com") {
            if looksLikeEmailSubject(ctx) { return .emailSubject }
            if looksLikeGmailCompose(ctx) || looksLikeEmailBody(ctx) { return .emailBody }
            return .generic
        }
        if lower.contains("outlook.live.com") || lower.contains("outlook.office.com") {
            if looksLikeEmailSubject(ctx) { return .emailSubject }
            if looksLikeGmailCompose(ctx) || looksLikeEmailBody(ctx) { return .emailBody }
            return .generic
        }

        if containsAny(lower, from: Heuristics.chatURLHints) {
            return .chatMessage
        }

        if containsAny(lower, from: Heuristics.noteURLHints) {
            return .note
        }

        return nil
    }

    // MARK: - Browser URL

    private func fetchBrowserURL(bundleId: String) -> String? {
        if let scripted = fetchBrowserURLViaAppleScript(bundleId: bundleId) {
            return scripted
        }

        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        return findAddressBarValue(in: axApp)
    }

    private func fetchBrowserURLViaAppleScript(bundleId: String) -> String? {
        let scriptSource: String?
        switch bundleId {
        case "com.google.Chrome", "com.microsoft.edgemac", "company.thebrowser.Browser":
            scriptSource = """
            tell application id "\(bundleId)"
                if (count of windows) = 0 then return ""
                return URL of active tab of front window
            end tell
            """
        case "com.apple.Safari":
            scriptSource = """
            tell application "Safari"
                if (count of windows) = 0 then return ""
                return URL of current tab of front window
            end tell
            """
        default:
            scriptSource = nil
        }

        guard let source = scriptSource,
              let script = NSAppleScript(source: source) else { return nil }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if error != nil { return nil }

        let url = result.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !url.isEmpty else { return nil }
        return url
    }

    private func findAddressBarValue(in element: AXUIElement, depth: Int = 0) -> String? {
        guard depth < 10 else { return nil }

        let role = copyStringAttr(element, kAXRoleAttribute)
        let subrole = copyStringAttr(element, kAXSubroleAttribute)
        let desc = copyStringAttr(element, kAXDescriptionAttribute) ?? ""
        let title = copyStringAttr(element, kAXTitleAttribute) ?? ""

        let isAddressBar = (role == "AXTextField") && (
            desc.lowercased().contains("address") ||
            desc.lowercased().contains("url") ||
            desc.lowercased().contains("location") ||
            desc.lowercased().contains("adresse") ||
            title.lowercased().contains("address") ||
            subrole == "AXSearchField"
        )

        if isAddressBar, let value = copyStringAttr(element, kAXValueAttribute) {
            if value.contains(".") && !value.contains("\n") {
                return value
            }
        }

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return nil }

        for child in children {
            if let found = findAddressBarValue(in: child, depth: depth + 1) {
                return found
            }
        }
        return nil
    }

    // MARK: - Native mail heuristikk

    private func subjectOrBody(_ ctx: FieldContext) -> DraftMode {
        return looksLikeEmailSubject(ctx) ? .emailSubject : .emailBody
    }

    // MARK: - Heuristics

    private func isBrowser(bundleId: String) -> Bool {
        Heuristics.browserBundleIDs.contains(bundleId)
    }

    private func looksLikeEmailSubject(_ ctx: FieldContext) -> Bool {
        guard ctx.axRole == "AXTextField" else { return false }
        let blob = normalize([ctx.axDescription, ctx.axHelp, ctx.axTitle, ctx.axPlaceholder])
        return containsAny(blob, from: Heuristics.subjectKeys)
    }

    private func looksLikeEmailBody(_ ctx: FieldContext) -> Bool {
        let blob = normalize([ctx.axDescription, ctx.axHelp, ctx.axTitle, ctx.axPlaceholder])
        let hasBodyHint = containsAny(blob, from: Heuristics.emailBodyKeys)
        let hasEmailHint = containsAny(blob, from: Heuristics.emailHints)
        let role = ctx.axRole ?? ""
        let isWritableTextRole = (role == "AXTextArea" || role == "AXTextField" || role == "AXGroup" || role == "AXWebArea")
        guard isWritableTextRole, !looksLikeEmailSubject(ctx) else { return false }
        return hasBodyHint && (hasEmailHint || looksLikeGmailCompose(ctx))
    }

    private func looksLikeGmailCompose(_ ctx: FieldContext) -> Bool {
        if let url = ctx.browserURL?.lowercased() {
            if url.contains("mail.google.com/mail") && (url.contains("compose=") || url.contains("#drafts")) {
                return true
            }
            if url.contains("outlook.live.com/mail") || url.contains("outlook.office.com/mail") {
                return true
            }
        }

        let blob = normalize([
            ctx.axDescription,
            ctx.axHelp,
            ctx.axTitle,
            ctx.axPlaceholder
        ])

        let hasComposeHint = containsAny(blob, from: Heuristics.composeHints)
        let hasEmailHint = containsAny(blob, from: Heuristics.emailHints)
        return hasComposeHint && hasEmailHint
    }

    private func normalize(_ parts: [String?]) -> String {
        parts.compactMap { $0 }
            .joined(separator: " | ")
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func containsAny(_ text: String, from hints: [String]) -> Bool {
        hints.contains { text.contains($0) }
    }

    private func inferEmailRecipientHint(from focused: AXUIElement, bundleId: String, browserURL: String?) -> String? {
        guard likelyEmailCompose(bundleId: bundleId, browserURL: browserURL, focused: focused) else {
            return nil
        }
        guard let root = rootWindow(for: focused) else { return nil }

        var remainingNodes = 180
        var strings: [String] = []
        collectVisibleStrings(in: root, remainingNodes: &remainingNodes, into: &strings)

        var bestCandidate: (text: String, score: Int)?
        for raw in strings {
            let candidate = cleanedRecipientCandidate(from: raw)
            let score = recipientCandidateScore(candidate)
            guard score > 0 else { continue }
            if let current = bestCandidate, current.score >= score {
                continue
            }
            bestCandidate = (candidate, score)
        }

        return bestCandidate?.text
    }

    private func likelyEmailCompose(bundleId: String, browserURL: String?, focused: AXUIElement) -> Bool {
        if bundleId == "com.apple.mail" || bundleId == "com.microsoft.Outlook" {
            return true
        }
        if let url = browserURL?.lowercased(),
           url.contains("mail.google.com") || url.contains("outlook.live.com") || url.contains("outlook.office.com") {
            return true
        }

        let title = copyStringAttr(focused, kAXTitleAttribute)
        let desc = copyStringAttr(focused, kAXDescriptionAttribute)
        let help = copyStringAttr(focused, kAXHelpAttribute)
        let placeholder = copyStringAttr(focused, kAXPlaceholderValueAttribute)
        let blob = normalize([title, desc, help, placeholder])
        return containsAny(blob, from: Heuristics.emailHints)
    }

    private func rootWindow(for element: AXUIElement) -> AXUIElement? {
        if let window = copyElementAttr(element, kAXWindowAttribute) {
            return window
        }

        var current: AXUIElement? = element
        var depth = 0
        while let node = current, depth < 16 {
            let role = copyStringAttr(node, kAXRoleAttribute) ?? ""
            if role == "AXWindow" || role == "AXSheet" {
                return node
            }
            current = copyElementAttr(node, kAXParentAttribute)
            depth += 1
        }
        return current
    }

    private func collectVisibleStrings(in element: AXUIElement, remainingNodes: inout Int, into results: inout [String]) {
        guard remainingNodes > 0 else { return }
        remainingNodes -= 1

        let role = copyStringAttr(element, kAXRoleAttribute) ?? ""
        let isInterestingRole = role == "AXStaticText" || role == "AXButton" || role == "AXTextField"
        if isInterestingRole {
            for value in [copyStringAttr(element, kAXTitleAttribute), copyStringAttr(element, kAXValueAttribute)] {
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !trimmed.isEmpty && trimmed.count <= 120 && !trimmed.contains("\n") {
                    results.append(trimmed)
                }
            }
        }

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return }

        for child in children {
            collectVisibleStrings(in: child, remainingNodes: &remainingNodes, into: &results)
            if remainingNodes <= 0 { break }
        }
    }

    private func cleanedRecipientCandidate(from raw: String) -> String {
        let trimmed = raw.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let angleStart = trimmed.firstIndex(of: "<"), angleStart > trimmed.startIndex {
            return trimmed[..<angleStart]
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"' ").union(.whitespacesAndNewlines))
        }
        return trimmed
    }

    private func recipientCandidateScore(_ candidate: String) -> Int {
        guard !candidate.isEmpty, candidate.count <= 60 else { return 0 }
        let lower = candidate.lowercased()
        let blockedTerms = [
            "send", "sende", "subject", "emne", "mottaker", "recipient", "compose", "ny melding",
            "new message", "sans serif", "flow", "bluespeak", "settings", "home", "continue",
            "til", "cc", "bcc", "inbox", "innboks"
        ]
        if blockedTerms.contains(where: { lower == $0 || lower.contains($0) }) {
            return 0
        }
        if candidate.rangeOfCharacter(from: .decimalDigits) != nil {
            return 0
        }

        let words = candidate.split(separator: " ").map(String.init)
        guard !words.isEmpty, words.count <= 4 else { return 0 }

        let lettersOnly = CharacterSet.letters.union(CharacterSet(charactersIn: "-'"))
        guard words.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy(lettersOnly.contains) }) else {
            return 0
        }

        let capitalizedWords = words.filter { word in
            guard let first = word.unicodeScalars.first else { return false }
            return CharacterSet.uppercaseLetters.contains(first)
        }.count

        switch capitalizedWords {
        case 2...4: return 4
        case 1: return words.count == 1 ? 2 : 3
        default: return 0
        }
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

    private func copyElementAttr(_ el: AXUIElement, _ attr: String) -> AXUIElement? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(el, attr as CFString, &value)
        guard err == .success, let element = value else { return nil }
        return (element as! AXUIElement)
    }

    // NY: konfigurerbar maxLength
    private func copyValuePreview(_ el: AXUIElement, maxLength: Int = 500) -> String? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &value)
        guard err == .success else { return nil }

        if let s = value as? String {
            // Ta de siste maxLength tegnene – mest relevant kontekst er det som er nærmest cursoren
            return String(s.suffix(maxLength))
        }
        return nil
    }
}
