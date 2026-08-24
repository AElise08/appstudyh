import SwiftUI

struct StudySearchResult: Identifiable {
    enum Category: String, CaseIterable, Identifiable {
        case all = "Tudo"
        case materials = "Livros e materiais"
        case notes = "Notas, marcações e cadernos"

        var id: String { rawValue }
    }

    enum Destination {
        case material(UUID)
        case artifact(UUID, sourceNodeID: UUID?)
        case canvasNode(UUID)
        case annotation(nodeID: UUID, annotationID: UUID)
        case notebook(UUID)
    }

    let id: String
    let workspaceID: UUID
    let workspaceName: String
    let nodeTitle: String
    let destination: Destination
    let category: Category
    let title: String
    let snippet: String
    let pageIndex: Int?
    let quote: String?
    let sourceURL: String?

    var icon: String {
        switch destination {
        case .material: return "doc.text.magnifyingglass"
        case .artifact: return "note.text"
        case .canvasNode: return "rectangle.and.pencil.and.ellipsis"
        case .annotation: return "highlighter"
        case .notebook: return "books.vertical"
        }
    }
}

struct GlobalSearchView: View {
    let workspaces: [Workspace]
    let onOpen: (StudySearchResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var workspaceFilter: UUID?
    @State private var category: StudySearchResult.Category = .all

    private var results: [StudySearchResult] {
        StudySearchIndex.search(
            query: query,
            workspaces: workspaces,
            workspaceID: workspaceFilter,
            category: category
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Pesquisar em livros, materiais, notas e cadernos", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                Button("Fechar") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(14)

            Divider()

            HStack {
                Picker("Matéria", selection: $workspaceFilter) {
                    Text("Todas as matérias").tag(UUID?.none)
                    ForEach(workspaces) { workspace in
                        Text(workspace.name).tag(Optional(workspace.id))
                    }
                }
                .frame(maxWidth: 230)
                Picker("Tipo", selection: $category) {
                    ForEach(StudySearchResult.Category.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                Spacer()
                if query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 {
                    Text("\(results.count) resultado(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)

            Divider()

            if query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
                ContentUnavailableView(
                    "Pesquisa global",
                    systemImage: "text.magnifyingglass",
                    description: Text("Digite pelo menos duas letras para pesquisar em todas as matérias.")
                )
            } else if results.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List(results) { result in
                    Button {
                        onOpen(result)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Label(result.title, systemImage: result.icon)
                                    .font(.headline)
                                Spacer()
                                Text(result.workspaceName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(result.nodeTitle)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            highlightedSnippet(result.snippet)
                                .font(.callout)
                                .lineLimit(3)
                                .foregroundStyle(.primary)
                            if let page = result.pageIndex {
                                Text("Abrir na posição \(page + 1)")
                                    .font(.caption2)
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 680, minHeight: 560)
    }

    private func highlightedSnippet(_ text: String) -> Text {
        guard let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return Text(text)
        }
        return Text(text[..<range.lowerBound])
            + Text(text[range]).bold().foregroundColor(.accentColor)
            + Text(text[range.upperBound...])
    }
}

enum StudySearchIndex {
    static func search(
        query: String,
        workspaces: [Workspace],
        workspaceID: UUID?,
        category: StudySearchResult.Category
    ) -> [StudySearchResult] {
        let needle = normalized(query)
        guard needle.count >= 2 else { return [] }
        var results: [StudySearchResult] = []
        for workspace in workspaces where workspaceID == nil || workspace.id == workspaceID {
            let nodesByID = Dictionary(uniqueKeysWithValues: workspace.nodes.map { ($0.id, $0) })
            if category != .notes {
                for node in workspace.nodes {
                    let text = searchableText(node)
                    guard normalized(node.title + " " + text).contains(needle) else { continue }
                    results.append(StudySearchResult(
                        id: "material-\(workspace.id)-\(node.id)",
                        workspaceID: workspace.id,
                        workspaceName: workspace.name,
                        nodeTitle: node.title,
                        destination: .material(node.id),
                        category: .materials,
                        title: node.kind == .epub ? "Livro" : "Material",
                        snippet: snippet(in: text.isEmpty ? node.title : text, query: query),
                        pageIndex: matchingPage(in: node, query: query),
                        quote: nil,
                        sourceURL: node.kind == .web ? node.webURL : nil
                    ))
                }
            }
            if category != .materials {
                for note in workspace.studyArtifacts ?? [] where note.kind == .note {
                    let text = [note.sourceQuote, note.body].compactMap { $0 }.joined(separator: "\n")
                    guard normalized(text).contains(needle) else { continue }
                    let node = note.sourceNodeID.flatMap { nodesByID[$0] }
                    results.append(StudySearchResult(
                        id: "note-\(workspace.id)-\(note.id)",
                        workspaceID: workspace.id,
                        workspaceName: workspace.name,
                        nodeTitle: node?.title ?? "Nota sem material vinculado",
                        destination: .artifact(note.id, sourceNodeID: node?.id),
                        category: .notes,
                        title: "Nota",
                        snippet: snippet(in: text, query: query),
                        pageIndex: note.sourcePageIndex,
                        quote: note.sourceQuote,
                        sourceURL: note.sourceURL
                    ))
                }
                for node in workspace.nodes {
                    for annotation in node.epubAnnotations ?? [] {
                        let text = annotation.quote + "\n" + (annotation.note ?? "")
                        guard normalized(text).contains(needle) else { continue }
                        results.append(StudySearchResult(
                            id: "annotation-\(workspace.id)-\(annotation.id)",
                            workspaceID: workspace.id,
                            workspaceName: workspace.name,
                            nodeTitle: node.title,
                            destination: .annotation(nodeID: node.id, annotationID: annotation.id),
                            category: .notes,
                            title: annotation.note?.isEmpty == false ? "Nota de trecho" : "Marcação",
                            snippet: snippet(in: text, query: query),
                            pageIndex: nil,
                            quote: annotation.quote,
                            sourceURL: nil
                        ))
                    }
                }
            }
            if category != .materials {
                for node in workspace.nodes where node.kind == .note {
                    let text = node.noteBody + "\n" + (node.inkRecognizedText ?? "")
                    guard normalized(node.title + " " + text).contains(needle) else { continue }
                    results.append(StudySearchResult(
                        id: "canvas-note-\(workspace.id)-\(node.id)",
                        workspaceID: workspace.id,
                        workspaceName: workspace.name,
                        nodeTitle: node.title,
                        destination: .canvasNode(node.id),
                        category: .notes,
                        title: "Nota da mesa",
                        snippet: snippet(in: text, query: query),
                        pageIndex: nil,
                        quote: nil,
                        sourceURL: nil
                    ))
                }
            }
            if category != .materials {
                for notebook in workspace.notebooks ?? [] {
                    let text = notebook.title + "\n" + notebook.plainText
                    guard normalized(text).contains(needle) else { continue }
                    let material = notebook.sourceMaterialID.flatMap { nodesByID[$0] }
                    results.append(StudySearchResult(
                        id: "notebook-\(workspace.id)-\(notebook.id)",
                        workspaceID: workspace.id,
                        workspaceName: workspace.name,
                        nodeTitle: material?.title ?? "Sem material vinculado",
                        destination: .notebook(notebook.id),
                        category: .notes,
                        title: notebook.title,
                        snippet: snippet(in: notebook.plainText.isEmpty ? notebook.title : notebook.plainText, query: query),
                        pageIndex: notebook.sourcePageIndex,
                        quote: nil,
                        sourceURL: nil
                    ))
                }
            }
        }
        return Array(results.prefix(150))
    }

    private static func searchableText(_ node: CanvasNode) -> String {
        switch node.kind {
        case .epub: return node.epubText ?? node.epubVisibleText ?? ""
        case .pdf: return node.pdfText ?? node.pdfVisibleText
        case .web: return (node.webVisibleText ?? "") + "\n" + node.webURL
        case .slides: return (node.slidesPages ?? []).joined(separator: "\n")
        case .note: return node.noteBody + "\n" + (node.inkRecognizedText ?? "")
        case .calc: return node.calcBody
        }
    }

    private static func matchingPage(in node: CanvasNode, query: String) -> Int? {
        switch node.kind {
        case .epub:
            guard let text = node.epubText, !text.isEmpty,
                  let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
                return node.epubPageIndex
            }
            let offset = text.distance(from: text.startIndex, to: range.lowerBound)
            let total = max(1, node.epubPageCount ?? 1)
            return min(total - 1, Int(Double(offset) / Double(max(1, text.count)) * Double(total)))
        case .pdf: return node.pdfPageIndex
        case .slides:
            return node.slidesPages?.firstIndex {
                $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            } ?? node.slidesPageIndex
        case .web, .note, .calc: return nil
        }
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
    }

    private static func snippet(in text: String, query: String) -> String {
        let compact = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        guard let range = compact.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return String(compact.prefix(220))
        }
        let offset = compact.distance(from: compact.startIndex, to: range.lowerBound)
        let start = compact.index(compact.startIndex, offsetBy: max(0, offset - 80))
        let end = compact.index(start, offsetBy: min(260, compact.distance(from: start, to: compact.endIndex)))
        return (start > compact.startIndex ? "…" : "") + compact[start..<end] + (end < compact.endIndex ? "…" : "")
    }
}
