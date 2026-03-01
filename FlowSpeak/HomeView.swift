import AppKit
import SwiftUI

struct HomeView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var activePage: Page = .home

    enum Page: CaseIterable, Identifiable {
        case home
        case style
        case settings

        var id: Self { self }

        var title: String {
            switch self {
            case .home: return "Home"
            case .style: return "Style"
            case .settings: return "Settings"
            }
        }

        var iconName: String {
            switch self {
            case .home: return "house.fill"
            case .style: return "textformat"
            case .settings: return "gearshape.fill"
            }
        }
    }

    var body: some View {
        Group {
            // Gate the main shell until we have either a live JWT or a refresh token we can rotate.
            if settings.hasAuthenticatedSession {
                HStack(spacing: 0) {
                    Sidebar(activePage: $activePage)
                    Divider()
                    pageContent
                }
                .background(AppTheme.canvas)
            } else {
                AuthGateView()
            }
        }
        .frame(width: 980, height: 640)
        .preferredColorScheme(.light)
    }

    @ViewBuilder
    private var pageContent: some View {
        switch activePage {
        case .home:
            MainPage()
        case .style:
            StylePage()
        case .settings:
            SettingsView()
        }
    }
}

private enum AuthFlowMode {
    case signIn
    case signUp

    var title: String {
        switch self {
        case .signIn: return "Log in"
        case .signUp: return "Create account"
        }
    }

    var subtitle: String {
        switch self {
        case .signIn:
            return "Sign in with your FlowSpeak account to use dictation, translation and rewrite on any Mac."
        case .signUp:
            return "Create a FlowSpeak account with email and password. You can start using the app immediately."
        }
    }

    var primaryLabel: String {
        switch self {
        case .signIn: return "Log in"
        case .signUp: return "Create account"
        }
    }

    var alternatePrompt: String {
        switch self {
        case .signIn: return "No account yet?"
        case .signUp: return "Already have an account?"
        }
    }

    var alternateLabel: String {
        switch self {
        case .signIn: return "Sign up"
        case .signUp: return "Log in"
        }
    }
}

struct AuthGateView: View {
    @ObservedObject private var settings = AppSettings.shared

    @State private var mode: AuthFlowMode = .signIn
    @State private var fullName: String = ""
    @State private var country: String = ""
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var marketingOptIn: Bool = false
    @State private var statusText: String = ""
    @State private var isBusy: Bool = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    AppTheme.canvas,
                    Color(red: 0.92, green: 0.96, blue: 1.00),
                    Color.white
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(AppTheme.accentSoft.opacity(0.85))
                .frame(width: 300, height: 300)
                .offset(x: 260, y: -170)

            Circle()
                .fill(Color.white.opacity(0.88))
                .frame(width: 420, height: 420)
                .offset(x: -310, y: 220)

            HStack(spacing: 32) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(AppTheme.accent)
                            .frame(width: 54, height: 54)
                            .overlay(
                                Image(systemName: "waveform.circle.fill")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundStyle(.white)
                            )

