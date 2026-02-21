import AppKit
import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
    case appearance
    case shortcuts
    case canvas
    case editor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: return "Appearance"
        case .shortcuts: return "Shortcuts"
        case .canvas: return "Canvas"
        case .editor: return "Editor"
        }
    }

    var icon: String {
        switch self {
        case .appearance: return "paintpalette"
        case .shortcuts: return "keyboard"
        case .canvas: return "cursorarrow.rays"
        case .editor: return "doc.text"
        }
    }
}

struct SettingsPanel: View {
    @Binding var settings: AppSettings
    let onClose: () -> Void
    @State private var selectedSection: SettingsSection = .appearance

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Color.black.opacity(0.07)).frame(width: 1)
            contentArea
        }
        .frame(minWidth: 680, minHeight: 460)
        .background(Color(red: 0.97, green: 0.97, blue: 0.98))
    }

    // MARK: – Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("SETTINGS")
                .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(white: 0.60))
                .tracking(1.4)
                .padding(.bottom, 12)

            ForEach(SettingsSection.allCases) { section in
                SidebarTabRow(
                    label: section.title,
                    icon: section.icon,
                    isSelected: selectedSection == section
                ) {
                    withAnimation(.easeInOut(duration: 0.13)) {
                        selectedSection = section
                    }
                }
            }

            Spacer()

            Button("Done") { onClose() }
                .buttonStyle(GraphPrimaryButtonStyle())
                .frame(maxWidth: .infinity)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 20)
        .frame(width: 185)
        .background(Color.black.opacity(0.03))
    }

    // MARK: – Content area

    private var contentArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            contentHeader
            Rectangle().fill(Color.black.opacity(0.06)).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Group {
                        switch selectedSection {
                        case .appearance: appearanceContent
                        case .shortcuts: shortcutsContent
                        case .canvas: canvasContent
                        case .editor: editorContent
                        }
                    }
                    .padding(28)
                }
            }
        }
    }

    private var contentHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: selectedSection.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(white: 0.45))
            Text(selectedSection.title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Color(white: 0.10))
            Spacer()
            Button { onClose() } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(GraphSecondaryButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: – Appearance

    private var appearanceContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            sectionLabel("Color Theme", detail: "Applies to the entire app immediately.")

            HStack(spacing: 14) {
                ForEach(AppTheme.allCases) { theme in
                    ThemeCard(theme: theme, isSelected: settings.theme == theme) {
                        settings.theme = theme
                    }
                }
            }
        }
    }

    // MARK: – Shortcuts

    private var shortcutsContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            sectionLabel("Keyboard Shortcuts", detail: "Customize how you open search. Click \"Record\" and press the key combo you want.")

            settingsCard {
                // Global search hotkey recorder
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Global Search")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(white: 0.12))
                        Text("Opens search from anywhere on your Mac")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(Color(white: 0.52))
                    }
                    Spacer()
                    HotKeyRecorderView(config: $settings.globalHotKeyConfig)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                rowDivider()

                // In-app search key
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("In-App Search")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(white: 0.12))
                        Text("⌘ + your key while GraphAlfred is active")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(Color(white: 0.52))
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        Text("⌘ +")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(white: 0.40))
                        TextField("", text: Binding(
                            get: { settings.inAppSearchKey },
                            set: { new in
                                let filtered = new.filter { $0.isLetter || $0.isNumber }
                                if let ch = filtered.last {
                                    settings.inAppSearchKey = String(ch).lowercased()
                                }
                            }
                        ))
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(white: 0.12))
                        .frame(width: 28, height: 28)
                        .multilineTextAlignment(.center)
                        .background(Color.white.opacity(0.80))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.black.opacity(0.12), lineWidth: 1))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
    }

    // MARK: – Canvas

    private var canvasContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            sectionLabel("Canvas Behavior", detail: "Control how the graph canvas responds to mouse and gesture input.")

            settingsCard {
                toggleRow(
                    label: "Right-click drag pans canvas",
                    detail: "Use right-mouse drag as an alternative to Space + drag",
                    isOn: $settings.rightClickPanEnabled
                )

                rowDivider()

                toggleRow(
                    label: "Drag-drop creates connections",
                    detail: "Dragging a node close to another automatically links them",
                    isOn: $settings.dragToConnectEnabled
                )
            }
        }
    }

    // MARK: – Editor

    private var editorContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            sectionLabel("Editor Behavior", detail: "Choose how the note editor opens when you edit a node.")

            settingsCard {
                toggleRow(
                    label: "Open editor as modal",
                    detail: "Editor expands as a full-screen overlay instead of a side panel",
                    isOn: $settings.editorOpensAsModal
                )
            }
        }
    }

    // MARK: – Reusable row builders

    @ViewBuilder
    private func sectionLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color(white: 0.10))
            Text(detail)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(Color(white: 0.52))
        }
    }

    @ViewBuilder
    private func settingsCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(Color.white.opacity(0.70))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.black.opacity(0.07), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func pickerRow<Content: View>(
        label: String,
        detail: String,
        @ViewBuilder picker: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(white: 0.12))
                Text(detail)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(Color(white: 0.52))
            }
            Spacer()
            picker()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func toggleRow(label: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(white: 0.12))
                Text(detail)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(Color(white: 0.52))
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func rowDivider() -> some View {
        Rectangle()
            .fill(Color.black.opacity(0.06))
            .frame(height: 1)
            .padding(.horizontal, 16)
    }
}

