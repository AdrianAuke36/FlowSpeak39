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

    @State private var newBundleId: String = ""
    @State private var newMode: InsertionMode = .pasteOnly

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("FlowLite")
                .font(.title2)
                .bold()

            Text("Hotkey: ⌃⌥Space  •  Hold to talk, release to insert.")
                .font(.body)

            Divider()

            HStack {
                Text("Default mode")
                Spacer()
                Picker("", selection: $settings.globalMode) {
                    ForEach(InsertionMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 220)
            }

            Text("App-specific overrides")
                .font(.headline)

            HStack(spacing: 10) {
                Button("Add current app") {
                    if let bid = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
                        newBundleId = bid
                    }
                }

                TextField("bundle id (e.g. com.google.Chrome)", text: $newBundleId)
                    .textFieldStyle(.roundedBorder)

                Picker("", selection: $newMode) {
                    ForEach(InsertionMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 200)

                Button("Add") {
                    let bid = newBundleId.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !bid.isEmpty else { return }
                    settings.setOverride(bundleId: bid, mode: newMode)
                    newBundleId = ""
                }
            }

            List {
                ForEach(settings.overrides.keys.sorted(), id: \.self) { key in
                    HStack {
                        Text(key)
                            .font(.system(size: 12, design: .monospaced))
                        Spacer()
                        Picker("", selection: Binding(
                            get: { InsertionMode(rawValue: settings.overrides[key] ?? "") ?? settings.globalMode },
                            set: { settings.setOverride(bundleId: key, mode: $0) }
                        )) {
                            ForEach(InsertionMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 220)

                        Button("Remove") { settings.removeOverride(bundleId: key) }
                    }
                }
            }
            .frame(height: 240)

            Text("Permissions: enable FlowLite in Privacy & Security → Accessibility + Input Monitoring.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(16)
    }
}
