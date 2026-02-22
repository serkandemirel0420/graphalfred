import AppKit
import SwiftUI

enum CanvasControlCommand: Equatable {
    case zoomOut
    case zoomIn
    case reset
}

struct CanvasControlCommandToken: Equatable {
    let id: UUID
    let command: CanvasControlCommand

    init(command: CanvasControlCommand) {
        self.id = UUID()
        self.command = command
    }
}

struct GraphCanvasView: View {
    let notes: [Note]
    let links: [Link]
    let highlightedNoteID: Int64?
    let activeDragNoteID: Int64?
    let isolatedNoteID: Int64?
    let focusCompanionNoteIDs: Set<Int64>
    let resolveFocusParentID: (Int64) -> Int64?
    let controlCommand: CanvasControlCommandToken?
    let theme: AppTheme
    let allowsDragToConnect: Bool
    let onSelect: (Note) -> Void
    let onDoubleSelect: (Note) -> Void
    let onIsolateNode: (Int64?) -> Void
    let onDragEnd: (Int64, Double, Double) -> Void
    let onConnect: (Int64, Int64) -> Void
    let onDeleteLink: (Int64, Int64) -> Void
    let onDeleteNote: (Int64) -> Void
    let onQuickCreate: (String, Double, Double, Int64?, Int64?) -> Void
    let onDragStateChange: (Int64?) -> Void
    let onViewStateChange: (String?, CGSize, CGFloat) -> Void
    /// Called when ESC is pressed. Return `true` to consume the event (editor was closed),
    /// `false` to let the canvas handle it normally.
    var onEscapeEditor: (() -> Bool)? = nil
    let initialPanOffset: CGSize
    let initialZoomScale: CGFloat
    let initialStageStates: [String: [Double]]
    let nodeStyle: NodeStyleConfig

    @State private var dragOrigins: [Int64: CGPoint] = [:]
    @State private var transientNodePositions: [Int64: CGPoint] = [:]
    @State private var activeNodeDragID: Int64?
    @State private var tapSequenceNoteID: Int64?
    @State private var tapCount = 0
    @State private var lastTapTime: Date = .distantPast
    @State private var pendingDoubleAction: DispatchWorkItem?
    @State private var pendingBackgroundAction: DispatchWorkItem?
    @State private var backgroundTapCount: Int = 0
    @State private var lastBackgroundTapTime: Date = .distantPast
    @State private var linkingSourceNoteID: Int64?
    @State private var contextualNoteID: Int64?
    @State private var elasticDragSourceNoteID: Int64?
    @State private var elasticDragTranslation: CGSize = .zero
    @State private var elasticDragTargetNoteID: Int64?
    @State private var selectedLink: (sourceID: Int64, targetID: Int64)?
    @State private var quickCreateDraft: QuickCreateDraft?

    @State private var zoomScale: CGFloat = 1.0
    @State private var zoomStart: CGFloat?
    @State private var panOffset: CGSize = .zero
    @State private var panStart: CGSize = .zero
    @State private var isSpacePressed = false
    @State private var isPanningCanvas = false
    @State private var isHoveringCanvas = false
    @State private var keyDownMonitor: Any?
    @State private var keyUpMonitor: Any?
    @State private var scrollMonitor: Any?
    @State private var rightMouseMonitor: Any?
    @State private var lastRightClickWindowPoint: CGPoint = .zero
    @State private var lastEscapePressTime: Date = .distantPast
    @State private var pendingEscapeParentID: Int64?
    @State private var focusReturnContextID: Int64?
    @State private var activeIsolatedNoteID: Int64?
    @State private var liveHighlightedNoteID: Int64?
    @State private var isHoveringBackground = false
    @State private var viewStateSaveTask: DispatchWorkItem?
    /// Key of the stage currently displayed ("root" = nil isolated note, or "\(noteID)").
    @State private var currentStageKey: String? = nil
    /// In-memory cache of saved pan/zoom per stage, seeded from initialStageStates on appear.
    @State private var stageCache: [String: (pan: CGSize, zoom: CGFloat)] = [:]

    private static let doubleTapThreshold: TimeInterval = 0.28
    private static let doubleEscapeThreshold: TimeInterval = 0.35
    private static let tapMovementThreshold: CGFloat = 6
    private static let backgroundTapThreshold: CGFloat = 6
    private static let dragStartThreshold: CGFloat = 3
    private static let minZoom: CGFloat = 0.45
    private static let maxZoom: CGFloat = 2.8

