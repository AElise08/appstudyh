import Foundation

enum ObsidianExporter {
    static func export(_ workspaces: [Workspace], to vault: URL) throws -> URL {
        let root = vault.appendingPathComponent("Studyh", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var indexLines = ["# Studyh", "", "Exportado em \(Date().formatted(date: .long, time: .shortened)).", ""]

        for workspace in workspaces {
            let subjectName = safeName(workspace.name)
            let subjectDirectory = root.appendingPathComponent(subjectName, isDirectory: true)
            try FileManager.default.createDirectory(at: subjectDirectory, withIntermediateDirectories: true)
            indexLines.append("## \(workspace.name)")
            let artifacts = workspace.studyArtifacts ?? []
            for node in workspace.nodes where node.isStudyMaterial {
                let notes = artifacts.filter { $0.kind == .note && $0.sourceNodeID == node.id }
                let decks = artifacts.filter { $0.kind == .flashcards && $0.sourceNodeID == node.id }
                let annotations = (node.epubAnnotations ?? []).filter {
                    !$0.quote.isEmpty || !($0.note ?? "").isEmpty
                }
                guard !notes.isEmpty || !annotations.isEmpty || !decks.isEmpty else { continue }
                let fileName = safeName(node.title) + ".md"
                let fileURL = subjectDirectory.appendingPathComponent(fileName)
                var lines = [
                    "---",
                    "studyh_subject_id: \(workspace.id.uuidString)",
                    "studyh_material_id: \(node.id.uuidString)",
                    "subject: \"\(yaml(workspace.name))\"",
                    "material: \"\(yaml(node.title))\"",
                    "type: \(node.kind.rawValue)",
                    "tags: [studyh, \(safeTag(workspace.name))]",
                    "---",
                    "",
                    "# \(node.title)",
                    "",
                    "Matéria: [[\(workspace.name)]]"
                ]
                if node.kind == .web { lines.append("Fonte: \(node.webURL)") }
                lines += ["", "## Notas", ""]
                for note in notes.sorted(by: { $0.createdAt < $1.createdAt }) {
                    let page = note.sourcePageIndex.map { " · posição \($0 + 1)" } ?? ""
                    lines.append("### \(note.createdAt.formatted(date: .abbreviated, time: .shortened))\(page)")
                    if let quote = note.sourceQuote, !quote.isEmpty {
                        lines.append("> \(quote.replacingOccurrences(of: "\n", with: "\n> "))")
                    }
                    lines.append("")
                    lines.append(editableBody(note.body))
                    lines.append("")
                }
                for annotation in annotations.sorted(by: { $0.createdAt < $1.createdAt }) {
                    lines.append("### Trecho · \(annotation.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    lines.append("> \(annotation.quote.replacingOccurrences(of: "\n", with: "\n> "))")
                    if let note = annotation.note, !note.isEmpty { lines += ["", note] }
                    lines.append("")
                }
                if !decks.isEmpty {
                    lines += ["## Flashcards", "", "Formato compatível com plugins de repetição espaçada do Obsidian.", ""]
                    for deck in decks.sorted(by: { $0.createdAt < $1.createdAt }) {
                        for card in flashcards(in: deck.body) {
                            lines.append("\(card.front.replacingOccurrences(of: "\n", with: " ")):: \(card.back.replacingOccurrences(of: "\n", with: " "))")
                            lines.append("")
                        }
                    }
                }
                try lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
                indexLines.append("- [[\(subjectName)/\(safeName(node.title))|\(node.title)]]")
            }
            for node in workspace.nodes where node.kind == .note && !node.noteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let fileBase = "Nota - " + safeName(node.title)
                let fileURL = subjectDirectory.appendingPathComponent(fileBase + ".md")
                let markdown = """
                ---
                studyh_subject_id: \(workspace.id.uuidString)
                studyh_note_id: \(node.id.uuidString)
                subject: "\(yaml(workspace.name))"
                tags: [studyh, studyh-note, \(safeTag(workspace.name))]
                ---

                # \(node.title)

                \(node.noteBody)
                """
                try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
                indexLines.append("- [[\(subjectName)/\(fileBase)|\(node.title)]]")
            }
            for notebook in (workspace.notebooks ?? []) where !notebook.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let fileBase = "Caderno - " + safeName(notebook.title)
                let fileURL = subjectDirectory.appendingPathComponent(fileBase + ".md")
                let material = notebook.sourceMaterialID.flatMap { id in workspace.nodes.first { $0.id == id } }
                var lines = [
                    "---",
                    "studyh_subject_id: \(workspace.id.uuidString)",
                    "studyh_notebook_id: \(notebook.id.uuidString)",
                    "subject: \"\(yaml(workspace.name))\"",
                    "tags: [studyh, studyh-notebook, \(safeTag(workspace.name))]"
                ]
                if let material {
                    lines.append("studyh_material_id: \(material.id.uuidString)")
                }
                if let page = notebook.sourcePageIndex {
                    lines.append("studyh_page_index: \(page)")
                }
                lines += ["---", "", "# \(notebook.title)", "", "Matéria: [[\(workspace.name)]]"]
                if let material {
                    let position = notebook.sourcePageIndex.map { " · posição \($0 + 1)" } ?? ""
                    lines.append("Material: [[\(material.title)]]\(position)")
                }
                lines += ["", notebook.plainText]
                try lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
                indexLines.append("- [[\(subjectName)/\(fileBase)|\(notebook.title)]]")
            }
            indexLines.append("")
        }
        try indexLines.joined(separator: "\n").write(
            to: root.appendingPathComponent("Studyh Index.md"),
            atomically: true,
            encoding: .utf8
        )
        return root
    }

    private static func editableBody(_ body: String) -> String {
        let parts = body.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        return parts.count == 2 && parts[0].hasPrefix("[") ? String(parts[1]) : body
    }

    private static func flashcards(in body: String) -> [(front: String, back: String)] {
        guard let expression = try? NSRegularExpression(
            pattern: #"(?is)\*{0,2}Frente:\*{0,2}\s*(.*?)\s*\*{0,2}Verso:\*{0,2}\s*(.*?)(?=\n\s*\*{0,2}Frente:|\z)"#
        ) else { return [] }
        let range = NSRange(body.startIndex..., in: body)
        return expression.matches(in: body, range: range).compactMap { match in
            guard let frontRange = Range(match.range(at: 1), in: body),
                  let backRange = Range(match.range(at: 2), in: body) else { return nil }
            return (
                String(body[frontRange]).trimmingCharacters(in: .whitespacesAndNewlines),
                String(body[backRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private static func safeName(_ value: String) -> String {
        let cleaned = value.replacingOccurrences(of: #"[\\/:*?\"<>|]"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Sem título" : String(cleaned.prefix(120))
    }

    private static func safeTag(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^a-z0-9_-]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func yaml(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
