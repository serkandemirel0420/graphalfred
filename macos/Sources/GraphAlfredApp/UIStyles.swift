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
                appBackgroundTop: Color(red: 0.95, green: 0.95, blue: 0.96),
                appBackgroundBottom: Color(red: 0.91, green: 0.91, blue: 0.93),
                canvasBackgroundTop: Color(red: 0.90, green: 0.90, blue: 0.92),
                canvasBackgroundBottom: Color(red: 0.86, green: 0.86, blue: 0.89)
            )
        case .ocean:
            return ThemePalette(
                appBackgroundTop: Color(red: 0.92, green: 0.95, blue: 0.98),
                appBackgroundBottom: Color(red: 0.87, green: 0.91, blue: 0.96),
                canvasBackgroundTop: Color(red: 0.86, green: 0.91, blue: 0.96),
                canvasBackgroundBottom: Color(red: 0.81, green: 0.87, blue: 0.94)
            )
        case .amber:
            return ThemePalette(
                appBackgroundTop: Color(red: 0.97, green: 0.95, blue: 0.91),
                appBackgroundBottom: Color(red: 0.93, green: 0.90, blue: 0.84),
                canvasBackgroundTop: Color(red: 0.91, green: 0.88, blue: 0.82),
                canvasBackgroundBottom: Color(red: 0.87, green: 0.84, blue: 0.77)
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
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(Color(white: configuration.isPressed ? 0.3 : 0.18))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.70 : 0.90))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.black.opacity(0.10), lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct GraphPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(white: configuration.isPressed ? 0.22 : 0.10))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct GraphDangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(red: 0.82, green: 0.18, blue: 0.15).opacity(configuration.isPressed ? 0.80 : 1))
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
            .foregroundStyle(
                isActive
                    ? Color(white: 0.08)
                    : Color(white: configuration.isPressed ? 0.10 : 0.38)
            )
            .frame(width: 30, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        isActive
                            ? Color.black.opacity(0.09)
                            : Color.black.opacity(configuration.isPressed ? 0.07 : 0.0)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