    var body: some View {
        GeometryReader { geometry in
            canvasLayer(in: geometry.size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(
                    colors: [theme.palette.canvasBackgroundTop, theme.palette.canvasBackgroundBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.black.opacity(0.07), lineWidth: 1)
            )
            .simultaneousGesture(canvasPanGesture)
            .simultaneousGesture(canvasMagnificationGesture)
            .onHover { isHoveringCanvas = $0 }
            .onAppear {
                panOffset = initialPanOffset
                panStart = initialPanOffset
                zoomScale = initialZoomScale
                activeIsolatedNoteID = isolatedNoteID
                liveHighlightedNoteID = highlightedNoteID
                currentStageKey = isolatedNoteID.map { "\($0)" }
                // Root state comes from initialPanOffset / initialZoomScale.
                stageCache["root"] = (pan: initialPanOffset, zoom: initialZoomScale)
                // Seed subdirectory stages from persisted stage states.
                for (key, vals) in initialStageStates where vals.count >= 3 {
                    stageCache[key] = (pan: CGSize(width: vals[0], height: vals[1]), zoom: CGFloat(vals[2]))
                }
                installEventMonitors()
            }
            .onChange(of: highlightedNoteID) { liveHighlightedNoteID = $0 }
            .onChange(of: isolatedNoteID) { next in
                // Restore the new stage's pan/zoom (saved by flushCurrentStageState at nav sites).
                let nextKey = next.map { "\($0)" }
                if let saved = stageCache[nextKey ?? "root"] {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.88)) {
                        panOffset = saved.pan
                        panStart = saved.pan
                        zoomScale = saved.zoom
                    }
                }
                // If no saved state: leave pan/zoom as-is (centerNode already set a good position
                // for forward-nav, or it's root with no prior pan for backward-nav).
                currentStageKey = nextKey

                activeIsolatedNoteID = next
                if next != nil {
                    if let next {
                        // Fallback to the focused node itself so double-Esc can always return to
                        // "node + direct connections" context even without an explicit parent map.
                        focusReturnContextID = contextualNoteID ?? resolveFocusParentID(next) ?? next
                    }
                    pendingEscapeParentID = nil
                    contextualNoteID = nil
                    selectedLink = nil
                    linkingSourceNoteID = nil
                    quickCreateDraft = nil
                }
            }
            .onChange(of: links) { _ in
                if let selectedLink {
                    let exists = links.contains { link in
                        normalizeEdge(link.sourceId, link.targetId) == (selectedLink.sourceID, selectedLink.targetID)
                    }
                    if !exists {
                        self.selectedLink = nil
                    }
                }
            }
            .onChange(of: controlCommand?.id) { _ in
                applyControlCommand(controlCommand?.command)
            }
            .onChange(of: panOffset) { _ in scheduleViewStateSave() }
            .onChange(of: zoomScale) { _ in scheduleViewStateSave() }
            .onDisappear {
                viewStateSaveTask?.cancel()
                viewStateSaveTask = nil
                onViewStateChange(currentStageKey, panOffset, zoomScale)
                pendingDoubleAction?.cancel()
                pendingBackgroundAction?.cancel()
                backgroundTapCount = 0
                onDragStateChange(nil)
                transientNodePositions.removeAll()
                selectedLink = nil
                contextualNoteID = nil
                linkingSourceNoteID = nil
                quickCreateDraft = nil
                focusReturnContextID = nil
                pendingEscapeParentID = nil
                activeIsolatedNoteID = nil
                elasticDragSourceNoteID = nil
                elasticDragTranslation = .zero
                elasticDragTargetNoteID = nil
                removeEventMonitors()
            }
        }
    }

    private var noteMap: [Int64: Note] {
        Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
    }

    private var contextualVisibleNoteIDs: Set<Int64> {
        guard let contextualNoteID else {
            return Set(notes.map(\.id))
        }

        var ids: Set<Int64> = [contextualNoteID]
        for link in links {
            if link.sourceId == contextualNoteID {
                ids.insert(link.targetId)
            } else if link.targetId == contextualNoteID {
                ids.insert(link.sourceId)
            }
        }
        return ids
    }

    private var visibleNotes: [Note] {
        if let isolatedNoteID, let isolated = noteMap[isolatedNoteID] {
            let companions = notes.filter { note in
                note.id != isolatedNoteID && focusCompanionNoteIDs.contains(note.id)
            }
            return [isolated] + companions
        }

        if contextualNoteID != nil {
            let visibleIDs = contextualVisibleNoteIDs
            return notes.filter { visibleIDs.contains($0.id) }
        }

        return notes.filter { $0.parentId == nil }
    }

    private var visibleLinks: [Link] {
        if isolatedNoteID != nil {
            return []
        }

        if let contextualNoteID {
            let visibleIDs = contextualVisibleNoteIDs
            return links.filter { link in
                (link.sourceId == contextualNoteID || link.targetId == contextualNoteID)
                    && visibleIDs.contains(link.sourceId)
                    && visibleIDs.contains(link.targetId)
            }
        }

        let rootIDs = Set(notes.filter { $0.parentId == nil }.map(\.id))
        return links.filter { rootIDs.contains($0.sourceId) && rootIDs.contains($0.targetId) }
    }

    @ViewBuilder
    private func canvasLayer(in size: CGSize) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .gesture(backgroundTapGesture(in: size))
                .contextMenu {
                    Button("New Note") {
                        let graphPos = approximateGraphPoint(from: lastRightClickWindowPoint, in: size)
                        quickCreateDraft = QuickCreateDraft(
                            title: "",
                            graphPoint: graphPos,
                            connectToID: nil,
                            focusParentID: isolatedNoteID ?? activeIsolatedNoteID
                        )
                    }
                }
                .onHover { hovering in
                    isHoveringBackground = hovering
                    if hovering {
                        NSCursor.openHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .onChange(of: isPanningCanvas) { panning in
                    guard isHoveringBackground else { return }
                    if panning {
                        NSCursor.pop()
                        NSCursor.closedHand.push()
                    } else {
                        NSCursor.pop()
                        NSCursor.openHand.push()
                    }
                }

            Canvas { context, _ in
                for link in visibleLinks {
                    guard let source = noteMap[link.sourceId], let target = noteMap[link.targetId] else {
                        continue
                    }

                    let edge = normalizeEdge(link.sourceId, link.targetId)
                    let isSelected = selectedLink?.sourceID == edge.0 && selectedLink?.targetID == edge.1
                    let from = point(for: source, in: size)
                    let to = point(for: target, in: size)

                    var path = Path()
                    path.move(to: from)
                    path.addLine(to: to)

                    if isSelected {
                        context.stroke(
                            path,
                            with: .color(Color.black.opacity(0.12)),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        context.stroke(
                            path,
                            with: .color(Color(white: 0.18)),
                            style: StrokeStyle(lineWidth: 2.0, lineCap: .round)
                        )
                    } else {
                        context.stroke(
                            path,
                            with: .color(Color.black.opacity(0.14)),
                            style: StrokeStyle(lineWidth: 1.0, lineCap: .round)
                        )
                    }
                }

                // Elastic drag-to-connect preview
                if let sourceID = elasticDragSourceNoteID,
                   let sourceNote = noteMap[sourceID] {
                    let from = point(for: sourceNote, in: size)
                    let dx = elasticDragTranslation.width
                    let dy = elasticDragTranslation.height
                    let to = CGPoint(x: from.x + dx, y: from.y + dy)
                    let dist = max(1, hypot(dx, dy))
                    let c1 = CGPoint(x: from.x, y: from.y + min(dist * 0.55, 90))
                    let c2 = CGPoint(x: to.x, y: to.y - min(dist * 0.25, 45))

                    var elasticPath = Path()
                    elasticPath.move(to: from)
                    elasticPath.addCurve(to: to, control1: c1, control2: c2)
                    context.stroke(
                        elasticPath,
                        with: .color(Color(white: 0.20).opacity(0.75)),
                        style: StrokeStyle(lineWidth: 2.0, lineCap: .round, dash: [6, 4])
                    )
                    let dotRect = CGRect(x: to.x - 4.5, y: to.y - 4.5, width: 9, height: 9)
                    context.fill(
                        Path(ellipseIn: dotRect),
                        with: .color(Color(white: 0.15).opacity(0.85))
                    )
                }
            }
            .allowsHitTesting(false)

            if isolatedNoteID == nil {
                ForEach(visibleLinks) { link in
                    if let source = noteMap[link.sourceId], let target = noteMap[link.targetId] {
                        let fromPoint = point(for: source, in: size)
                        let toPoint = point(for: target, in: size)
                        let edge = normalizeEdge(link.sourceId, link.targetId)
                        let hitShape = EdgeHitArea(start: fromPoint, end: toPoint, thickness: 16)

                        hitShape
                            .fill(Color.clear)
                            .contentShape(hitShape)
                            .onTapGesture {
                                selectedLink = (sourceID: edge.0, targetID: edge.1)
                                linkingSourceNoteID = nil
                            }
                    }
                }
            }

            ForEach(visibleNotes) { note in
                let isDragging = activeNodeDragID == note.id || activeDragNoteID == note.id
                let isHighlighted = highlightedNoteID == note.id
                let isElasticTarget = elasticDragTargetNoteID == note.id && elasticDragSourceNoteID != note.id
                let showsConnectHandle = isHighlighted

                ZStack(alignment: .bottom) {
                    NodeBubbleView(
                        note: note,
                        isHighlighted: isHighlighted || isElasticTarget,
                        isBeingDragged: isDragging,
                        style: nodeStyle
                    )
                    .gesture(interactionGesture(for: note.id))
                    .onHover { hovering in
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .contextMenu {
                        Button("Edit") {
                            onDoubleSelect(note)
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            if activeIsolatedNoteID == note.id || isolatedNoteID == note.id {
                                flushCurrentStageState()
                                activeIsolatedNoteID = nil
                                contextualNoteID = nil
                                pendingEscapeParentID = nil
                                focusReturnContextID = nil
                                onIsolateNode(nil)
                            }
                            linkingSourceNoteID = nil
                            quickCreateDraft = nil
                            onDeleteNote(note.id)
                        }
                    }

                    if showsConnectHandle {
                        dragConnectHandle(for: note.id, in: size)
                            .offset(y: 14)
                    }
                }
                .fixedSize()
                .offset(x: nodeOffsetX(for: note), y: nodeOffsetY(for: note))
                .zIndex(isDragging ? 4 : (isHighlighted ? 2 : (isElasticTarget ? 3 : 1)))
            }

            if selectedLink != nil, isolatedNoteID == nil {
                HStack(spacing: 6) {
                    Image(systemName: "link.badge.minus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(red: 0.82, green: 0.18, blue: 0.15))
                    Text("Connection selected")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(white: 0.12))
                    Text("· Delete to remove")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(Color(white: 0.48))
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.92))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.black.opacity(0.08), lineWidth: 0.5))
                .shadow(color: Color.black.opacity(0.10), radius: 10, y: 3)
                .position(x: size.width / 2, y: 26)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            if let contextualNoteID, isolatedNoteID == nil, let note = noteMap[contextualNoteID] {
                HStack(spacing: 6) {
                    Image(systemName: "scope")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(white: 0.30))
                    Text(note.title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(white: 0.12))
                    Text("· direct connections")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(Color(white: 0.48))
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.92))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.black.opacity(0.08), lineWidth: 0.5))
                .shadow(color: Color.black.opacity(0.10), radius: 10, y: 3)
                .position(x: size.width / 2, y: 26)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            if let elasticSourceID = elasticDragSourceNoteID,
               let source = noteMap[elasticSourceID] {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(white: 0.30))
                    Text("Connecting from")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(Color(white: 0.48))
                    Text(source.title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(white: 0.12))
                    if let targetID = elasticDragTargetNoteID, let target = noteMap[targetID] {
                        Text("→")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(Color(white: 0.48))
                        Text(target.title)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(red: 0.20, green: 0.50, blue: 0.90))
                    } else {
                        Text("· drop on a node")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(Color(white: 0.48))
                    }
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.92))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.black.opacity(0.08), lineWidth: 0.5))
                .shadow(color: Color.black.opacity(0.10), radius: 10, y: 3)
                .position(x: size.width / 2, y: 26)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            if let currentIsolated = activeIsolatedNoteID ?? isolatedNoteID {
                CanvasBreadcrumbBar(
                    crumbs: buildBreadcrumbs(for: currentIsolated),
                    onNavigate: { targetID in
                        pendingBackgroundAction?.cancel()
                        pendingBackgroundAction = nil
                        backgroundTapCount = 0
                        contextualNoteID = nil
                        quickCreateDraft = nil
                        pendingEscapeParentID = nil
                        focusReturnContextID = nil
                        activeIsolatedNoteID = targetID
                        flushCurrentStageState()
                        onIsolateNode(targetID)
                    }
                )
                .position(x: size.width / 2, y: 26)
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }

            if let quickCreateDraft {
                QuickCreateNodeBubble(
                    title: Binding(
                        get: { quickCreateDraft.title },
                        set: { nextTitle in
                            self.quickCreateDraft?.title = nextTitle
                        }
                    ),
                    style: nodeStyle,
                    onCancel: {
                        self.quickCreateDraft = nil
                    },
                    onCreate: commitQuickCreate
                )
                .fixedSize()
                .position(screenPoint(for: quickCreateDraft.graphPoint, in: size))
                .zIndex(6)
            }
        }
    }

    private var canvasPanGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard isSpacePressed else { return }
                guard activeNodeDragID == nil else { return }
                if !isPanningCanvas {
                    isPanningCanvas = true
                }
                panOffset = CGSize(
                    width: panStart.width + value.translation.width,
                    height: panStart.height + value.translation.height
                )
            }
            .onEnded { _ in
                guard isSpacePressed || isPanningCanvas else { return }
                panStart = panOffset
                isPanningCanvas = false
            }
    }

    private var canvasMagnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if zoomStart == nil {
                    zoomStart = zoomScale
                }

                let base = zoomStart ?? zoomScale
                zoomScale = clampedScale(base * value)
            }
            .onEnded { _ in
                zoomStart = nil
            }
    }

    private func backgroundTapGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !isSpacePressed else { return }
                let distance = hypot(value.translation.width, value.translation.height)
                guard distance > Self.backgroundTapThreshold else { return }
                if !isPanningCanvas {
                    isPanningCanvas = true
                }
                panOffset = CGSize(
                    width: panStart.width + value.translation.width,
                    height: panStart.height + value.translation.height
                )
            }
            .onEnded { value in
                if isPanningCanvas {
                    panStart = panOffset
                    isPanningCanvas = false
                    return
                }
                let distance = hypot(
                    value.location.x - value.startLocation.x,
                    value.location.y - value.startLocation.y
                )
                guard distance <= Self.backgroundTapThreshold else { return }
                handleBackgroundTap(at: value.location, in: size)
            }
    }

    private func handleBackgroundTap(at location: CGPoint, in size: CGSize) {
        pendingDoubleAction?.cancel()
        pendingDoubleAction = nil
        tapSequenceNoteID = nil
        tapCount = 0

        // Immediate dismissals — no double-tap detection needed for these.
        if selectedLink != nil {
            selectedLink = nil
            pendingBackgroundAction?.cancel()
            pendingBackgroundAction = nil
            backgroundTapCount = 0
            return
        }

        if linkingSourceNoteID != nil {
            linkingSourceNoteID = nil
            pendingBackgroundAction?.cancel()
            pendingBackgroundAction = nil
            backgroundTapCount = 0
            return
        }

        if let quickCreateDraft {
            let bubblePoint = screenPoint(for: quickCreateDraft.graphPoint, in: size)
            let distanceToBubble = hypot(location.x - bubblePoint.x, location.y - bubblePoint.y)
            if distanceToBubble > 120 {
                self.quickCreateDraft = nil
                pendingBackgroundAction?.cancel()
                pendingBackgroundAction = nil
                backgroundTapCount = 0
            }
            return
        }

        // Double-tap detection: single → create node, double → navigate backwards.
        let now = Date()
        let isDoubleTap = backgroundTapCount >= 1
            && now.timeIntervalSince(lastBackgroundTapTime) <= Self.doubleTapThreshold

        lastBackgroundTapTime = now

        if isDoubleTap {
            backgroundTapCount = 0
            pendingBackgroundAction?.cancel()
            pendingBackgroundAction = nil
            // Navigate backwards — same semantics as pressing ESC.
            if let currentIsolated = activeIsolatedNoteID {
                flushCurrentStageState()
                activeIsolatedNoteID = nil
                focusReturnContextID = nil
                pendingEscapeParentID = nil
                contextualNoteID = nil
                quickCreateDraft = nil
                if let parentID = resolveFocusParentID(currentIsolated) {
                    activeIsolatedNoteID = parentID
                    onIsolateNode(parentID)
                } else {
                    onIsolateNode(nil)
                }
            } else if contextualNoteID != nil {
                contextualNoteID = nil
                pendingEscapeParentID = nil
                focusReturnContextID = nil
            }
        } else {
            // Single tap — schedule node creation after double-tap window expires.
            backgroundTapCount = 1
            pendingBackgroundAction?.cancel()
            let graphPos = graphPoint(from: location, in: size)
            let focusParent = isolatedNoteID ?? activeIsolatedNoteID
            let action = DispatchWorkItem {
                pendingBackgroundAction = nil
                backgroundTapCount = 0
                quickCreateDraft = QuickCreateDraft(
                    title: "",
                    graphPoint: graphPos,
                    connectToID: nil,
                    focusParentID: focusParent
                )
            }
            pendingBackgroundAction = action
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.doubleTapThreshold, execute: action)
        }
    }

    private func point(for note: Note, in size: CGSize) -> CGPoint {
        let current = currentGraphPoint(for: note)
        return CGPoint(
            x: size.width / 2.0 + panOffset.width + (current.x * zoomScale),
            y: size.height / 2.0 + panOffset.height + (current.y * zoomScale)
        )
    }

    private func screenPoint(for graphPoint: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: size.width / 2.0 + panOffset.width + (graphPoint.x * zoomScale),
            y: size.height / 2.0 + panOffset.height + (graphPoint.y * zoomScale)
        )
    }

    private func graphPoint(from screenPoint: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: (screenPoint.x - size.width / 2.0 - panOffset.width) / zoomScale,
            y: (screenPoint.y - size.height / 2.0 - panOffset.height) / zoomScale
        )
    }

    private func nodeOffsetX(for note: Note) -> CGFloat {
        let current = currentGraphPoint(for: note)
        return panOffset.width + (current.x * zoomScale)
    }

    private func nodeOffsetY(for note: Note) -> CGFloat {
        let current = currentGraphPoint(for: note)
        return panOffset.height + (current.y * zoomScale)
    }

    private func currentGraphPoint(for note: Note) -> CGPoint {
        transientNodePositions[note.id] ?? CGPoint(x: note.x, y: note.y)
    }

    private func interactionGesture(for noteID: Int64) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if isSpacePressed {
                    return
                }

                let distance = hypot(value.translation.width, value.translation.height)
                if distance < Self.dragStartThreshold {
                    return
                }

                if highlightedNoteID != noteID, let note = noteMap[noteID] {
                    onSelect(note)
                }
                linkingSourceNoteID = nil
                selectedLink = nil
                quickCreateDraft = nil

                let base = dragOrigin(for: noteID)
                let nextX = base.x + value.translation.width / zoomScale
                let nextY = base.y + value.translation.height / zoomScale
                transientNodePositions[noteID] = CGPoint(x: nextX, y: nextY)

                if activeNodeDragID != noteID {
                    activeNodeDragID = noteID
                    onDragStateChange(noteID)
                }
            }
            .onEnded { value in
                if isSpacePressed {
                    return
                }

                let base = dragOrigin(for: noteID)
                let nextX = base.x + value.translation.width / zoomScale
                let nextY = base.y + value.translation.height / zoomScale
                let distance = hypot(value.translation.width, value.translation.height)
                let finalPoint = transientNodePositions[noteID] ?? CGPoint(x: nextX, y: nextY)
                transientNodePositions.removeValue(forKey: noteID)

                dragOrigins.removeValue(forKey: noteID)

                if activeNodeDragID == noteID {
                    activeNodeDragID = nil
                    onDragStateChange(nil)
                }

                if distance <= Self.tapMovementThreshold {
                    handleTap(noteID: noteID)
                    return
                }

                // A committed drag should reset multi-click state to avoid accidental double/triple actions.
                tapSequenceNoteID = nil
                tapCount = 0
                pendingDoubleAction?.cancel()
                pendingDoubleAction = nil

                if allowsDragToConnect, let targetID = nearestNodeID(from: noteID, to: finalPoint) {
                    onConnect(noteID, targetID)
                }

                onDragEnd(noteID, finalPoint.x, finalPoint.y)
            }
    }

    private func dragOrigin(for noteID: Int64) -> CGPoint {
        if let cached = dragOrigins[noteID] {
            return cached
        }

        if let transient = transientNodePositions[noteID] {
            dragOrigins[noteID] = transient
            return transient
        }

        let point = CGPoint(
            x: noteMap[noteID]?.x ?? 0,
            y: noteMap[noteID]?.y ?? 0
        )
        dragOrigins[noteID] = point
        return point
    }

    private func nearestNodeID(from sourceID: Int64, to point: CGPoint) -> Int64? {
        let maxDistance = max(42.0, 86.0 / zoomScale)
        var bestMatch: (id: Int64, distance: CGFloat)?

        for note in visibleNotes where note.id != sourceID {
            let other = currentGraphPoint(for: note)
            let distance = hypot(other.x - point.x, other.y - point.y)
            if distance > maxDistance {
                continue
            }

            if bestMatch == nil || distance < bestMatch!.distance {
                bestMatch = (note.id, distance)
            }
        }

        return bestMatch?.id
    }

    private func handleTap(noteID: Int64) {
        guard let note = noteMap[noteID] else { return }
        selectedLink = nil
        quickCreateDraft = nil

        if let sourceID = linkingSourceNoteID {
            if sourceID != noteID {
                onConnect(sourceID, noteID)
            }
            linkingSourceNoteID = nil
            tapSequenceNoteID = nil
            tapCount = 0
            pendingDoubleAction?.cancel()
            pendingDoubleAction = nil
            onSelect(note)
            return
        }

        let now = Date()

        let continuesSequence = tapSequenceNoteID == noteID
            && now.timeIntervalSince(lastTapTime) <= Self.doubleTapThreshold

        if !continuesSequence {
            pendingDoubleAction?.cancel()
            pendingDoubleAction = nil
            tapSequenceNoteID = noteID
            tapCount = 1
            lastTapTime = now
            if contextualNoteID != nil {
                contextualNoteID = noteID
            }
            onSelect(note)
            return
        }

        tapCount += 1
        lastTapTime = now

        if tapCount >= 2 {
            // Double (or more) click — navigate forward into this node.
            pendingDoubleAction?.cancel()
            pendingDoubleAction = nil
            tapCount = 0
            tapSequenceNoteID = nil
            selectedLink = nil
            activeIsolatedNoteID = note.id
            focusReturnContextID = contextualNoteID ?? resolveFocusParentID(note.id) ?? note.id
            onSelect(note)
            // Save current stage BEFORE centerNode modifies panOffset.
            flushCurrentStageState()
            // Only center on the node for a first visit; returning visits restore saved pan.
            if stageCache["\(note.id)"] == nil {
                centerNode(note)
            }
            onIsolateNode(note.id)
            return
        }
    }

    private func scheduleViewStateSave() {
        viewStateSaveTask?.cancel()
        let pan = panOffset
        let zoom = zoomScale
        let key = currentStageKey
        let task = DispatchWorkItem {
            onViewStateChange(key, pan, zoom)
        }
        viewStateSaveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: task)
    }

    /// Snapshot the current stage's pan/zoom into the in-memory cache and persist to disk
    /// immediately. Must be called BEFORE any state change that modifies panOffset/zoomScale
    /// (e.g. centerNode) or triggers a stage transition (onIsolateNode).
    private func flushCurrentStageState() {
        viewStateSaveTask?.cancel()
        viewStateSaveTask = nil
        let key = currentStageKey ?? "root"
        stageCache[key] = (pan: panOffset, zoom: zoomScale)
        onViewStateChange(currentStageKey, panOffset, zoomScale)
    }

    private func clampedScale(_ proposed: CGFloat) -> CGFloat {
        min(Self.maxZoom, max(Self.minZoom, proposed))
    }

    private func applyControlCommand(_ command: CanvasControlCommand?) {
        guard let command else {
            return
        }

        switch command {
        case .zoomOut:
            zoomScale = clampedScale(zoomScale / 1.15)
        case .zoomIn:
            zoomScale = clampedScale(zoomScale * 1.15)
        case .reset:
            resetViewTransform()
        }
    }

    private func resetViewTransform() {
        zoomScale = 1
        zoomStart = nil
        panOffset = .zero
        panStart = .zero
    }

    private func centerNode(_ note: Note) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
            let centered = CGSize(
                width: -(note.x * zoomScale),
                height: -(note.y * zoomScale)
            )
            panOffset = centered
            panStart = centered
        }
    }

    private func dragConnectHandle(for noteID: Int64, in size: CGSize) -> some View {
        Circle()
            .fill(elasticDragSourceNoteID == noteID ? Color(red: 0.20, green: 0.50, blue: 0.90) : Color(white: 0.18))
            .overlay(
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            )
            .frame(width: 20, height: 20)
            .shadow(color: Color.black.opacity(0.18), radius: 4, y: 2)
            .scaleEffect(elasticDragSourceNoteID == noteID ? 1.15 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: elasticDragSourceNoteID == noteID)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        let dist = hypot(value.translation.width, value.translation.height)
                        guard dist > 4 else { return }
                        if elasticDragSourceNoteID != noteID {
                            elasticDragSourceNoteID = noteID
                            linkingSourceNoteID = nil
                            selectedLink = nil
                            quickCreateDraft = nil
                        }
                        elasticDragTranslation = value.translation
                        if let sourceNote = noteMap[noteID] {
                            let from = point(for: sourceNote, in: size)
                            let to = CGPoint(x: from.x + value.translation.width,
                                            y: from.y + value.translation.height)
                            let graphEnd = graphPoint(from: to, in: size)
                            elasticDragTargetNoteID = nearestNodeID(from: noteID, to: graphEnd)
                        }
                    }
                    .onEnded { _ in
                        if let targetID = elasticDragTargetNoteID {
                            onConnect(noteID, targetID)
                        }
                        elasticDragSourceNoteID = nil
                        elasticDragTranslation = .zero
                        elasticDragTargetNoteID = nil
                    }
            )
            .help("Drag to connect to another node")
    }

    private func commitQuickCreate() {
        guard let quickCreateDraft else {
            return
        }

        let title = quickCreateDraft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            return
        }

        let focusParentID = quickCreateDraft.focusParentID ?? isolatedNoteID ?? activeIsolatedNoteID

        onQuickCreate(
            title,
            quickCreateDraft.graphPoint.x,
            quickCreateDraft.graphPoint.y,
            quickCreateDraft.connectToID,
            focusParentID
        )

        // Stay in focus mode after quick-create so repeated clicks keep creating nodes there.
        if let focusParentID {
            activeIsolatedNoteID = focusParentID
            focusReturnContextID = focusParentID
            flushCurrentStageState()
            onIsolateNode(focusParentID)
        }
        self.quickCreateDraft = nil
    }

    private func installEventMonitors() {
        if keyDownMonitor == nil {
            keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 49 {
                    if shouldCaptureSpaceKey(event) {
                        isSpacePressed = true
                        return nil
                    }
                    return event
                }
                if isDeleteKey(event) {
                    guard !isTextInputFocused() else {
                        return event
                    }

                    if let selectedLink {
                        onDeleteLink(selectedLink.sourceID, selectedLink.targetID)
                        self.selectedLink = nil
                        return nil
                    }

                    let targetNoteID = liveHighlightedNoteID ?? tapSequenceNoteID
                    guard let targetNoteID else {
                        return event
                    }

                    if activeIsolatedNoteID == targetNoteID || isolatedNoteID == targetNoteID {
                        flushCurrentStageState()
                        activeIsolatedNoteID = nil
                        contextualNoteID = nil
                        pendingEscapeParentID = nil
                        focusReturnContextID = nil
                        onIsolateNode(nil)
                    } else if contextualNoteID == targetNoteID {
                        contextualNoteID = nil
                    }

                    linkingSourceNoteID = nil
                    quickCreateDraft = nil
                    onDeleteNote(targetNoteID)
                    return nil
                }
                if event.keyCode == 53 {
                    // Editor takes priority: if an editor is open, close it and consume the event.
                    if let onEscapeEditor, onEscapeEditor() {
                        return nil
                    }

                    let shouldHandleEscape =
                        quickCreateDraft != nil
                        || activeIsolatedNoteID != nil
                        || contextualNoteID != nil
                        || isHoveringCanvas

                    guard shouldHandleEscape else {
                        return event
                    }

                    guard !isTextInputFocused() else {
                        return event
                    }

                    if quickCreateDraft != nil {
                        quickCreateDraft = nil
                        return nil
                    }

                    if let isolatedNoteID = activeIsolatedNoteID {
                        flushCurrentStageState()
                        activeIsolatedNoteID = nil
                        focusReturnContextID = nil
                        pendingEscapeParentID = nil
                        contextualNoteID = nil
                        quickCreateDraft = nil

                        if let parentID = resolveFocusParentID(isolatedNoteID) {
                            // Navigate up to parent's focus mode (hierarchical layers).
                            activeIsolatedNoteID = parentID
                            onIsolateNode(parentID)
                        } else {
                            // Already at root level — exit to root canvas.
                            onIsolateNode(nil)
                        }
                        return nil
                    }

                    if contextualNoteID != nil {
                        contextualNoteID = nil
                        pendingEscapeParentID = nil
                        focusReturnContextID = nil
                        return nil
                    }

                    pendingEscapeParentID = nil
                    focusReturnContextID = nil
                    return nil
                }
                return event
            }
        }

        if keyUpMonitor == nil {
            keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { event in
                if event.keyCode == 49 {
                    let didCaptureSpace = isSpacePressed
                    isSpacePressed = false
                    isPanningCanvas = false
                    if didCaptureSpace {
                        return nil
                    }
                }
                return event
            }
        }

        if scrollMonitor == nil {
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                guard isHoveringCanvas else {
                    return event
                }

                guard !isTextInputFocused() else {
                    return event
                }

                let intensity = event.hasPreciseScrollingDeltas ? 0.0045 : 0.03
                let zoomFactor = exp(event.scrollingDeltaY * intensity)
                zoomScale = clampedScale(zoomScale * zoomFactor)

                return nil
            }
        }

        if rightMouseMonitor == nil {
            // Capture the right-click position so context menus can create nodes near the cursor.
            rightMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { event in
                guard isHoveringCanvas else { return event }
                lastRightClickWindowPoint = event.locationInWindow
                return event  // pass through so SwiftUI context menus can fire
            }
        }
    }

    private func removeEventMonitors() {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
            self.keyDownMonitor = nil
        }

        if let keyUpMonitor {
            NSEvent.removeMonitor(keyUpMonitor)
            self.keyUpMonitor = nil
        }

        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }

        if let rightMouseMonitor {
            NSEvent.removeMonitor(rightMouseMonitor)
            self.rightMouseMonitor = nil
        }

        isSpacePressed = false
        isPanningCanvas = false
    }

    private func shouldCaptureSpaceKey(_ event: NSEvent) -> Bool {
        guard isHoveringCanvas else {
            return false
        }
        guard !isTextInputFocused() else {
            return false
        }

        let blockedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .function]
        return event.modifierFlags.intersection(blockedModifiers).isEmpty
    }

    private func isTextInputFocused() -> Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else {
            return false
        }
        return responder is NSTextView
    }

    private func isDeleteKey(_ event: NSEvent) -> Bool {
        event.keyCode == 51 || event.keyCode == 117
    }

    /// Converts a right-click window position (AppKit bottom-left origin) to a graph coordinate.
    /// Uses an approximate canvas offset since we don't have the exact canvas frame.
    private func approximateGraphPoint(from windowPoint: CGPoint, in size: CGSize) -> CGPoint {
        let contentHeight = NSApp.keyWindow?.contentView?.frame.height ?? size.height
        // Flip AppKit Y to SwiftUI Y, then subtract approximate toolbar height (24 padding + ~38 toolbar + 14 gap)
        let canvasX = windowPoint.x - 24
        let canvasY = (contentHeight - windowPoint.y) - 76
        return graphPoint(from: CGPoint(x: canvasX, y: canvasY), in: size)
    }

    private func normalizeEdge(_ a: Int64, _ b: Int64) -> (Int64, Int64) {
        a < b ? (a, b) : (b, a)
    }

    /// Builds the ancestry chain from the root ancestor down to `noteID`.
    private func buildBreadcrumbs(for noteID: Int64) -> [Note] {
        guard let note = noteMap[noteID] else { return [] }
        var path: [Note] = [note]
        var current = note
        while let parentID = current.parentId, let parent = noteMap[parentID] {
            path.insert(parent, at: 0)
            current = parent
        }
        return path
    }
}