                        Text("FlowSpeak")
                            .font(.system(size: 22, weight: .bold, design: .serif))
                            .foregroundStyle(AppTheme.primaryText)
                    }

                    Text("Voice-first writing for every app")
                        .font(.system(size: 42, weight: .bold, design: .serif))
                        .foregroundStyle(AppTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Log in once, then use hold-to-dictate, instant translation and invisible rewrite everywhere you type.")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 10) {
                        AuthFeatureRow(icon: "mic.fill", text: "Hold fn to dictate")
                        AuthFeatureRow(icon: "globe", text: "Hold fn + Shift to translate")
                        AuthFeatureRow(icon: "wand.and.stars", text: "Select text + hold fn + Control to rewrite")
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 16) {
                    Text(mode.title)
                        .font(.system(size: 42, weight: .bold, design: .serif))
                        .foregroundStyle(AppTheme.primaryText)

                    Text(mode.subtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 12) {
                        if mode == .signUp {
                            TextField("Full name", text: $fullName)
                                .textFieldStyle(.plain)
                                .storeField(minHeight: 52)

                            TextField("Country", text: $country)
                                .textFieldStyle(.plain)
                                .storeField(minHeight: 52)
                        }

                        TextField("you@example.com", text: $email)
                            .textFieldStyle(.plain)
                            .storeField(minHeight: 52)

                        SecureField("Password", text: $password)
                            .textFieldStyle(.plain)
                            .storeField(minHeight: 52)

                        if mode == .signUp {
                            Toggle(isOn: $marketingOptIn) {
                                Text("I agree to receive product updates, launch news, and occasional offers by email. You can unsubscribe at any time.")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(AppTheme.primaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .toggleStyle(.checkbox)
                            .padding(12)
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

                    if showsConfigurationWarning {
                        Text("Auth is not configured yet. Open advanced settings to add Supabase details.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.warning)
                    } else {
                        Text(statusLine)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(statusColor)
                    }

                    Button(action: submit) {
                        HStack {
                            Spacer()
                            if isBusy {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                                    .scaleEffect(0.8)
                            } else {
                                Text(mode.primaryLabel)
                                    .font(.system(size: 17, weight: .bold))
                            }
                            Spacer()
                        }
                        .frame(height: 54)
                    }
                    .buttonStyle(StorePrimaryButtonStyle())
                    .disabled(!canSubmit)
                    .opacity(canSubmit ? 1 : 0.65)

                    HStack(spacing: 4) {
                        Text(mode.alternatePrompt)
                            .foregroundStyle(AppTheme.secondaryText)
                        Button(mode.alternateLabel, action: toggleMode)
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                    }
                    .font(.system(size: 13, weight: .medium))
                }
                .padding(32)
                .frame(width: 420)
                .background(
                    RoundedRectangle(cornerRadius: 28)
                        .fill(AppTheme.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 28)
                                .strokeBorder(AppTheme.border, lineWidth: 1)
                        )
                )
                .shadow(color: AppTheme.shadow, radius: 18, x: 0, y: 10)
            }
            .padding(.horizontal, 56)
        }
        .onAppear {
            if email.isEmpty {
                email = settings.supabaseUserEmail
            }
        }
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedFullName: String {
        fullName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedCountry: String {
        country.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var showsConfigurationWarning: Bool {
        !settings.isSupabaseConfigured
    }

    private var canSubmit: Bool {
        guard !isBusy, !showsConfigurationWarning, !trimmedEmail.isEmpty, !password.isEmpty else {
            return false
        }

        if mode == .signUp {
            return !trimmedFullName.isEmpty && !trimmedCountry.isEmpty
        }

        return true
    }

    private var statusLine: String {
        if !statusText.isEmpty {
            return statusText
        }
        if settings.supabaseUserEmail.isEmpty {
            return "Use the same email on every Mac and your JWT will be managed automatically."
        }
        return "Last used account: \(settings.supabaseUserEmail)"
    }

    private var statusColor: Color {
        if statusText.localizedCaseInsensitiveContains("failed") ||
            statusText.localizedCaseInsensitiveContains("missing") ||
            statusText.localizedCaseInsensitiveContains("invalid") {
            return AppTheme.warning
        }
        if statusText.localizedCaseInsensitiveContains("signed in") ||
            statusText.localizedCaseInsensitiveContains("created") {
            return AppTheme.success
        }
        return AppTheme.secondaryText
    }

    private func submit() {
        guard !isBusy else { return }

        isBusy = true
        statusText = mode == .signIn ? "Signing in..." : "Creating account..."

        Task {
            defer {
                isBusy = false
                password = ""
            }

            do {
                switch mode {
                case .signIn:
                    try await settings.signInSupabase(email: email, password: password)
                    email = settings.supabaseUserEmail
                    statusText = "Signed in. Your JWT is active for backend requests."
                case .signUp:
                    let result = try await settings.signUpSupabase(
                        email: email,
                        password: password,
                        fullName: fullName,
                        country: country,
                        marketingOptIn: marketingOptIn
                    )
                    email = settings.supabaseUserEmail
                    switch result {
                    case .signedIn:
                        statusText = "Account created. You are signed in."
                    case .confirmationRequired:
                        statusText = "Account created. Check your email, then log in."
                    }
                }
            } catch {
                statusText = error.localizedDescription
            }
        }
    }

    private func toggleMode() {
        mode = (mode == .signIn) ? .signUp : .signIn
        statusText = ""
        if mode == .signIn {
            password = ""
        }
    }
}

struct AuthFeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 18)
            Text(text)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(AppTheme.secondaryText)
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @Binding var activePage: HomeView.Page

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("FlowSpeak")
                    .font(.system(size: 15, weight: .bold, design: .serif))
                    .foregroundStyle(AppTheme.primaryText)

                Text("Beta")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(AppTheme.accent)
                    )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)

            Divider()
                .padding(.bottom, 8)

            ForEach(HomeView.Page.allCases) { page in
                SidebarItem(
                    icon: page.iconName,
                    label: page.title,
                    active: activePage == page
                ) {
                    activePage = page
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Label("Snarveier", systemImage: "keyboard")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.primaryText)
                Label("Fn: Dictate", systemImage: "mic.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppTheme.secondaryText)
                Label("Fn + Shift: Translate", systemImage: "globe")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppTheme.secondaryText)
                Label("Fn + Control: Rewrite", systemImage: "wand.and.stars")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppTheme.secondaryText)
            }
            .padding(12)
            .appCard(fill: AppTheme.surfaceMuted)
            .padding(12)
        }
        .frame(width: 190)
        .background(AppTheme.sidebar)
    }
}

