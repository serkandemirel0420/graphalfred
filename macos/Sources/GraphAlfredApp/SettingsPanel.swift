import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
    case appearance
    case shortcuts
    case canvas

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: return "Appearance"
        case .shortcuts: return "Shortcuts"
        case .canvas: return "Canvas"
        }
    }

    var icon: String {
        switch self {
        case .appearance: return "paintpalette"
        case .shortcuts: return "keyboard"
        case .canvas: return "cursorarrow.rays"
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
            Rectangle().fill(Color.white.opacity(0.07)).frame(width: 1)
            contentArea
        }
        .frame(width: 720, height: 480)
        .background(
            ZStack {
                Color(red: 0.07, green: 0.07, blue: 0.09)
                LinearGradient(
                    colors: [Color.white.opacity(0.03), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: – Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("SETTINGS")
                .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.3))
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
        .background(Color.black.opacity(0.22))
    }

    // MARK: – Content area

    private var contentArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            contentHeader
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Group {
                        switch selectedSection {
                        case .appearance: appearanceContent
                        case .shortcuts: shortcutsContent
                        case .canvas: canvasContent
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
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.6))
            Text(selectedSection.title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
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
            sectionLabel("Keyboard Shortcuts", detail: "Customize how you open search across the system and within the app.")

            settingsCard {
                pickerRow(
                    label: "Global Search",
                    detail: "Opens search from anywhere on your Mac",
                    picker: {
                        Picker("", selection: $settings.globalSearchHotKey) {
                            ForEach(GlobalSearchHotKey.allCases) { shortcut in
                                Text(shortcut.title).tag(shortcut)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(minWidth: 200)
                    }
                )

                rowDivider()

                pickerRow(
                    label: "In-App Search",
                    detail: "Opens search while GraphAlfred is the active window",
                    picker: {
                        Picker("", selection: $settings.inAppSearchShortcut) {
                            ForEach(InAppSearchShortcut.allCases) { shortcut in
                                Text(shortcut.title).tag(shortcut)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(minWidth: 200)
                    }
                )
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

    // MARK: – Reusable row builders

    @ViewBuilder
    private func sectionLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(detail)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.45))
        }
    }

    @ViewBuilder
    private func settingsCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
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
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.45))
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
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.45))
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
            .fill(Color.white.opacity(0.07))
            .frame(height: 1)
            .padding(.horizontal, 16)
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
            .foregroundStyle(isSelected ? .white : Color.white.opacity(0.5))
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.10) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.12) : Color.clear, lineWidth: 1)
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

                    // Mini graph preview
                    VStack(spacing: 0) {
                        HStack(spacing: 18) {
                            Circle()
                                .fill(Color.white.opacity(0.22))
                                .frame(width: 9, height: 9)
                            Circle()
                                .fill(Color.white.opacity(0.14))
                                .frame(width: 7, height: 7)
                            Circle()
                                .fill(Color.white.opacity(0.18))
                                .frame(width: 8, height: 8)
                        }
                    }
                }
                .frame(height: 86)
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(
                            isSelected ? Color.cyan.opacity(0.75) : Color.white.opacity(0.1),
                            lineWidth: isSelected ? 2 : 1
                        )
                )

                HStack(spacing: 5) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.cyan.opacity(0.9))
                    }
                    Text(theme.title)
                        .font(.system(size: 12, weight: isSelected ? .bold : .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? .white : Color.white.opacity(0.62))
                }
                .frame(height: 16)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}
