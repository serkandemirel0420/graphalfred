import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
    case theme
    case hotkeys
    case canvas

    var id: String { rawValue }

    var title: String {
        switch self {
        case .theme:
            return "Theme"
        case .hotkeys:
            return "Hotkeys"
        case .canvas:
            return "Canvas"
        }
    }
}

struct SettingsPanel: View {
    @Binding var settings: AppSettings
    let onClose: () -> Void
    @State private var selectedSection: SettingsSection = .theme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Settings")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(GraphSecondaryButtonStyle())
            }

            HStack {
                Text("Category")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.82))

                Picker("Category", selection: $selectedSection) {
                    ForEach(SettingsSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 180, alignment: .leading)
            }

            Group {
                switch selectedSection {
                case .theme:
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Application Theme")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Applies immediately to the main window and graph canvas.")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.64))
                    }
                    .padding(.bottom, 2)

                    Picker("Theme", selection: $settings.theme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.title).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)

                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [settings.theme.palette.appBackgroundTop, settings.theme.palette.appBackgroundBottom],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .frame(height: 90)
                        .overlay(
                            Text(settings.theme.title)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.92))
                        )

                case .hotkeys:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Global Search Hotkey")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Picker("Global Search Hotkey", selection: $settings.globalSearchHotKey) {
                            ForEach(GlobalSearchHotKey.allCases) { shortcut in
                                Text(shortcut.title).tag(shortcut)
                            }
                        }
                        .pickerStyle(.menu)

                        Divider()
                            .overlay(Color.white.opacity(0.15))
                            .padding(.vertical, 2)

                        Text("In-App Search Shortcut")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Picker("In-App Search Shortcut", selection: $settings.inAppSearchShortcut) {
                            ForEach(InAppSearchShortcut.allCases) { shortcut in
                                Text(shortcut.title).tag(shortcut)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text("The in-app shortcut opens search while GraphAlfred is focused.")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.64))
                    }

                case .canvas:
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $settings.rightClickPanEnabled) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Right-click drag pans canvas")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                                Text("Use right mouse drag as an alternative to holding Space.")
                                    .font(.system(size: 12, weight: .regular, design: .rounded))
                                    .foregroundStyle(Color.white.opacity(0.64))
                            }
                        }

                        Toggle(isOn: $settings.dragToConnectEnabled) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Drag-drop creates connections")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                                Text("Disable if node dragging feels cluttered.")
                                    .font(.system(size: 12, weight: .regular, design: .rounded))
                                    .foregroundStyle(Color.white.opacity(0.64))
                            }
                        }
                    }
                    .toggleStyle(.switch)
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Done") {
                    onClose()
                }
                .buttonStyle(GraphPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520, height: 360)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.96), Color(red: 0.11, green: 0.11, blue: 0.13)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}
