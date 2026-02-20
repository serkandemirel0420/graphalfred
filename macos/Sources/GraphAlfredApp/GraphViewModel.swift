import Foundation
import AppKit

@MainActor
final class GraphViewModel: ObservableObject {
    @Published var graph: GraphPayload = .empty
    @Published var selectedNote: Note?
    @Published var editingDraft: NoteDraft?
    @Published var activeDragNoteId: Int64?
    @Published var isolatedNoteId: Int64?
    @Published var isSearchVisible = false
    @Published var searchText = ""
    @Published var searchResults: [Note] = []
    @Published var highlightedNoteId: Int64?
    @Published var isBusy = false
    @Published var errorMessage: String?

    private let apiClient = APIClient()
    private let backendController = BackendController()

    func boot() async {
        isBusy = true
        defer { isBusy = false }

        do {
            try await backendController.ensureRunning(apiClient: apiClient)
            try await reloadGraph()
            if graph.notes.isEmpty {
                try await seedInitialData()
                try await reloadGraph()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reloadGraph() async throws {
        graph = try await apiClient.fetchGraph()
    }

    func createNote() {
        selectedNote = nil
        isolatedNoteId = nil
        editingDraft = NoteDraft(
            existingId: nil,
            title: "",
            subtitle: "",
            content: "",
            x: 0,
            y: 0,
            relatedIds: []
        )
    }

    func openViewer(for note: Note) {
        editingDraft = nil
        selectedNote = note
    }

    func openEditor(for note: Note) {
        selectedNote = nil
        editingDraft = NoteDraft(
            existingId: note.id,
            title: note.title,
            subtitle: note.subtitle,
            content: note.content,
            x: note.x,
            y: note.y,
            relatedIds: relatedIDs(for: note.id)
        )
    }

    func closeEditor() {
        editingDraft = nil
    }

    func closeViewer() {
        selectedNote = nil
    }

    func highlightNote(_ note: Note) {
        highlightedNoteId = note.id
        if editingDraft == nil {
            selectedNote = nil
        }
    }

    func setIsolatedNote(id: Int64?) {
        isolatedNoteId = id
        if let id {
            highlightedNoteId = id
        }
    }

    func setActiveDragNote(id: Int64?) {
        activeDragNoteId = id
    }

    var activeDragTitle: String? {
        guard let activeDragNoteId else { return nil }
        return graph.notes.first(where: { $0.id == activeDragNoteId })?.title
    }

    func saveEditor() async {
        guard let draft = editingDraft else { return }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            errorMessage = "Title cannot be empty."
            return
        }

        do {
            if let id = draft.existingId {
                _ = try await apiClient.updateNote(
                    id: id,
                    UpdateNoteRequest(
                        title: title,
                        subtitle: draft.subtitle,
                        content: draft.content,
                        x: draft.x,
                        y: draft.y,
                        relatedIds: Array(draft.relatedIds)
                    )
                )
                highlightedNoteId = id
            } else {
                let created = try await apiClient.createNote(
                    CreateNoteRequest(
                        title: title,
                        subtitle: draft.subtitle,
                        content: draft.content,
                        x: draft.x,
                        y: draft.y,
                        relatedIds: Array(draft.relatedIds)
                    )
                )
                highlightedNoteId = created.id
            }

            editingDraft = nil
            selectedNote = nil
            try await reloadGraph()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteNote(id: Int64) async {
        do {
            try await apiClient.deleteNote(id: id)
            selectedNote = nil
            editingDraft = nil
            try await reloadGraph()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func autoAlign() async {
        do {
            graph = try await apiClient.autoLayout()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func persistPosition(noteId: Int64, x: Double, y: Double) {
        guard let index = graph.notes.firstIndex(where: { $0.id == noteId }) else { return }
        graph.notes[index].x = x
        graph.notes[index].y = y

        Task {
            do {
                _ = try await apiClient.updatePosition(id: noteId, x: x, y: y)
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func connectNotes(sourceID: Int64, targetID: Int64) {
        let edge = normalizeEdge(sourceID, targetID)
        guard edge.0 != edge.1 else {
            return
        }

        let exists = graph.links.contains { link in
            link.sourceId == edge.0 && link.targetId == edge.1
        }
        if exists {
            return
        }

        graph.links.append(Link(sourceId: edge.0, targetId: edge.1))

        Task {
            do {
                try await apiClient.createLink(LinkRequest(sourceId: edge.0, targetId: edge.1))
            } catch {
                await MainActor.run {
                    self.graph.links.removeAll { $0.sourceId == edge.0 && $0.targetId == edge.1 }
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func showSearch() {
        searchText = ""
        searchResults = []
        isSearchVisible = true
    }

    func showSearchFromGlobalHotKey() {
        NSApp.activate(ignoringOtherApps: true)
        showSearch()
    }

    func hideSearch() {
        isSearchVisible = false
    }

    func searchIfNeeded() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            searchResults = []
            return
        }

        do {
            searchResults = try await apiClient.search(query: query)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func jumpToSearchResult(_ note: Note) {
        highlightedNoteId = note.id
        selectedNote = note
        isSearchVisible = false
    }

    func updateDraftRelation(noteID: Int64, enabled: Bool) {
        guard var draft = editingDraft else { return }
        if enabled {
            draft.relatedIds.insert(noteID)
        } else {
            draft.relatedIds.remove(noteID)
        }
        editingDraft = draft
    }

    private func relatedIDs(for noteID: Int64) -> Set<Int64> {
        let direct = graph.links.compactMap { link -> Int64? in
            if link.sourceId == noteID {
                return link.targetId
            }
            if link.targetId == noteID {
                return link.sourceId
            }
            return nil
        }
        return Set(direct)
    }

    private func normalizeEdge(_ sourceID: Int64, _ targetID: Int64) -> (Int64, Int64) {
        sourceID < targetID ? (sourceID, targetID) : (targetID, sourceID)
    }

    private func seedInitialData() async throws {
        let philosophy = try await apiClient.createNote(
            CreateNoteRequest(
                title: "Philosophy",
                subtitle: "Root idea",
                content: "Your core concept note.",
                x: 0,
                y: 0,
                relatedIds: nil
            )
        )

        let books = try await apiClient.createNote(
            CreateNoteRequest(
                title: "Books",
                subtitle: "References",
                content: "All supporting books and papers.",
                x: 180,
                y: 50,
                relatedIds: [philosophy.id]
            )
        )

        _ = try await apiClient.createNote(
            CreateNoteRequest(
                title: "Rene Descartes",
                subtitle: "Thinker",
                content: "Connected person note.",
                x: 70,
                y: 220,
                relatedIds: [philosophy.id, books.id]
            )
        )
    }
}
