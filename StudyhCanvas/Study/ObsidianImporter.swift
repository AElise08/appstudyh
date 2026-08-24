import Foundation

struct ObsidianImportSummary {
    var notes = 0
    var attachments = 0
    var flashcards = 0
    var tasks = 0
    var connections = 0

    var message: String {
        "\(notes) nota(s), \(attachments) anexo(s), \(flashcards) flashcard(s), \(tasks) tarefa(s) e \(connections) conexão(ões)."
    }
}

enum ObsidianImporter {
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp"]
    private static let attachmentExtensions: Set<String> = imageExtensions.union([
        "pdf", "epub", "ppt", "pptx", "doc", "docx", "xls", "xlsx", "csv", "txt", "rtf", "mp3", "m4a", "wav", "mp4", "mov"
    ])

    static func importVault(at vaultURL: URL, into workspace: inout Workspace) throws -> ObsidianImportSummary {
        let manager = FileManager.default
        let vaultName = vaultURL.lastPathComponent
        let bookmark = (try? vaultURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )) ?? (try? vaultURL.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ))
        workspace.obsidianVaultBookmark = bookmark
        workspace.obsidianVaultName = vaultName

        guard let enumerator = manager.enumerator(
            at: vaultURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { throw CocoaError(.fileReadUnknown) }

        let urls = enumerator.compactMap { $0 as? URL }
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .sorted { relativePath($0, vault: vaultURL) < relativePath($1, vault: vaultURL) }
        let markdownURLs = urls.filter { ["md", "markdown"].contains($0.pathExtension.lowercased()) }
        let attachmentURLs = urls.filter { attachmentExtensions.contains($0.pathExtension.lowercased()) }
        let canvasURLs = urls.filter { $0.pathExtension.lowercased() == "canvas" }

        var summary = ObsidianImportSummary()
        var pathToNodeID: [String: UUID] = [:]
        for node in workspace.nodes {
            if let path = node.obsidian?.relativePath {
                pathToNodeID[normalizedPath(path)] = node.id
            }
        }

        for url in markdownURLs {
            let path = relativePath(url, vault: vaultURL)
            let body = try String(contentsOf: url, encoding: .utf8)
            let parsed = parseMarkdown(body, relativePath: path, vaultName: vaultName)
            let id = upsertNode(
                path: path,
                kind: .note,
                title: parsed.title ?? url.deletingPathExtension().lastPathComponent,
                noteBody: body,
                sourceURL: url.path,
                metadata: parsed.metadata,
                workspace: &workspace
            )
            pathToNodeID[normalizedPath(path)] = id
            summary.notes += 1
            summary.tasks += MarkdownTaskParser.tasks(in: body, nodeID: id).count
            applyDates(parsed.metadata.frontmatter, to: &workspace)

            let externalID = "obsidian:\(normalizedPath(path)):flashcards"
            workspace.studyArtifacts?.removeAll { $0.sourceExternalID == externalID }
            let cards = parsed.flashcards
            if !cards.isEmpty {
                let deck = cards.map { "Frente: \($0.front)\nVerso: \($0.back)" }
                    .joined(separator: "\n\n")
                var artifacts = workspace.studyArtifacts ?? []
                artifacts.append(StudyArtifact(
                    kind: .flashcards,
                    body: deck,
                    sourceNodeID: id,
                    sourceExternalID: externalID
                ))
                workspace.studyArtifacts = artifacts
                summary.flashcards += cards.count
            }
        }

        for url in attachmentURLs {
            let path = relativePath(url, vault: vaultURL)
            let ext = url.pathExtension.lowercased()
            let metadata = ObsidianMetadata(
                relativePath: path,
                vaultName: vaultName,
                attachmentType: imageExtensions.contains(ext) ? "image" : ext
            )
            let id: UUID
            if ext == "pdf", let bookmark = fileBookmark(url) {
                id = upsertMaterial(path: path, kind: .pdf, title: url.deletingPathExtension().lastPathComponent, bookmark: bookmark, metadata: metadata, workspace: &workspace)
            } else if ext == "epub", let bookmark = fileBookmark(url) {
                id = upsertMaterial(path: path, kind: .epub, title: url.deletingPathExtension().lastPathComponent, bookmark: bookmark, metadata: metadata, workspace: &workspace)
            } else if ["ppt", "pptx"].contains(ext), let pages = SlidesImporter.extractPages(from: url) {
                id = upsertSlides(path: path, title: url.deletingPathExtension().lastPathComponent, pages: pages, metadata: metadata, workspace: &workspace)
            } else {
                let label = imageExtensions.contains(ext) ? "Imagem do vault" : "Anexo do vault"
                id = upsertNode(
                    path: path,
                    kind: .note,
                    title: url.lastPathComponent,
                    noteBody: "\(label)\n\n\(path)",
                    sourceURL: url.path,
                    metadata: metadata,
                    linkedKind: .note,
                    workspace: &workspace
                )
            }
            pathToNodeID[normalizedPath(path)] = id
            summary.attachments += 1
        }

        let basenameMap = buildBasenameMap(pathToNodeID)
        var importedConnections: [CanvasConnection] = []
        for url in markdownURLs {
            let path = relativePath(url, vault: vaultURL)
            guard let sourceID = pathToNodeID[normalizedPath(path)],
                  let body = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for target in wikiLinks(in: body) {
                guard let targetID = resolveWikiLink(target, sourcePath: path, paths: pathToNodeID, basenames: basenameMap),
                      targetID != sourceID else { continue }
                importedConnections.append(CanvasConnection(
                    fromNodeID: sourceID,
                    toNodeID: targetID,
                    label: nil,
                    kind: .wikilink,
                    externalID: "obsidian:wiki:\(normalizedPath(path)):\(normalizedPath(target))"
                ))
            }
        }

        for url in canvasURLs {
            importCanvas(
                url,
                vaultURL: vaultURL,
                vaultName: vaultName,
                pathToNodeID: &pathToNodeID,
                connections: &importedConnections,
                workspace: &workspace
            )
        }

        var connections = (workspace.connections ?? []).filter { $0.externalID?.hasPrefix("obsidian:") != true }
        var seen = Set<String>()
        for connection in importedConnections {
            let key = connection.externalID ?? "\(connection.fromNodeID)-\(connection.toNodeID)-\(connection.kind.rawValue)"
            guard seen.insert(key).inserted else { continue }
            connections.append(connection)
        }
        workspace.connections = connections
        summary.connections = importedConnections.count
        return summary
    }

    static func parseMarkdown(
        _ body: String,
        relativePath: String,
        vaultName: String
    ) -> (title: String?, metadata: ObsidianMetadata, flashcards: [(front: String, back: String)]) {
        let frontmatter = parseFrontmatter(body)
        let tags = parseTags(frontmatter["tags"] ?? "") + inlineTags(in: body)
        let filename = URL(fileURLWithPath: relativePath).deletingPathExtension().lastPathComponent
        let daily = filename.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
        let metadata = ObsidianMetadata(
            relativePath: relativePath,
            vaultName: vaultName,
            frontmatter: frontmatter,
            tags: Array(Set(tags)).sorted(),
            status: frontmatter["status"],
            priority: frontmatter["priority"] ?? frontmatter["prioridade"],
            isDailyNote: daily
        )
        return (frontmatter["title"] ?? frontmatter["titulo"], metadata, parseFlashcards(body))
    }

    private static func upsertNode(
        path: String,
        kind: NodeKind,
        title: String,
        noteBody: String,
        sourceURL: String,
        metadata: ObsidianMetadata,
        linkedKind: StudyArtifactKind? = nil,
        workspace: inout Workspace
    ) -> UUID {
        if let index = workspace.nodes.firstIndex(where: { normalizedPath($0.obsidian?.relativePath ?? "") == normalizedPath(path) }) {
            workspace.nodes[index].title = title
            workspace.nodes[index].noteBody = noteBody
            workspace.nodes[index].sourceURL = sourceURL
            workspace.nodes[index].sourceArtifactKind = linkedKind
            workspace.nodes[index].obsidian = metadata
            return workspace.nodes[index].id
        }
        let frame = nextFrame(kind: kind, count: workspace.nodes.count)
        let node = CanvasNode(
            kind: kind,
            title: title,
            frame: frame,
            zIndex: (workspace.nodes.map(\.zIndex).max() ?? 0) + 1,
            noteBody: noteBody,
            sourceArtifactKind: linkedKind,
            sourceURL: sourceURL,
            obsidian: metadata
        )
        workspace.nodes.append(node)
        return node.id
    }

    private static func upsertMaterial(
        path: String,
        kind: NodeKind,
        title: String,
        bookmark: Data,
        metadata: ObsidianMetadata,
        workspace: inout Workspace
    ) -> UUID {
        if let index = workspace.nodes.firstIndex(where: { normalizedPath($0.obsidian?.relativePath ?? "") == normalizedPath(path) }) {
            workspace.nodes[index].title = title
            workspace.nodes[index].obsidian = metadata
            if kind == .pdf { workspace.nodes[index].pdfBookmark = bookmark }
            if kind == .epub { workspace.nodes[index].epubBookmark = bookmark }
            return workspace.nodes[index].id
        }
        var node = CanvasNode(
            kind: kind,
            title: title,
            frame: nextFrame(kind: kind, count: workspace.nodes.count),
            zIndex: (workspace.nodes.map(\.zIndex).max() ?? 0) + 1,
            obsidian: metadata
        )
        if kind == .pdf { node.pdfBookmark = bookmark }
        if kind == .epub { node.epubBookmark = bookmark }
        workspace.nodes.append(node)
        return node.id
    }

    private static func upsertSlides(
        path: String,
        title: String,
        pages: [String],
        metadata: ObsidianMetadata,
        workspace: inout Workspace
    ) -> UUID {
        if let index = workspace.nodes.firstIndex(where: { normalizedPath($0.obsidian?.relativePath ?? "") == normalizedPath(path) }) {
            workspace.nodes[index].title = title
            workspace.nodes[index].slidesPages = pages
            workspace.nodes[index].obsidian = metadata
            return workspace.nodes[index].id
        }
        let node = CanvasNode(
            kind: .slides,
            title: title,
            frame: nextFrame(kind: .slides, count: workspace.nodes.count),
            zIndex: (workspace.nodes.map(\.zIndex).max() ?? 0) + 1,
            slidesPages: pages,
            slidesPageIndex: 0,
            obsidian: metadata
        )
        workspace.nodes.append(node)
        return node.id
    }

    private static func importCanvas(
        _ url: URL,
        vaultURL: URL,
        vaultName: String,
        pathToNodeID: inout [String: UUID],
        connections: inout [CanvasConnection],
        workspace: inout Workspace
    ) {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let canvasPath = relativePath(url, vault: vaultURL)
        var externalNodeIDs: [String: UUID] = [:]
        for raw in root["nodes"] as? [[String: Any]] ?? [] {
            guard let externalID = raw["id"] as? String,
                  let type = raw["type"] as? String else { continue }
            let nodeID: UUID?
            if type == "file", let file = raw["file"] as? String {
                nodeID = pathToNodeID[normalizedPath(file.removingPercentEncoding ?? file)]
            } else if type == "text" {
                let path = canvasPath + "#" + externalID
                let metadata = ObsidianMetadata(
                    relativePath: path,
                    vaultName: vaultName,
                    color: raw["color"] as? String,
                    attachmentType: "canvas-text"
                )
                nodeID = upsertNode(
                    path: path,
                    kind: .note,
                    title: "Cartão · \(url.deletingPathExtension().lastPathComponent)",
                    noteBody: raw["text"] as? String ?? "",
                    sourceURL: url.path,
                    metadata: metadata,
                    workspace: &workspace
                )
            } else if type == "link", let link = raw["url"] as? String {
                let path = canvasPath + "#" + externalID
                let metadata = ObsidianMetadata(relativePath: path, vaultName: vaultName, attachmentType: "canvas-link")
                nodeID = upsertNode(
                    path: path,
                    kind: .web,
                    title: URL(string: link)?.host ?? link,
                    noteBody: "",
                    sourceURL: link,
                    metadata: metadata,
                    workspace: &workspace
                )
                if let nodeID, let index = workspace.nodes.firstIndex(where: { $0.id == nodeID }) {
                    workspace.nodes[index].webURL = link
                }
            } else {
                nodeID = nil
            }
            guard let nodeID else { continue }
            externalNodeIDs[externalID] = nodeID
            if let index = workspace.nodes.firstIndex(where: { $0.id == nodeID }) {
                workspace.nodes[index].frame.x = raw["x"] as? Double ?? workspace.nodes[index].frame.x
                workspace.nodes[index].frame.y = raw["y"] as? Double ?? workspace.nodes[index].frame.y
                workspace.nodes[index].frame.width = max(200, raw["width"] as? Double ?? workspace.nodes[index].frame.width)
                workspace.nodes[index].frame.height = max(160, raw["height"] as? Double ?? workspace.nodes[index].frame.height)
                if let color = raw["color"] as? String { workspace.nodes[index].obsidian?.color = color }
            }
        }
        for raw in root["edges"] as? [[String: Any]] ?? [] {
            guard let externalID = raw["id"] as? String,
                  let from = raw["fromNode"] as? String,
                  let to = raw["toNode"] as? String,
                  let fromID = externalNodeIDs[from],
                  let toID = externalNodeIDs[to] else { continue }
            connections.append(CanvasConnection(
                fromNodeID: fromID,
                toNodeID: toID,
                label: raw["label"] as? String,
                kind: .canvas,
                externalID: "obsidian:canvas:\(normalizedPath(canvasPath)):\(externalID)",
                color: raw["color"] as? String
            ))
        }
    }

    private static func parseFrontmatter(_ body: String) -> [String: String] {
        let lines = body.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return [:] }
        var result: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !key.isEmpty { result[key] = value }
        }
        return result
    }

    private static func parseFlashcards(_ body: String) -> [(front: String, back: String)] {
        body.components(separatedBy: .newlines).compactMap { line in
            guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("http"),
                  let range = line.range(of: "::") else { return nil }
            let front = line[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            let back = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !front.isEmpty, !back.isEmpty else { return nil }
            return (front, back)
        }
    }

    private static func wikiLinks(in body: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: #"\[\[([^\]|#]+)(?:#[^\]|]+)?(?:\|[^\]]+)?\]\]"#) else { return [] }
        let range = NSRange(body.startIndex..., in: body)
        return expression.matches(in: body, range: range).compactMap { match in
            guard let target = Range(match.range(at: 1), in: body) else { return nil }
            return String(body[target]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func inlineTags(in body: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: #"(?<!\w)#([\p{L}\p{N}_/-]+)"#) else { return [] }
        let range = NSRange(body.startIndex..., in: body)
        return expression.matches(in: body, range: range).compactMap { match in
            Range(match.range(at: 1), in: body).map { String(body[$0]) }
        }
    }

    private static func parseTags(_ value: String) -> [String] {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
            .filter { !$0.isEmpty }
    }

    private static func resolveWikiLink(
        _ target: String,
        sourcePath: String,
        paths: [String: UUID],
        basenames: [String: UUID]
    ) -> UUID? {
        let targetWithoutExtension = normalizedPath((target as NSString).deletingPathExtension)
        if let exact = paths[targetWithoutExtension + ".md"] ?? paths[targetWithoutExtension] { return exact }
        let sourceFolder = (sourcePath as NSString).deletingLastPathComponent
        let relative = normalizedPath((sourceFolder as NSString).appendingPathComponent(targetWithoutExtension + ".md"))
        if let local = paths[relative] { return local }
        return basenames[URL(fileURLWithPath: targetWithoutExtension).lastPathComponent.lowercased()]
    }

    private static func buildBasenameMap(_ paths: [String: UUID]) -> [String: UUID] {
        var result: [String: UUID] = [:]
        var ambiguous = Set<String>()
        for (path, id) in paths {
            let key = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent.lowercased()
            if result[key] != nil { ambiguous.insert(key) } else { result[key] = id }
        }
        for key in ambiguous { result.removeValue(forKey: key) }
        return result
    }

    private static func applyDates(_ frontmatter: [String: String], to workspace: inout Workspace) {
        let formatter = ISO8601DateFormatter()
        func date(_ keys: [String]) -> Date? {
            for key in keys {
                guard let raw = frontmatter[key] else { continue }
                if let value = formatter.date(from: raw) { return value }
                if let value = DateFormatter.studyhDate.date(from: raw) { return value }
            }
            return nil
        }
        if let exam = date(["exam", "exam_date", "prova", "data_prova"]),
           workspace.examDate == nil || exam < workspace.examDate! {
            workspace.examDate = exam
        }
        if let presentation = date(["presentation", "presentation_date", "apresentacao", "data_apresentacao"]),
           workspace.presentationDate == nil || presentation < workspace.presentationDate! {
            workspace.presentationDate = presentation
        }
    }

    private static func fileBookmark(_ url: URL) -> Data? {
        (try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil))
            ?? (try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil))
    }

    private static func relativePath(_ url: URL, vault: URL) -> String {
        let root = vault.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(root) else { return url.lastPathComponent }
        return String(path.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func normalizedPath(_ path: String) -> String {
        var value = path.replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        if value.hasSuffix(".markdown") { value = String(value.dropLast(9)) + ".md" }
        return value
    }

    private static func nextFrame(kind: NodeKind, count: Int) -> CanvasRect {
        let base = CanvasRect.default(for: kind, origin: .zero)
        let column = count % 4
        let row = count / 4
        return CanvasRect(
            x: Double(column) * 360,
            y: Double(row) * 280,
            width: base.width,
            height: base.height
        )
    }
}

private extension DateFormatter {
    static let studyhDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
