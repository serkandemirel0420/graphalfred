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
                appBackgroundTop: Color(red: 0.13, green: 0.13, blue: 0.14),
                appBackgroundBottom: Color(red: 0.06, green: 0.06, blue: 0.08),
                canvasBackgroundTop: Color.black.opacity(0.95),
                canvasBackgroundBottom: Color(red: 0.08, green: 0.08, blue: 0.1)
            )
        case .ocean:
            return ThemePalette(
                appBackgroundTop: Color(red: 0.06, green: 0.15, blue: 0.21),
                appBackgroundBottom: Color(red: 0.02, green: 0.07, blue: 0.11),
                canvasBackgroundTop: Color(red: 0.01, green: 0.09, blue: 0.14),
                canvasBackgroundBottom: Color(red: 0.02, green: 0.12, blue: 0.17)
            )
        case .amber:
            return ThemePalette(
                appBackgroundTop: Color(red: 0.21, green: 0.15, blue: 0.07),
                appBackgroundBottom: Color(red: 0.11, green: 0.07, blue: 0.03),
                canvasBackgroundTop: Color(red: 0.14, green: 0.09, blue: 0.04),
                canvasBackgroundBottom: Color(red: 0.10, green: 0.07, blue: 0.03)
            )
        }
    }
}

extension InAppSearchShortcut {
    var keyEquivalent: KeyEquivalent {
        KeyEquivalent(Character(rawValue))
    }
}

struct GraphSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.96))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.27 : 0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct GraphPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.15, green: 0.55, blue: 0.94),
                        Color(red: 0.13, green: 0.73, blue: 0.67)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .opacity(configuration.isPressed ? 0.85 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct GraphDangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.red.opacity(configuration.isPressed ? 0.72 : 0.86))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
