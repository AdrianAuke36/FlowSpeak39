//
//  SettingsView.swift
//  FlowSpeak
//
//  Created by Adrian Auke on 20/02/2026.
//

import AppKit
import Carbon.HIToolbox
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var history = DictationHistory.shared
    @ObservedObject private var appLog = AppLogStore.shared

    @State private var showsAdvancedAuthSettings: Bool = false
    @State private var showsShortcutSettings: Bool = false
    @State private var isCapturingShortcut: Bool = false
    @State private var shortcutCaptureStatus: String = "Press a supported key."
    @State private var shortcutCaptureMonitor: Any?
    @State private var microphones: [MicrophoneOption] = MicrophoneCatalog.availableOptions()
    @State private var supabaseEmailInput: String = ""
    @State private var supabasePasswordInput: String = ""
    @State private var supabaseAuthStatus: String = ""
    @State private var supabaseAuthBusy: Bool = false
    @State private var replyMemoryTitleInput: String = ""
    @State private var replyMemoryTriggersInput: String = ""
    @State private var replyMemorySourceInput: String = ""
    @State private var replyMemoryGuidanceInput: String = ""

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Settings")
                        .font(.system(size: 28, weight: .bold, design: .serif))
                        .foregroundStyle(AppTheme.primaryText)

                    Text(settings.shortcutInstructionText)
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.secondaryText)

                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            settingRow(title: "Språk") {
                                languagePicker(selection: $settings.appLanguage, width: 220)
                            }

                            settingRow(title: "Translate") {
                                languagePicker(selection: $settings.translationTargetLanguage, width: 220)
                            }

                            settingRow(title: "Stil") {
                                stylePicker(selection: $settings.writingStyle, width: 220)
                            }

                            settingRow(title: "Forståelse") {
                                VStack(alignment: .leading, spacing: 8) {
                                    interpretationLevelBar(selection: $settings.interpretationLevel)

                                    Text(settings.interpretationLevel.description)
                                        .font(.system(size: 11))
                                        .foregroundStyle(AppTheme.secondaryText)
                                }
                            }

                            settingRow(title: "Default innsettingsmodus") {
                                modePicker(selection: $settings.globalMode, width: 320)
                            }

                            settingRow(title: "Mikrofon") {
                                HStack(spacing: 8) {
                                    microphonePicker(selection: $settings.selectedMicrophoneUID, width: 380)

                                    Button {
                                        refreshMicrophones()
                                    } label: {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    .buttonStyle(StoreSecondaryButtonStyle())
                                    .help("Oppdater mikrofonliste")
                                }
                            }

                            settingRow(title: "Shortcuts") {
                                HStack(alignment: .center, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(settings.shortcutTriggerKey.summary)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(AppTheme.primaryText)

                                        Text("Velg hovedtasten for dictate, translate og rewrite.")
                                            .font(.system(size: 11))
                                            .foregroundStyle(AppTheme.secondaryText)
                                    }

                                    Spacer()

                                    Button("Change") {
                                        showsAdvancedAuthSettings = false
                                        showsShortcutSettings = true
                                    }
                                    .buttonStyle(StoreSecondaryButtonStyle())
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

                            settingRow(title: "Backend URL") {
                                TextField(AppSettings.defaultBackendBaseURL, text: $settings.backendBaseURL)
                                    .textFieldStyle(.plain)
                                    .storeField(maxWidth: 520)
                            }

                            settingRow(title: "Backend token/JWT") {
                                HStack(spacing: 8) {
                                    SecureField("Bearer token or JWT", text: $settings.backendToken)
                                        .textFieldStyle(.plain)
                                        .storeField(maxWidth: 520)

                                    if !settings.backendToken.isEmpty {
                                        Button("Copy") {
                                            copyBackendToken()
                                        }
                                        .buttonStyle(StoreSecondaryButtonStyle())

                                        Button("Clear") {
                                            settings.backendToken = ""
                                        }
                                        .buttonStyle(StoreSecondaryButtonStyle())
                                    }
                                }
                            }
                        }
                    } label: {
                        Text("General")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .groupBoxStyle(StoreGroupBoxStyle())

                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            if settings.hasSupabaseSession {
                                settingRow(title: "Logged in as") {
                                    readOnlyValue(settings.supabaseUserEmail.isEmpty ? "Unknown account" : settings.supabaseUserEmail)
                                }

                                HStack(spacing: 8) {
                                    Button("Sign out") {
                                        signOutSupabase()
                                    }
                                    .buttonStyle(StoreSecondaryButtonStyle())
                                    .disabled(supabaseAuthBusy)

                                    Button("Switch account") {
                                        switchAccountSupabase()
                                    }
                                    .buttonStyle(StoreSecondaryButtonStyle())
                                    .disabled(supabaseAuthBusy)

                                    Button("Advanced auth settings") {
                                        stopShortcutCapture()
                                        showsShortcutSettings = false
                                        showsAdvancedAuthSettings = true
                                    }
                                    .buttonStyle(StoreSecondaryButtonStyle())
                                }
                            } else {
                                Text("Not signed in. Use the main window to log in, or open advanced auth settings for setup.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppTheme.secondaryText)

                                Button("Advanced auth settings") {
                                    stopShortcutCapture()
                                    showsShortcutSettings = false
                                    showsAdvancedAuthSettings = true
                                }
                                .buttonStyle(StoreSecondaryButtonStyle())
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

                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
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
                                .buttonStyle(StoreSecondaryButtonStyle())
                            }
                        }
                    } label: {
                        Text("History")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .groupBoxStyle(StoreGroupBoxStyle())

                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            privacyInfoRow(
                                title: "Talegjenkjenning",
                                detail: "FlowSpeak bruker Apples talegjenkjenning etter at du har gitt tillatelse. macOS kan sende taledata til Apple for å behandle forespørslene."
                            )

                            privacyInfoRow(
                                title: "AI-behandling",
                                detail: "Teksten du dikterer sendes til FlowSpeak-backenden. Hvis AI er aktiv, sender backenden tekst videre til OpenAI for formatering, oversettelse og rewrite."
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
                                .buttonStyle(StoreSecondaryButtonStyle())

                                Button("Sign out and clear local session") {
                                    clearLocalPrivateData()
                                }
                                .buttonStyle(StoreSecondaryButtonStyle())
                            }
                        }
                    } label: {
                        Text("Privacy")
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
                                .buttonStyle(StoreSecondaryButtonStyle())
                                .disabled(appLog.entryCount == 0)

                                Button("Save debug log…") {
                                    saveDebugLog()
                                }
                                .buttonStyle(StoreSecondaryButtonStyle())
                                .disabled(appLog.entryCount == 0)

                                Button("Clear debug log") {
                                    appLog.clear()
                                }
                                .buttonStyle(StoreSecondaryButtonStyle())
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

                    GroupBox {
                        Text("Permissions: aktiver FlowSpeak i Privacy & Security → Accessibility + Input Monitoring.")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Text("Permissions")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .groupBoxStyle(StoreGroupBoxStyle())
                }
                .padding(18)
            }
            .background(AppTheme.canvas)
            .disabled(showsModalOverlay)
            .blur(radius: showsModalOverlay ? 1.5 : 0)

            if showsModalOverlay {
                Color.black.opacity(0.14)
                    .ignoresSafeArea()
                    .onTapGesture {
                        stopShortcutCapture()
                        showsAdvancedAuthSettings = false
                        showsShortcutSettings = false
                    }

                if showsAdvancedAuthSettings {
                    advancedAuthOverlay
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else if showsShortcutSettings {
                    shortcutSettingsOverlay
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
        }
        .background(AppTheme.canvas)
        .animation(.easeOut(duration: 0.16), value: showsModalOverlay)
        .onAppear {
            refreshMicrophones()
            if supabaseEmailInput.isEmpty {
                supabaseEmailInput = settings.supabaseUserEmail
            }
        }
        .onDisappear {
            stopShortcutCapture()
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

    private func stylePicker(selection: Binding<WritingStyle>, width: CGFloat) -> some View {
        Picker("", selection: selection) {
            ForEach(WritingStyle.allCases) { style in
                Text(style.menuLabel).tag(style)
            }
        }
        .storePicker(maxWidth: width)
    }

    private func interpretationLevelBar(selection: Binding<InterpretationLevel>) -> some View {
        HStack(spacing: 6) {
            ForEach(InterpretationLevel.allCases) { level in
                Button {
                    selection.wrappedValue = level
                } label: {
                    Text(level.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(
                            selection.wrappedValue == level
                                ? Color.white
                                : AppTheme.primaryText
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(
                                    selection.wrappedValue == level
                                        ? AppTheme.accent
                                        : AppTheme.surface
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .frame(maxWidth: 520)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(AppTheme.surfaceMuted)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(AppTheme.fieldBorder, lineWidth: 1)
                )
        )
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
            .frame(maxWidth: 520, minHeight: 42, alignment: .leading)
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
        panel.nameFieldStringValue = "FlowSpeak-debug-log-\(formatter.string(from: Date())).txt"
        panel.allowedContentTypes = [.plainText]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            supabaseAuthStatus = "Could not save debug log. \(error.localizedDescription)"
            AppLogStore.shared.record(.error, "Debug log save failed", metadata: ["error": error.localizedDescription])
        }
    }

    private var showsModalOverlay: Bool {
        showsAdvancedAuthSettings || showsShortcutSettings
    }

    private var advancedAuthOverlay: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Advanced Auth Settings")
                    .font(.system(size: 24, weight: .bold, design: .serif))
                    .foregroundStyle(AppTheme.primaryText)

                Text("Use this page for setup or troubleshooting. Most users only need the login screen in the main window.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.secondaryText)

                settingRow(title: "Supabase URL") {
                    TextField("https://<project-ref>.supabase.co", text: $settings.supabaseProjectURL)
                        .textFieldStyle(.plain)
                        .storeField(maxWidth: 520)
                }

                settingRow(title: "Supabase anon key") {
                    SecureField("eyJ...", text: $settings.supabaseAnonKey)
                        .textFieldStyle(.plain)
                        .storeField(maxWidth: 520)
                }

                if settings.hasSupabaseSession {
                    settingRow(title: "Current account") {
                        readOnlyValue(settings.supabaseUserEmail.isEmpty ? "Unknown account" : settings.supabaseUserEmail)
                    }

                    HStack(spacing: 8) {
                        Button("Refresh JWT") {
                            refreshSupabaseJWT()
                        }
                        .buttonStyle(StoreSecondaryButtonStyle())
                        .disabled(supabaseAuthBusy)

                        Button("Sign out") {
                            signOutSupabase()
                        }
                        .buttonStyle(StoreSecondaryButtonStyle())
                        .disabled(supabaseAuthBusy)

                        Button("Switch account") {
                            switchAccountSupabase()
                        }
                        .buttonStyle(StoreSecondaryButtonStyle())
                        .disabled(supabaseAuthBusy)
                    }
                } else {
                    settingRow(title: "Email") {
                        TextField("you@example.com", text: $supabaseEmailInput)
                            .textFieldStyle(.plain)
                            .storeField(maxWidth: 520)
                    }

                    settingRow(title: "Password") {
                        SecureField("Password", text: $supabasePasswordInput)
                            .textFieldStyle(.plain)
                            .storeField(maxWidth: 520)
                    }

                    HStack(spacing: 8) {
                        Button("Sign in (Supabase JWT)") {
                            signInSupabase()
                        }
                        .buttonStyle(StoreSecondaryButtonStyle())
                        .disabled(supabaseAuthBusy)

                        Button("Create account") {
                            signUpSupabase()
                        }
                        .buttonStyle(StoreSecondaryButtonStyle())
                        .disabled(supabaseAuthBusy)

                        Button("Reset password") {
                            requestSupabasePasswordReset()
                        }
                        .buttonStyle(StoreSecondaryButtonStyle())
                        .disabled(supabaseAuthBusy)
                    }
                }

                Text(supabaseStatusText)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .padding(18)
        }
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(AppTheme.canvas)
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .strokeBorder(AppTheme.fieldBorder, lineWidth: 1)
                )
        )
        .frame(width: 640, height: 500)
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
        .onTapGesture {
            // Prevent clicks inside the card from dismissing the overlay.
        }
    }

    private var shortcutSettingsOverlay: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Shortcuts")
                            .font(.system(size: 24, weight: .bold, design: .serif))
                            .foregroundStyle(AppTheme.primaryText)

                        Text("Velg hovedtasten. Translate bruker + Shift, rewrite bruker + Control, og lagre siste melding midlertidig med + <.")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.secondaryText)
                    }

                    Spacer()

                    Button {
                        stopShortcutCapture()
                        showsShortcutSettings = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 10) {
                    shortcutPreviewRow(title: "Dictate", shortcut: settings.shortcutTriggerKey.dictateShortcut)
                    shortcutPreviewRow(title: "Translate", shortcut: settings.shortcutTriggerKey.translateShortcut)
                    shortcutPreviewRow(title: "Rewrite", shortcut: settings.shortcutTriggerKey.rewriteShortcut)
                    shortcutPreviewRow(title: "Save reply", shortcut: settings.shortcutTriggerKey.saveReplyContextShortcut)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(AppTheme.surfaceMuted)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(AppTheme.fieldBorder, lineWidth: 1)
                        )
                )

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Trykk en tast nå")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.primaryText)

                        Text(isCapturingShortcut ? shortcutCaptureStatus : "FlowSpeak lytter etter en støttet tast.")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.secondaryText)
                    }

                    Spacer()

                    Button(isCapturingShortcut ? "Listening…" : "Rebind") {
                        startShortcutCapture()
                    }
                    .buttonStyle(StoreSecondaryButtonStyle())
                    .disabled(isCapturingShortcut)
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

                VStack(alignment: .leading, spacing: 10) {
                    Text("Presets")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryText)

                    ForEach(ShortcutTriggerKey.allCases) { option in
                        Button {
                            settings.shortcutTriggerKey = option
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(option.label)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(AppTheme.primaryText)

                                    Text(option.summary)
                                        .font(.system(size: 11))
                                        .foregroundStyle(AppTheme.secondaryText)
                                }

                                Spacer()

                                Image(systemName: settings.shortcutTriggerKey == option ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(settings.shortcutTriggerKey == option ? AppTheme.accent : AppTheme.fieldBorder)
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(AppTheme.surface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder(
                                                settings.shortcutTriggerKey == option ? AppTheme.accent : AppTheme.fieldBorder,
                                                lineWidth: 1
                                            )
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    Spacer()

                    Button("Done") {
                        stopShortcutCapture()
                        showsShortcutSettings = false
                    }
                    .buttonStyle(StoreSecondaryButtonStyle())
                }
            }
            .allowsHitTesting(!isCapturingShortcut)

            if isCapturingShortcut {
                Color.black.opacity(0.12)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 14) {
                    Text("Press a key now")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppTheme.primaryText)

                    Text("Trykk Fn, Left Option, Right Option, Left Command eller Right Command.")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.secondaryText)

                    Text(shortcutCaptureStatus)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.primaryText)

                    HStack {
                        Spacer()

                        Button("Cancel") {
                            stopShortcutCapture()
                        }
                        .buttonStyle(StoreSecondaryButtonStyle())
                    }
                }
                .padding(18)
                .frame(width: 380)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(AppTheme.canvas)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(AppTheme.fieldBorder, lineWidth: 1)
                        )
                )
                .shadow(color: .black.opacity(0.18), radius: 22, y: 8)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(AppTheme.canvas)
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .strokeBorder(AppTheme.fieldBorder, lineWidth: 1)
                )
        )
        .frame(width: 560)
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
        .onTapGesture {
            // Prevent clicks inside the card from dismissing the overlay.
        }
    }

    private func shortcutPreviewRow(title: String, shortcut: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.primaryText)

            Spacer()

            Text(shortcut)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.secondaryText)
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

    private var canAddReplyMemory: Bool {
        !replyMemoryTitleInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !replyMemoryTriggersInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !replyMemoryGuidanceInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addReplyMemory() {
        settings.addReplyMemory(
            title: replyMemoryTitleInput,
            triggerText: replyMemoryTriggersInput,
            sourceText: replyMemorySourceInput,
            guidance: replyMemoryGuidanceInput
        )

        replyMemoryTitleInput = ""
        replyMemoryTriggersInput = ""
        replyMemorySourceInput = ""
        replyMemoryGuidanceInput = ""
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
}
