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

struct NodeStyleConfig {
    var titleFontSize: CGFloat
    var subtitleFontSize: CGFloat
    var paddingH: CGFloat
    var paddingV: CGFloat
    var cornerRadius: CGFloat

    static let `default` = NodeStyleConfig(
        titleFontSize: 14, subtitleFontSize: 11,
        paddingH: 14, paddingV: 9, cornerRadius: 12
    )
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
    /// ⌘K — default in-app search hotkey
    static let cmdK = HotKeyConfig(keyCode: 40, modifiers: 256, displayString: "⌘K", disabled: false)
}

struct AppSettings: Codable, Equatable {
    var theme: AppTheme = .graphite
    /// Recorded in-app search hotkey (replaces single-char inAppSearchKey).
    var inAppHotKeyConfig: HotKeyConfig = .cmdK
    /// Recorded global hotkey configuration.
    var globalHotKeyConfig: HotKeyConfig = .default
    var rightClickPanEnabled: Bool = true
    var dragToConnectEnabled: Bool = false
    var editorOpensAsModal: Bool = false
    var canvasPanX: Double = 0
    var canvasPanY: Double = 0
    var canvasZoom: Double = 1.0
    /// Per-stage pan/zoom. Key = "root" or "\(noteID)". Value = [panX, panY, zoom].
    var stageStates: [String: [Double]] = [:]
    var nodeTitleFontSize: Double = 14
    var nodeSubtitleFontSize: Double = 11
    var nodePaddingH: Double = 14
    var nodePaddingV: Double = 9
    var nodeCornerRadius: Double = 12

    var nodeStyleConfig: NodeStyleConfig {
        NodeStyleConfig(
            titleFontSize: CGFloat(nodeTitleFontSize),
            subtitleFontSize: CGFloat(nodeSubtitleFontSize),
            paddingH: CGFloat(nodePaddingH),
            paddingV: CGFloat(nodePaddingV),
            cornerRadius: CGFloat(nodeCornerRadius)
        )
    }

    static let `default` = AppSettings()

    private enum CodingKeys: String, CodingKey {
        case theme, inAppHotKeyConfig, inAppSearchKey, globalHotKeyConfig
        case rightClickPanEnabled, dragToConnectEnabled, editorOpensAsModal
        case canvasPanX, canvasPanY, canvasZoom, stageStates
        case nodeTitleFontSize, nodeSubtitleFontSize, nodePaddingH, nodePaddingV, nodeCornerRadius
    }

    init(
        theme: AppTheme = .graphite,
        inAppHotKeyConfig: HotKeyConfig = .cmdK,
        globalHotKeyConfig: HotKeyConfig = .default,
        rightClickPanEnabled: Bool = true,
        dragToConnectEnabled: Bool = false,
        editorOpensAsModal: Bool = false,
        canvasPanX: Double = 0,
        canvasPanY: Double = 0,
        canvasZoom: Double = 1.0,
        stageStates: [String: [Double]] = [:],
        nodeTitleFontSize: Double = 14,
        nodeSubtitleFontSize: Double = 11,
        nodePaddingH: Double = 14,
        nodePaddingV: Double = 9,
        nodeCornerRadius: Double = 12
    ) {
        self.theme = theme
        self.inAppHotKeyConfig = inAppHotKeyConfig
        self.globalHotKeyConfig = globalHotKeyConfig
        self.rightClickPanEnabled = rightClickPanEnabled
        self.dragToConnectEnabled = dragToConnectEnabled
        self.editorOpensAsModal = editorOpensAsModal
        self.canvasPanX = canvasPanX
        self.canvasPanY = canvasPanY
        self.canvasZoom = canvasZoom
        self.stageStates = stageStates
        self.nodeTitleFontSize = nodeTitleFontSize
        self.nodeSubtitleFontSize = nodeSubtitleFontSize
        self.nodePaddingH = nodePaddingH
        self.nodePaddingV = nodePaddingV
        self.nodeCornerRadius = nodeCornerRadius
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        theme = try container.decodeIfPresent(AppTheme.self, forKey: .theme) ?? .graphite
        // Prefer new inAppHotKeyConfig; fall back to legacy inAppSearchKey
        if let config = try container.decodeIfPresent(HotKeyConfig.self, forKey: .inAppHotKeyConfig) {
            inAppHotKeyConfig = config
        } else {
            inAppHotKeyConfig = .cmdK
        }
        globalHotKeyConfig = try container.decodeIfPresent(HotKeyConfig.self, forKey: .globalHotKeyConfig) ?? .default
        rightClickPanEnabled = try container.decodeIfPresent(Bool.self, forKey: .rightClickPanEnabled) ?? true
        dragToConnectEnabled = try container.decodeIfPresent(Bool.self, forKey: .dragToConnectEnabled) ?? false
        editorOpensAsModal = try container.decodeIfPresent(Bool.self, forKey: .editorOpensAsModal) ?? false
        canvasPanX = try container.decodeIfPresent(Double.self, forKey: .canvasPanX) ?? 0
        canvasPanY = try container.decodeIfPresent(Double.self, forKey: .canvasPanY) ?? 0
        canvasZoom = try container.decodeIfPresent(Double.self, forKey: .canvasZoom) ?? 1.0
        stageStates = try container.decodeIfPresent([String: [Double]].self, forKey: .stageStates) ?? [:]
        nodeTitleFontSize = try container.decodeIfPresent(Double.self, forKey: .nodeTitleFontSize) ?? 14
        nodeSubtitleFontSize = try container.decodeIfPresent(Double.self, forKey: .nodeSubtitleFontSize) ?? 11
        nodePaddingH = try container.decodeIfPresent(Double.self, forKey: .nodePaddingH) ?? 14
        nodePaddingV = try container.decodeIfPresent(Double.self, forKey: .nodePaddingV) ?? 9
        nodeCornerRadius = try container.decodeIfPresent(Double.self, forKey: .nodeCornerRadius) ?? 12
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(theme, forKey: .theme)
        try container.encode(inAppHotKeyConfig, forKey: .inAppHotKeyConfig)
        try container.encode(globalHotKeyConfig, forKey: .globalHotKeyConfig)
        try container.encode(rightClickPanEnabled, forKey: .rightClickPanEnabled)
        try container.encode(dragToConnectEnabled, forKey: .dragToConnectEnabled)
        try container.encode(editorOpensAsModal, forKey: .editorOpensAsModal)
        try container.encode(canvasPanX, forKey: .canvasPanX)
        try container.encode(canvasPanY, forKey: .canvasPanY)
        try container.encode(canvasZoom, forKey: .canvasZoom)
        try container.encode(stageStates, forKey: .stageStates)
        try container.encode(nodeTitleFontSize, forKey: .nodeTitleFontSize)
        try container.encode(nodeSubtitleFontSize, forKey: .nodeSubtitleFontSize)
        try container.encode(nodePaddingH, forKey: .nodePaddingH)
        try container.encode(nodePaddingV, forKey: .nodePaddingV)
        try container.encode(nodeCornerRadius, forKey: .nodeCornerRadius)
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
