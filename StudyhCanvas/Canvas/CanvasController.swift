import SwiftUI

@MainActor
final class CanvasController: ObservableObject {
    @Published var selectedNodeIDs: Set<UUID> = []
    @Published var selectedInkStrokeIDs: Set<UUID> = []
    @Published var tool: CanvasTool = .select
    @Published var lassoRect: CGRect?
    @Published var isPanning = false
    @Published var aiPanelText: String = ""
    @Published var aiBusy = false
    @Published var aiError: String?
    @Published var lastAIMode: AIMode?
    @Published var viewportSize: CGSize = .zero
    @Published var inspectedNodeID: UUID?
    @Published var inkColor: CanvasInkColor = .blue
    @Published var activeStudyNodeID: UUID?

    enum CanvasTool: String, Hashable {
        case select
        case lasso
        case pan
        case draw
        case erase
    }

    func bringToFront(id: UUID, workspace: inout Workspace) {
        guard let maxZ = workspace.nodes.map(\.zIndex).max() else { return }
        if let i = workspace.nodes.firstIndex(where: { $0.id == id }) {
            workspace.nodes[i].zIndex = maxZ + 1
        }
    }

    @discardableResult
    func addNode(
        kind: NodeKind,
        title: String? = nil,
        noteBody: String = "",
        sourceArtifactID: UUID? = nil,
        sourceArtifactCardIndex: Int? = nil,
        sourceArtifactKind: StudyArtifactKind? = nil,
        sourceMaterialID: UUID? = nil,
        sourcePageIndex: Int? = nil,
        sourceQuote: String? = nil,
        sourceURL: String? = nil,
        in workspace: inout Workspace
    ) -> UUID {
        let viewport = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        let worldCenter = CGPoint(
            x: (viewport.x - workspace.cameraX) / workspace.cameraScale,
            y: (viewport.y - workspace.cameraY) / workspace.cameraScale
        )
        let defaultSize = CanvasRect.default(for: kind, origin: .zero)
        let cascade = Double(workspace.nodes.count % 5) * 28
        let origin = CGPoint(
            x: worldCenter.x - defaultSize.width / 2 + cascade,
            y: worldCenter.y - defaultSize.height / 2 + cascade
        )
        let z = (workspace.nodes.map(\.zIndex).max() ?? 0) + 1
        let node = CanvasNode(
            kind: kind,
            title: title,
            frame: .default(for: kind, origin: origin),
            zIndex: z,
            noteBody: noteBody,
            calcBody: "",
            sourceArtifactID: sourceArtifactID,
            sourceArtifactCardIndex: sourceArtifactCardIndex,
            sourceArtifactKind: sourceArtifactKind,
            sourceMaterialID: sourceMaterialID,
            sourcePageIndex: sourcePageIndex,
            sourceQuote: sourceQuote,
            sourceURL: sourceURL
        )
        workspace.nodes.append(node)
        selectedNodeIDs = [node.id]
        return node.id
    }

    func organize(in workspace: inout Workspace) {
        guard !workspace.nodes.isEmpty else { return }
        let sortedIDs = workspace.nodes.sorted { lhs, rhs in
            let left = layoutPriority(lhs)
            let right = layoutPriority(rhs)
            return left == right ? lhs.zIndex < rhs.zIndex : left < right
        }.map(\.id)
        let availableWidth = max(920, viewportSize.width / max(0.6, workspace.cameraScale))
        let gap: Double = 36
        var x: Double = 0
        var y: Double = 0
        var rowHeight: Double = 0
        for id in sortedIDs {
            guard let index = workspace.nodes.firstIndex(where: { $0.id == id }) else { continue }
            let width = workspace.nodes[index].frame.width
            let height = workspace.nodes[index].frame.height
            if x > 0, x + width > availableWidth {
                x = 0
                y += rowHeight + gap
                rowHeight = 0
            }
            workspace.nodes[index].frame.x = x
            workspace.nodes[index].frame.y = y
            x += width + gap
            rowHeight = max(rowHeight, height)
        }
        frameAll(in: &workspace)
    }

    func frameAll(in workspace: inout Workspace, padding: Double = 64) {
        guard viewportSize.width > 0, viewportSize.height > 0,
              let first = workspace.nodes.first?.frame.cgRect else { return }
        let bounds = workspace.nodes.dropFirst().reduce(first) { $0.union($1.frame.cgRect) }
        let availableWidth = max(200, viewportSize.width - padding * 2)
        let availableHeight = max(160, viewportSize.height - padding * 2)
        let scale = min(
            1.25,
            max(0.55, min(availableWidth / max(1, bounds.width), availableHeight / max(1, bounds.height)))
        )
        workspace.cameraScale = scale
        workspace.cameraX = viewportSize.width / 2 - bounds.midX * scale
        workspace.cameraY = viewportSize.height / 2 - bounds.midY * scale
    }

