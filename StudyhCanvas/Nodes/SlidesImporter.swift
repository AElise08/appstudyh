import Foundation

enum SlidesImporter {
    static func extractPages(from url: URL) -> [String]? {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory
            .appendingPathComponent("Studyh-Slides-" + UUID().uuidString, isDirectory: true)
        defer { try? manager.removeItem(at: directory) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", url.path, directory.path]
        do {
            try process.run()
        } catch {
            return nil
        }
        let deadline = Date().addingTimeInterval(20)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }

        let slidesDirectory = directory.appendingPathComponent("ppt/slides", isDirectory: true)
        guard let files = try? manager.contentsOfDirectory(
            at: slidesDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let slideFiles = files
            .filter { $0.pathExtension.lowercased() == "xml" }
            .sorted { lhs, rhs in
                let left = Int(lhs.deletingPathExtension().lastPathComponent) ?? .max
                let right = Int(rhs.deletingPathExtension().lastPathComponent) ?? .max
                return left < right
            }
        guard !slideFiles.isEmpty else { return nil }

        var pages: [String] = []
        for file in slideFiles.prefix(500) {
            guard let parser = XMLParser(contentsOf: file) else { continue }
            let delegate = SlideTextParser()
            parser.delegate = delegate
            parser.parse()
            let text = delegate.texts
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            pages.append(text.isEmpty ? "(slide sem texto)" : String(text.prefix(8_000)))
        }
        return pages.allSatisfy(\.isEmpty) ? nil : pages
    }
}

private final class SlideTextParser: NSObject, XMLParserDelegate {
    private(set) var texts: [String] = []
    private var buffer = ""
    private var insideTextRun = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let localName = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if localName == "t" {
            insideTextRun = true
            buffer = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideTextRun { buffer += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let localName = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if localName == "t" {
            insideTextRun = false
            texts.append(buffer)
            buffer = ""
        }
    }
}
