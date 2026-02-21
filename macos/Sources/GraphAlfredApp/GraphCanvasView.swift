import AppKit
import SwiftUI

struct GraphCanvasView: View {
    let notes: [Note]
    let links: [Link]
    let highlightedNoteID: Int64?
    let activeDragNoteID: Int64?
    let isolatedNoteID: Int64?
    let theme: AppTheme
    let allowsRightMousePan: Bool
    let allowsDragToConnect: Bool
    let onSelect: (Note) -> Void
    let onDoubleSelect: (Note) -> Void
    let onIsolateNode: (Int64?) -> Void
    let onDragEnd: (Int64, Double, Double) -> Void
    let onConnect: (Int64, Int64) -> Void
    let onDeleteLink: (Int64, Int64) -> Void
    let onQuickCreate: (String, Double, Double, Int64?) -> Void
    let onDragStateChange: (Int64?) -> Void

    @State private var dragOrigins: [Int64: CGPoint] = [:]
    @State private var transientNodePositions: [Int64: CGPoint] = [:]
    @State private var activeNodeDragID: Int64?
    @State private var tapSequenceNoteID: Int64?
    @State private var tapCount = 0
    @State private var lastTapTime: Date = .distantPast
    @State private var pendingDoubleAction: DispatchWorkItem?
    @State private var linkingSourceNoteID: Int64?
    @State private var contextualNoteID: Int64?
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
    @State private var isRightMousePanning = false
    @State private var rightMouseStartLocation: CGPoint?
    @State private var rightMousePanOrigin: CGSize = .zero

