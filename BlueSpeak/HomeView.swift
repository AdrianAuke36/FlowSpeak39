import AppKit
import ApplicationServices
import AVFoundation
import Combine
import Speech
import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var activePage: Page = .home
    @State private var permissionRefreshNonce: Int = 0
    @State private var showSignedOutPopup: Bool = false
    @State private var showUpgradePlansModal: Bool = false
    @State private var showAccountPopover: Bool = false
    @State private var settingsInitialSection: SettingsSection = .general
    @State private var settingsViewIdentity: UUID = UUID()

    enum Page: CaseIterable, Identifiable {
        case home
        case history
        case bugReport
        case settings

        var id: Self { self }

        var title: String {
            switch self {
            case .home:
                return AppSettings.shared.ui("Hjem", "Home")
            case .history:
                return AppSettings.shared.ui("Historikk", "History")
            case .bugReport:
                return AppSettings.shared.ui("Rapporter feil", "Report bug")
            case .settings:
                return AppSettings.shared.ui("Innstillinger", "Settings")
            }
        }

        var iconName: String {
            switch self {
            case .home: return "house.fill"
            case .history: return "clock.arrow.circlepath"
            case .bugReport: return "ladybug.fill"
            case .settings: return "gearshape.fill"
            }
        }
    }

    var body: some View {
        Group {
            // Gate the main shell until we have either a live JWT or a refresh token we can rotate.
            if settings.hasAuthenticatedSession {
                if shouldShowSetupOnboarding {
                    SetupOnboardingView()
                } else {
                    ZStack {
                        HStack(spacing: 0) {
                            Sidebar(
                                activePage: $activePage,
                                onUpgradeTap: { showUpgradePlansModal = true }
                            )
                            Divider()
                            pageContent
                        }

                        VStack {
                            HStack(spacing: 10) {
                                Menu {
                                    ForEach(InterfaceLanguage.allCases) { language in
                                        Button {
                                            settings.interfaceLanguage = language
                                        } label: {
                                            HStack {
                                                Text("\(language.flagEmoji) \(language.label)")
                                                if settings.interfaceLanguage == language {
                                                    Spacer(minLength: 8)
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    Text(settings.interfaceLanguage.flagEmoji)
                                        .font(.system(size: 18))
                                        .frame(width: 34, height: 34)
                                }
                                .menuStyle(.borderlessButton)
                                .buttonStyle(.plain)
                                .background(
                                    Circle()
                                        .fill(AppTheme.surface)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(AppTheme.border, lineWidth: 1)
                                        )
                                )
                                .help(settings.ui("Bytt appspråk", "Change app language"))

                                Button {
                                    showAccountPopover.toggle()
                                } label: {
                                    Image(systemName: "person.crop.circle")
                                        .font(.system(size: 19, weight: .medium))
                                        .foregroundStyle(AppTheme.primaryText)
                                        .frame(width: 34, height: 34)
                                }
                                .buttonStyle(.plain)
                                .background(
                                    Circle()
                                        .fill(AppTheme.surface)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(AppTheme.border, lineWidth: 1)
                                        )
                                )
                                .popover(isPresented: $showAccountPopover, arrowEdge: .top) {
                                    AccountMenuPopover(
                                        displayName: resolvedAccountName,
                                        email: settings.supabaseUserEmail,
                                        onUpgrade: {
                                            showAccountPopover = false
                                            showUpgradePlansModal = true
                                        },
                                        onManageAccount: {
                                            showAccountPopover = false
                                            openAccountSettings()
                                        }
                                    )
                                }
                            }
                            .padding(.top, 14)
                            .padding(.trailing, 20)

                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .zIndex(60)

                        if showUpgradePlansModal {
                            UpgradePlansModal(isPresented: $showUpgradePlansModal)
                                .transition(.opacity)
                                .zIndex(100)
                        }
                    }
                    .background(AppTheme.canvas)
                }
            } else {
                ZStack {
                    AuthGateView()

                    if showSignedOutPopup {
                        SignedOutPopup(isVisible: $showSignedOutPopup)
                            .transition(.opacity)
                            .zIndex(120)
                    }
                }
            }
        }
        .frame(minWidth: 980, minHeight: 640)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            refreshPermissionGate()
            if settings.consumePendingSignedOutPopup() {
                showSignedOutPopup = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionGate()
        }
        .onReceive(NotificationCenter.default.publisher(for: .signedOutPopupRequested)) { _ in
            if !settings.hasAuthenticatedSession && settings.consumePendingSignedOutPopup() {
                showSignedOutPopup = true
            }
        }
        .onChange(of: settings.hasAuthenticatedSession) { _, isAuthenticated in
            if !isAuthenticated {
                GamificationStore.shared.reset()
                if settings.consumePendingSignedOutPopup() {
                    showSignedOutPopup = true
                }
            }
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch activePage {
        case .home:
            MainPage()
        case .history:
            HistoryPage()
        case .bugReport:
            BugReportPage()
        case .settings:
            SettingsView(initialSection: settingsInitialSection)
                .id(settingsViewIdentity)
                .onAppear {
                    if settingsInitialSection != .general {
                        settingsInitialSection = .general
                    }
                }
        }
    }

    private var shouldShowSetupOnboarding: Bool {
        _ = permissionRefreshNonce
        return !settings.hasCompletedSetupOnboarding || Self.hasMissingCriticalPermissions
    }

    private func refreshPermissionGate() {
        permissionRefreshNonce += 1
    }

    private var resolvedAccountName: String {
        let first = settings.supabaseUserFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = settings.supabaseUserLastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let full = [first, last]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !full.isEmpty {
            return full
        }

        let fallback = settings.greetingDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fallback.isEmpty {
            return fallback
        }

        return settings.ui("BlueSpeak-bruker", "BlueSpeak user")
    }

    private func openAccountSettings() {
        settingsInitialSection = .account
        settingsViewIdentity = UUID()
        activePage = .settings
    }

    private static var hasMissingCriticalPermissions: Bool {
        !AXIsProcessTrusted() ||
        !CGPreflightListenEventAccess()
    }
}

private struct AccountMenuPopover: View {
    @ObservedObject private var settings = AppSettings.shared
    let displayName: String
    let email: String
    let onUpgrade: () -> Void
    let onManageAccount: () -> Void

    private func ui(_ norwegian: String, _ english: String) -> String {
        settings.ui(norwegian, english)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Circle()
                    .fill(AppTheme.accentSoft)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Text(initials)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(AppTheme.accent)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(1)

                    Text(email.isEmpty ? ui("Ingen e-post", "No email") : email)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                }
            }
            .padding(16)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text(ui("Du er på BlueSpeak Free", "You are on BlueSpeak Free"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)

                HStack(spacing: 10) {
                    Button(ui("Oppgrader", "Upgrade")) {
                        onUpgrade()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)

                    Button(ui("Administrer konto", "Manage account")) {
                        onManageAccount()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(16)
        }
        .frame(width: 360)
        .background(AppTheme.sheetMaterial)
    }

    private var initials: String {
        let words = displayName
            .split(whereSeparator: \.isWhitespace)
            .prefix(2)
        let letters = words.compactMap { word -> String? in
            guard let first = word.first else { return nil }
            return String(first).uppercased()
        }
        if letters.isEmpty {
            return "B"
        }
        return letters.joined()
    }
}

private struct UpgradePlansModal: View {
    @ObservedObject private var settings = AppSettings.shared
    @Binding var isPresented: Bool
    @State private var billingCycle: BillingCycle = .annual

    private enum BillingCycle: String {
        case monthly
        case annual
    }

    private func ui(_ norwegian: String, _ english: String) -> String {
        settings.ui(norwegian, english)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.34)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 12) {
                    Text(ui("Planer og betaling", "Plans and Billing"))
                        .font(AppTheme.heading(size: 44, weight: .bold))
                        .foregroundStyle(AppTheme.primaryText)

                    Spacer()

                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.secondaryText)
                    .background(
                        Circle()
                            .fill(AppTheme.surface)
                            .overlay(
                                Circle()
                                    .strokeBorder(AppTheme.border, lineWidth: 1)
                            )
                    )
                }

                Divider()

                billingCyclePicker

                HStack(spacing: 0) {
                    planCard(
                        subtitle: ui("For enkeltpersoner", "For individuals"),
                        title: "Basic",
                        price: ui("Gratis", "Free"),
                        badge: nil,
                        features: [
                            ui("3 000 ord per dag", "3,000 words per day"),
                            ui("Diktering, oversettelse og rewrite", "Dictation, translate and rewrite"),
                            ui("Fungerer i alle apper", "Works across all apps"),
                            ui("Standard kundestøtte", "Standard support")
                        ],
                        actionTitle: nil,
                        action: nil,
                        emphasized: false
                    )

                    Divider()

                    planCard(
                        subtitle: ui("For enkeltpersoner og team", "For individuals and teams"),
                        title: "Pro",
                        price: billingCycle == .annual
                            ? ui("12 USD per bruker/mnd", "12 USD per user/mo")
                            : ui("15 USD per bruker/mnd", "15 USD per user/mo"),
                        badge: billingCycle == .annual ? "-20%" : nil,
                        features: [
                            ui("Alt i Basic", "Everything in Basic"),
                            ui("Ubegrenset ord på alle enheter", "Unlimited words on all devices"),
                            ui("Prioritert support", "Priority support"),
                            ui("Tidlig tilgang til nye funksjoner", "Early feature access"),
                            ui("Avansert svar- og rewrite-kontroll", "Advanced reply + rewrite controls")
                        ],
                        actionTitle: ui("Oppgrader til Pro", "Upgrade to Pro"),
                        action: openUpgradePage,
                        emphasized: true
                    )

                    Divider()

                    planCard(
                        subtitle: ui("For team med avanserte behov", "For teams with advanced needs"),
                        title: "Enterprise",
                        price: billingCycle == .annual
                            ? ui("24 USD per bruker/mnd", "24 USD per user/mo")
                            : ui("30 USD per bruker/mnd", "30 USD per user/mo"),
                        badge: nil,
                        features: [
                            ui("Alt i Pro", "Everything in Pro"),
                            "SSO / SAML",
                            ui("Bruksinnsikt", "Usage insights"),
                            ui("Dedikert onboarding", "Dedicated onboarding"),
                            ui("Prioritert SLA-support", "Priority SLA support")
                        ],
                        actionTitle: ui("Opprett team", "Create a team"),
                        action: openTeamPage,
                        emphasized: false
                    )
                }
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(AppTheme.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(AppTheme.border, lineWidth: 1)
                        )
                )
            }
            .padding(28)
            .frame(maxWidth: 1120)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(AppTheme.sheetMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(AppTheme.surface.opacity(0.22))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(AppTheme.border, lineWidth: 1)
                    )
                    .shadow(color: AppTheme.shadow, radius: 22, x: 0, y: 10)
            )
            .padding(24)
        }
    }

    private var billingCyclePicker: some View {
        HStack(spacing: 0) {
            billingCycleButton(title: ui("Månedlig", "Monthly"), cycle: .monthly)
            billingCycleButton(title: ui("Årlig", "Annual"), cycle: .annual)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(AppTheme.border, lineWidth: 1)
                )
        )
        .frame(maxWidth: 340)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func billingCycleButton(title: String, cycle: BillingCycle) -> some View {
        let selected = billingCycle == cycle
        return Button(title) {
            billingCycle = cycle
        }
        .buttonStyle(.plain)
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(selected ? AppTheme.primaryText : AppTheme.secondaryText)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(selected ? AppTheme.canvas : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(selected ? AppTheme.border : Color.clear, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func planCard(
        subtitle: String,
        title: String,
        price: String,
        badge: String?,
        features: [String],
        actionTitle: String?,
        action: (() -> Void)?,
        emphasized: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(subtitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppTheme.secondaryText)

                HStack(spacing: 8) {
                    Text(title)
                        .font(AppTheme.heading(size: 38, weight: .bold))
                        .foregroundStyle(AppTheme.primaryText)

                    if let badge {
                        Text(badge)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AppTheme.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(AppTheme.accentSoft)
                            )
                    }
                }

                Text(price)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(AppTheme.primaryText)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                ForEach(features, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppTheme.success)
                            .padding(.top, 3)

                        Text(item)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AppTheme.primaryText)
                    }
                }

                Spacer(minLength: 8)

                if let actionTitle, let action {
                    Button(actionTitle) {
                        action()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(emphasized ? AppTheme.primaryText : AppTheme.surface)
                    .foregroundStyle(emphasized ? AppTheme.canvas : AppTheme.primaryText)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, minHeight: 560)
    }

    private func openUpgradePage() {
        guard let url = URL(string: "https://flow-speak-direct.lovable.app") else { return }
        NSWorkspace.shared.open(url)
    }

    private func openTeamPage() {
        guard let url = URL(string: "https://flow-speak-direct.lovable.app") else { return }
        NSWorkspace.shared.open(url)
    }
}