struct SidebarItem: View {
    let icon: String
    let label: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 13, weight: active ? .semibold : .regular))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(active ? AppTheme.accentSoft : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .foregroundColor(active ? AppTheme.accent : AppTheme.secondaryText)
    }
}

// MARK: - Style Page

enum StyleScope: String, CaseIterable, Identifiable {
    case personal
    case work
    case email
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .personal: return "Personal messages"
        case .work: return "Work messages"
        case .email: return "Email"
        case .other: return "Other"
        }
    }

    var iconNames: [String] {
        switch self {
        case .personal: return ["message.fill", "paperplane.fill", "bubble.left.and.bubble.right.fill"]
        case .work: return ["briefcase.fill", "person.2.fill", "building.2.fill"]
        case .email: return ["envelope.fill", "tray.fill", "mail.stack.fill"]
        case .other: return ["doc.text.fill", "note.text", "square.grid.2x2.fill"]
        }
    }

    var bannerTitle: String {
        switch self {
        case .personal: return "This style applies in personal messaging apps"
        case .work: return "This style applies in workplace messaging apps"
        case .email: return "This style applies in major email apps"
        case .other: return "This style applies in other writing apps"
        }
    }

    var sampleText: String {
        switch self {
        case .personal:
            return "Hey, are you free for lunch tomorrow? Let's do 12 if that works for you."
        case .work:
            return "Hi team, are you available for a quick status sync at 12? Please share blockers."
        case .email:
            return "Hi Alex,\n\nIt was great talking with you today. Looking forward to our next chat.\n\nBest,\nMary"
        case .other:
            return "So far, I am enjoying the new workout routine. I am excited for tomorrow's session."
        }
    }
}

