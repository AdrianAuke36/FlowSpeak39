//
//  SettingsView.swift
//  FlowSpeak
//
//  Created by Adrian Auke on 20/02/2026.
//

import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var history = DictationHistory.shared

    @State private var showsAdvancedAuthSettings: Bool = false
    @State private var microphones: [MicrophoneOption] = MicrophoneCatalog.availableOptions()
    @State private var supabaseEmailInput: String = ""
    @State private var supabasePasswordInput: String = ""
    @State private var supabaseAuthStatus: String = ""
    @State private var supabaseAuthBusy: Bool = false

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Settings")
                        .font(.system(size: 28, weight: .bold, design: .serif))
                        .foregroundStyle(AppTheme.primaryText)

                    Text("Hold `fn` for å starte diktering. Slipp `fn` for å sette inn teksten. Hold `fn+Shift` for oversettelse i én diktering. Marker tekst, hold `fn+Control` mens du sier rewrite-instruksjonen, og slipp `fn` for å kjøre.")
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

                                    Button("Advanced auth settings") {
                                        showsAdvancedAuthSettings = true
                                    }
                                    .buttonStyle(StoreSecondaryButtonStyle())
                                }
                            } else {
                                Text("Not signed in. Use the main window to log in, or open advanced auth settings for setup.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppTheme.secondaryText)

                                Button("Advanced auth settings") {
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
            .disabled(showsAdvancedAuthSettings)
            .blur(radius: showsAdvancedAuthSettings ? 1.5 : 0)

            if showsAdvancedAuthSettings {
                Color.black.opacity(0.14)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showsAdvancedAuthSettings = false
                    }

                advancedAuthOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .background(AppTheme.canvas)
        .animation(.easeOut(duration: 0.16), value: showsAdvancedAuthSettings)
        .onAppear {
            refreshMicrophones()
            if supabaseEmailInput.isEmpty {
                supabaseEmailInput = settings.supabaseUserEmail
            }
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
                Text(language.menuLabel).tag(language)
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

                    if !settings.hasSupabaseSession {
                        Button("Create account") {
                            signUpSupabase()
                        }
                        .buttonStyle(StoreSecondaryButtonStyle())
                        .disabled(supabaseAuthBusy)
                    }

                    if settings.hasSupabaseSession {
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

    private func copyBackendToken() {
        let token = settings.backendToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(token, forType: .string)
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