private enum AuthFlowMode {
    case signIn
    case signUp

    var title: String {
        switch self {
        case .signIn:
            return AppSettings.shared.ui("Logg inn", "Log in")
        case .signUp:
            return AppSettings.shared.ui("Opprett konto", "Create account")
        }
    }

    var subtitle: String {
        switch self {
        case .signIn:
            return AppSettings.shared.ui(
                "Logg inn med BlueSpeak-kontoen din for å bruke diktering, oversettelse og rewrite på alle Mac-er.",
                "Sign in with your BlueSpeak account to use dictation, translation and rewrite on any Mac."
            )
        case .signUp:
            return AppSettings.shared.ui(
                "Opprett en BlueSpeak-konto med e-post og passord. Du kan starte med appen med en gang.",
                "Create a BlueSpeak account with email and password. You can start using the app immediately."
            )
        }
    }

    var primaryLabel: String {
        switch self {
        case .signIn:
            return AppSettings.shared.ui("Logg inn", "Log in")
        case .signUp:
            return AppSettings.shared.ui("Opprett konto", "Create account")
        }
    }

    var alternatePrompt: String {
        switch self {
        case .signIn:
            return AppSettings.shared.ui("Ingen konto ennå?", "No account yet?")
        case .signUp:
            return AppSettings.shared.ui("Har du allerede en konto?", "Already have an account?")
        }
    }