// MARK: – Breadcrumb bar

private struct CanvasBreadcrumbBar: View {
    /// Ordered from oldest ancestor to current node.
    let crumbs: [Note]
    /// Called with nil to navigate to root, or a note ID to focus that level.
    let onNavigate: (Int64?) -> Void

    var body: some View {
        HStack(spacing: 5) {
            // Home / root button
            Button { onNavigate(nil) } label: {
                Image(systemName: "house.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(crumbs.isEmpty ? Color(white: 0.12) : Color(white: 0.45))
            }
            .buttonStyle(.plain)
            .help("Go to root")

            ForEach(Array(crumbs.enumerated()), id: \.element.id) { idx, crumb in
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color(white: 0.55))

                let isLast = idx == crumbs.count - 1

                if isLast {
                    Text(crumb.title)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(white: 0.10))
                        .lineLimit(1)
                        .fixedSize()
                } else {
                    Button {
                        onNavigate(crumb.id)
                    } label: {
                        Text(crumb.title)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(white: 0.38))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .buttonStyle(.plain)
                    .help("Go to \(crumb.title)")
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.black.opacity(0.08), lineWidth: 0.5))
        .shadow(color: Color.black.opacity(0.10), radius: 10, y: 3)
    }
}

// MARK: – Edge hit area

