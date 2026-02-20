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