    var alternateLabel: String {
        switch self {
        case .signIn:
            return AppSettings.shared.ui("Registrer deg", "Sign up")
        case .signUp:
            return AppSettings.shared.ui("Logg inn", "Log in")
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

    private func ui(_ norwegian: String, _ english: String) -> String {
        settings.ui(norwegian, english)
    }

    var body: some View {
        ZStack {
            AppTheme.canvas
                .ignoresSafeArea()

            HStack(spacing: 32) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        BrandMarkView(size: 22)
                        BrandWordmarkView(size: 40)
                    }

                    Text(ui("Stemme-først skriving i alle apper", "Voice-first writing for every app"))
                        .font(AppTheme.heading(size: 42, weight: .bold))
                        .foregroundStyle(AppTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(ui(
                        "Logg inn én gang, og bruk hold-for-å-diktere, umiddelbar oversettelse og usynlig rewrite overalt du skriver.",
                        "Log in once, then use hold-to-dictate, instant translation and invisible rewrite everywhere you type."
                    ))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 10) {
                        AuthFeatureRow(icon: "mic.fill", text: ui(
                            "Hold \(settings.shortcutTriggerKey.dictateShortcut) for å diktere",
                            "Hold \(settings.shortcutTriggerKey.dictateShortcut) to dictate"
                        ))
                        AuthFeatureRow(icon: "globe", text: ui(
                            "Hold \(settings.shortcutTriggerKey.translateShortcut) for å oversette",
                            "Hold \(settings.shortcutTriggerKey.translateShortcut) to translate"
                        ))
                        AuthFeatureRow(icon: "wand.and.stars", text: ui(
                            "Marker tekst + hold \(settings.shortcutTriggerKey.rewriteShortcut) for rewrite",
                            "Select text + hold \(settings.shortcutTriggerKey.rewriteShortcut) to rewrite"
                        ))
                        AuthFeatureRow(icon: "tray.and.arrow.down.fill", text: ui(
                            "Marker melding + trykk \(settings.shortcutTriggerKey.saveReplyContextShortcut) for å lagre svarkontekst",
                            "Select message + press \(settings.shortcutTriggerKey.saveReplyContextShortcut) to save reply context"
                        ))
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 16) {
                    Text(mode.title)
                        .font(AppTheme.heading(size: 30, weight: .bold))
                        .foregroundStyle(AppTheme.primaryText)

                    Text(mode.subtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 12) {
                        if mode == .signUp {
                            TextField(ui("Fullt navn", "Full name"), text: $fullName)
                                .textFieldStyle(.plain)
                                .storeField(minHeight: 52)

                            TextField(ui("Land", "Country"), text: $country)
                                .textFieldStyle(.plain)
                                .storeField(minHeight: 52)
                        }

                        TextField(ui("du@eksempel.no", "you@example.com"), text: $email)
                            .textFieldStyle(.plain)
                            .storeField(minHeight: 52)

                        SecureField(ui("Passord", "Password"), text: $password)
                            .textFieldStyle(.plain)
                            .storeField(minHeight: 52)

                        if mode == .signUp {
                            Toggle(isOn: $marketingOptIn) {
                                Text(ui(
                                    "Jeg godtar å motta produktoppdateringer, lanseringsnyheter og sporadiske tilbud på e-post. Du kan melde deg av når som helst.",
                                    "I agree to receive product updates, launch news, and occasional offers by email. You can unsubscribe at any time."
                                ))
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
                        Text(ui(
                            "Innlogging er ikke konfigurert ennå. Åpne avanserte innstillinger for å legge til Supabase-detaljer.",
                            "Auth is not configured yet. Open advanced settings to add Supabase details."
                        ))
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
                                    .tint(AppTheme.accentText)
                                    .scaleEffect(0.8)
                            } else {
                                Text(mode.primaryLabel)
                                    .font(.system(size: 17, weight: .bold))
                            }
                            Spacer()
                        }
                        .frame(height: 54)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .controlSize(.large)
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

                    if mode == .signIn {
                        Button(ui("Glemt passord?", "Forgot password?")) {
                            requestPasswordReset()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                        .disabled(isBusy || showsConfigurationWarning)
                    }
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
            return ui(
                "Bruk samme e-post på alle Mac-er, så håndteres JWT automatisk.",
                "Use the same email on every Mac and your JWT will be managed automatically."
            )
        }
        return ui("Sist brukte konto: ", "Last used account: ") + settings.supabaseUserEmail
    }

    private var statusColor: Color {
        if statusText.localizedCaseInsensitiveContains("failed") ||
            statusText.localizedCaseInsensitiveContains("missing") ||
            statusText.localizedCaseInsensitiveContains("invalid") ||
            statusText.localizedCaseInsensitiveContains("feilet") ||
            statusText.localizedCaseInsensitiveContains("mangler") ||
            statusText.localizedCaseInsensitiveContains("ugyldig") {
            return AppTheme.warning
        }
        if statusText.localizedCaseInsensitiveContains("signed in") ||
            statusText.localizedCaseInsensitiveContains("created") ||
            statusText.localizedCaseInsensitiveContains("innlogget") ||
            statusText.localizedCaseInsensitiveContains("opprettet") {
            return AppTheme.success
        }
        return AppTheme.secondaryText
    }

    private func submit() {
        guard !isBusy else { return }

        isBusy = true
        statusText = mode == .signIn
            ? ui("Logger inn...", "Signing in...")
            : ui("Oppretter konto...", "Creating account...")

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
                    statusText = ui(
                        "Innlogget. JWT er aktiv for backend-kall.",
                        "Signed in. Your JWT is active for backend requests."
                    )
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
                        statusText = ui("Konto opprettet. Du er innlogget.", "Account created. You are signed in.")
                    case .confirmationRequired:
                        statusText = ui(
                            "Konto opprettet. Sjekk e-posten din og logg inn.",
                            "Account created. Check your email, then log in."
                        )
                    }
                }
            } catch {
                statusText = error.localizedDescription
                AppLogStore.shared.record(.warning, "Auth action failed", metadata: [
                    "mode": mode == .signIn ? "sign_in" : "sign_up",
                    "error": error.localizedDescription
                ])
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

    private func requestPasswordReset() {
        guard !isBusy else { return }
        guard !showsConfigurationWarning else {
            statusText = ui("Innlogging er ikke konfigurert ennå.", "Auth is not configured yet.")
            AppLogStore.shared.record(.warning, "Password reset blocked", metadata: ["reason": "auth_not_configured"])
            return
        }

        isBusy = true
        statusText = ui("Sender e-post for passordtilbakestilling...", "Sending reset email...")

        Task {
            defer { isBusy = false }

            do {
                try await settings.requestSupabasePasswordReset(email: email)
                statusText = ui(
                    "Hvis kontoen finnes, er en e-post for passordtilbakestilling sendt.",
                    "If the account exists, a password reset email has been sent."
                )
            } catch {
                statusText = error.localizedDescription
                AppLogStore.shared.record(.warning, "Password reset failed", metadata: ["error": error.localizedDescription])
            }
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

private enum SetupOnboardingStep {
    case accessibility
    case inputMonitoring
    case microphone
    case speechRecognition

    var order: Int {
        switch self {
        case .accessibility: return 0
        case .inputMonitoring: return 1
        case .microphone: return 2
        case .speechRecognition: return 3
        }
    }
}

private enum MicrophonePermissionState {
    case authorized
    case denied
    case restricted
    case notDetermined
}

struct SetupOnboardingView: View {
    @ObservedObject private var settings = AppSettings.shared

    @State private var step: SetupOnboardingStep = .accessibility
    @State private var speechGranted: Bool = false
    @State private var microphoneGranted: Bool = false
    @State private var accessibilityGranted: Bool = false
    @State private var inputMonitoringGranted: Bool = false
    @State private var statusText: String = ""

    private let speechRecognitionSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")!
    private let microphoneSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
    private let accessibilitySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    private let inputMonitoringSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
    private let permissionRefreshTimer = Timer.publish(every: 0.8, on: .main, in: .common).autoconnect()

    private func ui(_ norwegian: String, _ english: String) -> String {
        settings.ui(norwegian, english)
    }

    private var speechRecognitionRequired: Bool {
        settings.speechRecognitionRequiredForDictation
    }

    var body: some View {
        ZStack {
            AppTheme.canvas
                .ignoresSafeArea()

            HStack(spacing: 56) {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 10) {
                        BrandMarkView(size: 24)
                        BrandWordmarkView(size: 48)
                    }

                    if step != .accessibility {
                        Button {
                            step = previousStep(for: step)
                            statusText = ""
                        } label: {
                            Label(ui("Tilbake", "Back"), systemImage: "arrow.left")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        .buttonStyle(.plain)
                    }

                    Text(stepTitle)
                        .font(AppTheme.heading(size: 44, weight: .bold))
                        .foregroundStyle(AppTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(stepSubtitle)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)

                    if currentStepGranted {
                        permissionBadge(text: grantedBadgeText, color: AppTheme.success)
                    }

                    if !statusText.isEmpty {
                        Text(statusText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 12) {
                        if showsPrimaryActionButton {
                            Button(primaryActionTitle, action: primaryAction)
                                .buttonStyle(.borderedProminent)
                                .tint(AppTheme.accent)
                                .controlSize(.large)
                        }

                        Button(ui("Sjekk tillatelser på nytt", "Re-check permissions")) {
                            refreshPermissionState()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)

                        if showsContinueButton {
                            Button(ui("Fortsett", "Continue"), action: continueAction)
                                .buttonStyle(.borderedProminent)
                                .tint(AppTheme.accent)
                                .controlSize(.large)
                                .disabled(!canContinue)
                                .opacity(canContinue ? 1 : 0.45)
                        }

                        if showsSkipButton {
                            Button(ui("Hopp over nå", "Skip for now"), action: skipCurrentOptionalStep)
                                .buttonStyle(.bordered)
                                .controlSize(.large)
                        }

                        if showsFinishButton {
                            Button(ui("Fullfør oppsett", "Finish setup"), action: finishOnboarding)
                                .buttonStyle(.borderedProminent)
                                .tint(AppTheme.accent)
                                .controlSize(.large)
                                .disabled(!criticalPermissionsGranted)
                                .opacity(criticalPermissionsGranted ? 1 : 0.45)
                        }
                    }
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                permissionPreviewCard
                    .frame(width: 340)
            }
            .padding(.horizontal, 56)
        }
        .onAppear {
            refreshPermissionState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionState()
        }
        .onReceive(permissionRefreshTimer) { _ in
            refreshPermissionState()
        }
    }

    private var stepTitle: String {
        switch step {
        case .speechRecognition:
            return ui("Aktiver talegjenkjenning", "Enable speech recognition")
        case .microphone:
            return ui("Sett opp mikrofon", "Set up your microphone")
        case .accessibility:
            return ui("Aktiver Tilgjengelighet", "Enable Accessibility")
        case .inputMonitoring:
            return ui("Aktiver Inndataovervåking", "Enable Input Monitoring")
        }
    }

    private var stepSubtitle: String {
        switch step {
        case .speechRecognition:
            if speechRecognitionRequired {
                return ui(
                    "BlueSpeak bruker Apples talegjenkjenning for å gjøre stemmen din om til tekst. Du kan hoppe over nå og aktivere senere.",
                    "BlueSpeak uses Apple's speech recognition to turn your voice into text. You can skip this now and enable it later."
                )
            }
            return ui(
                "Talegjenkjenning er valgfritt når skybasert STT er valgt. Du kan aktivere det senere hvis du bytter tilbake til Apple Speech.",
                "Speech recognition is optional when cloud STT is selected. You can enable it later if you switch back to Apple Speech."
            )
        case .microphone:
            return ui(
                "BlueSpeak aktiverer bare mikrofonen når du starter diktering. Du kan hoppe over nå og aktivere senere.",
                "BlueSpeak only activates your microphone when you choose to start dictation. You can skip this now and enable it later."
            )
        case .accessibility:
            return ui(
                "BlueSpeak trenger Tilgjengelighet-tilgang for å lime inn diktering i aktive tekstfelt og kjøre rewrite.",
                "BlueSpeak needs accessibility access to paste dictation into focused text fields and run rewrite."
            )
        case .inputMonitoring:
            return ui(
                "BlueSpeak trenger Inndataovervåking for å oppdage hovedtasten globalt og trigge dikteringssnarveier.",
                "BlueSpeak needs input monitoring to detect the fn key globally and trigger dictation shortcuts."
            )
        }
    }

    private var primaryActionTitle: String {
        switch step {
        case .accessibility:
            return ui("Åpne Tilgjengelighet-innstillinger", "Open Accessibility Settings")
        case .inputMonitoring:
            if inputMonitoringGranted { return ui("Fortsett", "Continue") }
            return ui("Tillat Inndataovervåking", "Allow input monitoring")
        case .microphone:
            let status = microphonePermissionState()
            if status == .denied || status == .restricted { return ui("Åpne mikrofoninnstillinger", "Open Microphone Settings") }
            return ui("Tillat mikrofon", "Allow microphone")
        case .speechRecognition:
            if !speechRecognitionRequired { return ui("Fortsett", "Continue") }
            let status = SFSpeechRecognizer.authorizationStatus()
            if status == .denied || status == .restricted { return ui("Åpne taleinnstillinger", "Open Speech Settings") }
            return ui("Tillat talegjenkjenning", "Allow speech recognition")
        }
    }

    private var showsPrimaryActionButton: Bool {
        return !currentStepGranted
    }

    private var showsContinueButton: Bool {
        currentStepGranted && step != .speechRecognition
    }

    private var showsFinishButton: Bool {
        switch step {
        case .speechRecognition:
            return currentStepGranted || criticalPermissionsGranted
        case .accessibility, .inputMonitoring, .microphone:
            return false
        }
    }

    private var showsSkipButton: Bool {
        isOptionalStep && !currentStepGranted && criticalPermissionsGranted
    }

    private var isOptionalStep: Bool {
        step == .microphone || step == .speechRecognition
    }

    private var criticalPermissionsGranted: Bool {
        accessibilityGranted && inputMonitoringGranted
    }

    private var canContinue: Bool {
        currentStepGranted
    }

    private var currentStepGranted: Bool {
        switch step {
        case .speechRecognition:
            return !speechRecognitionRequired || speechGranted
        case .microphone:
            return microphoneGranted
        case .accessibility:
            return accessibilityGranted
        case .inputMonitoring:
            return inputMonitoringGranted
        }
    }

    private var grantedBadgeText: String {
        switch step {
        case .accessibility:
            return ui("Tilgjengelighet aktivert", "Accessibility access granted")
        case .inputMonitoring:
            return ui("Inndataovervåking aktivert", "Input Monitoring granted")
        case .microphone:
            return ui("Mikrofontilgang aktivert", "Microphone access granted")
        case .speechRecognition:
            return ui("Talegjenkjenning aktivert", "Speech recognition granted")
        }
    }

    @ViewBuilder
    private var permissionPreviewCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            RoundedRectangle(cornerRadius: 18)
                .fill(AppTheme.surfaceMuted)
                .frame(width: 72, height: 72)
                .overlay(
                    Image(systemName: stepIconName)
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryText)
                )

            Text(stepCardTitle)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AppTheme.primaryText)

            Text(stepCardDescription)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.secondaryText)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 120), spacing: 10),
                    GridItem(.flexible(minimum: 120), spacing: 10)
                ],
                alignment: .leading,
                spacing: 10
            ) {
                permissionStatePill(
                    step: .speechRecognition,
                    label: ui("Tale", "Speech"),
                    granted: speechGranted
                )
                permissionStatePill(
                    step: .microphone,
                    label: ui("Mikrofon", "Mic"),
                    granted: microphoneGranted
                )
                permissionStatePill(
                    step: .accessibility,
                    label: ui("Tilgang", "Access"),
                    granted: accessibilityGranted
                )
                permissionStatePill(
                    step: .inputMonitoring,
                    label: ui("Inndata", "Input"),
                    granted: inputMonitoringGranted
                )
            }
            .padding(.top, 6)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(AppTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .strokeBorder(AppTheme.border, lineWidth: 1)
                )
        )
    }

    private func permissionBadge(text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
            Text(text)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(color.opacity(0.14))
        )
    }

    private func permissionStatePill(step cardStep: SetupOnboardingStep, label: String, granted: Bool) -> some View {
        let isCurrentStep = cardStep == step
        return HStack(alignment: .center, spacing: 8) {
            Image(systemName: cardStep.iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isCurrentStep ? AppTheme.primaryText : AppTheme.secondaryText)

            Image(systemName: granted ? "checkmark.circle.fill" : "minus.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(granted ? AppTheme.success : AppTheme.secondaryText)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Spacer(minLength: 0)
        }
        .foregroundStyle(AppTheme.secondaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isCurrentStep ? AppTheme.surface : AppTheme.surfaceMuted)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            isCurrentStep ? AppTheme.fieldBorder : AppTheme.border,
                            lineWidth: 1
                        )
                )
        )
    }

    private func primaryAction() {
        switch step {
        case .accessibility:
            handleAccessibilityAction()
        case .inputMonitoring:
            handleInputMonitoringAction()
        case .microphone:
            handleMicrophoneAction()
        case .speechRecognition:
            handleSpeechRecognitionAction()
        }
    }

    private func continueAction() {
        guard currentStepGranted else { return }

        if step == .speechRecognition {
            finishOnboarding()
            return
        }

        step = nextStep(for: step)
        statusText = ""
        refreshPermissionState()
    }

    private func skipCurrentOptionalStep() {
        guard isOptionalStep else { return }

        switch step {
        case .microphone:
            step = .speechRecognition
            statusText = ui(
                "Mikrofon kan aktiveres senere i Systeminnstillinger.",
                "Microphone can be enabled later in System Settings."
            )
        case .speechRecognition:
            finishOnboarding()
        case .accessibility, .inputMonitoring:
            break
        }
    }

    private func finishOnboarding() {
        guard criticalPermissionsGranted else {
            statusText = ui(
                "Tilgjengelighet og Inndataovervåking må være aktivert før oppsettet kan fullføres.",
                "Accessibility and Input Monitoring must be enabled before setup can finish."
            )
            return
        }

        AppLogStore.shared.record(
            .info,
            "Onboarding completed",
            metadata: [
                "accessibility": accessibilityGranted ? "true" : "false",
                "inputMonitoring": inputMonitoringGranted ? "true" : "false",
                "microphone": microphoneGranted ? "true" : "false",
                "speechRecognition": speechGranted ? "true" : "false"
            ]
        )
        statusText = ""
        settings.completeSetupOnboarding()
    }

    private func handleSpeechRecognitionAction() {
        if !speechRecognitionRequired {
            speechGranted = true
            statusText = ui(
                "Talegjenkjenning er valgfritt med nåværende STT-leverandør.",
                "Speech recognition is optional with current STT provider."
            )
            refreshPermissionState()
            return
        }
        let status = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .authorized:
            speechGranted = true
            statusText = ui(
                "Talegjenkjenning er klar. Trykk Fortsett når du vil gå videre.",
                "Speech recognition is ready. Press Continue when you want to move on."
            )
            refreshPermissionState()
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { authorizationStatus in
                DispatchQueue.main.async {
                    self.refreshPermissionState()
                    if authorizationStatus == .authorized {
                        self.statusText = ui(
                            "Talegjenkjenning er klar. Trykk Fortsett når du vil gå videre.",
                            "Speech recognition is ready. Press Continue when you want to move on."
                        )
                    } else {
                        self.statusText = ui(
                            "Talegjenkjenning ble avslått. Åpne Systeminnstillinger for å tillate det.",
                            "Speech recognition was denied. Open System Settings to allow it."
                        )
                    }
                }
            }
        case .denied, .restricted:
            statusText = ui(
                "Aktiver talegjenkjenning i Systeminnstillinger, og gå tilbake til BlueSpeak.",
                "Enable speech recognition in System Settings, then return to BlueSpeak."
            )
            NSWorkspace.shared.open(speechRecognitionSettingsURL)
        @unknown default:
            statusText = ui("Kunne ikke verifisere tillatelse for talegjenkjenning.", "Unable to verify speech recognition permission.")
        }
    }

    private func handleMicrophoneAction() {
        let status = microphonePermissionState()
        AppLogStore.shared.record(
            .info,
            "Onboarding microphone action",
            metadata: ["status": microphoneAuthorizationStatusLabel(status)]
        )

        if status == .authorized {
            microphoneGranted = true
            statusText = ui(
                "Mikrofontilgang er klar. Trykk Fortsett når du vil gå videre.",
                "Microphone access is ready. Press Continue when you want to move on."
            )
            refreshPermissionState()
            return
        }

        if status == .denied || status == .restricted {
            if status == .restricted {
                statusText = ui("Mikrofontilgang er begrenset av macOS-policy.", "Microphone access is restricted by macOS policy.")
            } else {
                statusText = ui(
                    "Mikrofontilgang ble avslått. Åpne Systeminnstillinger for å tillate det.",
                    "Microphone access was denied. Open System Settings to allow it."
                )
            }
            NSWorkspace.shared.open(microphoneSettingsURL)
            return
        }

        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                self.finishMicrophonePermissionRequest(granted: granted)
            }
        }
    }

    private func microphonePermissionState() -> MicrophonePermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }

    private func finishMicrophonePermissionRequest(granted: Bool) {
        refreshPermissionState()

        let updatedStatus = microphonePermissionState()
        AppLogStore.shared.record(
            .info,
            "Onboarding microphone callback",
            metadata: [
                "granted": granted ? "true" : "false",
                "status": microphoneAuthorizationStatusLabel(updatedStatus)
            ]
        )

        if granted || updatedStatus == .authorized {
            statusText = ui(
                "Mikrofontilgang er klar. Trykk Fortsett når du vil gå videre.",
                "Microphone access is ready. Press Continue when you want to move on."
            )
            return
        }

        switch updatedStatus {
        case .restricted:
            statusText = ui("Mikrofontilgang er begrenset av macOS-policy.", "Microphone access is restricted by macOS policy.")
        case .denied:
            statusText = ui(
                "Mikrofontilgang ble avslått. Åpne Systeminnstillinger for å tillate det.",
                "Microphone access was denied. Open System Settings to allow it."
            )
            NSWorkspace.shared.open(microphoneSettingsURL)
        case .notDetermined:
            statusText = ui(
                "Kunne ikke vise mikrofonforespørselen. Avslutt og åpne BlueSpeak på nytt, og prøv igjen.",
                "Could not show microphone prompt. Quit and reopen BlueSpeak, then try again."
            )
        case .authorized:
            statusText = ui(
                "Mikrofontilgang er klar. Trykk Fortsett når du vil gå videre.",
                "Microphone access is ready. Press Continue when you want to move on."
            )
        }
    }

    private func microphoneAuthorizationStatusLabel(_ status: MicrophonePermissionState) -> String {
        switch status {
        case .authorized:
            return "authorized"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        case .notDetermined:
            return "notDetermined"
        }
    }

    private func handleAccessibilityAction() {
        refreshPermissionState()
        guard !accessibilityGranted else {
            continueAction()
            return
        }

        statusText = ui(
            "Aktiver BlueSpeak i Personvern og sikkerhet, gå deretter tilbake hit og trykk Fortsett.",
            "Enable BlueSpeak in Privacy & Security, then return here and press Continue."
        )
        NSWorkspace.shared.open(accessibilitySettingsURL)
    }

    private func handleInputMonitoringAction() {
        refreshPermissionState()
        guard !inputMonitoringGranted else {
            continueAction()
            return
        }

        let granted = CGRequestListenEventAccess()
        refreshPermissionState()
        if granted {
            statusText = ui(
                "Inndataovervåking er klar. Trykk Fortsett når du vil gå videre.",
                "Input Monitoring is ready. Press Continue when you want to move on."
            )
        } else {
            statusText = ui(
                "Aktiver BlueSpeak i Inndataovervåking, gå deretter tilbake hit og trykk Fortsett.",
                "Enable BlueSpeak in Input Monitoring, then return here and press Continue."
            )
            NSWorkspace.shared.open(inputMonitoringSettingsURL)
        }
    }

    private func refreshPermissionState() {
        speechGranted = !speechRecognitionRequired || (SFSpeechRecognizer.authorizationStatus() == .authorized)
        microphoneGranted = microphonePermissionState() == .authorized
        accessibilityGranted = AXIsProcessTrusted()
        inputMonitoringGranted = CGPreflightListenEventAccess()

        if speechGranted && microphoneGranted && accessibilityGranted && inputMonitoringGranted {
            statusText = ""
            settings.completeSetupOnboarding()
            return
        }

        if currentStepGranted {
            switch step {
            case .accessibility:
                statusText = ui(
                    "Tilgjengelighet er klar. Trykk Fortsett når du vil gå videre.",
                    "Accessibility is ready. Press Continue when you want to move on."
                )
            case .inputMonitoring:
                statusText = ui(
                    "Inndataovervåking er klar. Trykk Fortsett når du vil gå videre.",
                    "Input Monitoring is ready. Press Continue when you want to move on."
                )
            case .microphone:
                statusText = ui(
                    "Mikrofontilgang er klar. Trykk Fortsett når du vil gå videre.",
                    "Microphone access is ready. Press Continue when you want to move on."
                )
            case .speechRecognition:
                statusText = ui("Talegjenkjenning er klar.", "Speech recognition is ready.")
            }
        }

        if let incompleteCriticalStep = firstIncompleteCriticalStep,
           incompleteCriticalStep.order < step.order {
            step = incompleteCriticalStep
        }
    }

    private var firstIncompleteCriticalStep: SetupOnboardingStep? {
        if !accessibilityGranted { return .accessibility }
        if !inputMonitoringGranted { return .inputMonitoring }
        return nil
    }

    private var stepIconName: String {
        step.iconName
    }

    private var stepCardTitle: String {
        switch step {
        case .accessibility:
            return ui("Tilgjengelighet", "Accessibility access")
        case .inputMonitoring:
            return ui("Inndataovervåking", "Input Monitoring")
        case .microphone:
            return ui("Mikrofontilgang", "Microphone access")
        case .speechRecognition:
            return ui("Talegjenkjenning", "Speech recognition")
        }
    }

    private var stepCardDescription: String {
        switch step {
        case .accessibility:
            return ui(
                "Slå på BlueSpeak i Personvern og sikkerhet. macOS kan kreve omstart før full tilgang blir aktiv.",
                "Turn on BlueSpeak in Privacy & Security. macOS can require relaunch before full access becomes active."
            )
        case .inputMonitoring:
            return ui(
                "BlueSpeak bruker dette kun for å oppdage hovedtast-snarveien globalt. Slå det på, og fortsett.",
                "BlueSpeak uses this only to detect the fn shortcut globally. Turn it on, then continue."
            )
        case .microphone:
            return ui(
                "Valgfritt: macOS spør én gang om mikrofontilgang. Etter at du tillater det, kan BlueSpeak ta opp når du holder hovedtasten.",
                "Optional: macOS asks once for microphone access. After you allow it, BlueSpeak can record when you hold fn."
            )
        case .speechRecognition:
            if speechRecognitionRequired {
                return ui(
                    "Valgfritt: macOS spør én gang om talegjenkjenning. Etter at du tillater det, kan BlueSpeak bruke Apples talegjenkjenning.",
                    "Optional: macOS asks once for voice transcription. After you allow it, BlueSpeak can use Apple's speech recognition engine."
                )
            }
            return ui(
                "Valgfritt: dette er ikke nødvendig med sky-STT, men du kan fortsatt aktivere det nå for Apple Speech som reserve.",
                "Optional: this is not required with cloud STT, but you can still enable it now for Apple Speech fallback."
            )
        }
    }

    private func nextStep(for current: SetupOnboardingStep) -> SetupOnboardingStep {
        switch current {
        case .accessibility:
            return .inputMonitoring
        case .inputMonitoring:
            return .microphone
        case .microphone:
            return .speechRecognition
        case .speechRecognition:
            return .speechRecognition
        }
    }

    private func previousStep(for current: SetupOnboardingStep) -> SetupOnboardingStep {
        switch current {
        case .accessibility:
            return .accessibility
        case .inputMonitoring:
            return .accessibility
        case .microphone:
            return .inputMonitoring
        case .speechRecognition:
            return .microphone
        }
    }
}