    private static let doubleTapThreshold: TimeInterval = 0.28
    private static let tapMovementThreshold: CGFloat = 6
    private static let backgroundTapThreshold: CGFloat = 6
    private static let dragStartThreshold: CGFloat = 3
    private static let minZoom: CGFloat = 0.45
    private static let maxZoom: CGFloat = 2.8

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                canvasLayer(in: geometry.size)
                transformControls
            }
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
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .simultaneousGesture(canvasPanGesture)
            .simultaneousGesture(canvasMagnificationGesture)
            .onHover { isHoveringCanvas = $0 }
            .onAppear {
                installEventMonitors()
            }
            .onChange(of: isolatedNoteID) { next in
                if next != nil {
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
            .onDisappear {
                pendingDoubleAction?.cancel()
                onDragStateChange(nil)
                transientNodePositions.removeAll()
                selectedLink = nil
                contextualNoteID = nil
                linkingSourceNoteID = nil
                quickCreateDraft = nil
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
            return [isolated]
        }

        if contextualNoteID != nil {
            let visibleIDs = contextualVisibleNoteIDs
            return notes.filter { visibleIDs.contains($0.id) }
        }

        return notes
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

        return links
    }

    @ViewBuilder
    private func canvasLayer(in size: CGSize) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .gesture(backgroundTapGesture(in: size))

            Canvas { context, _ in
                for link in visibleLinks {
                    guard let source = noteMap[link.sourceId], let target = noteMap[link.targetId] else {
                        continue
                    }

                    let edge = normalizeEdge(link.sourceId, link.targetId)
                    let isSelected = selectedLink?.sourceID == edge.0 && selectedLink?.targetID == edge.1

                    var path = Path()
                    path.move(to: point(for: source, in: size))
                    path.addLine(to: point(for: target, in: size))
                    context.stroke(
                        path,
                        with: .color(isSelected ? Color.red.opacity(0.88) : Color.white.opacity(0.20)),
                        lineWidth: isSelected ? 2.8 : 1.2
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
                let showsConnectHandle = isolatedNoteID == nil && isHighlighted

                ZStack(alignment: .topTrailing) {
                    NodeBubbleView(
                        note: note,
                        isHighlighted: isHighlighted,
                        isBeingDragged: isDragging
                    )
                    .gesture(interactionGesture(for: note.id))

                    if showsConnectHandle {
                        connectHandle(for: note.id, isActive: linkingSourceNoteID == note.id)
                            .offset(x: 10, y: -10)
                    }
                }
                .fixedSize()
                .offset(x: nodeOffsetX(for: note), y: nodeOffsetY(for: note))
                .zIndex(isDragging ? 4 : (isHighlighted ? 2 : 1))
            }

            if let selectedLink, isolatedNoteID == nil {
                HStack(spacing: 7) {
                    Image(systemName: "link.badge.minus")
                        .foregroundStyle(Color.red.opacity(0.95))
                    Text("Connection selected (\(selectedLink.sourceID)-\(selectedLink.targetID)). Press Delete to remove.")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.85))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .position(x: size.width - 250, y: 24)
            }

            if let contextualNoteID, isolatedNoteID == nil, let note = noteMap[contextualNoteID] {
                HStack(spacing: 7) {
                    Image(systemName: "scope")
                        .foregroundStyle(Color.cyan.opacity(0.92))
                    Text("Context: \(note.title). Showing direct connections.")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.85))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .position(x: size.width / 2, y: 24)
            }

            if let linkingSourceNoteID, let source = noteMap[linkingSourceNoteID], isolatedNoteID == nil {
                HStack(spacing: 7) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.cyan.opacity(0.92))
                    Text("Select a note to connect with \(source.title)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.85))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .position(x: 180, y: 24)
            }

            if let isolatedNoteID, let note = noteMap[isolatedNoteID] {
                VStack(spacing: 6) {
                    Text("Focus Mode")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.86))
                    Text(note.title)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.72))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .position(x: size.width / 2, y: 24)
            }

            if let quickCreateDraft {
                QuickCreateNodeBubble(
                    title: Binding(
                        get: { quickCreateDraft.title },
                        set: { nextTitle in
                            self.quickCreateDraft?.title = nextTitle
                        }
                    ),
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

    private var transformControls: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    zoomScale = clampedScale(zoomScale / 1.15)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(GraphSecondaryButtonStyle())

                Button {
                    zoomScale = clampedScale(zoomScale * 1.15)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(GraphSecondaryButtonStyle())

                Button("Reset") {
                    resetViewTransform()
                }
                .buttonStyle(GraphSecondaryButtonStyle())

                if isolatedNoteID != nil {
                    Button("Show All") {
                        onIsolateNode(nil)
                        contextualNoteID = nil
                        selectedLink = nil
                        quickCreateDraft = nil
                    }
                    .buttonStyle(GraphPrimaryButtonStyle())
                }
            }

            Text("\(Int((zoomScale * 100).rounded()))%")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.78))
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .padding(12)
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
            .onEnded { value in
                let distance = hypot(
                    value.location.x - value.startLocation.x,
                    value.location.y - value.startLocation.y
                )

                guard distance <= Self.backgroundTapThreshold else {
                    return
                }

                handleBackgroundTap(at: value.location, in: size)
            }
    }

    private func handleBackgroundTap(at location: CGPoint, in size: CGSize) {
        pendingDoubleAction?.cancel()
        pendingDoubleAction = nil
        tapSequenceNoteID = nil
        tapCount = 0

        if selectedLink != nil {
            selectedLink = nil
            return
        }

        if linkingSourceNoteID != nil {
            linkingSourceNoteID = nil
            return
        }

        if let quickCreateDraft {
            let bubblePoint = screenPoint(for: quickCreateDraft.graphPoint, in: size)
            let distanceToBubble = hypot(location.x - bubblePoint.x, location.y - bubblePoint.y)
            if distanceToBubble > 120 {
                self.quickCreateDraft = nil
            }
            return
        }

        if let isolatedNoteID {
            quickCreateDraft = QuickCreateDraft(
                title: "",
                graphPoint: graphPoint(from: location, in: size),
                connectToID: isolatedNoteID
            )
            return
        }

        if contextualNoteID != nil {
            contextualNoteID = nil
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
                if isSpacePressed || isRightMousePanning {
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
                if isSpacePressed || isRightMousePanning {
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
        guard isolatedNoteID == nil else {
            return nil
        }

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

        if tapCount >= 3 {
            pendingDoubleAction?.cancel()
            pendingDoubleAction = nil
            tapCount = 0
            tapSequenceNoteID = nil
            contextualNoteID = nil
            selectedLink = nil
            onSelect(note)
            centerNode(note)
            onIsolateNode(note.id)
            return
        }

        if tapCount == 2 {
            pendingDoubleAction?.cancel()
            let action = DispatchWorkItem {
                onDoubleSelect(note)
                tapCount = 0
                tapSequenceNoteID = nil
                pendingDoubleAction = nil
            }
            pendingDoubleAction = action
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.doubleTapThreshold, execute: action)
        }
    }

    private func clampedScale(_ proposed: CGFloat) -> CGFloat {
        min(Self.maxZoom, max(Self.minZoom, proposed))
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

    private func connectHandle(for noteID: Int64, isActive: Bool) -> some View {
        Button {
            pendingDoubleAction?.cancel()
            pendingDoubleAction = nil
            tapSequenceNoteID = nil
            tapCount = 0
            selectedLink = nil

            if isActive {
                linkingSourceNoteID = nil
            } else {
                linkingSourceNoteID = noteID
            }
        } label: {
            Image(systemName: isActive ? "xmark" : "plus")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(7)
                .background(isActive ? Color.red.opacity(0.88) : Color.cyan.opacity(0.88))
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.6), lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
        .help(isActive ? "Cancel connect mode" : "Create a connection")
    }

    private func commitQuickCreate() {
        guard let quickCreateDraft else {
            return
        }

        let title = quickCreateDraft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            return
        }

        onQuickCreate(
            title,
            quickCreateDraft.graphPoint.x,
            quickCreateDraft.graphPoint.y,
            quickCreateDraft.connectToID
        )

        if let parentID = quickCreateDraft.connectToID {
            contextualNoteID = parentID
        }
        onIsolateNode(nil)
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
                if isDeleteKey(event), let selectedLink {
                    onDeleteLink(selectedLink.sourceID, selectedLink.targetID)
                    self.selectedLink = nil
                    return nil
                }
                if event.keyCode == 53 {
                    if quickCreateDraft != nil {
                        quickCreateDraft = nil
                        return nil
                    }
                    if isolatedNoteID != nil {
                        onIsolateNode(nil)
                        contextualNoteID = nil
                        return nil
                    }
                    if contextualNoteID != nil {
                        contextualNoteID = nil
                        return nil
                    }
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

                guard event.modifierFlags.contains(.command) else {
                    return event
                }

                let intensity = event.hasPreciseScrollingDeltas ? 0.0045 : 0.03
                let zoomFactor = exp(event.scrollingDeltaY * intensity)
                zoomScale = clampedScale(zoomScale * zoomFactor)

                return nil
            }
        }

        if rightMouseMonitor == nil {
            rightMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .rightMouseDragged, .rightMouseUp]) { event in
                guard allowsRightMousePan else {
                    return event
                }
                guard isHoveringCanvas else {
                    return event
                }
                guard !isTextInputFocused() else {
                    return event
                }

                switch event.type {
                case .rightMouseDown:
                    isRightMousePanning = true
                    rightMouseStartLocation = event.locationInWindow
                    rightMousePanOrigin = panOffset
                    return nil
                case .rightMouseDragged:
                    guard isRightMousePanning, let start = rightMouseStartLocation else {
                        return nil
                    }

                    let current = event.locationInWindow
                    panOffset = CGSize(
                        width: rightMousePanOrigin.width + (current.x - start.x),
                        height: rightMousePanOrigin.height + (current.y - start.y)
                    )
                    return nil
                case .rightMouseUp:
                    guard isRightMousePanning else {
                        return event
                    }
                    panStart = panOffset
                    isRightMousePanning = false
                    rightMouseStartLocation = nil
                    return nil
                default:
                    return event
                }
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
        isRightMousePanning = false
        rightMouseStartLocation = nil
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

    private func normalizeEdge(_ a: Int64, _ b: Int64) -> (Int64, Int64) {
        a < b ? (a, b) : (b, a)
    }
}

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
}