// MARK: – Window wrapper (used by the Window scene)

struct SettingsWindowView: View {
    @EnvironmentObject private var viewModel: GraphViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SettingsPanel(
            settings: Binding(
                get: { viewModel.settings },
                set: { viewModel.applySettings($0) }
            ),
            onClose: { dismiss() }
        )
    }
}

// MARK: – Sidebar tab row

private struct SidebarTabRow: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 17, alignment: .center)
                Text(label)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                Spacer()
            }
            .foregroundStyle(isSelected ? Color(white: 0.10) : Color(white: 0.50))
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.black.opacity(0.07) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.black.opacity(0.08) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: – Theme card

private struct ThemeCard: View {
    let theme: AppTheme
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [theme.palette.canvasBackgroundTop, theme.palette.canvasBackgroundBottom],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    HStack(spacing: 18) {
                        Circle()
                            .fill(Color.white.opacity(0.85))
                            .frame(width: 9, height: 9)
                            .shadow(color: Color.black.opacity(0.08), radius: 3, y: 1)
                        Circle()
                            .fill(Color.white.opacity(0.70))
                            .frame(width: 7, height: 7)
                        Circle()
                            .fill(Color.white.opacity(0.78))
                            .frame(width: 8, height: 8)
                    }
                }
                .frame(height: 86)
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(
                            isSelected ? Color(white: 0.25).opacity(0.6) : Color.black.opacity(0.08),
                            lineWidth: isSelected ? 2 : 1
                        )
                )

                HStack(spacing: 5) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(white: 0.20))
                    }
                    Text(theme.title)
                        .font(.system(size: 12, weight: isSelected ? .bold : .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? Color(white: 0.10) : Color(white: 0.50))
                }
                .frame(height: 16)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

// MARK: – Hot-key recorder

private struct HotKeyRecorderView: View {
    @Binding var config: HotKeyConfig
    @State private var isRecording = false
    @State private var eventMonitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Text(isRecording ? "Press any key…" : (config.disabled ? "Disabled" : config.displayString))
                .font(isRecording
                      ? .system(size: 12, weight: .regular, design: .rounded)
                      : .system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(
                    isRecording
                        ? Color(white: 0.45)
                        : (config.disabled ? Color(white: 0.55) : Color(white: 0.12))
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(minWidth: 100, alignment: .center)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isRecording ? Color.blue.opacity(0.05) : Color.black.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(
                            isRecording ? Color.blue.opacity(0.35) : Color.black.opacity(0.10),
                            lineWidth: 1
                        )
                )

            Button(isRecording ? "Cancel" : "Record") {
                if isRecording { stopRecording() } else { startRecording() }
            }
            .buttonStyle(GraphSecondaryButtonStyle())

            if !config.disabled && !isRecording {
                Button("Disable") {
                    config = .off
                }
                .buttonStyle(GraphSecondaryButtonStyle())
            }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isRecording else { return event }

            // ESC cancels recording without changing config.
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // Require at least one modifier so bare keys don't accidentally bind.
            guard flags.contains(.option) || flags.contains(.command) || flags.contains(.control) else {
                return nil
            }

            let keyCode = UInt32(event.keyCode)
            var carbonMods: UInt32 = 0
            if flags.contains(.option)  { carbonMods |= 2048 }
            if flags.contains(.command) { carbonMods |= 256  }
            if flags.contains(.control) { carbonMods |= 4096 }
            if flags.contains(.shift)   { carbonMods |= 512  }

            var display = ""
            if flags.contains(.control) { display += "⌃" }
            if flags.contains(.option)  { display += "⌥" }
            if flags.contains(.shift)   { display += "⇧" }
            if flags.contains(.command) { display += "⌘" }
            display += hotkeyKeyName(for: event.keyCode, characters: event.charactersIgnoringModifiers)

            config = HotKeyConfig(keyCode: keyCode, modifiers: carbonMods, displayString: display, disabled: false)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func hotkeyKeyName(for keyCode: UInt16, characters: String?) -> String {
        switch keyCode {
        case 49:  return "Space"
        case 36:  return "↩"
        case 48:  return "⇥"
        case 51:  return "⌫"
        case 117: return "⌦"
        case 53:  return "Esc"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 115: return "Home"
        case 119: return "End"
        case 116: return "PgUp"
        case 121: return "PgDn"
        default:
            return characters?.uppercased().first.map(String.init) ?? "?"
        }
    }
}