private extension SetupOnboardingStep {
    var iconName: String {
        switch self {
        case .speechRecognition:
            return "waveform.badge.magnifyingglass"
        case .microphone:
            return "mic.fill"
        case .accessibility:
            return "hand.raised.fill"
        case .inputMonitoring:
            return "keyboard.fill"
        }
    }
}

@MainActor
final class GamificationStore: ObservableObject {
    static let shared = GamificationStore()

    @Published private(set) var snapshot: GamificationSnapshot?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastRefreshAt: Date?
    @Published private(set) var lastError: String?

    private let minimumRefreshInterval: TimeInterval = 2.5
    private var lastAttemptAt: Date = .distantPast

    private init() {}

    func refresh(force: Bool = false) async {
        if isLoading { return }
        let now = Date()
        if !force && now.timeIntervalSince(lastAttemptAt) < minimumRefreshInterval {
            return
        }

        lastAttemptAt = now
        isLoading = true
        defer { isLoading = false }

        do {
            let value = try await AIClient.shared.fetchGamification()
            snapshot = value
            lastRefreshAt = Date()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func reset() {
        snapshot = nil
        lastError = nil
        lastRefreshAt = nil
        lastAttemptAt = .distantPast
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var history = DictationHistory.shared
    @StateObject private var gamification = GamificationStore.shared
    @Binding var activePage: HomeView.Page
    let onUpgradeTap: () -> Void

    private let sidebarWidth: CGFloat = 300

    private func ui(_ norwegian: String, _ english: String) -> String {
        settings.ui(norwegian, english)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                BrandMarkView(size: 18)
                BrandWordmarkView(size: 34)
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)
                    .layoutPriority(1)

                Text(planBadgeLabel)
                    .font(AppTheme.mono(size: 11, weight: .regular))
                    .foregroundStyle(planBadgeTextColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(AppTheme.fieldMaterial)
                            .overlay(
                                Capsule()
                                    .strokeBorder(planBadgeBorderColor, lineWidth: 1)
                            )
                    )

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)

            Divider()
                .padding(.bottom, 8)

            ForEach(primaryPages) { page in
                SidebarItem(
                    icon: page.iconName,
                    label: page.title,
                    active: activePage == page,
                    showLabel: true
                ) {
                    activePage = page
                }
            }

            Spacer()

            if subscriptionPlan == .free {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ui("Gratisplan", "Free plan"))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppTheme.primaryText)

                        Spacer()

                        Text(wordsLeftLabel)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(1)
                    }

