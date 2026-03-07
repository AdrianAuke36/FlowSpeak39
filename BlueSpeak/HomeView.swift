import AppKit
import ApplicationServices
import AVFoundation
import Combine
import Speech
import SwiftUI

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
        case style
        case settings

        var id: Self { self }

        var title: String {
            switch self {
            case .home: return "Home"
            case .history: return "History"
            case .style: return "Style"
            case .settings: return "Settings"
            }
        }

        var iconName: String {
            switch self {
            case .home: return "house.fill"
            case .history: return "clock.arrow.circlepath"
            case .style: return "textformat"
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
        .frame(minWidth: 1160, minHeight: 760)
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
        .onChange(of: settings.hasAuthenticatedSession) { _, isAuthenticated in
            if !isAuthenticated && settings.consumePendingSignedOutPopup() {
                showSignedOutPopup = true
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
        case .style:
            StylePage()
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

        return "BlueSpeak user"
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
    let displayName: String
    let email: String
    let onUpgrade: () -> Void
    let onManageAccount: () -> Void

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

                    Text(email.isEmpty ? "No email" : email)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                }
            }
            .padding(16)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("You are on BlueSpeak Basic")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)

                HStack(spacing: 10) {
                    Button("Upgrade") {
                        onUpgrade()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)

                    Button("Manage account") {
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
    @Binding var isPresented: Bool
    @State private var billingCycle: BillingCycle = .annual

    private enum BillingCycle: String {
        case monthly
        case annual
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.34)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 12) {
                    Text("Plans and Billing")
                        .font(.system(size: 44, weight: .bold, design: .serif))
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
                        subtitle: "For individuals",
                        title: "Basic",
                        price: "Free",
                        badge: nil,
                        features: [
                            "3,000 words per day",
                            "Dictation, translate and rewrite",
                            "Works across all apps",
                            "Standard support"
                        ],
                        actionTitle: nil,
                        action: nil,
                        emphasized: false
                    )

                    Divider()

                    planCard(
                        subtitle: "For individuals and teams",
                        title: "Pro",
                        price: billingCycle == .annual ? "12 USD per user/mo" : "15 USD per user/mo",
                        badge: billingCycle == .annual ? "-20%" : nil,
                        features: [
                            "Everything in Basic",
                            "Unlimited words on all devices",
                            "Priority support",
                            "Early feature access",
                            "Advanced reply + rewrite controls"
                        ],
                        actionTitle: "Upgrade to Pro",
                        action: openUpgradePage,
                        emphasized: true
                    )

                    Divider()

                    planCard(
                        subtitle: "For teams with advanced needs",
                        title: "Enterprise",
                        price: billingCycle == .annual ? "24 USD per user/mo" : "30 USD per user/mo",
                        badge: nil,
                        features: [
                            "Everything in Pro",
                            "SSO / SAML",
                            "Usage dashboards",
                            "Dedicated onboarding",
                            "Priority SLA support"
                        ],
                        actionTitle: "Create a team",
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
            billingCycleButton(title: "Monthly", cycle: .monthly)
            billingCycleButton(title: "Annual", cycle: .annual)
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
                        .font(.system(size: 38, weight: .bold, design: .serif))
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
        case .signIn: return "Log in"
        case .signUp: return "Create account"
        }
    }

    var subtitle: String {
        switch self {
        case .signIn:
            return "Sign in with your BlueSpeak account to use dictation, translation and rewrite on any Mac."
        case .signUp:
            return "Create a BlueSpeak account with email and password. You can start using the app immediately."
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
            AppTheme.canvas
                .ignoresSafeArea()

            HStack(spacing: 32) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(AppTheme.accent)
                            .frame(width: 54, height: 54)
                            .overlay(
                                Image(systemName: "waveform.circle.fill")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundStyle(AppTheme.accentText)
                            )

                        Text("BlueSpeak")
                            .font(.system(size: 18, weight: .bold, design: .serif))
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
                        AuthFeatureRow(icon: "mic.fill", text: "Hold \(settings.shortcutTriggerKey.dictateShortcut) to dictate")
                        AuthFeatureRow(icon: "globe", text: "Hold \(settings.shortcutTriggerKey.translateShortcut) to translate")
                        AuthFeatureRow(icon: "wand.and.stars", text: "Select text + hold \(settings.shortcutTriggerKey.rewriteShortcut) to rewrite")
                        AuthFeatureRow(icon: "tray.and.arrow.down.fill", text: "Select message + press \(settings.shortcutTriggerKey.saveReplyContextShortcut) to save reply context")
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 16) {
                    Text(mode.title)
                        .font(.system(size: 30, weight: .bold, design: .serif))
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
                        Button("Forgot password?") {
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
            statusText = "Auth is not configured yet."
            AppLogStore.shared.record(.warning, "Password reset blocked", metadata: ["reason": "auth_not_configured"])
            return
        }

        isBusy = true
        statusText = "Sending reset email..."

        Task {
            defer { isBusy = false }

            do {
                try await settings.requestSupabasePasswordReset(email: email)
                statusText = "If the account exists, a password reset email has been sent."
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

    var body: some View {
        ZStack {
            AppTheme.canvas
                .ignoresSafeArea()

            HStack(spacing: 56) {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(AppTheme.surfaceMuted)
                            .frame(width: 54, height: 54)
                            .overlay(
                                Image(systemName: "waveform.circle")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(AppTheme.primaryText)
                            )

                        Text("BlueSpeak")
                            .font(.system(size: 24, weight: .bold, design: .serif))
                            .foregroundStyle(AppTheme.primaryText)
                    }

                    if step != .accessibility {
                        Button {
                            step = previousStep(for: step)
                            statusText = ""
                        } label: {
                            Label("Back", systemImage: "arrow.left")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        .buttonStyle(.plain)
                    }

                    Text(stepTitle)
                        .font(.system(size: 44, weight: .bold, design: .serif))
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

                        Button("Re-check permissions") {
                            refreshPermissionState()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)

                        if showsContinueButton {
                            Button("Continue", action: continueAction)
                                .buttonStyle(.borderedProminent)
                                .tint(AppTheme.accent)
                                .controlSize(.large)
                                .disabled(!canContinue)
                                .opacity(canContinue ? 1 : 0.45)
                        }

                        if showsSkipButton {
                            Button("Skip for now", action: skipCurrentOptionalStep)
                                .buttonStyle(.bordered)
                                .controlSize(.large)
                        }

                        if showsFinishButton {
                            Button("Finish setup", action: finishOnboarding)
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
            return "Enable speech recognition"
        case .microphone:
            return "Set up your microphone"
        case .accessibility:
            return "Enable Accessibility"
        case .inputMonitoring:
            return "Enable Input Monitoring"
        }
    }

    private var stepSubtitle: String {
        switch step {
        case .speechRecognition:
            return "BlueSpeak uses Apple's speech recognition to turn your voice into text. You can skip this now and enable it later."
        case .microphone:
            return "BlueSpeak only activates your microphone when you choose to start dictation. You can skip this now and enable it later."
        case .accessibility:
            return "BlueSpeak needs accessibility access to paste dictation into focused text fields and run rewrite."
        case .inputMonitoring:
            return "BlueSpeak needs input monitoring to detect the fn key globally and trigger dictation shortcuts."
        }
    }

    private var primaryActionTitle: String {
        switch step {
        case .accessibility:
            return "Open Accessibility Settings"
        case .inputMonitoring:
            if inputMonitoringGranted { return "Continue" }
            return "Allow input monitoring"
        case .microphone:
            let status = microphonePermissionState()
            if status == .denied || status == .restricted { return "Open Microphone Settings" }
            return "Allow microphone"
        case .speechRecognition:
            let status = SFSpeechRecognizer.authorizationStatus()
            if status == .denied || status == .restricted { return "Open Speech Settings" }
            return "Allow speech recognition"
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
            return speechGranted
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
            return "Accessibility access granted"
        case .inputMonitoring:
            return "Input Monitoring granted"
        case .microphone:
            return "Microphone access granted"
        case .speechRecognition:
            return "Speech recognition granted"
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
                    label: "Speech",
                    granted: speechGranted
                )
                permissionStatePill(
                    step: .microphone,
                    label: "Mic",
                    granted: microphoneGranted
                )
                permissionStatePill(
                    step: .accessibility,
                    label: "Access",
                    granted: accessibilityGranted
                )
                permissionStatePill(
                    step: .inputMonitoring,
                    label: "Input",
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
            statusText = "Microphone can be enabled later in System Settings."
        case .speechRecognition:
            finishOnboarding()
        case .accessibility, .inputMonitoring:
            break
        }
    }

    private func finishOnboarding() {
        guard criticalPermissionsGranted else {
            statusText = "Accessibility and Input Monitoring must be enabled before setup can finish."
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
        let status = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .authorized:
            speechGranted = true
            statusText = "Speech recognition is ready. Press Continue when you want to move on."
            refreshPermissionState()
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { authorizationStatus in
                DispatchQueue.main.async {
                    self.refreshPermissionState()
                    if authorizationStatus == .authorized {
                        self.statusText = "Speech recognition is ready. Press Continue when you want to move on."
                    } else {
                        self.statusText = "Speech recognition was denied. Open System Settings to allow it."
                    }
                }
            }
        case .denied, .restricted:
            statusText = "Enable speech recognition in System Settings, then return to BlueSpeak."
            NSWorkspace.shared.open(speechRecognitionSettingsURL)
        @unknown default:
            statusText = "Unable to verify speech recognition permission."
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
            statusText = "Microphone access is ready. Press Continue when you want to move on."
            refreshPermissionState()
            return
        }

        if status == .denied || status == .restricted {
            if status == .restricted {
                statusText = "Microphone access is restricted by macOS policy."
            } else {
                statusText = "Microphone access was denied. Open System Settings to allow it."
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
            statusText = "Microphone access is ready. Press Continue when you want to move on."
            return
        }

        switch updatedStatus {
        case .restricted:
            statusText = "Microphone access is restricted by macOS policy."
        case .denied:
            statusText = "Microphone access was denied. Open System Settings to allow it."
            NSWorkspace.shared.open(microphoneSettingsURL)
        case .notDetermined:
            statusText = "Could not show microphone prompt. Quit and reopen BlueSpeak, then try again."
        case .authorized:
            statusText = "Microphone access is ready. Press Continue when you want to move on."
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

        statusText = "Enable BlueSpeak in Privacy & Security, then return here and press Continue."
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
            statusText = "Input Monitoring is ready. Press Continue when you want to move on."
        } else {
            statusText = "Enable BlueSpeak in Input Monitoring, then return here and press Continue."
            NSWorkspace.shared.open(inputMonitoringSettingsURL)
        }
    }

    private func refreshPermissionState() {
        speechGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
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
                statusText = "Accessibility is ready. Press Continue when you want to move on."
            case .inputMonitoring:
                statusText = "Input Monitoring is ready. Press Continue when you want to move on."
            case .microphone:
                statusText = "Microphone access is ready. Press Continue when you want to move on."
            case .speechRecognition:
                statusText = "Speech recognition is ready."
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
            return "Accessibility access"
        case .inputMonitoring:
            return "Input Monitoring"
        case .microphone:
            return "Microphone access"
        case .speechRecognition:
            return "Speech recognition"
        }
    }

    private var stepCardDescription: String {
        switch step {
        case .accessibility:
            return "Turn on BlueSpeak in Privacy & Security. macOS can require relaunch before full access becomes active."
        case .inputMonitoring:
            return "BlueSpeak uses this only to detect the fn shortcut globally. Turn it on, then continue."
        case .microphone:
            return "Optional: macOS asks once for microphone access. After you allow it, BlueSpeak can record when you hold fn."
        case .speechRecognition:
            return "Optional: macOS asks once for voice transcription. After you allow it, BlueSpeak can use Apple's speech recognition engine."
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

// MARK: - Sidebar

struct Sidebar: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var history = DictationHistory.shared
    @Binding var activePage: HomeView.Page
    let onUpgradeTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                // Removed RoundedRectangle with waveform.path per instructions

                Text("BlueSpeak")
                    .font(.system(size: 26, weight: .bold, design: .serif))
                    .foregroundStyle(AppTheme.primaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)

            Divider()
                .padding(.bottom, 8)

            ForEach(primaryPages) { page in
                SidebarItem(
                    icon: page.iconName,
                    label: page.title,
                    active: activePage == page
                ) {
                    activePage = page
                }
            }

            Spacer()

            if subscriptionPlan == .free {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Free plan")
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
                        Text("\(displayedWordsUsedToday)/\(Self.freeDailyWordLimit) words today")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(AppTheme.secondaryText)

                        Spacer()

                        Button("Upgrade") {
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
                Text("Tips")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.primaryText)

                tipRow(icon: "mic.fill", text: "Hold \(settings.shortcutTriggerKey.compactLabel) to dictate")
                tipRow(icon: "globe", text: "\(settings.shortcutTriggerKey.compactLabel) + Shift to translate")
                tipRow(icon: "wand.and.stars", text: "\(settings.shortcutTriggerKey.compactLabel) + Ctrl to rewrite")
                tipRow(icon: "square.and.arrow.down.on.square", text: "\(settings.shortcutTriggerKey.compactLabel) + < to save context")
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
                active: activePage == .settings
            ) {
                activePage = .settings
            }
            .padding(.bottom, 12)
        }
        .frame(width: 220)
        .background(
            Rectangle()
                .fill(AppTheme.sidebarMaterial)
                .overlay(
                    Rectangle()
                        .fill(AppTheme.sidebar.opacity(0.5))
                )
        )
    }

    private var primaryPages: [HomeView.Page] {
        HomeView.Page.allCases.filter { $0 != .settings }
    }

    private enum SubscriptionPlan {
        case free
        case paid
    }

    private static let freeDailyWordLimit = 3000

    private var subscriptionPlan: SubscriptionPlan {
        switch normalizedPlanClaim {
        case "pro", "team", "enterprise", "paid":
            return .paid
        default:
            return .free
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
        min(history.todayWordCount, Self.freeDailyWordLimit)
    }

    private var freeWordsRemaining: Int {
        max(0, Self.freeDailyWordLimit - history.todayWordCount)
    }

    private var freeUsageProgress: Double {
        guard Self.freeDailyWordLimit > 0 else { return 0 }
        return min(max(Double(history.todayWordCount) / Double(Self.freeDailyWordLimit), 0), 1)
    }

    private var wordsLeftLabel: String {
        freeWordsRemaining == 0
            ? "0 left today"
            : "\(freeWordsRemaining) left today"
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 18)
                Text(label)
                    .font(.system(size: 16, weight: active ? .semibold : .medium))
                Spacer()
            }
            .padding(.horizontal, 14)
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

            Picker("Style scope", selection: $selectedScope) {
                ForEach(StyleScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
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
                    .fill(AppTheme.cardMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(AppTheme.surface.opacity(0.2))
                    )
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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(welcomeTitle)
                        .font(.system(size: 40, weight: .bold, design: .serif))
                        .foregroundStyle(AppTheme.primaryText)

                    HStack(spacing: 8) {
                        Text("Press")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppTheme.secondaryText)

                        Text(settings.shortcutTriggerKey.compactLabel)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
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

                        Text("to dictate anywhere.")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }

                HStack(spacing: 12) {
                    SimpleStatCard(title: "Day streak", value: streakLabel)
                    SimpleStatCard(title: "Words today", value: "\(history.todayWordCount)")
                    SimpleStatCard(title: "Words total", value: "\(history.wordCount)")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Recent transcriptions")
                        .font(.system(size: 30, weight: .bold, design: .serif))
                        .foregroundStyle(AppTheme.primaryText)

                    if recentEntries.isEmpty {
                        Text("No transcriptions yet.")
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
    }

    private var streakLabel: String {
        let days = history.entries.isEmpty ? 0 : 1
        return "\(days) day"
    }

    private var recentEntries: [DictationEntry] {
        Array(history.entries.prefix(5))
    }

    private var welcomeTitle: String {
        let name = settings.greetingDisplayName
        if name.isEmpty {
            return "Welcome back"
        }
        return "Welcome back, \(name)"
    }
}

struct HistoryPage: View {
    @ObservedObject private var history = DictationHistory.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("History")
                    .font(.system(size: 34, weight: .bold, design: .serif))
                    .foregroundStyle(AppTheme.primaryText)

                if history.entries.isEmpty {
                    Text("No transcriptions yet.")
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
