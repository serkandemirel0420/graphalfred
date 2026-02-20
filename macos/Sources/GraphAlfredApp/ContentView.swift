import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: GraphViewModel
    @State private var hotKeyManager = GlobalHotKeyManager()

    var body: some View {
        ZStack(alignment: .trailing) {
            LinearGradient(
                colors: [Color(red: 0.13, green: 0.13, blue: 0.14), Color(red: 0.06, green: 0.06, blue: 0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Text("Graph")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)

                Text("Visualize relationships between your notes, discover hidden links, and edit content directly in a graph.")
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.78))
                    .frame(maxWidth: 940, alignment: .leading)

                HStack(spacing: 12) {
                    Button("New Note") {
                        viewModel.createNote()
                    }
                    .buttonStyle(GraphSecondaryButtonStyle())

                    Button("Auto Align") {
                        Task {
                            await viewModel.autoAlign()
                        }
                    }
                    .buttonStyle(GraphSecondaryButtonStyle())

                    Button("Search") {
                        viewModel.showSearch()
                    }
                    .keyboardShortcut("k", modifiers: .command)
                    .buttonStyle(GraphPrimaryButtonStyle())

                    Spacer()

                    if let draggingTitle = viewModel.activeDragTitle {
                        Text("Moving: \(draggingTitle)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.orange.opacity(0.95))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.30))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    if let isolatedNoteId = viewModel.isolatedNoteId,
                       let note = viewModel.graph.notes.first(where: { $0.id == isolatedNoteId }) {
                        Text("Focus: \(note.title)  •  Click background or Esc to show all")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.cyan.opacity(0.95))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.30))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    if viewModel.isBusy {
                        ProgressView()
                            .tint(.white)
                    }
                }

                GraphCanvasView(
                    notes: viewModel.graph.notes,
                    links: viewModel.graph.links,
                    highlightedNoteID: viewModel.highlightedNoteId,
                    activeDragNoteID: viewModel.activeDragNoteId,
                    isolatedNoteID: viewModel.isolatedNoteId,
                    onSelect: { note in
                        viewModel.highlightNote(note)
                    },
                    onDoubleSelect: { note in
                        viewModel.openEditor(for: note)
                    },
                    onIsolateNode: { noteID in
                        viewModel.setIsolatedNote(id: noteID)
                    },
                    onDragEnd: { noteID, x, y in
                        viewModel.persistPosition(noteId: noteID, x: x, y: y)
                    },
                    onConnect: { sourceID, targetID in
                        viewModel.connectNotes(sourceID: sourceID, targetID: targetID)
                    },
                    onDragStateChange: { noteID in
                        viewModel.setActiveDragNote(id: noteID)
                    }
                )
            }
            .padding(24)
            .padding(.trailing, isInspectorVisible ? 420 : 0)
            .animation(.easeInOut(duration: 0.2), value: isInspectorVisible)

            if isInspectorVisible {
                inspectorPanel
                    .frame(width: 390)
                    .padding(.vertical, 24)
                    .padding(.trailing, 20)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(2)
            }

            if viewModel.isSearchVisible {
                QuickSearchOverlay(
                    query: $viewModel.searchText,
                    results: viewModel.searchResults,
                    onClose: {
                        viewModel.hideSearch()
                    },
                    onPick: { note in
                        viewModel.jumpToSearchResult(note)
                    }
                )
                .transition(.opacity)
                .zIndex(4)
            }

            if let error = viewModel.errorMessage {
                VStack {
                    Spacer()
                    HStack {
                        Text(error)
                            .foregroundStyle(.white)
                        Button("Dismiss") {
                            viewModel.errorMessage = nil
                        }
                        .buttonStyle(GraphSecondaryButtonStyle())
                    }
                    .padding(12)
                    .background(Color.red.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.bottom, 14)
                }
            }
        }
        .task {
            hotKeyManager.start {
                Task { @MainActor in
                    viewModel.showSearchFromGlobalHotKey()
                }
            }
            await viewModel.boot()
        }
        .onDisappear {
            hotKeyManager.stop()
        }
        .onChange(of: viewModel.searchText) { _ in
            Task {
                await viewModel.searchIfNeeded()
            }
        }
    }

    @ViewBuilder
    private var inspectorPanel: some View {
        if viewModel.editingDraft != nil {
            NoteEditorPanel(
                draft: draftBinding,
                allNotes: viewModel.graph.notes,
                onToggleRelation: { noteID, enabled in
                    viewModel.updateDraftRelation(noteID: noteID, enabled: enabled)
                },
                onCancel: {
                    viewModel.closeEditor()
                },
                onSave: {
                    Task {
                        await viewModel.saveEditor()
                    }
                }
            )
        } else if let note = viewModel.selectedNote {
            NoteViewerPanel(
                note: note,
                onClose: {
                    viewModel.closeViewer()
                },
                onEdit: {
                    viewModel.openEditor(for: note)
                },
                onDelete: {
                    viewModel.closeViewer()
                    Task {
                        await viewModel.deleteNote(id: note.id)
                    }
                }
            )
        }
    }

    private var isInspectorVisible: Bool {
        viewModel.editingDraft != nil || viewModel.selectedNote != nil
    }

    private var draftBinding: Binding<NoteDraft> {
        Binding {
            viewModel.editingDraft ?? NoteDraft(
                existingId: nil,
                title: "",
                subtitle: "",
                content: "",
                x: 0,
                y: 0,
                relatedIds: []
            )
        } set: { draft in
            viewModel.editingDraft = draft
        }
    }
}
