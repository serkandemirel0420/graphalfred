import Foundation

struct Note: Codable, Identifiable, Hashable {
    let id: Int64
    var title: String
    var subtitle: String
    var content: String
    var x: Double
    var y: Double
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
    var relatedIds: [Int64]?
}

struct UpdateNoteRequest: Codable {
    var title: String
    var subtitle: String
    var content: String
    var x: Double
    var y: Double
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

enum InAppSearchShortcut: String, Codable, CaseIterable, Identifiable {
    case commandK = "k"
    case commandL = "l"
    case commandP = "p"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .commandK:
            return "Command + K"
        case .commandL:
            return "Command + L"
        case .commandP:
            return "Command + P"
        }
    }
}

enum GlobalSearchHotKey: String, Codable, CaseIterable, Identifiable {
    case optionSpace
    case commandOptionSpace
    case controlOptionSpace
    case disabled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .optionSpace:
            return "Option + Space"
        case .commandOptionSpace:
            return "Command + Option + Space"
        case .controlOptionSpace:
            return "Control + Option + Space"
        case .disabled:
            return "Disabled"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var theme: AppTheme = .graphite
    var inAppSearchShortcut: InAppSearchShortcut = .commandK
    var globalSearchHotKey: GlobalSearchHotKey = .optionSpace
    var rightClickPanEnabled: Bool = true
    var dragToConnectEnabled: Bool = false

    static let `default` = AppSettings()

    private enum CodingKeys: String, CodingKey {
        case theme
        case inAppSearchShortcut
        case globalSearchHotKey
        case rightClickPanEnabled
        case dragToConnectEnabled
    }

    init(
        theme: AppTheme = .graphite,
        inAppSearchShortcut: InAppSearchShortcut = .commandK,
        globalSearchHotKey: GlobalSearchHotKey = .optionSpace,
        rightClickPanEnabled: Bool = true,
        dragToConnectEnabled: Bool = false
    ) {
        self.theme = theme
        self.inAppSearchShortcut = inAppSearchShortcut
        self.globalSearchHotKey = globalSearchHotKey
        self.rightClickPanEnabled = rightClickPanEnabled
        self.dragToConnectEnabled = dragToConnectEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        theme = try container.decodeIfPresent(AppTheme.self, forKey: .theme) ?? .graphite
        inAppSearchShortcut = try container.decodeIfPresent(InAppSearchShortcut.self, forKey: .inAppSearchShortcut) ?? .commandK
        globalSearchHotKey = try container.decodeIfPresent(GlobalSearchHotKey.self, forKey: .globalSearchHotKey) ?? .optionSpace
        rightClickPanEnabled = try container.decodeIfPresent(Bool.self, forKey: .rightClickPanEnabled) ?? true
        dragToConnectEnabled = try container.decodeIfPresent(Bool.self, forKey: .dragToConnectEnabled) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(theme, forKey: .theme)
        try container.encode(inAppSearchShortcut, forKey: .inAppSearchShortcut)
        try container.encode(globalSearchHotKey, forKey: .globalSearchHotKey)
        try container.encode(rightClickPanEnabled, forKey: .rightClickPanEnabled)
        try container.encode(dragToConnectEnabled, forKey: .dragToConnectEnabled)
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
