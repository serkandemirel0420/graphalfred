import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: GraphViewModel
    @State private var hotKeyManager = GlobalHotKeyManager()
    @State private var isEditorExpanded = false
    @State private var canvasControlCommand: CanvasControlCommandToken?

    var body: some View {
        ZStack(alignment: .trailing) {
            LinearGradient(
                colors: [viewModel.settings.theme.palette.appBackgroundTop, viewModel.settings.theme.palette.appBackgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) {
                    // Primary action
                    Button {
                        viewModel.createNote()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                            Text("New Note")
                        }
                    }
                    .buttonStyle(GraphPrimaryButtonStyle())

                    toolbarDivider()

                    // Canvas tools
                    Button {
                        Task { await viewModel.autoAlign() }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(ToolbarIconButtonStyle())
                    .help("Auto Align")

                    Button {
                        canvasControlCommand = CanvasControlCommandToken(command: .zoomOut)
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .buttonStyle(ToolbarIconButtonStyle())
                    .help("Zoom Out")

                    Button {
                        canvasControlCommand = CanvasControlCommandToken(command: .zoomIn)
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .buttonStyle(ToolbarIconButtonStyle())
                    .help("Zoom In")

                    Button {
                        canvasControlCommand = CanvasControlCommandToken(command: .reset)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(ToolbarIconButtonStyle())
                    .help("Reset View")

                    toolbarDivider()

                    // Search
                    Button {
                        viewModel.showSearch()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Search")
                        }
                    }
                    .keyboardShortcut(viewModel.settings.inAppSearchShortcut.keyEquivalent, modifiers: .command)
                    .buttonStyle(GraphSecondaryButtonStyle())

                    Spacer()

                    // Status indicators
                    if let draggingTitle = viewModel.activeDragTitle {
                        Label(draggingTitle, systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.orange.opacity(0.9))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.orange.opacity(0.10))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.orange.opacity(0.22), lineWidth: 0.5))
                    }

                    if viewModel.isBusy {
                        ProgressView()
                            .tint(Color.black.opacity(0.45))
                            .scaleEffect(0.75)
                    }

                    // Settings
                    Button {
                        viewModel.showSettings()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(ToolbarIconButtonStyle())
                    .help("Settings")
                }

                GraphCanvasView(
                    notes: viewModel.graph.notes,
                    links: viewModel.graph.links,
                    highlightedNoteID: viewModel.highlightedNoteId,
                    activeDragNoteID: viewModel.activeDragNoteId,
                    isolatedNoteID: viewModel.isolatedNoteId,
                    focusCompanionNoteIDs: viewModel.focusCompanionIDs(for: viewModel.isolatedNoteId),
                    resolveFocusParentID: { nodeID in
                        viewModel.focusParentID(for: nodeID)
                    },
                    controlCommand: canvasControlCommand,
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
                    onDeleteNote: { noteID in
                        Task {
                            await viewModel.deleteNote(id: noteID)
                        }
                    },
                    onQuickCreate: { title, x, y, connectTo, focusParentID in
                        viewModel.quickCreateNote(title: title, x: x, y: y, connectTo: connectTo, focusParentID: focusParentID)
                    },
                    onDragStateChange: { noteID in
                        viewModel.setActiveDragNote(id: noteID)
                    },
                    onViewStateChange: { pan, zoom in
                        viewModel.saveCanvasViewState(panX: pan.width, panY: pan.height, zoom: zoom)
                    },
                    initialPanOffset: CGSize(
                        width: viewModel.settings.canvasPanX,
                        height: viewModel.settings.canvasPanY
                    ),
                    initialZoomScale: viewModel.settings.canvasZoom
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
                allNotes: viewModel.relationCandidates(for: viewModel.editingDraft),
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

    @ViewBuilder
    private func toolbarDivider() -> some View {
        Rectangle()
            .fill(Color.black.opacity(0.10))
            .frame(width: 1, height: 18)
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
                parentId: nil,
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
                    colors: [Color(red: 0.97, green: 0.97, blue: 0.98), Color(red: 0.93, green: 0.93, blue: 0.95)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(18)

                NoteEditorPanel(
                    draft: draftBinding,
                    allNotes: viewModel.relationCandidates(for: viewModel.editingDraft),
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
