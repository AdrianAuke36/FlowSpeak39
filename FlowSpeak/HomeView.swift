import AppKit
import SwiftUI

struct HomeView: View {
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
        HStack(spacing: 0) {
            Sidebar(activePage: $activePage)
            Divider()
            pageContent
        }
        .frame(width: 980, height: 640)
        .background(Color(NSColor.windowBackgroundColor))
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

// MARK: - Sidebar

struct Sidebar: View {
    @Binding var activePage: HomeView.Page

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Logo
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary)
                        .frame(width: 28, height: 28)
                    Text("🎙").font(.system(size: 14))
                }
                Text("FlowSpeak")
                    .font(.system(size: 15, weight: .bold, design: .serif))
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
                Label("Snarvei", systemImage: "keyboard")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(red: 0.24, green: 0.24, blue: 0.24))
                Text("Hold fn for å starte og slippe for å sette inn tekst.")
                    .font(.system(size: 11))
                    .foregroundColor(Color(red: 0.28, green: 0.28, blue: 0.28).opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                Label("Hold fn+Shift for Translate-språk", systemImage: "globe")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(red: 0.32, green: 0.32, blue: 0.32))
                Label("Velg stil i Style-siden", systemImage: "textformat")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(red: 0.32, green: 0.32, blue: 0.32))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(red: 0.96, green: 0.96, blue: 0.93))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                    )
            )
            .padding(12)
        }
        .frame(width: 190)
        .background(Color(NSColor.controlBackgroundColor))
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
                    .fill(active ? Color.primary.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .foregroundColor(active ? .primary : .secondary)
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
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 18)

            HStack(spacing: 24) {
                ForEach(StyleScope.allCases) { scope in
                    Button(action: { selectedScope = scope }) {
                        VStack(spacing: 8) {
                            Text(scope.title)
                                .font(.system(size: 14, weight: selectedScope == scope ? .semibold : .medium))
                                .foregroundColor(selectedScope == scope ? .primary : .secondary)
                            Rectangle()
                                .fill(selectedScope == scope ? Color.primary : Color.clear)
                                .frame(height: 2)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 14)

            HStack(spacing: 12) {
                HStack(spacing: -6) {
                    ForEach(selectedScope.iconNames, id: \.self) { icon in
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary.opacity(0.85))
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.white.opacity(0.8)))
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                    }
                }
                .padding(.trailing, 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedScope.bannerTitle)
                        .font(.system(size: 13, weight: .semibold))
                    Text("Style formatting currently works best in English. More language tuning coming soon.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 0.98, green: 0.98, blue: 0.91))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color(red: 0.84, green: 0.84, blue: 0.70), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 28)
            .padding(.bottom, 18)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
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
        .background(Color(NSColor.windowBackgroundColor))
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
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(size: 22, weight: .regular, design: .serif))
                Text(subtitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)

                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        Text(sampleText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary.opacity(0.85))
                            .multilineTextAlignment(.leading)
                            .lineLimit(7)
                            .padding(10),
                        alignment: .topLeading
                    )
                    .frame(height: 170)
            }
            .padding(16)
            .frame(width: 245, alignment: .topLeading)
            .frame(height: 290)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.windowBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                isSelected ? Color(red: 0.62, green: 0.46, blue: 0.85) : Color.primary.opacity(0.12),
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
                VStack(alignment: .leading, spacing: 3) {
                    Text("Velkommen tilbake")
                        .font(.system(size: 20, weight: .bold, design: .serif))
                    Text("Hold fn for diktering (fn+Shift = Translate, fn+Control = Rewrite)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

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

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("💡 Tips")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Bruk Style-siden for tone. På Home kan du raskt velge språk, stil og innsettingsmodus.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                quickControls
            }
            .padding(14)
            .cardSurface()
            .padding(.horizontal, 28)
            .padding(.bottom, 20)

            // History header
            Text("I DAG")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
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
                        .foregroundColor(.secondary)
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
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var streakLabel: String {
        let days = history.entries.isEmpty ? 0 : 1
        return "\(days) dag"
    }

    private var quickControls: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Språk")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Picker("", selection: $settings.appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.menuLabel).tag(language)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 110)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Translate")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Picker("", selection: $settings.translationTargetLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.menuLabel).tag(language)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 110)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Stil")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Picker("", selection: $settings.writingStyle) {
                    ForEach(WritingStyle.allCases) { style in
                        Text(style.menuLabel).tag(style)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Innstikking")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Picker("", selection: $settings.globalMode) {
                    ForEach(InsertionMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 185)
            }
        }
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
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        )
        .foregroundColor(.primary)
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
                .foregroundColor(.secondary)
                .padding(.top, 2)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(entry.appName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)

                    Spacer()

                    ModeBadge(mode: entry.mode)
                    Button(action: copyToClipboard) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Kopier tekst")
                }

                Text(entry.text)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
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
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
                )
        )
    }
}

private extension View {
    func cardSurface() -> some View {
        modifier(CardSurfaceModifier())
    }
}
