import SwiftUI
import AppKit

struct InfiniteCanvasView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.undoManager) private var undoManager
    @Binding var workspace: Workspace
    @ObservedObject var canvas: CanvasController
    let onOpenNode: (UUID) -> Void

    @State private var dragOrigins: [UUID: CanvasRect] = [:]
    @State private var resizeOrigins: [UUID: CanvasRect] = [:]
    @State private var dragTranslations: [UUID: CGSize] = [:]
    @State private var resizeTranslations: [UUID: CGSize] = [:]
    @State private var panOrigin: CGSize = .zero
    @State private var isDraggingPan = false
    @State private var lassoStart: CGPoint?
    @State private var magnificationOrigin: Double?
    @State private var activeInkPoints: [InkPoint] = []
    @State private var pendingErasedStrokeIDs: Set<UUID> = []
    @State private var interactionWorkspaceBefore: Workspace?
    @State private var pendingMaterialDeletion: CanvasNode?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                grid
                    .contentShape(Rectangle())
                    .gesture(backgroundGesture(in: geo.size))

                connectionLayer
                    .allowsHitTesting(false)

                inkLayer
                    .allowsHitTesting(false)

                ForEach(culledNodes(geo.size)) { node in
                    nodeView(node)
                }

                if let lasso = canvas.lassoRect {
                    Rectangle()
                        .stroke(Color.accentColor.opacity(0.9), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                        .background(Color.accentColor.opacity(0.12))
                        .frame(width: lasso.width, height: lasso.height)
                        .position(x: lasso.midX, y: lasso.midY)
                        .allowsHitTesting(false)
                }

                VStack {
                    Spacer()
                    HStack {
                        MiniMapView(workspace: $workspace, viewportSize: geo.size)
                            .padding(12)
                        Spacer()
                    }
                }
            }
            .overlay {
                ScrollWheelMonitor(excludedRects: orderedNodes.map(viewFrame) + [
                    CGRect(x: 0, y: geo.size.height - 116, width: 164, height: 116)
                ]) { dx, dy, command, location in
                    if command {
                        zoom(by: pow(1.006, -dy), anchoredAt: location)
                    } else {
                        workspace.cameraX += dx
                        workspace.cameraY += dy
                    }
                }
                .allowsHitTesting(false)
            }
            .simultaneousGesture(magnificationGesture(in: geo.size))
            .onAppear { canvas.viewportSize = geo.size }
            .onChange(of: geo.size) { _, size in canvas.viewportSize = size }
        }
        .clipped()
        .background(Color(nsColor: .windowBackgroundColor))
        .alert(item: $pendingMaterialDeletion) { node in
            let impact = workspace.removalImpact(for: [node.id])
            return Alert(
                title: Text("Remover material?"),
                message: Text(
                    impact.linkedRecordCount == 0
                        ? "O material “\(node.title)” será removido. Você poderá desfazer esta ação."
                        : "O material “\(node.title)” será removido. \(impact.linkedRecordCount) registro(s) vinculado(s) serão preservados sem o vínculo com o material. Você poderá desfazer esta ação."
                ),
                primaryButton: .destructive(Text("Remover")) {
                    deleteNode(node.id)
                },
                secondaryButton: .cancel(Text("Cancelar"))
            )
        }
    }

    private var orderedNodes: [CanvasNode] {
        workspace.nodes.sorted { $0.zIndex < $1.zIndex }
    }

    private func culledNodes(_ size: CGSize) -> [CanvasNode] {
        let margin: CGFloat = 600
        let visible = CGRect(origin: .zero, size: size).insetBy(dx: -margin, dy: -margin)
        return orderedNodes.filter { viewFrame(for: $0).intersects(visible) }
    }

    private var grid: some View {
        Canvas { context, size in
            let scale = workspace.cameraScale
            let step = 48 * scale
            guard step > 8 else { return }
            var x = workspace.cameraX.truncatingRemainder(dividingBy: step)
            if x < 0 { x += step }
            var y = workspace.cameraY.truncatingRemainder(dividingBy: step)
            if y < 0 { y += step }
            var path = Path()
            stride(from: x, to: size.width, by: step).forEach { gx in
                path.move(to: CGPoint(x: gx, y: 0))
                path.addLine(to: CGPoint(x: gx, y: size.height))
            }
            stride(from: y, to: size.height, by: step).forEach { gy in
                path.move(to: CGPoint(x: 0, y: gy))
                path.addLine(to: CGPoint(x: size.width, y: gy))
            }
            context.stroke(path, with: .color(.white.opacity(0.06)), lineWidth: 1)
        }
    }

    private var connectionLayer: some View {
        Canvas { context, _ in
            let nodes = Dictionary(uniqueKeysWithValues: workspace.nodes.map { ($0.id, $0) })
            for connection in workspace.connections ?? [] {
                guard let from = nodes[connection.fromNodeID], let to = nodes[connection.toNodeID] else { continue }
                let start = CGPoint(x: viewFrame(for: from).midX, y: viewFrame(for: from).midY)
                let end = CGPoint(x: viewFrame(for: to).midX, y: viewFrame(for: to).midY)
                var path = Path()
                path.move(to: start)
                path.addLine(to: end)
                let color = connectionColor(connection)
                context.stroke(path, with: .color(color.opacity(0.7)), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: connection.kind == .wikilink ? [7, 5] : []))

                let angle = atan2(end.y - start.y, end.x - start.x)
                let arrowLength: CGFloat = 10
                var arrow = Path()
                arrow.move(to: end)
                arrow.addLine(to: CGPoint(x: end.x - arrowLength * cos(angle - 0.45), y: end.y - arrowLength * sin(angle - 0.45)))
                arrow.move(to: end)
                arrow.addLine(to: CGPoint(x: end.x - arrowLength * cos(angle + 0.45), y: end.y - arrowLength * sin(angle + 0.45)))
                context.stroke(arrow, with: .color(color.opacity(0.85)), lineWidth: 2)

                if let label = connection.label, !label.isEmpty {
                    context.draw(
                        Text(label).font(.caption2).foregroundStyle(color),
                        at: CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
                    )
                }
            }
        }
    }

    private func connectionColor(_ connection: CanvasConnection) -> Color {
        switch connection.color {
        case "1": return .red
        case "2": return .orange
        case "3": return .yellow
        case "4": return .green
        case "5": return .cyan
        case "6": return .purple
        default: return connection.kind == .wikilink ? .blue : .purple
        }
    }

    private var inkLayer: some View {
        Canvas { context, size in
            let margin: CGFloat = 200
            let visible = CGRect(origin: .zero, size: size).insetBy(dx: -margin, dy: -margin)
            for stroke in (workspace.inkStrokes ?? []) + activeStroke {
                guard !pendingErasedStrokeIDs.contains(stroke.id) else { continue }
                guard strokeViewBounds(stroke).intersects(visible) else { continue }
                guard let first = stroke.points.first else { continue }
                var path = Path()
                path.move(to: canvasPoint(first))
                for point in stroke.points.dropFirst() {
                    path.addLine(to: canvasPoint(point))
                }
                context.stroke(
                    path,
                    with: .color(
                        canvas.selectedInkStrokeIDs.contains(stroke.id)
                            ? Color.orange
                            : CanvasInkColor.color(for: stroke.colorHex).opacity(0.92)
                    ),
                    style: StrokeStyle(
                        lineWidth: max(1.2, stroke.width * workspace.cameraScale),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }
        }
    }

    private var activeStroke: [InkStroke] {
        activeInkPoints.isEmpty ? [] : [InkStroke(
            points: activeInkPoints,
            colorHex: canvas.inkColor.rawValue
        )]
    }

    private func canvasPoint(_ point: InkPoint) -> CGPoint {
        CGPoint(
            x: point.x * workspace.cameraScale + workspace.cameraX,
            y: point.y * workspace.cameraScale + workspace.cameraY
        )
    }

    private func nodeView(_ node: CanvasNode) -> some View {
        let scale = workspace.cameraScale
        let viewRect = viewFrame(for: node)
        return NodeChrome(
            node: binding(for: node.id),
            selected: canvas.selectedNodeIDs.contains(node.id),
            scale: scale,
            onSelect: {
                if NSEvent.modifierFlags.contains(.shift) {
                    if canvas.selectedNodeIDs.contains(node.id) {
                        canvas.selectedNodeIDs.remove(node.id)
                    } else {
                        canvas.selectedNodeIDs.insert(node.id)
                    }
                } else {
                    canvas.selectedNodeIDs = [node.id]
                    canvas.selectedInkStrokeIDs = []
                }
            },
            onBringForward: {
                let previous = workspace
                canvas.bringToFront(id: node.id, workspace: &workspace)
                canvas.registerWorkspaceUndo(
                    from: previous,
                    in: store,
                    undoManager: undoManager,
                    actionName: "Trazer para frente"
                )
            },
            onDelete: {
                if node.isStudyMaterial {
                    pendingMaterialDeletion = node
                } else {
                    deleteNode(node.id)
                }
            },
            onInspect: {
                canvas.inspectedNodeID = node.id
            },
            onOpen: {
                onOpenNode(node.id)
            },
            onDragStart: {
                if !canvas.selectedNodeIDs.contains(node.id) {
                    canvas.selectedNodeIDs = [node.id]
                    canvas.selectedInkStrokeIDs = []
                }
            },
            onDrag: { translation in
                move(nodeID: node.id, translation: translation)
            },
            onResize: { translation in
                resize(nodeID: node.id, translation: translation)
            },
            onGestureEnd: {
                commitNodeInteraction()
                if let previous = interactionWorkspaceBefore {
                    canvas.registerWorkspaceUndo(
                        from: previous,
                        in: store,
                        undoManager: undoManager,
                        actionName: dragTranslations.isEmpty ? "Redimensionar nó" : "Mover nós"
                    )
                }
                interactionWorkspaceBefore = nil
                dragOrigins = [:]
                resizeOrigins = [:]
                dragTranslations = [:]
                resizeTranslations = [:]
            }
        )
        .frame(
            width: max(200, node.frame.width + (resizeTranslations[node.id]?.width ?? 0) / scale),
            height: max(160, node.frame.height + (resizeTranslations[node.id]?.height ?? 0) / scale)
        )
        .scaleEffect(scale)
        .position(x: viewRect.midX, y: viewRect.midY)
    }

    private func binding(for id: UUID) -> Binding<CanvasNode> {
        Binding(
            get: {
                workspace.nodes.first(where: { $0.id == id }) ?? CanvasNode(
                    kind: .note,
                    frame: .default(for: .note, origin: .zero)
                )
            },
            set: { updated in
                if let i = workspace.nodes.firstIndex(where: { $0.id == id }) {
                    workspace.nodes[i] = updated
                }
            }
        )
    }

    private func deleteNode(_ id: UUID) {
        let previous = workspace
        workspace.removeNodesPreservingDependentContent([id])
        canvas.selectedNodeIDs.remove(id)
        if canvas.inspectedNodeID == id { canvas.inspectedNodeID = nil }
        canvas.registerWorkspaceUndo(
            from: previous,
            in: store,
            undoManager: undoManager,
            actionName: "Excluir nó"
        )
    }

    private func viewFrame(for node: CanvasNode) -> CGRect {
        let s = workspace.cameraScale
        let drag = dragTranslations[node.id] ?? .zero
        let resize = resizeTranslations[node.id] ?? .zero
        return CGRect(
            x: node.frame.x * s + workspace.cameraX + drag.width,
            y: node.frame.y * s + workspace.cameraY + drag.height,
            width: max(200 * s, node.frame.width * s + resize.width),
            height: max(160 * s, node.frame.height * s + resize.height)
        )
    }

    private func move(nodeID: UUID, translation: CGSize) {
        if interactionWorkspaceBefore == nil { interactionWorkspaceBefore = workspace }
        let ids = canvas.selectedNodeIDs.contains(nodeID) ? canvas.selectedNodeIDs : [nodeID]
        for id in ids {
            if dragOrigins[id] == nil, let node = workspace.nodes.first(where: { $0.id == id }) {
                dragOrigins[id] = node.frame
            }
            dragTranslations[id] = translation
        }
    }

    private func resize(nodeID: UUID, translation: CGSize) {
        if interactionWorkspaceBefore == nil { interactionWorkspaceBefore = workspace }
        if resizeOrigins[nodeID] == nil, let node = workspace.nodes.first(where: { $0.id == nodeID }) {
            resizeOrigins[nodeID] = node.frame
        }
        resizeTranslations[nodeID] = translation
    }

    private func commitNodeInteraction() {
        let scale = workspace.cameraScale
        for (id, translation) in dragTranslations {
            guard let origin = dragOrigins[id],
                  let i = workspace.nodes.firstIndex(where: { $0.id == id }) else { continue }
            workspace.nodes[i].frame.x = origin.x + translation.width / scale
            workspace.nodes[i].frame.y = origin.y + translation.height / scale
        }
        for (id, translation) in resizeTranslations {
            guard let origin = resizeOrigins[id],
                  let i = workspace.nodes.firstIndex(where: { $0.id == id }) else { continue }
            workspace.nodes[i].frame.width = max(200, origin.width + translation.width / scale)
            workspace.nodes[i].frame.height = max(160, origin.height + translation.height / scale)
        }
    }

    private func backgroundGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                dragOrigins = [:]
                resizeOrigins = [:]
                dragTranslations = [:]
                resizeTranslations = [:]
                if canvas.tool == .draw {
                    let point = worldPoint(value.location)
                    if let last = activeInkPoints.last {
                        let dx = point.x - last.x
                        let dy = point.y - last.y
                        guard hypot(dx, dy) > 0.8 else { return }
                    }
                    activeInkPoints.append(point)
                } else if canvas.tool == .erase {
                    collectStrokesToErase(around: worldPoint(value.location))
                } else if canvas.tool == .lasso {
                    if lassoStart == nil { lassoStart = value.startLocation }
                    let start = lassoStart ?? value.startLocation
                    canvas.lassoRect = CGRect(
                        x: min(start.x, value.location.x),
                        y: min(start.y, value.location.y),
                        width: abs(value.location.x - start.x),
                        height: abs(value.location.y - start.y)
                    )
                } else {
                    if !isDraggingPan {
                        isDraggingPan = true
                        panOrigin = CGSize(width: workspace.cameraX, height: workspace.cameraY)
                    }
                    workspace.cameraX = panOrigin.width + value.translation.width
                    workspace.cameraY = panOrigin.height + value.translation.height
                    canvas.selectedNodeIDs = []
                    canvas.selectedInkStrokeIDs = []
                }
            }
            .onEnded { _ in
                if canvas.tool == .draw, activeInkPoints.count > 1 {
                    let previous = workspace
                    var strokes = workspace.inkStrokes ?? []
                    strokes.append(InkStroke(
                        points: activeInkPoints,
                        colorHex: canvas.inkColor.rawValue
                    ))
                    workspace.inkStrokes = strokes
                    canvas.registerWorkspaceUndo(
                        from: previous,
                        in: store,
                        undoManager: undoManager,
                        actionName: "Desenhar traço"
                    )
                } else if canvas.tool == .erase, !pendingErasedStrokeIDs.isEmpty {
                    let previous = workspace
                    workspace.inkStrokes?.removeAll { pendingErasedStrokeIDs.contains($0.id) }
                    canvas.selectedInkStrokeIDs.subtract(pendingErasedStrokeIDs)
                    canvas.registerWorkspaceUndo(
                        from: previous,
                        in: store,
                        undoManager: undoManager,
                        actionName: "Apagar traços"
                    )
                } else if canvas.tool == .lasso, let rect = canvas.lassoRect {
                    canvas.selectedNodeIDs = Set(
                        workspace.nodes.filter { viewFrame(for: $0).intersects(rect) }.map(\.id)
                    )
                    canvas.selectedInkStrokeIDs = Set(
                        (workspace.inkStrokes ?? [])
                            .filter { strokeViewBounds($0).intersects(rect) }
                            .map(\.id)
                    )
                }
                canvas.lassoRect = nil
                lassoStart = nil
                activeInkPoints = []
                pendingErasedStrokeIDs = []
                isDraggingPan = false
                dragOrigins = [:]
                resizeOrigins = [:]
            }
    }

    private func worldPoint(_ point: CGPoint) -> InkPoint {
        InkPoint(
            x: (point.x - workspace.cameraX) / workspace.cameraScale,
            y: (point.y - workspace.cameraY) / workspace.cameraScale
        )
    }

    private func collectStrokesToErase(around point: InkPoint) {
        let radius = 14 / workspace.cameraScale
        for stroke in workspace.inkStrokes ?? [] where !pendingErasedStrokeIDs.contains(stroke.id) {
            if distance(from: point, to: stroke) <= radius {
                pendingErasedStrokeIDs.insert(stroke.id)
            }
        }
    }

    private func distance(from point: InkPoint, to stroke: InkStroke) -> Double {
        guard let first = stroke.points.first else { return .infinity }
        guard stroke.points.count > 1 else { return hypot(point.x - first.x, point.y - first.y) }
        var result = Double.infinity
        for (start, end) in zip(stroke.points, stroke.points.dropFirst()) {
            let dx = end.x - start.x
            let dy = end.y - start.y
            let lengthSquared = dx * dx + dy * dy
            let projection = lengthSquared == 0 ? 0 : min(1, max(0,
                ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
            ))
            result = min(result, hypot(
                point.x - (start.x + projection * dx),
                point.y - (start.y + projection * dy)
            ))
        }
        return result
    }

    private func strokeViewBounds(_ stroke: InkStroke) -> CGRect {
        guard let first = stroke.points.first else { return .null }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in stroke.points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return CGRect(
            x: minX * workspace.cameraScale + workspace.cameraX,
            y: minY * workspace.cameraScale + workspace.cameraY,
            width: max(2, (maxX - minX) * workspace.cameraScale),
            height: max(2, (maxY - minY) * workspace.cameraScale)
        ).insetBy(dx: -4, dy: -4)
    }

    private func magnificationGesture(in size: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if magnificationOrigin == nil { magnificationOrigin = workspace.cameraScale }
                let origin = magnificationOrigin ?? workspace.cameraScale
                let next = min(2.4, max(0.5, origin * value))
                let factor = next / workspace.cameraScale
                zoom(by: factor, anchoredAt: CGPoint(x: size.width / 2, y: size.height / 2))
            }
            .onEnded { _ in magnificationOrigin = nil }
    }

    private func zoom(by factor: Double, anchoredAt anchor: CGPoint) {
        let old = workspace.cameraScale
        let next = min(2.4, max(0.5, workspace.cameraScale * factor))
        guard next != old else { return }
        let worldX = (anchor.x - workspace.cameraX) / old
        let worldY = (anchor.y - workspace.cameraY) / old
        workspace.cameraScale = next
        workspace.cameraX = anchor.x - worldX * next
        workspace.cameraY = anchor.y - worldY * next
    }
}