private struct EdgeHitArea: Shape {
    let start: CGPoint
    let end: CGPoint
    let thickness: CGFloat

    func path(in _: CGRect) -> Path {
        var base = Path()
        base.move(to: start)
        base.addLine(to: end)
        return base.strokedPath(
            .init(
                lineWidth: thickness,
                lineCap: .round,
                lineJoin: .round
            )
        )
    }
}

private struct QuickCreateDraft {
    var title: String
    var graphPoint: CGPoint
    var connectToID: Int64?
    var focusParentID: Int64?
}

private struct QuickCreateNodeBubble: View {
    @Binding var title: String
    let style: NodeStyleConfig
    let onCancel: () -> Void
    let onCreate: () -> Void

    @FocusState private var isFocused: Bool
    private var hasValidTitle: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            TextField(
                "",
                text: $title,
                prompt: Text("New note…")
                    .foregroundColor(Color(white: 0.62))
            )
            .textFieldStyle(.plain)
            .font(.system(size: style.titleFontSize, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(white: 0.10))
            .frame(minWidth: 150, maxWidth: 260)
            .focused($isFocused)
            .onSubmit {
                if hasValidTitle {
                    onCreate()
                }
            }

            if hasValidTitle {
                Image(systemName: "return")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(white: 0.30))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        }
        .padding(.horizontal, style.paddingH)
        .padding(.vertical, style.paddingV)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                .stroke(Color.black.opacity(0.14), lineWidth: 1.5)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 10, y: 4)
        .onExitCommand {
            onCancel()
        }
        .onAppear {
            DispatchQueue.main.async {
                isFocused = true
            }
        }
    }
}