struct StylePage: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var selectedScope: StyleScope = .personal

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Style")
                .font(.system(size: 34, weight: .bold, design: .serif))
                .foregroundStyle(AppTheme.primaryText)
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 18)

            HStack(spacing: 20) {
                ForEach(StyleScope.allCases) { scope in
                    Button(action: { selectedScope = scope }) {
                        VStack(spacing: 8) {
                            Text(scope.title)
                                .font(.system(size: 13, weight: selectedScope == scope ? .semibold : .medium))
                                .foregroundColor(selectedScope == scope ? AppTheme.primaryText : AppTheme.secondaryText)
                            Rectangle()
                                .fill(selectedScope == scope ? AppTheme.accent : Color.clear)
                                .frame(height: 2)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(WritingStyle.allCases) { style in
                        StyleOptionCard(
                            style: style,
                            sampleText: previewText(for: style),
                            isSelected: settings.writingStyle == style
                        ) {
                            settings.writingStyle = style
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 8)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.canvas)
    }

    private func previewText(for style: WritingStyle) -> String {
        style.previewText(from: selectedScope.sampleText)
    }
}

struct StyleOptionCard: View {
    let style: WritingStyle
    let sampleText: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)
                Text(subtitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.secondaryText)

                RoundedRectangle(cornerRadius: 10)
                    .fill(AppTheme.surfaceMuted)
                    .overlay(
                        Text(sampleText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.secondaryText)
                            .multilineTextAlignment(.leading)
                            .lineSpacing(2)
                            .lineLimit(6)
                            .padding(12),
                        alignment: .topLeading
                    )
                    .frame(height: 148)
            }
            .padding(14)
            .frame(width: 228, alignment: .topLeading)
            .frame(height: 248)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(AppTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(
                                isSelected ? AppTheme.accent : AppTheme.border,
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var title: String {
        style.cardTitle
    }

    private var subtitle: String {
        style.cardSubtitle
    }
}

// MARK: - Main Page

struct MainPage: View {
    @ObservedObject private var history = DictationHistory.shared
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .top) {
                Text("Velkommen tilbake")
                    .font(.system(size: 20, weight: .bold, design: .serif))
                    .foregroundStyle(AppTheme.primaryText)

                Spacer()

                // Stats
                HStack(spacing: 6) {
                    StatPill(icon: "🔥", value: streakLabel)
                    StatPill(icon: "🚀", value: "\(history.todayWordCount) ord")
                    StatPill(icon: "📝", value: "\(history.todayEntries.count) dikteringer")
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 16)

            // History header
            Text("I DAG")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(AppTheme.secondaryText)
                .kerning(1.5)
                .padding(.horizontal, 28)
                .padding(.bottom, 8)

            // History list
            if history.todayEntries.isEmpty {
                VStack(spacing: 8) {
                    Text("🎙")
                        .font(.system(size: 32))
                    Text("Ingen dikteringer i dag enda")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(history.todayEntries.enumerated()), id: \.element.id) { i, entry in
                            HistoryRow(entry: entry, isLast: i == history.todayEntries.count - 1)
                        }
                    }
                    .cardSurface()
                    .padding(.horizontal, 28)
                    .padding(.bottom, 20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.canvas)
    }

    private var streakLabel: String {
        let days = history.entries.isEmpty ? 0 : 1
        return "\(days) dag"
    }
}

struct StatPill: View {
    let icon: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(icon).font(.system(size: 11))
            Text(value).font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(AppTheme.surface)
                .overlay(Capsule().strokeBorder(AppTheme.border, lineWidth: 1))
        )
        .foregroundColor(AppTheme.primaryText)
    }
}

struct HistoryRow: View {
    let entry: DictationEntry
    let isLast: Bool

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(Self.timeFormatter.string(from: entry.date))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(AppTheme.secondaryText)
                .padding(.top, 2)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(entry.appName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppTheme.secondaryText)

                    Spacer()

                    ModeBadge(mode: entry.mode)
                    Button(action: copyToClipboard) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppTheme.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .help("Kopier tekst")
                }

                Text(entry.text)
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.primaryText)
                    .lineLimit(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(
            isLast ? nil : Divider()
                .padding(.leading, 68),
            alignment: .bottom
        )
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
    }
}

struct ModeBadge: View {
    let mode: DictationMode

    var color: Color {
        switch mode {
        case .email:   return Color.blue
        case .chat:    return Color.green
        case .note:    return Color.orange
        case .generic: return Color.gray
        }
    }

    var body: some View {
        Text(mode.label)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}

private extension WritingStyle {
    var cardTitle: String {
        switch self {
        case .clean: return "Clean"
        case .formal: return "Formal."
        case .casual: return "Casual"
        case .excited: return "Excited!"
        }
    }

    var cardSubtitle: String {
        switch self {
        case .clean: return "Grammar + self-correct + no fillers"
        case .formal: return "Caps + Punctuation"
        case .casual: return "Caps + Less punctuation"
        case .excited: return "More exclamations"
        }
    }

    func previewText(from source: String) -> String {
        switch self {
        case .clean:
            return source
                .replacingOccurrences(of: "  ", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        case .formal:
            return source
        case .casual:
            return source
                .replacingOccurrences(of: "I am", with: "I'm")
                .replacingOccurrences(of: "Please", with: "pls")
                .replacingOccurrences(of: "Best,", with: "Best")
                .replacingOccurrences(of: ".", with: "")
        case .excited:
            return source
                .replacingOccurrences(of: ".", with: "!")
                .replacingOccurrences(of: "Best,", with: "Best!")
        }
    }
}

private struct CardSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(AppTheme.border, lineWidth: 1)
                )
                .shadow(color: AppTheme.shadow, radius: 10, x: 0, y: 6)
        )
    }
}

private extension View {
    func cardSurface() -> some View {
        modifier(CardSurfaceModifier())
    }
}
