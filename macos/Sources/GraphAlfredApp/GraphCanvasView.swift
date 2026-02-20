import AppKit
import SwiftUI

struct GraphCanvasView: View {
    let notes: [Note]
    let links: [Link]
    let highlightedNoteID: Int64?
    let activeDragNoteID: Int64?
    let isolatedNoteID: Int64?
    let onSelect: (Note) -> Void
    let onDoubleSelect: (Note) -> Void
    let onIsolateNode: (Int64?) -> Void
    let onDragEnd: (Int64, Double, Double) -> Void
    let onConnect: (Int64, Int64) -> Void
    let onDragStateChange: (Int64?) -> Void

    @State private var dragOrigins: [Int64: CGPoint] = [:]
    @State private var transientNodePositions: [Int64: CGPoint] = [:]
    @State private var activeNodeDragID: Int64?
    @State private var tapSequenceNoteID: Int64?
    @State private var tapCount = 0
    @State private var lastTapTime: Date = .distantPast
    @State private var pendingDoubleAction: DispatchWorkItem?

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

    private static let doubleTapThreshold: TimeInterval = 0.28
    private static let tapMovementThreshold: CGFloat = 6
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
                    colors: [Color.black.opacity(0.95), Color(red: 0.08, green: 0.08, blue: 0.1)],
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
            .onDisappear {
                pendingDoubleAction?.cancel()
                onDragStateChange(nil)
                transientNodePositions.removeAll()
                removeEventMonitors()
            }
        }
    }

    private var noteMap: [Int64: Note] {
        Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
    }

    private var visibleNotes: [Note] {
        guard let isolatedNoteID else {
            return notes
        }
        guard let isolated = noteMap[isolatedNoteID] else {
            return notes
        }
        return [isolated]
    }

    @ViewBuilder
    private func canvasLayer(in size: CGSize) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .onTapGesture {
                    if isolatedNoteID != nil {
                        onIsolateNode(nil)
                    }
                }

            if isolatedNoteID == nil {
                Canvas { context, _ in
                    for link in links {
                        guard let source = noteMap[link.sourceId], let target = noteMap[link.targetId] else {
                            continue
                        }

                        var path = Path()
                        path.move(to: point(for: source, in: size))
                        path.addLine(to: point(for: target, in: size))
                        context.stroke(path, with: .color(Color.white.opacity(0.20)), lineWidth: 1.2)
                    }
                }
                .allowsHitTesting(false)
            }

            ForEach(visibleNotes) { note in
                let isDragging = activeNodeDragID == note.id || activeDragNoteID == note.id
                let isHighlighted = highlightedNoteID == note.id

                NodeBubbleView(
                    note: note,
                    isHighlighted: isHighlighted,
                    isBeingDragged: isDragging
                )
                .fixedSize()
                .offset(x: nodeOffsetX(for: note), y: nodeOffsetY(for: note))
                .gesture(interactionGesture(for: note.id))
                .zIndex(isDragging ? 4 : (isHighlighted ? 2 : 1))
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

    private func point(for note: Note, in size: CGSize) -> CGPoint {
        let current = currentGraphPoint(for: note)
        return CGPoint(
            x: size.width / 2.0 + panOffset.width + (current.x * zoomScale),
            y: size.height / 2.0 + panOffset.height + (current.y * zoomScale)
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
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if isSpacePressed {
                    return
                }

                let distance = hypot(value.translation.width, value.translation.height)
                if distance < 1.5 {
                    return
                }

                let canDrag = canDragNode(noteID)
                if !canDrag {
                    return
                }

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
                let canDrag = canDragNode(noteID)
                let finalPoint = transientNodePositions[noteID] ?? CGPoint(x: nextX, y: nextY)
                transientNodePositions.removeValue(forKey: noteID)

                dragOrigins.removeValue(forKey: noteID)

                if activeNodeDragID == noteID {
                    activeNodeDragID = nil
                    onDragStateChange(nil)
                }

                if distance <= Self.tapMovementThreshold || !canDrag {
                    handleTap(noteID: noteID)
                    return
                }

                // A committed drag should reset multi-click state to avoid accidental double/triple actions.
                tapSequenceNoteID = nil
                tapCount = 0
                pendingDoubleAction?.cancel()
                pendingDoubleAction = nil

                if let targetID = nearestNodeID(from: noteID, to: finalPoint) {
                    onConnect(noteID, targetID)
                }

                onDragEnd(noteID, finalPoint.x, finalPoint.y)
            }
    }

    private func canDragNode(_ noteID: Int64) -> Bool {
        activeNodeDragID == noteID
            || highlightedNoteID == noteID
            || tapSequenceNoteID == noteID
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

        for note in notes where note.id != sourceID {
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
        let now = Date()

        let continuesSequence = tapSequenceNoteID == noteID
            && now.timeIntervalSince(lastTapTime) <= Self.doubleTapThreshold

        if !continuesSequence {
            pendingDoubleAction?.cancel()
            pendingDoubleAction = nil
            tapSequenceNoteID = noteID
            tapCount = 1
            lastTapTime = now
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
            onSelect(note)
            centerNode(note)
            if isolatedNoteID == note.id {
                onIsolateNode(nil)
            } else {
                onIsolateNode(note.id)
            }
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

    private func installEventMonitors() {
        if keyDownMonitor == nil {
            keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 49 {
                    isSpacePressed = true
                }
                if event.keyCode == 53, isolatedNoteID != nil {
                    onIsolateNode(nil)
                    return nil
                }
                return event
            }
        }

        if keyUpMonitor == nil {
            keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { event in
                if event.keyCode == 49 {
                    isSpacePressed = false
                    isPanningCanvas = false
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

        isSpacePressed = false
        isPanningCanvas = false
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
