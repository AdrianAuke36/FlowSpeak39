//
//  SettingsView.swift
//  BlueSpeak
//
//  Created by Adrian Auke on 20/02/2026.
//

import AppKit
import Carbon.HIToolbox
import SwiftUI
import UniformTypeIdentifiers

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case account
    case privacy
    case billing
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .account: return "Account"
        case .privacy: return "Data & Privacy"
        case .billing: return "Plans & Billing"
        case .advanced: return "Advanced"
        }
    }

    var subtitle: String {
        switch self {
        case .general:
            return "Language, microphone and core dictation behavior."
        case .account:
            return "Session status and sign-in account actions."
        case .privacy:
            return "What is stored, what is sent, and local data controls."
        case .billing:
            return "Free usage progress and upgrade options."
        case .advanced:
            return "Backend, auth setup, email rules, shortcuts and diagnostics."
        }
    }

    var iconName: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .account: return "person.crop.circle"
        case .privacy: return "lock.shield"
        case .billing: return "creditcard"
        case .advanced: return "wrench.and.screwdriver"
        }
    }
}

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var history = DictationHistory.shared
    @ObservedObject private var appLog = AppLogStore.shared

    @State private var selectedSection: SettingsSection = .general
    @State private var isCapturingShortcut: Bool = false
    @State private var shortcutCaptureStatus: String = "Press a supported key."
    @State private var shortcutCaptureMonitor: Any?
    @State private var microphones: [MicrophoneOption] = MicrophoneCatalog.availableOptions()
    @State private var supabaseEmailInput: String = ""
    @State private var supabasePasswordInput: String = ""
    @State private var accountFirstNameInput: String = ""
    @State private var accountLastNameInput: String = ""
    @State private var supabaseAuthStatus: String = ""
    @State private var supabaseAuthBusy: Bool = false
    @State private var showDeleteAccountConfirmation: Bool = false

    init(initialSection: SettingsSection = .general) {
        _selectedSection = State(initialValue: initialSection)
    }

    var body: some View {
        HStack(spacing: 16) {
            sectionSidebar

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(selectedSection.title)
                        .font(.system(size: 30, weight: .bold, design: .serif))
                        .foregroundStyle(AppTheme.primaryText)

                    Text(selectedSection.subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryText)

                    sectionContent
                }
                .padding(18)
            }
            .background(AppTheme.canvas)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(18)
        .background(AppTheme.canvas)
        .onAppear {
            refreshMicrophones()
            if supabaseEmailInput.isEmpty {
                supabaseEmailInput = settings.supabaseUserEmail
            }
            if accountFirstNameInput.isEmpty {
                accountFirstNameInput = settings.supabaseUserFirstName
            }
            if accountLastNameInput.isEmpty {
                accountLastNameInput = settings.supabaseUserLastName
            }
        }
        .onDisappear {
            stopShortcutCapture()
        }
        .onChange(of: settings.supabaseUserFirstName) { _, nextValue in
            accountFirstNameInput = nextValue
        }
        .onChange(of: settings.supabaseUserLastName) { _, nextValue in
            accountLastNameInput = nextValue
        }
        .alert("Delete account permanently?", isPresented: $showDeleteAccountConfirmation) {
            Button("Delete", role: .destructive) {
                deleteSupabaseAccount()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This action removes your account and signs you out on this Mac.")
        }
    }

    private var sectionSidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SETTINGS")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .padding(.horizontal, 8)
                .padding(.bottom, 6)

            ForEach(SettingsSection.allCases) { section in
                sectionButton(for: section)
            }

            Spacer()
        }
        .padding(12)
        .frame(maxWidth: 230, maxHeight: .infinity, alignment: .topLeading)
        .background(sidebarBackground)
    }

    private func sectionButton(for section: SettingsSection) -> some View {
        let isSelected = selectedSection == section

        return Button {
            selectedSection = section
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 16)

                Text(section.title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? AppTheme.accentSoft : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.primaryText)
    }

    private var sidebarBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(AppTheme.cardMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.surface.opacity(0.20))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(AppTheme.border, lineWidth: 1)
            )
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .general:
            generalContent
        case .account:
            accountContent
        case .privacy:
            privacyContent
        case .billing:
            billingContent
        case .advanced:
            advancedContent
        }
    }

    private var generalContent: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                settingRow(title: "Språk") {
                    languagePicker(selection: $settings.appLanguage, width: 240)
                }

                settingRow(title: "Translate") {
                    languagePicker(selection: $settings.translationTargetLanguage, width: 240)
                }

                settingRow(title: "Forståelse") {
                    VStack(alignment: .leading, spacing: 8) {
                        interpretationLevelBar(selection: $settings.interpretationLevel)

                        Text(settings.interpretationLevel.description)
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }

                settingRow(title: "Mikrofon") {
                    HStack(spacing: 8) {
                        microphonePicker(selection: $settings.selectedMicrophoneUID, width: 420)

                        Button {
                            refreshMicrophones()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .help("Oppdater mikrofonliste")
                    }
                }

                settingRow(title: "Shortcuts") {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(settings.shortcutTriggerKey.summary)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppTheme.primaryText)

                            Text("Administrer hurtigtaster i Advanced-seksjonen.")
                                .font(.system(size: 11))
                                .foregroundStyle(AppTheme.secondaryText)
                        }

                        Spacer()

                        Button("Open Advanced") {
                            selectedSection = .advanced
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(AppTheme.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(AppTheme.fieldBorder, lineWidth: 1)
                            )
                    )
                }
            }
        } label: {
            Text("General")
                .font(.system(size: 13, weight: .semibold))
        }
        .groupBoxStyle(StoreGroupBoxStyle())
    }

    private var accountContent: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                if settings.hasSupabaseSession {
                    settingRow(title: "Logged in as") {
                        readOnlyValue(settings.supabaseUserEmail.isEmpty ? "Unknown account" : settings.supabaseUserEmail)
                    }

                    settingRow(title: "First name") {
                        TextField("First name", text: $accountFirstNameInput)
                            .textFieldStyle(.plain)
                            .storeField(maxWidth: 320)
                    }

                    settingRow(title: "Last name") {
                        TextField("Last name", text: $accountLastNameInput)
                            .textFieldStyle(.plain)
                            .storeField(maxWidth: 320)
                    }

                    HStack(spacing: 8) {
                        Button("Save name") {
                            updateSupabaseName()
                        }
                        .buttonStyle(.bordered)
                        .disabled(supabaseAuthBusy)

                        Button("Reset password") {
                            requestSupabasePasswordResetForCurrentAccount()
                        }
                        .buttonStyle(.bordered)
                        .disabled(supabaseAuthBusy)

                        Button("Sign out") {
                            signOutSupabase()
                        }
                        .buttonStyle(.bordered)
                        .disabled(supabaseAuthBusy)

                        Button("Delete account", role: .destructive) {
                            showDeleteAccountConfirmation = true
                        }
                        .buttonStyle(.bordered)
                        .disabled(supabaseAuthBusy)
                    }
                } else {
                    Text("Not signed in. Use the login screen in the main window.")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Text(supabaseStatusText)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.secondaryText)
            }
        } label: {
            Text("Account")
                .font(.system(size: 13, weight: .semibold))
        }
        .groupBoxStyle(StoreGroupBoxStyle())
    }

    private var privacyContent: some View {
        VStack(spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    privacyInfoRow(
                        title: "Talegjenkjenning",
                        detail: "BlueSpeak bruker Apples talegjenkjenning etter at du har gitt tillatelse. macOS kan sende taledata til Apple for å behandle forespørslene."
                    )

                    privacyInfoRow(
                        title: "AI-behandling",
                        detail: "Teksten du dikterer sendes til BlueSpeak-backenden. Hvis AI er aktiv, sender backenden tekst videre til OpenAI for formatering, oversettelse og rewrite."
                    )

                    privacyInfoRow(
                        title: "Lokalt lagret på denne Mac-en",
                        detail: "Dikteringshistorikk, språk- og stilvalg, valgt mikrofon og aktiv innloggingsøkt lagres lokalt på denne maskinen."
                    )

                    privacyInfoRow(
                        title: "Konto",
                        detail: "Innlogging og sesjonsfornying håndteres via Supabase."
                    )

                    HStack(spacing: 8) {
                        Button("Clear local history") {
                            history.clearAll()
                        }
                        .buttonStyle(.bordered)

                        Button("Sign out and clear local session") {
                            clearLocalPrivateData()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } label: {
                Text("Data & Privacy")
                    .font(.system(size: 13, weight: .semibold))
            }
            .groupBoxStyle(StoreGroupBoxStyle())

            GroupBox {
                Text("Permissions: aktiver BlueSpeak i Privacy & Security → Accessibility + Input Monitoring.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Text("Permissions")
                    .font(.system(size: 13, weight: .semibold))
            }
            .groupBoxStyle(StoreGroupBoxStyle())
        }
    }

    private var billingContent: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Current plan")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryText)

                    Spacer()

                    Text(currentPlanLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(subscriptionPlan == .free ? AppTheme.warning : AppTheme.success)
                }

                if subscriptionPlan == .free {
                    Text("Free includes \(Self.freeDailyWordLimit) words per day.")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.secondaryText)

                    ProgressView(value: freeUsageProgress)
                        .progressViewStyle(.linear)
                        .tint(AppTheme.warning)

                    HStack {
                        Text("\(displayedWordsUsedToday)/\(Self.freeDailyWordLimit) words today")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.secondaryText)

                        Spacer()

                        Text(wordsLeftLabel)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.primaryText)
                    }

                    Button("Upgrade to Pro") {
                        openUpgradePage()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                } else {
                    Text("You are on a paid plan. Unlimited usage is active.")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        } label: {
            Text("Plans & Billing")
                .font(.system(size: 13, weight: .semibold))
        }
        .groupBoxStyle(StoreGroupBoxStyle())
    }

    private var advancedContent: some View {
        VStack(spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    settingRow(title: "Default innsettingsmodus") {
                        modePicker(selection: $settings.globalMode, width: 360)
                    }

                    settingRow(title: "Backend URL") {
                        TextField(AppSettings.defaultBackendBaseURL, text: $settings.backendBaseURL)
                            .textFieldStyle(.plain)
                            .storeField(maxWidth: 560)
                    }

                    settingRow(title: "Backend token/JWT") {
                        HStack(spacing: 8) {
                            SecureField("Bearer token or JWT", text: $settings.backendToken)
                                .textFieldStyle(.plain)
                                .storeField(maxWidth: 560)

                            if !settings.backendToken.isEmpty {
                                Button("Copy") {
                                    copyBackendToken()
                                }
                                .buttonStyle(.bordered)

                                Button("Clear") {
                                    settings.backendToken = ""
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            } label: {
                Text("Backend")
                    .font(.system(size: 13, weight: .semibold))
            }
            .groupBoxStyle(StoreGroupBoxStyle())

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    settingRow(title: "Supabase URL") {
                        TextField("https://<project-ref>.supabase.co", text: $settings.supabaseProjectURL)
                            .textFieldStyle(.plain)
                            .storeField(maxWidth: 560)
                    }

                    settingRow(title: "Supabase anon key") {
                        SecureField("eyJ...", text: $settings.supabaseAnonKey)
                            .textFieldStyle(.plain)
                            .storeField(maxWidth: 560)
                    }

                    if settings.hasSupabaseSession {
                        settingRow(title: "Current account") {
                            readOnlyValue(settings.supabaseUserEmail.isEmpty ? "Unknown account" : settings.supabaseUserEmail)
                        }

                        HStack(spacing: 8) {
                            Button("Refresh JWT") {
                                refreshSupabaseJWT()
                            }
                            .buttonStyle(.bordered)
                            .disabled(supabaseAuthBusy)

                            Button("Sign out") {
                                signOutSupabase()
                            }
                            .buttonStyle(.bordered)
                            .disabled(supabaseAuthBusy)

                            Button("Switch account") {
                                switchAccountSupabase()
                            }
                            .buttonStyle(.bordered)
                            .disabled(supabaseAuthBusy)
                        }
                    } else {
                        settingRow(title: "Email") {
                            TextField("you@example.com", text: $supabaseEmailInput)
                                .textFieldStyle(.plain)
                                .storeField(maxWidth: 560)
                        }

                        settingRow(title: "Password") {
                            SecureField("Password", text: $supabasePasswordInput)
                                .textFieldStyle(.plain)
                                .storeField(maxWidth: 560)
                        }

                        HStack(spacing: 8) {
                            Button("Sign in (Supabase JWT)") {
                                signInSupabase()
                            }
                            .buttonStyle(.bordered)
                            .disabled(supabaseAuthBusy)

                            Button("Create account") {
                                signUpSupabase()
                            }
                            .buttonStyle(.bordered)
                            .disabled(supabaseAuthBusy)

                            Button("Reset password") {
                                requestSupabasePasswordReset()
                            }
                            .buttonStyle(.bordered)
                            .disabled(supabaseAuthBusy)
                        }
                    }

                    Text(supabaseStatusText)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.secondaryText)
                }
            } label: {
                Text("Auth setup")
                    .font(.system(size: 13, weight: .semibold))
            }
            .groupBoxStyle(StoreGroupBoxStyle())

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    settingRow(title: "Tiltale") {
                        Picker("Tiltale", selection: $settings.emailReplyGreetingMode) {
                            ForEach(EmailReplyGreetingMode.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                        .storePicker(maxWidth: 300)
                    }

                    settingRow(title: "Avslutning") {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Avslutning", selection: $settings.emailReplySignoffMode) {
                                ForEach(EmailReplySignoffMode.allCases) { option in
                                    Text(option.label).tag(option)
                                }
                            }
                            .storePicker(maxWidth: 300)

                            if settings.emailReplySignoffMode == .custom {
                                TextField("Lim inn signaturen du vil bruke i e-postsvar", text: $settings.emailReplyCustomSignature, axis: .vertical)
                                    .textFieldStyle(.plain)
                                    .storeField(maxWidth: 560)
                            } else if settings.emailReplySignoffMode == .autoName {
                                Text(settings.resolvedEmailReplySignoffText)
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppTheme.secondaryText)
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
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
                    }
                }
            } label: {
                Text("Mail")
                    .font(.system(size: 13, weight: .semibold))
            }
            .groupBoxStyle(StoreGroupBoxStyle())

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    settingRow(title: "Current shortcut") {
                        readOnlyValue(settings.shortcutTriggerKey.summary)
                    }

                    HStack(spacing: 8) {
                        Button(isCapturingShortcut ? "Listening…" : "Rebind") {
                            startShortcutCapture()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.accent)
                        .disabled(isCapturingShortcut)

                        if isCapturingShortcut {
                            Button("Cancel") {
                                stopShortcutCapture()
                            }
                            .buttonStyle(.bordered)
                        }

                        Spacer()
                    }

                    Text(isCapturingShortcut ? shortcutCaptureStatus : "Trykk Fn, Left Option, Right Option, Left Command eller Right Command.")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryText)

                    Picker("Preset", selection: $settings.shortcutTriggerKey) {
                        ForEach(ShortcutTriggerKey.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .storePicker(maxWidth: 320)
                }
            } label: {
                Text("Shortcuts")
                    .font(.system(size: 13, weight: .semibold))
            }
            .groupBoxStyle(StoreGroupBoxStyle())

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Maks lagrede diktater")
                        Spacer()
                        Stepper(
                            value: historyMaxEntriesBinding,
                            in: 20...2000,
                            step: 20
                        ) {
                            Text("\(history.maxEntries)")
                                .frame(width: 58, alignment: .trailing)
                        }
                        .frame(width: 180)
                    }

                    HStack {
                        Text("Lagringer nå: \(history.entries.count)")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.secondaryText)
                        Spacer()
                        Button("Tøm historikk") {
                            history.clearAll()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } label: {
                Text("History")
                    .font(.system(size: 13, weight: .semibold))
            }
            .groupBoxStyle(StoreGroupBoxStyle())

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Klientloggen lagrer lokale auth-, permission- og AI-feil, slik at testere kan sende deg noe konkret når appen stopper.")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Text("Hendelser: \(appLog.entryCount)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.primaryText)

                        Spacer()

                        Button("Copy debug log") {
                            copyDebugLog()
                        }
                        .buttonStyle(.bordered)
                        .disabled(appLog.entryCount == 0)

                        Button("Save debug log…") {
                            saveDebugLog()
                        }
                        .buttonStyle(.bordered)
                        .disabled(appLog.entryCount == 0)

                        Button("Clear debug log") {
                            appLog.clear()
                        }
                        .buttonStyle(.bordered)
                        .disabled(appLog.entryCount == 0)
                    }

                    if let latest = appLog.latestSummary, !latest.isEmpty {
                        Text(latest)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(2)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
            } label: {
                Text("Diagnostics")
                    .font(.system(size: 13, weight: .semibold))
            }
            .groupBoxStyle(StoreGroupBoxStyle())
        }
    }

    private func settingRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.primaryText)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func languagePicker(selection: Binding<AppLanguage>, width: CGFloat) -> some View {
        Picker("", selection: selection) {
            ForEach(AppLanguage.allCases) { language in
                Text(language.pickerMenuLabel).tag(language)
            }
        }
        .storePicker(maxWidth: width)
    }

    private func interpretationLevelBar(selection: Binding<InterpretationLevel>) -> some View {
        Picker("Forståelse", selection: selection) {
            ForEach(InterpretationLevel.allCases) { level in
                Text(level.label).tag(level)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 520)
    }

    private func modePicker(selection: Binding<InsertionMode>, width: CGFloat = 320) -> some View {
        Picker("", selection: selection) {
            ForEach(InsertionMode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .storePicker(maxWidth: width)
    }

    private func microphonePicker(selection: Binding<String>, width: CGFloat) -> some View {
        Picker("", selection: selection) {
            ForEach(microphones) { microphone in
                Text(microphone.name).tag(microphone.id)
            }
        }
        .storePicker(maxWidth: width)
    }

    private func readOnlyValue(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(AppTheme.primaryText)
            .padding(.horizontal, 12)
            .frame(maxWidth: 560, minHeight: 42, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(AppTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(AppTheme.fieldBorder, lineWidth: 1)
                    )
            )
    }

    private func privacyInfoRow(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.primaryText)

            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func copyDebugLog() {
        let text = appLog.exportText()
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func saveDebugLog() {
        let text = appLog.exportText()
        guard !text.isEmpty else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "BlueSpeak-debug-log-\(formatter.string(from: Date())).txt"
        panel.allowedContentTypes = [.plainText]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            supabaseAuthStatus = "Could not save debug log. \(error.localizedDescription)"
            AppLogStore.shared.record(.error, "Debug log save failed", metadata: ["error": error.localizedDescription])
        }
    }

    private func refreshMicrophones() {
        microphones = MicrophoneCatalog.availableOptions()
        let validIDs = Set(microphones.map(\.id))
        if !validIDs.contains(settings.selectedMicrophoneUID) {
            settings.selectedMicrophoneUID = MicrophoneOption.systemDefaultID
        }
    }

    private var historyMaxEntriesBinding: Binding<Int> {
        Binding(
            get: { history.maxEntries },
            set: { history.setMaxEntries($0) }
        )
    }

    private var supabaseStatusText: String {
        if !supabaseAuthStatus.isEmpty {
            return supabaseAuthStatus
        }
        guard settings.hasSupabaseSession else {
            return "No Supabase session. Sign in to use per-user JWT."
        }
        if let expiry = settings.supabaseSessionExpiresAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            let remaining = formatter.localizedString(for: expiry, relativeTo: Date())
            return "Supabase session active (\(remaining))."
        }
        return "Supabase session active."
    }

    private func signInSupabase() {
        performSupabaseAuth(starting: "Signing in...") {
            try await settings.signInSupabase(
                email: supabaseEmailInput,
                password: supabasePasswordInput
            )
            return "Signed in. JWT is active for backend requests."
        }
    }

    private func signUpSupabase() {
        performSupabaseAuth(starting: "Creating account...") {
            let result = try await settings.signUpSupabase(
                email: supabaseEmailInput,
                password: supabasePasswordInput
            )

            switch result {
            case .signedIn:
                return "Account created. JWT is active for backend requests."
            case .confirmationRequired:
                return "Account created. Check your email, then sign in."
            }
        }
    }

    private func refreshSupabaseJWT() {
        supabaseAuthBusy = true
        supabaseAuthStatus = "Refreshing session..."
        Task {
            defer { supabaseAuthBusy = false }
            let refreshed = await settings.refreshSupabaseSessionIfNeeded(force: true)
            supabaseAuthStatus = refreshed
                ? "Session refreshed."
                : "Refresh failed. Sign in again."
        }
    }

    private func signOutSupabase() {
        settings.signOutSupabaseSession()
        supabasePasswordInput = ""
        supabaseAuthStatus = "Signed out."
    }

    private func switchAccountSupabase() {
        settings.signOutSupabaseSession(clearRememberedEmail: true)
        supabaseEmailInput = ""
        supabasePasswordInput = ""
        supabaseAuthStatus = "Signed out. Enter another email to switch accounts."
    }

    private func updateSupabaseName() {
        performSupabaseAuth(starting: "Saving name...") {
            try await settings.updateSupabaseProfile(
                firstName: accountFirstNameInput,
                lastName: accountLastNameInput
            )
            return "Name updated."
        }
    }

    private func requestSupabasePasswordResetForCurrentAccount() {
        performSupabaseAuth(starting: "Sending reset email...") {
            let email = settings.supabaseUserEmail.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !email.isEmpty else {
                return "No account email available."
            }
            try await settings.requestSupabasePasswordReset(email: email)
            return "If the account exists, a reset email has been sent to \(email)."
        }
    }

    private func deleteSupabaseAccount() {
        performSupabaseAuth(starting: "Deleting account...") {
            try await settings.deleteSupabaseAccount()
            supabaseEmailInput = ""
            accountFirstNameInput = ""
            accountLastNameInput = ""
            return "Account deleted."
        }
    }

    private func requestSupabasePasswordReset() {
        let email = supabaseEmailInput
        supabaseAuthBusy = true
        supabaseAuthStatus = "Sending reset email..."

        Task {
            defer { supabaseAuthBusy = false }

            do {
                try await settings.requestSupabasePasswordReset(email: email)
                supabaseAuthStatus = "If the account exists, a password reset email has been sent."
            } catch {
                supabaseAuthStatus = error.localizedDescription
            }
        }
    }

    private func copyBackendToken() {
        let token = settings.backendToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(token, forType: .string)
    }

    private func clearLocalPrivateData() {
        history.clearAll()
        settings.signOutSupabaseSession(clearRememberedEmail: true)
        supabaseEmailInput = ""
        supabasePasswordInput = ""
        supabaseAuthStatus = "Local history and session removed from this Mac."
    }

    private func startShortcutCapture() {
        stopShortcutCapture()
        settings.isShortcutCaptureActive = true
        isCapturingShortcut = true
        shortcutCaptureStatus = "Waiting for key…"

        shortcutCaptureMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            if let key = shortcutKey(from: event) {
                settings.shortcutTriggerKey = key
                shortcutCaptureStatus = "Set to \(key.label)."
                stopShortcutCapture()
            }
            return event
        }
    }

    private func stopShortcutCapture() {
        settings.isShortcutCaptureActive = false
        if let monitor = shortcutCaptureMonitor {
            NSEvent.removeMonitor(monitor)
            shortcutCaptureMonitor = nil
        }
        isCapturingShortcut = false
    }

    private func shortcutKey(from event: NSEvent) -> ShortcutTriggerKey? {
        guard event.type == .flagsChanged else { return nil }

        switch event.keyCode {
        case UInt16(kVK_Function):
            return .function
        case UInt16(kVK_Option):
            return .leftOption
        case UInt16(kVK_RightOption):
            return .rightOption
        case UInt16(kVK_Command):
            return .leftCommand
        case UInt16(kVK_RightCommand):
            return .rightCommand
        default:
            return nil
        }
    }

    private func performSupabaseAuth(
        starting status: String,
        action: @escaping @MainActor () async throws -> String
    ) {
        supabaseAuthBusy = true
        supabaseAuthStatus = status

        Task {
            defer {
                supabaseAuthBusy = false
                supabasePasswordInput = ""
            }

            do {
                let nextStatus = try await action()
                supabaseEmailInput = settings.supabaseUserEmail
                supabaseAuthStatus = nextStatus
            } catch {
                supabaseAuthStatus = error.localizedDescription
            }
        }
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

    private var currentPlanLabel: String {
        subscriptionPlan == .free ? "Free" : "Pro"
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

    private func openUpgradePage() {
        guard let url = URL(string: "https://flow-speak-direct.lovable.app") else { return }
        NSWorkspace.shared.open(url)
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
