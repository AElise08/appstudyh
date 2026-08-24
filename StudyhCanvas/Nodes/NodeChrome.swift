import SwiftUI

struct NodeChrome: View {
    @Binding var node: CanvasNode
    var selected: Bool
    var scale: CGFloat
    var onSelect: () -> Void
    var onBringForward: () -> Void
    var onDelete: () -> Void
    var onInspect: () -> Void
    var onOpen: () -> Void
    var onDragStart: () -> Void
    var onDrag: (CGSize) -> Void
    var onResize: (CGSize) -> Void
    var onGestureEnd: () -> Void
    @State private var draggingHeader = false

    var body: some View {
        VStack(spacing: 0) {
            header
            nodeBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(nodeSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(selected ? Color.accentColor : Color.white.opacity(0.12), lineWidth: selected ? 2 : 1)
        )
        .overlay(alignment: .bottomTrailing) {
            ResizeHandle()
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .onChanged { value in
                            onResize(value.translation)
                        }
                        .onEnded { _ in onGestureEnd() }
                )
                .padding(6)
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(accent)
                .frame(width: 4)
        }
        .shadow(color: .black.opacity(0.28), radius: selected ? 16 : 8, y: 6)
        .onTapGesture {
            onSelect()
            onBringForward()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(node.kind.title): \(node.title)")
        .accessibilityValue(selected ? "Selecionado" : "Não selecionado")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
                .gesture(headerDragGesture)
                .help("Arraste para mover")
            Image(systemName: icon)
                .foregroundStyle(accent)
            TextField("Título", text: $node.title)
                .textFieldStyle(.plain)
                .font(.headline)
            if let priority = node.obsidian?.priority, !priority.isEmpty {
                Text(priority)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.18), in: Capsule())
            }
            if let status = node.obsidian?.status, !status.isEmpty {
                Text(status)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.14), in: Capsule())
            }
            Spacer()
            if node.isStudyMaterial || node.sourceMaterialID != nil {
                Button(action: onOpen) {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.plain)
                .foregroundStyle(accent)
                .help("Abrir no modo Estudar")
                .accessibilityLabel("Estudar \(node.title)")
            }
            Button(action: onInspect) {
                Image(systemName: "rectangle.trailinghalf.inset.filled")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Abrir ao lado")
            .accessibilityLabel("Abrir \(node.title) ao lado")
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Excluir nó")
            .accessibilityLabel("Excluir \(node.title)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(accent.opacity(0.13))
        .onTapGesture(count: 2) { onOpen() }
    }

    private var headerDragGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                if !draggingHeader {
                    draggingHeader = true
                    onDragStart()
                }
                onDrag(value.translation)
            }
            .onEnded { _ in
                draggingHeader = false
                onBringForward()
                onGestureEnd()
            }
    }

    @ViewBuilder
    private var nodeBody: some View {
        NodeContentView(node: $node)
    }

    private var icon: String {
        node.sourceArtifactKind == .flashcards ? "rectangle.on.rectangle.angled" : node.kind.icon
    }

    private var accent: Color {
        if let color = node.obsidian?.color {
            switch color {
            case "1": return .red
            case "2": return .orange
            case "3": return .yellow
            case "4": return .green
            case "5": return .cyan
            case "6": return .purple
            default: break
            }
        }
        if node.sourceArtifactKind == .flashcards { return .purple }
        if node.sourceArtifactKind == .note { return .yellow }
        switch node.kind {
        case .pdf: return .red
        case .epub: return .orange
        case .web: return .blue
        case .slides: return .purple
        case .note: return .yellow
        case .calc: return .green
        }
    }

    private var nodeSurface: some ShapeStyle {
        if node.kind == .note {
            return AnyShapeStyle(Color.yellow.opacity(0.08))
        }
        return AnyShapeStyle(.regularMaterial)
    }
}

struct NodeContentView: View {
    @Binding var node: CanvasNode
    var isActive: Bool = true

    @ViewBuilder
    var body: some View {
        Group {
            switch node.kind {
            case .note: NoteNodeView(node: $node)
            case .pdf: PDFNodeView(node: $node)
            case .epub: EPUBNodeView(node: $node)
            case .web: WebNodeView(node: $node, isActive: isActive)
            case .calc: CalcNodeView(node: $node)
            case .slides: SlidesNodeView(node: $node)
            }
        }
        .onAppear(perform: recordCurrentUnit)
        .onChange(of: currentUnitIndex) { _, _ in recordCurrentUnit() }
    }

    private var currentUnitIndex: Int? {
        switch node.kind {
        case .pdf: return node.pdfPageIndex
        case .epub: return node.epubPageIndex
        case .slides: return node.slidesPageIndex
        case .note, .web, .calc: return nil
        }
    }

    private func recordCurrentUnit() {
        guard let currentUnitIndex, currentUnitIndex >= 0 else { return }
        var visited = Set(node.visitedUnitIndices ?? [])
        guard visited.insert(currentUnitIndex).inserted else { return }
        node.visitedUnitIndices = visited.sorted()
    }
}

private struct ResizeHandle: View {
    var body: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.caption2)
            .padding(4)
            .background(.bar, in: RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
            .accessibilityLabel("Redimensionar nó")
    }
}