                    ProgressView(value: freeUsageProgress)
                        .progressViewStyle(.linear)
                        .tint(AppTheme.warning)

                    HStack(spacing: 8) {
                        Text(ui(
                            "\(displayedWordsUsedToday)/\(Self.freeDailyWordLimit) ord i dag",
                            "\(displayedWordsUsedToday)/\(Self.freeDailyWordLimit) words today"
                        ))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(AppTheme.secondaryText)

                        Spacer()

                        Button(ui("Oppgrader", "Upgrade")) {
                            onUpgradeTap()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(AppTheme.accent)
                    }
                }
                .padding(.all, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(AppTheme.fieldMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(AppTheme.surfaceMuted.opacity(0.28))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(AppTheme.border, lineWidth: 1)
                        )
                )
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(ui("Tips", "Tips"))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.primaryText)

                tipRow(icon: "mic.fill", text: ui(
                    "Hold \(settings.shortcutTriggerKey.compactLabel) for å diktere",
                    "Hold \(settings.shortcutTriggerKey.compactLabel) to dictate"
                ))
                tipRow(icon: "globe", text: ui(
                    "\(settings.shortcutTriggerKey.compactLabel) + Shift for å oversette",
                    "\(settings.shortcutTriggerKey.compactLabel) + Shift to translate"
                ))
                tipRow(icon: "wand.and.stars", text: ui(
                    "\(settings.shortcutTriggerKey.compactLabel) + Ctrl for rewrite",
                    "\(settings.shortcutTriggerKey.compactLabel) + Ctrl to rewrite"
                ))
                tipRow(icon: "square.and.arrow.down.on.square", text: ui(
                    "\(settings.shortcutTriggerKey.compactLabel) + K for å lagre kontekst",
                    "\(settings.shortcutTriggerKey.compactLabel) + K to save context"
                ))
            }
            .padding(.all, 12)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(AppTheme.fieldMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(AppTheme.surfaceMuted.opacity(0.28))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(AppTheme.border, lineWidth: 1)
                    )
            )
            .padding(.horizontal, 10)
            .padding(.bottom, 10)

            SidebarItem(
                icon: HomeView.Page.settings.iconName,
                label: HomeView.Page.settings.title,
                active: activePage == .settings,
                showLabel: true
            ) {
                activePage = .settings
            }
            .padding(.bottom, 12)
        }
        .frame(width: sidebarWidth)
        .background(AppTheme.sidebarMaterial)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(AppTheme.border)
                .frame(width: 1)
        }
        .shadow(color: AppTheme.shadow, radius: 8, x: 3, y: 0)
        .onAppear {
            Task { await gamification.refresh(force: true) }
        }
        .onReceive(history.$entries) { _ in
            Task { await gamification.refresh(force: false) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await gamification.refresh(force: false) }
        }
    }

    private var primaryPages: [HomeView.Page] {
        HomeView.Page.allCases.filter { $0 != .settings }
    }

    private enum SubscriptionPlan {
        case free
        case pro
        case enterprise
    }

    private static let freeDailyWordLimit = 3000

    private var subscriptionPlan: SubscriptionPlan {
        switch normalizedPlanClaim {
        case "enterprise":
            return .enterprise
        case "pro", "team", "paid":
            return .pro
        default:
            return .free
        }
    }

    private var planBadgeLabel: String {
        switch subscriptionPlan {
        case .free:
            return ui("Gratis", "Free")
        case .pro:
            return "Pro"
        case .enterprise:
            return "Enterprise"
        }
    }

    private var planBadgeTextColor: Color {
        switch subscriptionPlan {
        case .free:
            return AppTheme.secondaryText
        case .pro:
            return AppTheme.accent
        case .enterprise:
            return AppTheme.success
        }
    }

    private var planBadgeBorderColor: Color {
        switch subscriptionPlan {
        case .free:
            return AppTheme.border
        case .pro:
            return AppTheme.accent.opacity(0.35)
        case .enterprise:
            return AppTheme.success.opacity(0.35)
        }
    }

    private var normalizedPlanClaim: String {
        guard let payload = jwtPayload(from: settings.backendToken),
              let rawPlan = payload["plan"] as? String else {
            return "free"
        }
        return rawPlan.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var displayedWordsUsedToday: Int {
        min(wordsUsedToday, Self.freeDailyWordLimit)
    }

    private var freeWordsRemaining: Int {
        max(0, Self.freeDailyWordLimit - wordsUsedToday)
    }

    private var freeUsageProgress: Double {
        guard Self.freeDailyWordLimit > 0 else { return 0 }
        return min(max(Double(wordsUsedToday) / Double(Self.freeDailyWordLimit), 0), 1)
    }

    private var wordsUsedToday: Int {
        let remote = gamification.snapshot?.today.wordsCount ?? 0
        return max(remote, history.todayWordCount)
    }

    private var wordsLeftLabel: String {
        freeWordsRemaining == 0
            ? ui("0 igjen i dag", "0 left today")
            : ui("\(freeWordsRemaining) igjen i dag", "\(freeWordsRemaining) left today")
    }

    @ViewBuilder
    private func tipRow(icon: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 12, alignment: .center)

            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
    }

    private func jwtPayload(from token: String) -> [String: Any]? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }

        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let padding = (4 - (base64.count % 4)) % 4
        if padding > 0 {
            base64 += String(repeating: "=", count: padding)
        }

        guard let payloadData = Data(base64Encoded: base64),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            return nil
        }

        return payload
    }
}