private struct NodeBubbleView: View {
    let note: Note
    let isHighlighted: Bool
    let isBeingDragged: Bool
    let style: NodeStyleConfig

    private var nodeScale: CGFloat {
        isBeingDragged ? 1.06 : (isHighlighted ? 1.04 : 1.0)
    }

    private var bubbleFillColor: Color {
        if isBeingDragged {
            return Color.orange.opacity(0.10)
        }
        if isHighlighted {
            return Color(red: 0.93, green: 0.95, blue: 0.99)
        }
        return Color.white
    }

    private var bubbleStrokeColor: Color {
        if isBeingDragged {
            return Color.orange.opacity(0.45)
        }
        if isHighlighted {
            return Color(red: 0.55, green: 0.65, blue: 0.90).opacity(0.55)
        }
        return Color.black.opacity(0.09)
    }

    private var bubbleStrokeWidth: CGFloat {
        (isHighlighted || isBeingDragged) ? 1.5 : 1.0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(note.title)
                .font(.system(size: style.titleFontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(white: 0.10))
                .lineLimit(1)

            if !note.subtitle.isEmpty {
                Text(note.subtitle)
                    .font(.system(size: style.subtitleFontSize, weight: .regular, design: .rounded))
                    .foregroundStyle(Color(white: 0.48))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, style.paddingH)
        .padding(.vertical, style.paddingV)
        .background(
            RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                .fill(bubbleFillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                .stroke(bubbleStrokeColor, lineWidth: bubbleStrokeWidth)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 8, y: 3)
        .scaleEffect(nodeScale)
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: nodeScale)
    }
}
