import SwiftUI

struct ThemePalette {
    let appBackgroundTop: Color
    let appBackgroundBottom: Color
    let canvasBackgroundTop: Color
    let canvasBackgroundBottom: Color
}

extension AppTheme {
    var palette: ThemePalette {
        switch self {
        case .graphite:
            return ThemePalette(
                appBackgroundTop: Color(red: 0.11, green: 0.11, blue: 0.13),
                appBackgroundBottom: Color(red: 0.06, green: 0.06, blue: 0.08),
                canvasBackgroundTop: Color(red: 0.05, green: 0.05, blue: 0.07),
                canvasBackgroundBottom: Color(red: 0.02, green: 0.02, blue: 0.04)
            )
        case .ocean:
            return ThemePalette(
                appBackgroundTop: Color(red: 0.06, green: 0.15, blue: 0.21),
                appBackgroundBottom: Color(red: 0.02, green: 0.07, blue: 0.11),
                canvasBackgroundTop: Color(red: 0.01, green: 0.09, blue: 0.14),
                canvasBackgroundBottom: Color(red: 0.02, green: 0.05, blue: 0.11)
            )
        case .amber:
            return ThemePalette(
                appBackgroundTop: Color(red: 0.21, green: 0.15, blue: 0.07),
                appBackgroundBottom: Color(red: 0.11, green: 0.07, blue: 0.03),
                canvasBackgroundTop: Color(red: 0.13, green: 0.08, blue: 0.03),
                canvasBackgroundBottom: Color(red: 0.08, green: 0.05, blue: 0.02)
            )
        }
    }
}

extension InAppSearchShortcut {
    var keyEquivalent: KeyEquivalent {
        KeyEquivalent(Character(rawValue))
    }
}

// MARK: – Button styles

struct GraphSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white.opacity(configuration.isPressed ? 0.7 : 0.88))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.18 : 0.09))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct GraphPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.14, green: 0.52, blue: 0.92).opacity(configuration.isPressed ? 0.8 : 1),
                                Color(red: 0.10, green: 0.68, blue: 0.65).opacity(configuration.isPressed ? 0.8 : 1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct GraphDangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.red.opacity(configuration.isPressed ? 0.65 : 0.78))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: – Icon toolbar button style

struct ToolbarIconButtonStyle: ButtonStyle {
    var isActive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isActive ? Color.cyan.opacity(0.9) : Color.white.opacity(configuration.isPressed ? 0.6 : 0.78))
            .frame(width: 30, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        isActive
                        ? Color.cyan.opacity(0.12)
                        : Color.white.opacity(configuration.isPressed ? 0.14 : 0.06)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isActive ? Color.cyan.opacity(0.25) : Color.white.opacity(0.08), lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