    private func layoutPriority(_ node: CanvasNode) -> Int {
        if node.isStudyMaterial { return 0 }
        if node.sourceArtifactKind == .note { return 1 }
        if node.sourceArtifactKind == .flashcards { return 2 }
        return 3
    }

    func deleteSelected(from workspace: inout Workspace) {
        if let inspectedNodeID, selectedNodeIDs.contains(inspectedNodeID) {
            self.inspectedNodeID = nil
        }
        workspace.removeNodesPreservingDependentContent(selectedNodeIDs)
        workspace.inkStrokes?.removeAll { selectedInkStrokeIDs.contains($0.id) }
        selectedNodeIDs.removeAll()
        selectedInkStrokeIDs.removeAll()
    }

    func registerWorkspaceUndo(
        from previous: Workspace,
        in store: WorkspaceStore,
        undoManager: UndoManager?,
        actionName: String
    ) {
        guard let undoManager,
              let current = store.workspaces.first(where: { $0.id == previous.id }),
              current != previous else { return }
        registerWorkspaceRestore(
            previous,
            workspaceID: previous.id,
            store: store,
            undoManager: undoManager,
            actionName: actionName
        )
    }

    func registerStoreUndo(
        workspaces: [Workspace],
        selectedID: UUID?,
        in store: WorkspaceStore,
        undoManager: UndoManager?,
        actionName: String
    ) {
        guard let undoManager,
              workspaces != store.workspaces || selectedID != store.selectedID else { return }
        registerStoreRestore(
            workspaces,
            selectedID: selectedID,
            store: store,
            undoManager: undoManager,
            actionName: actionName
        )
    }

    func zoom(by factor: Double, in workspace: inout Workspace) {
        let anchor = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        let old = workspace.cameraScale
        let next = min(2.4, max(0.5, old * factor))
        guard next != old else { return }
        let worldX = (anchor.x - workspace.cameraX) / old
        let worldY = (anchor.y - workspace.cameraY) / old
        workspace.cameraScale = next
        workspace.cameraX = anchor.x - worldX * next
        workspace.cameraY = anchor.y - worldY * next
    }

    private func registerWorkspaceRestore(
        _ snapshot: Workspace,
        workspaceID: UUID,
        store: WorkspaceStore,
        undoManager: UndoManager,
        actionName: String
    ) {
        undoManager.registerUndo(withTarget: self) { target in
            guard let index = store.workspaces.firstIndex(where: { $0.id == workspaceID }) else { return }
            let inverse = store.workspaces[index]
            store.markAllWorkspacesDirty()
            store.workspaces[index] = snapshot
            store.persistSoon()
            target.registerWorkspaceRestore(
                inverse,
                workspaceID: workspaceID,
                store: store,
                undoManager: undoManager,
                actionName: actionName
            )
        }
        undoManager.setActionName(actionName)
    }

    private func registerStoreRestore(
        _ workspaces: [Workspace],
        selectedID: UUID?,
        store: WorkspaceStore,
        undoManager: UndoManager,
        actionName: String
    ) {
        undoManager.registerUndo(withTarget: self) { target in
            let inverseWorkspaces = store.workspaces
            let inverseSelection = store.selectedID
            store.restoreStoreState(workspaces, selectedID: selectedID)
            target.registerStoreRestore(
                inverseWorkspaces,
                selectedID: inverseSelection,
                store: store,
                undoManager: undoManager,
                actionName: actionName
            )
        }
        undoManager.setActionName(actionName)
    }
}

enum CanvasInkColor: String, CaseIterable, Identifiable {
    case blue = "#3788FF"
    case red = "#F04F4F"
    case green = "#32A66A"
    case yellow = "#E9B949"
    case purple = "#9B6DFF"
    case black = "#1D1D1F"
    case white = "#F5F5F7"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .blue: return "Azul"
        case .red: return "Vermelho"
        case .green: return "Verde"
        case .yellow: return "Amarelo"
        case .purple: return "Roxo"
        case .black: return "Preto"
        case .white: return "Branco"
        }
    }

    var color: Color {
        switch self {
        case .blue: return Color(red: 0.22, green: 0.53, blue: 1)
        case .red: return Color(red: 0.94, green: 0.31, blue: 0.31)
        case .green: return Color(red: 0.20, green: 0.65, blue: 0.42)
        case .yellow: return Color(red: 0.91, green: 0.72, blue: 0.29)
        case .purple: return Color(red: 0.61, green: 0.43, blue: 1)
        case .black: return Color(red: 0.11, green: 0.11, blue: 0.12)
        case .white: return Color(red: 0.96, green: 0.96, blue: 0.97)
        }
    }

    static func color(for hex: String?) -> Color {
        allCases.first(where: { $0.rawValue == hex })?.color ?? .accentColor
    }
}