private struct QuickCreateNodeBubble: View {
    @Binding var title: String
    let onCancel: () -> Void
    let onCreate: () -> Void

    @FocusState private var isFocused: Bool
    private var hasValidTitle: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(Color.green.opacity(0.9))
                .frame(width: 10, height: 10)

            TextField(
                "",
                text: $title,
                prompt: Text("New linked note")
                    .foregroundColor(Color.white.opacity(0.5))
            )
            .textFieldStyle(.plain)
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(minWidth: 160, maxWidth: 280)
            .focused($isFocused)
            .onSubmit {
                if hasValidTitle {
                    onCreate()
                }
            }

            if hasValidTitle {
                Image(systemName: "return")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.65))
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(isFocused ? Color.green.opacity(0.82) : Color.white.opacity(0.24), lineWidth: isFocused ? 1.8 : 1)
        )
        .shadow(color: Color.black.opacity(0.38), radius: 7, y: 3)
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

    private var nodeBackground: Color {
        if isBeingDragged {
            return Color.orange.opacity(0.2)
        }
        if isHighlighted {
            return Color.green.opacity(0.22)
        }
        return Color.black.opacity(0.52)
    }

    private var nodeStrokeColor: Color {
        if isBeingDragged {
            return Color.orange.opacity(0.95)
        }
        if isHighlighted {
            return Color.green.opacity(0.8)
        }
        return Color.white.opacity(0.18)
    }

    private var nodeStrokeWidth: CGFloat {
        if isBeingDragged {
            return 1.8
        }
        return isHighlighted ? 2 : 1
    }

    private var nodeScale: CGFloat {
        if isBeingDragged {
            return 1.04
        }
        return isHighlighted ? 1.02 : 1
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(isBeingDragged ? Color.orange : (isHighlighted ? Color.green : Color.white.opacity(0.78)))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(note.title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if !note.subtitle.isEmpty {
                    Text(note.subtitle)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(nodeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(nodeStrokeColor, lineWidth: nodeStrokeWidth)
        )
        .shadow(color: Color.black.opacity(0.42), radius: 8, y: 3)
        .scaleEffect(nodeScale)
    }
}
