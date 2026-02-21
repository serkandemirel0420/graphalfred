import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: GraphViewModel
    @State private var hotKeyManager = GlobalHotKeyManager()
    @State private var isEditorExpanded = false

    var body: some View {
        ZStack(alignment: .trailing) {
            LinearGradient(
                colors: [viewModel.settings.theme.palette.appBackgroundTop, viewModel.settings.theme.palette.appBackgroundBottom],
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
                    .keyboardShortcut(viewModel.settings.inAppSearchShortcut.keyEquivalent, modifiers: .command)
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
                    theme: viewModel.settings.theme,
                    allowsRightMousePan: viewModel.settings.rightClickPanEnabled,
                    allowsDragToConnect: viewModel.settings.dragToConnectEnabled,
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
                    onDeleteLink: { sourceID, targetID in
                        viewModel.deleteLink(sourceID: sourceID, targetID: targetID)
                    },
                    onQuickCreate: { title, x, y, connectTo in
                        viewModel.quickCreateNote(title: title, x: x, y: y, connectTo: connectTo)
                    },
                    onDragStateChange: { noteID in
                        viewModel.setActiveDragNote(id: noteID)
                    }
                )
            }
            .padding(24)
            .padding(.trailing, isInspectorVisible ? 500 : 0)
            .animation(.easeInOut(duration: 0.2), value: isInspectorVisible)

            if isInspectorVisible {
                inspectorPanel
                    .frame(width: 460)
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

            if isEditorExpanded {
                expandedEditorView
                    .zIndex(12)
                    .transition(.opacity)
            }
        }
        .task {
            restartGlobalHotKey()
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
        .onChange(of: viewModel.settings.globalSearchHotKey) { _ in
            restartGlobalHotKey()
        }
        .onChange(of: viewModel.editingDraft?.id) { next in
            if next == nil {
                isEditorExpanded = false
            }
        }
        .sheet(isPresented: settingsPresentedBinding) {
            SettingsPanel(
                settings: settingsBinding,
                onClose: {
                    viewModel.hideSettings()
                }
            )
        }
    }

    @ViewBuilder
    private var inspectorPanel: some View {
        if viewModel.editingDraft != nil {
            NoteEditorPanel(
                draft: draftBinding,
                allNotes: viewModel.graph.notes,
                isExpanded: false,
                onToggleExpand: {
                    isEditorExpanded = true
                },
                onToggleRelation: { noteID, enabled in
                    viewModel.updateDraftRelation(noteID: noteID, enabled: enabled)
                },
                onCancel: {
                    isEditorExpanded = false
                    viewModel.closeEditor()
                },
                onSave: {
                    Task { @MainActor in
                        await viewModel.saveEditor()
                        isEditorExpanded = false
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

    private var settingsPresentedBinding: Binding<Bool> {
        Binding {
            viewModel.isSettingsVisible
        } set: { isPresented in
            if isPresented {
                viewModel.showSettings()
            } else {
                viewModel.hideSettings()
            }
        }
    }

    private var settingsBinding: Binding<AppSettings> {
        Binding {
            viewModel.settings
        } set: { settings in
            viewModel.applySettings(settings)
        }
    }

    private func restartGlobalHotKey() {
        hotKeyManager.start(shortcut: viewModel.settings.globalSearchHotKey) {
            Task { @MainActor in
                viewModel.showSearchFromGlobalHotKey()
            }
        }
    }

    @ViewBuilder
    private var expandedEditorView: some View {
        if viewModel.editingDraft != nil {
            ZStack {
                Rectangle()
                    .fill(.black.opacity(0.62))
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [Color(red: 0.11, green: 0.11, blue: 0.13), Color(red: 0.05, green: 0.05, blue: 0.07)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(18)

                NoteEditorPanel(
                    draft: draftBinding,
                    allNotes: viewModel.graph.notes,
                    isExpanded: true,
                    onToggleExpand: {
                        isEditorExpanded = false
                    },
                    onToggleRelation: { noteID, enabled in
                        viewModel.updateDraftRelation(noteID: noteID, enabled: enabled)
                    },
                    onCancel: {
                        isEditorExpanded = false
                        viewModel.closeEditor()
                    },
                    onSave: {
                        Task { @MainActor in
                            await viewModel.saveEditor()
                            isEditorExpanded = false
                        }
                    }
                )
                .padding(34)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onExitCommand {
                isEditorExpanded = false
            }
        } else {
            Color.clear
                .onAppear {
                    isEditorExpanded = false
                }
        }
    }
}