struct SidebarItem: View {
    let icon: String
    let label: String
    let active: Bool
    let showLabel: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: showLabel ? 12 : 0) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 18)
                if showLabel {
                    Text(label)
                        .font(.system(size: 16, weight: active ? .semibold : .medium))
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: showLabel ? .leading : .center)
            .padding(.horizontal, showLabel ? 14 : 0)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(active ? AppTheme.accentSoft : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .foregroundColor(active ? AppTheme.accent : AppTheme.secondaryText)
        .help(label)
    }
}

// MARK: - Main Page

struct MainPage: View {
    @ObservedObject private var history = DictationHistory.shared
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var gamification = GamificationStore.shared

    private func ui(_ norwegian: String, _ english: String) -> String {
        settings.ui(norwegian, english)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(welcomeTitle)
                        .font(AppTheme.heading(size: 40, weight: .bold))
                        .foregroundStyle(AppTheme.primaryText)

                    HStack(spacing: 8) {
                        Text(ui("Trykk", "Press"))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppTheme.secondaryText)

                        Text(settings.shortcutTriggerKey.compactLabel)
                            .font(AppTheme.mono(size: 14, weight: .bold))
                            .foregroundStyle(AppTheme.primaryText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(AppTheme.surface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(AppTheme.border, lineWidth: 1)
                                    )
                            )

                        Text(ui("for å diktere hvor som helst.", "to dictate anywhere."))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }

                HStack(spacing: 12) {
                    SimpleStatCard(title: ui("Dagsstreak", "Day streak"), value: streakLabel)
                    SimpleStatCard(title: ui("Nivå", "Level"), value: "Lv \(currentLevel)")
                    SimpleStatCard(title: ui("Totalt tid spart", "Total time saved"), value: TimeSaved.formatted(for: wordsTotal))
                }

                if let missions = gamification.snapshot?.missions {
                    DailyMissionsCard(missions: missions)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(ui("Nylige transkripsjoner", "Recent transcriptions"))
                        .font(AppTheme.heading(size: 30, weight: .bold))
                        .foregroundStyle(AppTheme.primaryText)

                    if recentEntries.isEmpty {
                        Text(ui("Ingen transkripsjoner ennå.", "No transcriptions yet."))
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.secondaryText)
                            .padding(.top, 6)
                    } else {
                        HistoryListCard(entries: recentEntries)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.canvas)
        .onAppear {
            Task { await gamification.refresh(force: true) }
        }
        .onReceive(history.$entries) { _ in
            Task { await gamification.refresh(force: false) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await gamification.refresh(force: false) }
        }
    }

    private var streakLabel: String {
        let fallback = history.entries.isEmpty ? 0 : 1
        let days = max(0, gamification.snapshot?.profile.streakDays ?? fallback)
        if days == 1 {
            return settings.ui("1 dag", "1 day")
        }
        return settings.ui("\(days) dager", "\(days) days")
    }

    private var currentLevel: Int {
        max(1, gamification.snapshot?.profile.level ?? 1)
    }

    private var wordsToday: Int {
        let remote = gamification.snapshot?.today.wordsCount ?? 0
        return max(remote, history.todayWordCount)
    }

    private var wordsTotal: Int {
        max(0, history.wordCount)
    }

    private var recentEntries: [DictationEntry] {
        Array(history.entries.prefix(5))
    }

    private var welcomeTitle: String {
        let name = settings.greetingDisplayName
        if name.isEmpty {
            return ui("Velkommen tilbake", "Welcome back")
        }
        return ui("Velkommen tilbake, \(name)", "Welcome back, \(name)")
    }
}

struct HistoryPage: View {
    @ObservedObject private var history = DictationHistory.shared
    @ObservedObject private var settings = AppSettings.shared

    private func ui(_ norwegian: String, _ english: String) -> String {
        settings.ui(norwegian, english)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(ui("Historikk", "History"))
                    .font(AppTheme.heading(size: 34, weight: .bold))
                    .foregroundStyle(AppTheme.primaryText)

                if history.entries.isEmpty {
                    Text(ui("Ingen transkripsjoner ennå.", "No transcriptions yet."))
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.secondaryText)
                        .padding(.top, 6)
                } else {
                    HistoryListCard(entries: history.entries)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.canvas)
    }
}

