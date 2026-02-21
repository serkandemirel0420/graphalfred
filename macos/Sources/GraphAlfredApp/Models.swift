import Foundation

struct Note: Codable, Identifiable, Hashable {
    let id: Int64
    var title: String
    var subtitle: String
    var content: String
    var x: Double
    var y: Double
    var parentId: Int64?
    var updatedAt: String
}

struct Link: Codable, Hashable, Identifiable {
    var sourceId: Int64
    var targetId: Int64

    var id: String {
        "\(sourceId)-\(targetId)"
    }
}

struct GraphPayload: Codable {
    var notes: [Note]
    var links: [Link]

    static let empty = GraphPayload(notes: [], links: [])
}

struct CreateNoteRequest: Codable {
    var title: String
    var subtitle: String?
    var content: String?
    var x: Double?
    var y: Double?
    var parentId: Int64? = nil
    var relatedIds: [Int64]?
}

struct UpdateNoteRequest: Codable {
    var title: String
    var subtitle: String
    var content: String
    var x: Double
    var y: Double
    var parentId: Int64? = nil
    var relatedIds: [Int64]?
}

struct UpdatePositionRequest: Codable {
    var x: Double
    var y: Double
}

struct LinkRequest: Codable {
    var sourceId: Int64
    var targetId: Int64
}

struct SearchResponse: Codable {
    var results: [Note]
}

struct NoteDraft: Identifiable {
    var existingId: Int64?
    var title: String
    var subtitle: String
    var content: String
    var x: Double
    var y: Double
    var parentId: Int64?
    var relatedIds: Set<Int64>

    var id: String {
        if let existingId {
            return "note-\(existingId)"
        }
        return "new-note"
    }
}

enum AppTheme: String, Codable, CaseIterable, Identifiable {
    case graphite
    case ocean
    case amber

    var id: String { rawValue }

    var title: String {
        switch self {
        case .graphite:
            return "Graphite"
        case .ocean:
            return "Ocean"
        case .amber:
            return "Amber"
        }
    }
}

// Legacy enums kept only so old UserDefaults data can still be decoded.
enum InAppSearchShortcut: String, Codable, CaseIterable, Identifiable {
    case commandK = "k"; case commandL = "l"; case commandP = "p"
    var id: String { rawValue }
    var title: String { rawValue }
}
enum GlobalSearchHotKey: String, Codable, CaseIterable, Identifiable {
    case optionSpace; case commandOptionSpace; case controlOptionSpace; case disabled
    var id: String { rawValue }
    var title: String { rawValue }
}

/// A recorded global hotkey using Carbon key codes.
struct HotKeyConfig: Codable, Equatable {
    /// Carbon virtual key code (kVK_Space = 49).
    var keyCode: UInt32
    /// Carbon modifier flags (optionKey = 2048, cmdKey = 256, controlKey = 4096).
    var modifiers: UInt32
    /// Human-readable label shown in settings (e.g. "⌥ Space").
    var displayString: String
    var disabled: Bool

    static let `default` = HotKeyConfig(keyCode: 49, modifiers: 2048, displayString: "⌥ Space", disabled: false)
    static let off = HotKeyConfig(keyCode: 0, modifiers: 0, displayString: "Disabled", disabled: true)
}

struct AppSettings: Codable, Equatable {
    var theme: AppTheme = .graphite
    /// Single character key for in-app search (used as Cmd + key).
    var inAppSearchKey: String = "k"
    /// Recorded global hotkey configuration.
    var globalHotKeyConfig: HotKeyConfig = .default
    var rightClickPanEnabled: Bool = true
    var dragToConnectEnabled: Bool = false
    var editorOpensAsModal: Bool = false
    var canvasPanX: Double = 0
    var canvasPanY: Double = 0
    var canvasZoom: Double = 1.0

    static let `default` = AppSettings()

    private enum CodingKeys: String, CodingKey {
        case theme, inAppSearchKey, globalHotKeyConfig
        case rightClickPanEnabled, dragToConnectEnabled, editorOpensAsModal
        case canvasPanX, canvasPanY, canvasZoom
    }

    init(
        theme: AppTheme = .graphite,
        inAppSearchKey: String = "k",
        globalHotKeyConfig: HotKeyConfig = .default,
        rightClickPanEnabled: Bool = true,
        dragToConnectEnabled: Bool = false,
        editorOpensAsModal: Bool = false,
        canvasPanX: Double = 0,
        canvasPanY: Double = 0,
        canvasZoom: Double = 1.0
    ) {
        self.theme = theme
        self.inAppSearchKey = inAppSearchKey
        self.globalHotKeyConfig = globalHotKeyConfig
        self.rightClickPanEnabled = rightClickPanEnabled
        self.dragToConnectEnabled = dragToConnectEnabled
        self.editorOpensAsModal = editorOpensAsModal
        self.canvasPanX = canvasPanX
        self.canvasPanY = canvasPanY
        self.canvasZoom = canvasZoom
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        theme = try container.decodeIfPresent(AppTheme.self, forKey: .theme) ?? .graphite
        inAppSearchKey = try container.decodeIfPresent(String.self, forKey: .inAppSearchKey) ?? "k"
        globalHotKeyConfig = try container.decodeIfPresent(HotKeyConfig.self, forKey: .globalHotKeyConfig) ?? .default
        rightClickPanEnabled = try container.decodeIfPresent(Bool.self, forKey: .rightClickPanEnabled) ?? true
        dragToConnectEnabled = try container.decodeIfPresent(Bool.self, forKey: .dragToConnectEnabled) ?? false
        editorOpensAsModal = try container.decodeIfPresent(Bool.self, forKey: .editorOpensAsModal) ?? false
        canvasPanX = try container.decodeIfPresent(Double.self, forKey: .canvasPanX) ?? 0
        canvasPanY = try container.decodeIfPresent(Double.self, forKey: .canvasPanY) ?? 0
        canvasZoom = try container.decodeIfPresent(Double.self, forKey: .canvasZoom) ?? 1.0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(theme, forKey: .theme)
        try container.encode(inAppSearchKey, forKey: .inAppSearchKey)
        try container.encode(globalHotKeyConfig, forKey: .globalHotKeyConfig)
        try container.encode(rightClickPanEnabled, forKey: .rightClickPanEnabled)
        try container.encode(dragToConnectEnabled, forKey: .dragToConnectEnabled)
        try container.encode(editorOpensAsModal, forKey: .editorOpensAsModal)
        try container.encode(canvasPanX, forKey: .canvasPanX)
        try container.encode(canvasPanY, forKey: .canvasPanY)
        try container.encode(canvasZoom, forKey: .canvasZoom)
    }
}

enum AppSettingsStore {
    private static let settingsKey = "graphalfred.settings.v1"

    static func load() -> AppSettings {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: settingsKey) else {
            return .default
        }

        guard let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .default
        }

        return settings
    }

    static func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }
        UserDefaults.standard.set(data, forKey: settingsKey)
    }
}
