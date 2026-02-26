//
//  SettingsView.swift
//  FlowSpeak
//
//  Created by Adrian Auke on 20/02/2026.
//


import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var history = DictationHistory.shared

    @State private var newBundleId: String = ""
    @State private var newMode: InsertionMode = .pasteOnly
    @State private var microphones: [MicrophoneOption] = MicrophoneCatalog.availableOptions()
    @State private var supabaseEmailInput: String = ""
    @State private var supabasePasswordInput: String = ""
    @State private var supabaseAuthStatus: String = ""
    @State private var supabaseAuthBusy: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings")
                    .font(.system(size: 28, weight: .bold, design: .serif))

                Text("Hold `fn` for å starte diktering. Slipp `fn` for å sette inn teksten. Hold `fn+Shift` for oversettelse i én diktering. Marker tekst, hold `fn+Control` mens du sier rewrite-instruksjonen, og slipp `fn` for å kjøre.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        settingRow(title: "Språk") {
                            languagePicker(selection: $settings.appLanguage)
                                .frame(width: 170)
                        }

                        settingRow(title: "Translate") {
                            languagePicker(selection: $settings.translationTargetLanguage)
                                .frame(width: 170)
                        }

                        settingRow(title: "Stil") {
                            stylePicker(selection: $settings.writingStyle)
                                .frame(width: 170)
                        }

                        settingRow(title: "Default innsettingsmodus") {
                            modePicker(selection: $settings.globalMode)
                                .frame(width: 260)
                        }

                        settingRow(title: "Mikrofon") {
                            HStack(spacing: 8) {
                                microphonePicker(selection: $settings.selectedMicrophoneUID)
                                    .frame(width: 320)

                                Button {
                                    refreshMicrophones()
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .help("Oppdater mikrofonliste")
                            }
                        }

                        settingRow(title: "Backend URL") {
                            TextField(AppSettings.defaultBackendBaseURL, text: $settings.backendBaseURL)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 320)
                        }

                        settingRow(title: "Backend token/JWT") {
                            HStack(spacing: 8) {
                                SecureField("Bearer token or JWT", text: $settings.backendToken)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 320)

                                if !settings.backendToken.isEmpty {
                                    Button("Clear") {
                                        settings.backendToken = ""
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    Text("General")
                        .font(.system(size: 13, weight: .semibold))
                }
                .groupBoxStyle(.automatic)

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        settingRow(title: "Supabase URL") {
                            TextField("https://<project-ref>.supabase.co", text: $settings.supabaseProjectURL)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 320)
                        }

                        settingRow(title: "Supabase anon key") {
                            SecureField("eyJ...", text: $settings.supabaseAnonKey)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 320)
                        }

                        settingRow(title: "Email") {
                            TextField("you@example.com", text: $supabaseEmailInput)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 320)
                        }

                        settingRow(title: "Password") {
                            SecureField("Password", text: $supabasePasswordInput)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 320)
                        }

                        HStack(spacing: 8) {
                            Button("Sign in (Supabase JWT)") {
                                signInSupabase()
                            }
                            .disabled(supabaseAuthBusy)

                            Button("Refresh JWT") {
                                refreshSupabaseJWT()
                            }
                            .disabled(supabaseAuthBusy)

                            Button("Sign out") {
                                signOutSupabase()
                            }
                            .disabled(supabaseAuthBusy)
                        }

                        Text(supabaseStatusText)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Text("Auth")
                        .font(.system(size: 13, weight: .semibold))
                }
                .groupBoxStyle(.automatic)

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        let sortedOverrideKeys = settings.overrides.keys.sorted()

                        HStack(spacing: 10) {
                            Button("Bruk app i fokus") {
                                if let bid = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
                                    newBundleId = bid
                                }
                            }

                            TextField("bundle id (f.eks. com.google.Chrome)", text: $newBundleId)
                                .textFieldStyle(.roundedBorder)

                            modePicker(selection: $newMode)
                                .frame(width: 240)

                            Button("Legg til") {
                                guard !trimmedBundleId.isEmpty else { return }
                                settings.setOverride(bundleId: trimmedBundleId, mode: newMode)
                                newBundleId = ""
                            }
                        }

                        if sortedOverrideKeys.isEmpty {
                            Text("Ingen app-spesifikke regler enda.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(sortedOverrideKeys.enumerated()), id: \.element) { index, key in
                                    HStack {
                                        Text(key)
                                            .font(.system(size: 12, design: .monospaced))
                                        Spacer()
                                        modePicker(selection: overrideBinding(for: key))
                                            .frame(width: 260)

                                        Button("Fjern") { settings.removeOverride(bundleId: key) }
                                    }
                                    .padding(.vertical, 7)

                                    if index < sortedOverrideKeys.count - 1 {
                                        Divider()
                                    }
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                } label: {
                    Text("App-specific Overrides")
                        .font(.system(size: 13, weight: .semibold))
                }
                .groupBoxStyle(.automatic)

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
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Tøm historikk") {
                                history.clearAll()
                            }
                        }
                    }
                } label: {
                    Text("History")
                        .font(.system(size: 13, weight: .semibold))
                }
                .groupBoxStyle(.automatic)

                GroupBox {
                    Text("Permissions: aktiver FlowSpeak i Privacy & Security → Accessibility + Input Monitoring.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text("Permissions")
                        .font(.system(size: 13, weight: .semibold))
                }
                .groupBoxStyle(.automatic)
            }
            .padding(18)
        }
        .onAppear {
            refreshMicrophones()
            if supabaseEmailInput.isEmpty {
                supabaseEmailInput = settings.supabaseUserEmail
            }
        }
    }

    private var trimmedBundleId: String {
        newBundleId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func overrideBinding(for bundleId: String) -> Binding<InsertionMode> {
        Binding(
            get: { InsertionMode(rawValue: settings.overrides[bundleId] ?? "") ?? settings.globalMode },
            set: { settings.setOverride(bundleId: bundleId, mode: $0) }
        )
    }

    private func settingRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
            Spacer()
            content()
        }
    }

    private func languagePicker(selection: Binding<AppLanguage>) -> some View {
        Picker("", selection: selection) {
            ForEach(AppLanguage.allCases) { language in
                Text(language.menuLabel).tag(language)
            }
        }
        .pickerStyle(.menu)
    }

    private func stylePicker(selection: Binding<WritingStyle>) -> some View {
        Picker("", selection: selection) {
            ForEach(WritingStyle.allCases) { style in
                Text(style.menuLabel).tag(style)
            }
        }
        .pickerStyle(.menu)
    }

    private func modePicker(selection: Binding<InsertionMode>) -> some View {
        Picker("", selection: selection) {
            ForEach(InsertionMode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.menu)
    }

    private func microphonePicker(selection: Binding<String>) -> some View {
        Picker("", selection: selection) {
            ForEach(microphones) { microphone in
                Text(microphone.name).tag(microphone.id)
            }
        }
        .pickerStyle(.menu)
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
        supabaseAuthBusy = true
        supabaseAuthStatus = "Signing in..."
        Task {
            defer {
                supabaseAuthBusy = false
                supabasePasswordInput = ""
            }
            do {
                try await settings.signInSupabase(
                    email: supabaseEmailInput,
                    password: supabasePasswordInput
                )
                supabaseEmailInput = settings.supabaseUserEmail
                supabaseAuthStatus = "Signed in. JWT is active for backend requests."
            } catch {
                supabaseAuthStatus = error.localizedDescription
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
}