private struct MiniMapView: View {
    @Binding var workspace: Workspace
    let viewportSize: CGSize
    private let mapSize = CGSize(width: 140, height: 92)

    var body: some View {
        let bounds = contentBounds
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(.black.opacity(0.45))
            ForEach(workspace.nodes) { node in
                let r = project(node.frame.cgRect, bounds: bounds)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor.opacity(0.7))
                    .frame(width: max(3, r.width), height: max(3, r.height))
                    .offset(x: r.minX, y: r.minY)
            }
            let viewport = project(viewportWorldRect, bounds: bounds)
            Rectangle()
                .stroke(.white.opacity(0.9), lineWidth: 1.5)
                .background(.white.opacity(0.06))
                .frame(width: max(2, viewport.width), height: max(2, viewport.height))
                .offset(x: viewport.minX, y: viewport.minY)
        }
        .frame(width: mapSize.width, height: mapSize.height)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in navigate(to: value.location, bounds: bounds) }
        )
        .help("Clique ou arraste para navegar")
        .accessibilityLabel("Minimapa do canvas")
        .accessibilityHint("Clique ou arraste para navegar pelo canvas")
    }

    private var contentBounds: CGRect {
        let frames = workspace.nodes.map(\.frame.cgRect) + [viewportWorldRect]
        let union = frames.reduce(CGRect(x: -400, y: -300, width: 800, height: 600)) { $0.union($1) }
        return union.insetBy(dx: -80, dy: -80)
    }

    private func project(_ rect: CGRect, bounds: CGRect) -> CGRect {
        let w = mapSize.width
        let h = mapSize.height
        let sx = w / bounds.width
        let sy = h / bounds.height
        return CGRect(
            x: (rect.minX - bounds.minX) * sx,
            y: (rect.minY - bounds.minY) * sy,
            width: rect.width * sx,
            height: rect.height * sy
        )
    }

    private var viewportWorldRect: CGRect {
        CGRect(
            x: -workspace.cameraX / workspace.cameraScale,
            y: -workspace.cameraY / workspace.cameraScale,
            width: viewportSize.width / workspace.cameraScale,
            height: viewportSize.height / workspace.cameraScale
        )
    }

    private func navigate(to point: CGPoint, bounds: CGRect) {
        let worldX = bounds.minX + point.x / mapSize.width * bounds.width
        let worldY = bounds.minY + point.y / mapSize.height * bounds.height
        workspace.cameraX = viewportSize.width / 2 - worldX * workspace.cameraScale
        workspace.cameraY = viewportSize.height / 2 - worldY * workspace.cameraScale
    }
}

private struct ScrollWheelMonitor: NSViewRepresentable {
    var excludedRects: [CGRect]
    var onScroll: (_ dx: CGFloat, _ dy: CGFloat, _ command: Bool, _ location: CGPoint) -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.excludedRects = excludedRects
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        nsView.onScroll = onScroll
        nsView.excludedRects = excludedRects
    }

    final class MonitorView: NSView {
        var onScroll: ((_ dx: CGFloat, _ dy: CGFloat, _ command: Bool, _ location: CGPoint) -> Void)?
        var excludedRects: [CGRect] = []
        private var eventMonitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
            eventMonitor = nil
            guard window != nil else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(point) else { return event }
                guard !self.excludedRects.contains(where: { $0.contains(point) }) else { return event }
                self.onScroll?(
                    event.scrollingDeltaX,
                    event.scrollingDeltaY,
                    event.modifierFlags.contains(.command),
                    point
                )
                return nil
            }
        }

        deinit {
            if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        }
    }
}