struct BugReportPage: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var appLog = AppLogStore.shared

    @State private var summary: String = ""
    @State private var whereSeen: String = ""
    @State private var stepsToReproduce: String = ""
    @State private var expectedResult: String = ""
    @State private var actualResult: String = ""
    @State private var includeDebugLog: Bool = true
    @State private var includeEnvironment: Bool = true
    @State private var statusMessage: String = ""
    @State private var statusIsError: Bool = false

    private func ui(_ norwegian: String, _ english: String) -> String {
        settings.ui(norwegian, english)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(ui("Rapporter feil", "Report a bug"))
                    .font(AppTheme.heading(size: 34, weight: .bold))
                    .foregroundStyle(AppTheme.primaryText)

                Text(ui(
                    "Beskriv feilen så konkret som mulig. Kopier eller lagre rapporten og send den til support.",
                    "Describe the issue as clearly as possible. Copy or save the report, then send it to support."
                ))
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        bugField(title: ui("Kort oppsummering", "Short summary"), text: $summary, placeholder: ui("Hva er feilen?", "What is the bug?"))
                        bugField(title: ui("Hvor skjedde det?", "Where did it happen?"), text: $whereSeen, placeholder: ui("f.eks. Gmail i Chrome, Notes, Word", "e.g. Gmail in Chrome, Notes, Word"))
                        bugEditor(title: ui("Steg for å gjenskape", "Steps to reproduce"), text: $stepsToReproduce, placeholder: ui("1. ...  2. ...  3. ...", "1. ...  2. ...  3. ..."))
                        bugEditor(title: ui("Forventet resultat", "Expected result"), text: $expectedResult, placeholder: ui("Hva skulle ha skjedd?", "What should have happened?"))
                        bugEditor(title: ui("Faktisk resultat", "Actual result"), text: $actualResult, placeholder: ui("Hva skjedde i stedet?", "What happened instead?"))

                        HStack(spacing: 14) {
                            Toggle(ui("Ta med debug-logg", "Include debug log"), isOn: $includeDebugLog)
                                .toggleStyle(.switch)
                            Toggle(ui("Ta med miljødata", "Include environment"), isOn: $includeEnvironment)
                                .toggleStyle(.switch)
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryText)
                    }
                } label: {
                    Text(ui("Feildetaljer", "Bug details"))
                        .font(.system(size: 13, weight: .semibold))
                }
                .groupBoxStyle(StoreGroupBoxStyle())

                HStack(spacing: 8) {
                    Button(ui("Kopier rapport", "Copy report")) {
                        copyReportToClipboard()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)

                    Button(ui("Lagre rapport…", "Save report…")) {
                        saveReportToFile()
                    }
                    .buttonStyle(.bordered)

                    Button(ui("Tøm felter", "Clear fields")) {
                        clearInputs()
                    }
                    .buttonStyle(.bordered)
                }

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(statusIsError ? AppTheme.destructive : AppTheme.secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(AppTheme.fieldMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(statusIsError ? AppTheme.destructive.opacity(0.35) : AppTheme.fieldBorder, lineWidth: 1)
                                )
                        )
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.canvas)
    }

    @ViewBuilder
    private func bugField(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.primaryText)

            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.primaryText)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
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

    @ViewBuilder
    private func bugEditor(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.primaryText)

            ZStack(alignment: .topLeading) {
                TextEditor(text: text)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.primaryText)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 90)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)

                if text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(placeholder)
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.tertiaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                }
            }
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

    private var generatedReport: String {
        var lines: [String] = []
        lines.append("BlueSpeak Bug Report")
        lines.append("Generated: \(Self.isoDateFormatter.string(from: Date()))")

        if includeEnvironment {
            lines.append("App Version: \(appVersionString)")
            lines.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
            lines.append("UI Language: \(settings.interfaceLanguage.label)")
            lines.append("Dictation Language: \(settings.appLanguage.menuLabel)")
            lines.append("Translate Target: \(settings.translationTargetLanguage.menuLabel)")
            lines.append("STT Provider: \(settings.sttProvider.label)")
        }

        lines.append("")
        lines.append("Summary")
        lines.append(normalize(summary))
        lines.append("")
        lines.append("Where")
        lines.append(normalize(whereSeen))
        lines.append("")
        lines.append("Steps to Reproduce")
        lines.append(normalize(stepsToReproduce))
        lines.append("")
        lines.append("Expected")
        lines.append(normalize(expectedResult))
        lines.append("")
        lines.append("Actual")
        lines.append(normalize(actualResult))

        if includeDebugLog {
            let log = trimmedDebugLog()
            lines.append("")
            lines.append("Debug Log")
            lines.append(log.isEmpty ? "(empty)" : log)
        }

        return lines.joined(separator: "\n")
    }

    private var appVersionString: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }

    private func trimmedDebugLog(limit: Int = 180) -> String {
        let all = appLog.exportText()
        guard !all.isEmpty else { return "" }
        let rows = all.components(separatedBy: .newlines)
        return rows.suffix(limit).joined(separator: "\n")
    }

    private func normalize(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(not provided)" : trimmed
    }

    private func copyReportToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(generatedReport, forType: .string)
        statusIsError = false
        statusMessage = ui("Rapport kopiert til utklippstavlen.", "Report copied to clipboard.")
    }

    private func saveReportToFile() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "BlueSpeak-bug-report-\(formatter.string(from: Date())).txt"
        panel.allowedContentTypes = [.plainText]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try generatedReport.write(to: url, atomically: true, encoding: .utf8)
            statusIsError = false
            statusMessage = ui("Rapport lagret.", "Report saved.")
        } catch {
            statusIsError = true
            statusMessage = ui(
                "Kunne ikke lagre rapport. \(error.localizedDescription)",
                "Could not save report. \(error.localizedDescription)"
            )
            AppLogStore.shared.record(.error, "Bug report save failed", metadata: ["error": error.localizedDescription])
        }
    }

    private func clearInputs() {
        summary = ""
        whereSeen = ""
        stepsToReproduce = ""
        expectedResult = ""
        actualResult = ""
        statusMessage = ""
        statusIsError = false
    }

    private static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZ"
        return formatter
    }()
}

struct SimpleStatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(AppTheme.primaryText)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.cardMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppTheme.surface.opacity(0.2))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(AppTheme.border, lineWidth: 1)
                )
        )
    }
}

struct DailyMissionsCard: View {
    @ObservedObject private var settings = AppSettings.shared
    let missions: GamificationMissions

    private func ui(_ norwegian: String, _ english: String) -> String {
        settings.ui(norwegian, english)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(ui("Dagens mål", "Daily missions"))
                    .font(AppTheme.heading(size: 22, weight: .bold))
                    .foregroundStyle(AppTheme.primaryText)

                Spacer()

                Text("\(missions.completedCount)/\(max(1, missions.totalCount))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }

            ProgressView(value: progressValue)
                .progressViewStyle(.linear)
                .tint(AppTheme.accent)

            VStack(spacing: 8) {
                ForEach(missions.items) { item in
                    HStack(spacing: 10) {
                        Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(item.completed ? AppTheme.success : AppTheme.secondaryText)

                        Text(localizedMissionTitle(for: item))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppTheme.primaryText)

                        Spacer(minLength: 8)

                        Text("\(item.current)/\(item.target)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
            }
        }
        .padding(14)
        .cardSurface()
    }

    private var progressValue: Double {
        guard missions.totalCount > 0 else { return 0 }
        return min(max(Double(missions.completedCount) / Double(missions.totalCount), 0), 1)
    }

    private func localizedMissionTitle(for mission: GamificationMissionItem) -> String {
        switch mission.id {
        case "words":
            return ui("Dikter ord", "Dictate words")
        case "dictate":
            return ui("Fullfør dikteringer", "Complete dictations")
        case "transform":
            return ui("Oversett eller rewrite", "Translate or rewrite")
        default:
            return mission.title
        }
    }
}

struct HistoryListCard: View {
    let entries: [DictationEntry]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                HistoryRow(entry: entry, isLast: index == entries.count - 1)
            }
        }
        .cardSurface()
    }
}

struct HistoryRow: View {
    let entry: DictationEntry
    let isLast: Bool

    @ObservedObject private var settings = AppSettings.shared

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(Self.timeFormatter.string(from: entry.date))
                .font(AppTheme.mono(size: 11))
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
                    .help(settings.ui("Kopier tekst", "Copy text"))
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


private struct CardSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.cardMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(AppTheme.surface.opacity(0.2))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(AppTheme.border, lineWidth: 1)
                )
                .shadow(color: AppTheme.shadow, radius: 8, x: 0, y: 4)
        )
    }
}

private extension View {
    func cardSurface() -> some View {
        modifier(CardSurfaceModifier())
    }
}
