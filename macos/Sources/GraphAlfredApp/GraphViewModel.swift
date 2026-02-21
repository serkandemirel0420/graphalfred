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
    @Published var isSettingsVisible = false
    @Published var settings: AppSettings = AppSettingsStore.load()
    @Published private(set) var canUndo = false

    private let apiClient = APIClient()
    private let backendController = BackendController()
    private var undoStack: [UndoEntry] = []
    private var isApplyingUndo = false
    private let maxUndoDepth = 200

    private struct UndoEntry {
        let title: String
        let perform: @MainActor () async -> Void
    }

    func boot() async {
        isBusy = true
        defer { isBusy = false }
        clearUndoHistory()

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

    func quickCreateNote(title: String, x: Double, y: Double, connectTo: Int64?) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return
        }

        Task {
            do {
                let created = try await apiClient.createNote(
                    CreateNoteRequest(
                        title: trimmedTitle,
                        subtitle: nil,
                        content: nil,
                        x: x,
                        y: y,
                        relatedIds: connectTo.map { [$0] }
                    )
                )

                await MainActor.run {
                    self.highlightedNoteId = created.id
                    self.selectedNote = nil
                    self.editingDraft = nil
                    self.registerUndoAction(title: "Undo Quick Create Note") { [weak self] in
                        await self?.deleteNote(id: created.id, registerUndo: false)
                    }
                }

                try await reloadGraph()
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
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

    func showSettings() {
        isSettingsVisible = true
    }

    func hideSettings() {
        isSettingsVisible = false
    }

    func applySettings(_ settings: AppSettings) {
        self.settings = settings
        AppSettingsStore.save(settings)
    }

    func undoLastAction() {
        guard !isApplyingUndo else {
            return
        }
        guard let entry = undoStack.popLast() else {
            return
        }
        canUndo = !undoStack.isEmpty

        Task { @MainActor in
            isApplyingUndo = true
            await entry.perform()
            isApplyingUndo = false
        }
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
                let previousNote = graph.notes.first(where: { $0.id == id })
                let previousRelated = relatedIDs(for: id)

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

                if let previousNote {
                    registerUndoAction(title: "Undo Edit Note") { [weak self] in
                        await self?.restoreNote(previousNote, relatedIDs: previousRelated)
                    }
                }
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

                registerUndoAction(title: "Undo Create Note") { [weak self] in
                    await self?.deleteNote(id: created.id, registerUndo: false)
                }
            }

            editingDraft = nil
            selectedNote = nil
            try await reloadGraph()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteNote(id: Int64, registerUndo: Bool = true) async {
        let snapshot = graph.notes.first(where: { $0.id == id })
        let snapshotRelated = relatedIDs(for: id)

        do {
            try await apiClient.deleteNote(id: id)
            selectedNote = nil
            editingDraft = nil
            try await reloadGraph()

            if registerUndo, let snapshot {
                registerUndoAction(title: "Undo Delete Note") { [weak self] in
                    await self?.recreateDeletedNote(snapshot, relatedIDs: snapshotRelated)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func autoAlign() async {
        let previousPositions = Dictionary(uniqueKeysWithValues: graph.notes.map { ($0.id, (x: $0.x, y: $0.y)) })

        do {
            graph = try await apiClient.autoLayout()
            registerUndoAction(title: "Undo Auto Align") { [weak self] in
                await self?.restorePositions(previousPositions)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func persistPosition(noteId: Int64, x: Double, y: Double, registerUndo: Bool = true) {
        guard let index = graph.notes.firstIndex(where: { $0.id == noteId }) else { return }
        let previous = (x: graph.notes[index].x, y: graph.notes[index].y)
        if abs(previous.x - x) < 0.0001 && abs(previous.y - y) < 0.0001 {
            return
        }

        graph.notes[index].x = x
        graph.notes[index].y = y

        Task {
            do {
                _ = try await apiClient.updatePosition(id: noteId, x: x, y: y)
                await MainActor.run {
                    if registerUndo {
                        self.registerUndoAction(title: "Undo Move Node") { [weak self] in
                            self?.persistPosition(
                                noteId: noteId,
                                x: previous.x,
                                y: previous.y,
                                registerUndo: false
                            )
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    if let rollbackIndex = self.graph.notes.firstIndex(where: { $0.id == noteId }) {
                        self.graph.notes[rollbackIndex].x = previous.x
                        self.graph.notes[rollbackIndex].y = previous.y
                    }
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func connectNotes(sourceID: Int64, targetID: Int64, registerUndo: Bool = true) {
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
                await MainActor.run {
                    if registerUndo {
                        self.registerUndoAction(title: "Undo Connect Notes") { [weak self] in
                            self?.deleteLink(sourceID: edge.0, targetID: edge.1, registerUndo: false)
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.graph.links.removeAll { $0.sourceId == edge.0 && $0.targetId == edge.1 }
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func deleteLink(sourceID: Int64, targetID: Int64, registerUndo: Bool = true) {
        let edge = normalizeEdge(sourceID, targetID)
        let existing = graph.links.first { $0.sourceId == edge.0 && $0.targetId == edge.1 }
        guard existing != nil else {
            return
        }

        graph.links.removeAll { $0.sourceId == edge.0 && $0.targetId == edge.1 }

        Task {
            do {
                try await apiClient.deleteLink(LinkRequest(sourceId: edge.0, targetId: edge.1))
                await MainActor.run {
                    if registerUndo {
                        self.registerUndoAction(title: "Undo Delete Connection") { [weak self] in
                            self?.connectNotes(sourceID: edge.0, targetID: edge.1, registerUndo: false)
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.graph.links.append(Link(sourceId: edge.0, targetId: edge.1))
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

    private func registerUndoAction(title: String, _ perform: @escaping @MainActor () async -> Void) {
        guard !isApplyingUndo else {
            return
        }

        undoStack.append(UndoEntry(title: title, perform: perform))
        if undoStack.count > maxUndoDepth {
            undoStack.removeFirst(undoStack.count - maxUndoDepth)
        }
        canUndo = !undoStack.isEmpty
    }

    private func clearUndoHistory() {
        undoStack.removeAll()
        canUndo = false
    }

    private func restoreNote(_ note: Note, relatedIDs: Set<Int64>) async {
        do {
            _ = try await apiClient.updateNote(
                id: note.id,
                UpdateNoteRequest(
                    title: note.title,
                    subtitle: note.subtitle,
                    content: note.content,
                    x: note.x,
                    y: note.y,
                    relatedIds: Array(relatedIDs)
                )
            )
            highlightedNoteId = note.id
            try await reloadGraph()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func recreateDeletedNote(_ note: Note, relatedIDs: Set<Int64>) async {
        let existingIDs = Set(graph.notes.map(\.id))
        let validRelatedIDs = relatedIDs.filter { existingIDs.contains($0) }

        do {
            let recreated = try await apiClient.createNote(
                CreateNoteRequest(
                    title: note.title,
                    subtitle: note.subtitle,
                    content: note.content,
                    x: note.x,
                    y: note.y,
                    relatedIds: Array(validRelatedIDs)
                )
            )
            highlightedNoteId = recreated.id
            try await reloadGraph()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restorePositions(_ positions: [Int64: (x: Double, y: Double)]) async {
        for (noteID, position) in positions {
            if let index = graph.notes.firstIndex(where: { $0.id == noteID }) {
                graph.notes[index].x = position.x
                graph.notes[index].y = position.y
            }
        }

        do {
            for (noteID, position) in positions {
                _ = try await apiClient.updatePosition(id: noteID, x: position.x, y: position.y)
            }
            try await reloadGraph()
        } catch {
            errorMessage = error.localizedDescription
        }
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
