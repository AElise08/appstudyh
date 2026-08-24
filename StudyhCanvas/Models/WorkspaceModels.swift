import Foundation
import CoreGraphics

enum NodeKind: String, Codable, CaseIterable, Identifiable {
    case note
    case pdf
    case epub
    case web
    case calc
    case slides

    var id: String { rawValue }

    static var allCases: [NodeKind] { [.note, .pdf, .web] }

    var title: String {
        switch self {
        case .note: return "Nota"
        case .pdf: return "PDF"
        case .epub: return "EPUB"
        case .web: return "Pesquisa"
        case .calc: return "Resolução"
        case .slides: return "Slides"
        }
    }

    var icon: String {
        switch self {
        case .note: return "note.text"
        case .pdf: return "doc.richtext"
        case .epub: return "books.vertical"
        case .web: return "globe"
        case .calc: return "pencil.and.scribble"
        case .slides: return "rectangle.split"
        }
    }
}

struct CanvasRect: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    static func `default`(for kind: NodeKind, origin: CGPoint) -> CanvasRect {
        let size: CGSize
        switch kind {
        case .note: size = CGSize(width: 280, height: 220)
        case .pdf: size = CGSize(width: 420, height: 560)
        case .epub: size = CGSize(width: 420, height: 560)
        case .web: size = CGSize(width: 480, height: 420)
        case .calc: size = CGSize(width: 380, height: 360)
        case .slides: size = CGSize(width: 520, height: 390)
        }
        return CanvasRect(x: origin.x, y: origin.y, width: size.width, height: size.height)
    }
}

struct InkPoint: Codable, Equatable {
    var x: Double
    var y: Double

    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

struct InkStroke: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var points: [InkPoint]
    var width: Double = 2.5
    var colorHex: String?
}

struct ObsidianMetadata: Codable, Equatable {
    var relativePath: String
    var vaultName: String
    var frontmatter: [String: String] = [:]
    var tags: [String] = []
    var status: String?
    var priority: String?
    var color: String?
    var isDailyNote: Bool = false
    var attachmentType: String?
    var importedAt: Date = Date()
}

enum CanvasConnectionKind: String, Codable {
    case wikilink
    case canvas
}

struct CanvasConnection: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var fromNodeID: UUID
    var toNodeID: UUID
    var label: String?
    var kind: CanvasConnectionKind
    var externalID: String?
    var color: String?
}

enum EPUBReaderTheme: String, Codable, CaseIterable, Identifiable {
    case automatic
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: return "Automático"
        case .light: return "Claro"
        case .dark: return "Escuro"
        }
    }
}

struct EPUBAnnotation: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var quote: String
    var note: String?
    var color: EPUBHighlightColor?
    var createdAt: Date = Date()
}

enum EPUBHighlightColor: String, Codable, CaseIterable, Identifiable {
    case yellow
    case green
    case blue
    case pink
    case purple

    var id: String { rawValue }

    var label: String {
        switch self {
        case .yellow: return "Amarelo"
        case .green: return "Verde"
        case .blue: return "Azul"
        case .pink: return "Rosa"
        case .purple: return "Roxo"
        }
    }

    var cssColor: String {
        switch self {
        case .yellow: return "#ffd95a"
        case .green: return "#8de29b"
        case .blue: return "#88c8ff"
        case .pink: return "#ff9fc5"
        case .purple: return "#c6a4ff"
        }
    }
}

struct CanvasNode: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: NodeKind
    var title: String
    var frame: CanvasRect
    var zIndex: Int
    var noteBody: String
    var pdfBookmark: Data?
    var pdfPageIndex: Int
    var pdfSelectedText: String
    var pdfVisibleText: String
    var pdfText: String?
    var pdfPageCount: Int?
    var pdfNavigationQuote: String?
    var epubBookmark: Data?
    var epubText: String?
    var epubPageIndex: Int?
    var epubFontSize: Double?
    var epubTheme: EPUBReaderTheme?
    var epubAnnotations: [EPUBAnnotation]?
    var epubVisibleText: String?
    var epubPageCount: Int?
    var webURL: String
    var webSelectedText: String
    var webVisibleText: String?
    var webNavigationQuote: String?
    var calcBody: String
    var inkStrokes: [InkStroke]?
    var inkRecognizedText: String?
    var slidesPages: [String]?
    var slidesPageIndex: Int?
    var slidesSelectedText: String?
    var slidesNavigationQuote: String?
    var visitedUnitIndices: [Int]?
    var sourceArtifactID: UUID?
    var sourceArtifactCardIndex: Int?
    var sourceArtifactKind: StudyArtifactKind?
    var sourceMaterialID: UUID?
    var sourcePageIndex: Int?
    var sourceQuote: String?
    var sourceURL: String?
    var obsidian: ObsidianMetadata?

    init(
        id: UUID = UUID(),
        kind: NodeKind,
        title: String? = nil,
        frame: CanvasRect,
        zIndex: Int = 0,
        noteBody: String = "",
        pdfBookmark: Data? = nil,
        pdfPageIndex: Int = 0,
        pdfSelectedText: String = "",
        pdfVisibleText: String = "",
        pdfText: String? = nil,
        pdfPageCount: Int? = nil,
        pdfNavigationQuote: String? = nil,
        epubBookmark: Data? = nil,
        epubText: String? = nil,
        epubPageIndex: Int? = nil,
        epubFontSize: Double? = nil,
        epubTheme: EPUBReaderTheme? = nil,
        epubAnnotations: [EPUBAnnotation]? = nil,
        epubVisibleText: String? = nil,
        epubPageCount: Int? = nil,
        webURL: String = "https://www.google.com",
        webSelectedText: String = "",
        webVisibleText: String? = nil,
        webNavigationQuote: String? = nil,
        calcBody: String = "",
        inkStrokes: [InkStroke]? = nil,
        inkRecognizedText: String? = nil,
        slidesPages: [String]? = nil,
        slidesPageIndex: Int? = nil,
        slidesSelectedText: String? = nil,
        slidesNavigationQuote: String? = nil,
        visitedUnitIndices: [Int]? = nil,
        sourceArtifactID: UUID? = nil,
        sourceArtifactCardIndex: Int? = nil,
        sourceArtifactKind: StudyArtifactKind? = nil,
        sourceMaterialID: UUID? = nil,
        sourcePageIndex: Int? = nil,
        sourceQuote: String? = nil,
        sourceURL: String? = nil,
        obsidian: ObsidianMetadata? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title ?? kind.title
        self.frame = frame
        self.zIndex = zIndex
        self.noteBody = noteBody
        self.pdfBookmark = pdfBookmark
        self.pdfPageIndex = pdfPageIndex
        self.pdfSelectedText = pdfSelectedText
        self.pdfVisibleText = pdfVisibleText
        self.pdfText = pdfText
        self.pdfPageCount = pdfPageCount
        self.pdfNavigationQuote = pdfNavigationQuote
        self.epubBookmark = epubBookmark
        self.epubText = epubText
        self.epubPageIndex = epubPageIndex
        self.epubFontSize = epubFontSize
        self.epubTheme = epubTheme
        self.epubAnnotations = epubAnnotations
        self.epubVisibleText = epubVisibleText
        self.epubPageCount = epubPageCount
        self.webURL = webURL
        self.webSelectedText = webSelectedText
        self.webVisibleText = webVisibleText
        self.webNavigationQuote = webNavigationQuote
        self.calcBody = calcBody
        self.inkStrokes = inkStrokes
        self.inkRecognizedText = inkRecognizedText
        self.slidesPages = slidesPages
        self.slidesPageIndex = slidesPageIndex
        self.slidesSelectedText = slidesSelectedText
        self.slidesNavigationQuote = slidesNavigationQuote
        self.visitedUnitIndices = visitedUnitIndices
        self.sourceArtifactID = sourceArtifactID
        self.sourceArtifactCardIndex = sourceArtifactCardIndex
        self.sourceArtifactKind = sourceArtifactKind
        self.sourceMaterialID = sourceMaterialID
        self.sourcePageIndex = sourcePageIndex
        self.sourceQuote = sourceQuote
        self.sourceURL = sourceURL
        self.obsidian = obsidian
    }

    var contextExcerpt: String {
        switch kind {
        case .note:
            return joinedText(noteBody, inkRecognizedText)
        case .pdf:
            let selected = pdfSelectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !selected.isEmpty { return selected }
            return pdfVisibleText
        case .epub:
            return epubCurrentPageContext
        case .web:
            let selected = webSelectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !selected.isEmpty { return selected }
            let visible = webVisibleText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return visible.isEmpty ? webURL : visible
        case .calc:
            return joinedText(calcBody, inkRecognizedText)
        case .slides:
            let selected = slidesSelectedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return selected.isEmpty ? slidesCurrentPageContext : "[Slide: seleção do estudante]\n\(selected)"
        }
    }

    private var slidesCurrentPageContext: String {
        guard let pages = slidesPages, !pages.isEmpty else { return "" }
        let index = min(max(0, slidesPageIndex ?? 0), pages.count - 1)
        return "Slide \(index + 1) de \(pages.count)\n\(pages[index])"
    }

    var isStudyMaterial: Bool {
        kind == .pdf || kind == .epub || kind == .web || kind == .slides
    }

    var flashcardContext: String {
        switch kind {
        case .epub:
            return epubProgressContext
        case .pdf:
            let selected = pdfSelectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = selected.isEmpty ? pdfVisibleText : selected
            return "[PDF: somente página atual \(pdfPageIndex + 1)]\n\(text)"
        case .web:
            let selected = webSelectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !selected.isEmpty else { return "" }
            return "[Web: somente seleção explícita do estudante]\n\(selected)"
        case .slides:
            return slidesCurrentPageContext
        case .note, .calc:
            return contextExcerpt
        }
    }

    var epubProgressContext: String {
        guard kind == .epub else { return contextExcerpt }
        let fullText = epubText ?? ""
        let totalPages = max(1, epubPageCount ?? 1)
        let page = min(max(0, epubPageIndex ?? 0), totalPages - 1)
        let visible = epubVisibleText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let anchor = epubAnchorOffset(in: fullText, visibleText: visible)
        // Stop at the start of the currently visible paragraph, then append only
        // what WebKit reports on screen. Never infer a forward window from page
        // proportions: layout, images and font size make that leak future text.
        let readEnd = min(fullText.count, anchor)
        let previous = excerpt(in: fullText, around: readEnd, before: 18_000, after: 0)
        let recent = visible.isEmpty
            ? previous
            : previous + "\n\n[Página visível agora]\n" + visible
        let relevantAnnotations = Array((epubAnnotations ?? []).filter { annotation in
            guard let range = fullText.range(of: annotation.quote) else { return false }
            return fullText.distance(from: fullText.startIndex, to: range.lowerBound) <= readEnd
        }.suffix(12))
        return formattedEPUBContext(
            heading: "Conteúdo lido até a página \(page + 1) de \(totalPages)",
            text: recent,
            annotations: relevantAnnotations
        )
    }

    /// Context used for questions about sequence ("depois", "em seguida", etc.).
    /// The visible page alone cannot answer those questions, so include a generous
    /// continuation after the current anchor while keeping the previous context
    /// short enough for the local model.
    var epubQuestionContext: String {
        guard kind == .epub else { return contextExcerpt }
        let fullText = epubText ?? ""
        let totalPages = max(1, epubPageCount ?? 1)
        let page = min(max(0, epubPageIndex ?? 0), totalPages - 1)
        let visible = epubVisibleText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let anchor = epubAnchorOffset(in: fullText, visibleText: visible)
        let previous = excerpt(in: fullText, around: anchor, before: 1_200, after: 500)
        let continuation = excerpt(in: fullText, around: anchor + 500, before: 0, after: 4_600)
        // For a direct question, keep only the marks on this page. Including all
        // previous highlights can push the continuation out of the model window.
        var relevantAnnotations = (epubAnnotations ?? []).filter { annotation in
            let sample = String(annotation.quote.prefix(60))
            return !sample.isEmpty && visible.localizedCaseInsensitiveContains(sample)
        }
        if relevantAnnotations.isEmpty {
            // WebKit can report the page text before restored <mark> elements are
            // included in visibleText. Fall back to annotations close to the
            // current page anchor so a question about a highlight still has its
            // exact quote and note.
            relevantAnnotations = (epubAnnotations ?? [])
                .compactMap { annotation -> (EPUBAnnotation, Int)? in
                    guard let range = fullText.range(of: annotation.quote) else { return nil }
                    let offset = fullText.distance(from: fullText.startIndex, to: range.lowerBound)
                    let distance = abs(offset - anchor)
                    return distance <= 3_000 ? (annotation, distance) : nil
                }
                .sorted { $0.1 < $1.1 }
                .prefix(4)
                .map(\.0)
        }
        var parts = ["[Livro: página atual \(page + 1) de \(totalPages)]"]
        parts.append(narrativePerspectiveContext(in: fullText, around: anchor))
        if !relevantAnnotations.isEmpty {
            parts.append("[Destaque(s) atual(is) que o estudante pode estar mencionando]\n\(formattedAnnotations(relevantAnnotations))")
        }
        parts.append("[Trecho atual e contexto imediatamente anterior]\n\(previous)")
        parts.append("[Continuação imediatamente depois da página/trecho atual — use esta seção para perguntas com 'depois', 'em seguida' ou 'posteriormente']\n\(continuation)")
        return parts.joined(separator: "\n\n")
    }

    private var epubCurrentPageContext: String {
        let visible = epubVisibleText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let annotations = (epubAnnotations ?? []).filter { annotation in
            let sample = String(annotation.quote.prefix(60))
            return !sample.isEmpty && visible.localizedCaseInsensitiveContains(sample)
        }
        let fullText = epubText ?? ""
        let anchor = epubAnchorOffset(in: fullText, visibleText: visible)
        let narrativeContext = excerpt(in: fullText, around: anchor, before: 4_500, after: 500)
        var parts = [
            "[Página atual \((epubPageIndex ?? 0) + 1) de \(max(1, epubPageCount ?? 1))]"
        ]
        parts.append(narrativePerspectiveContext(in: fullText, around: anchor))
        parts += [
            "[Contexto narrativo imediatamente anterior e ao redor]\n\(narrativeContext)",
            "[Texto visível agora]\n\(visible.isEmpty ? String(fullText.prefix(900)) : visible)"
        ]
        if !annotations.isEmpty { parts.append(formattedAnnotations(annotations)) }
        return parts.joined(separator: "\n\n")
    }

    private func formattedEPUBContext(
        heading: String,
        text: String,
        annotations: [EPUBAnnotation]
    ) -> String {
        var parts = ["[\(heading)]"]
        if !annotations.isEmpty {
            parts.append(formattedAnnotations(annotations))
        }
        parts.append("[Texto]\n\(text)")
        return parts.joined(separator: "\n\n")
    }

    private func formattedAnnotations(_ annotations: [EPUBAnnotation]) -> String {
        let markings = annotations.map { annotation in
            var line = "• Destaque: \(annotation.quote)"
            if let note = annotation.note, !note.isEmpty {
                line += "\n  Nota do estudante: \(note)"
            }
            return line
        }.joined(separator: "\n")
        return "[Marcações e notas do estudante]\n\(markings)"
    }

    private func narrativePerspectiveContext(in text: String, around anchor: Int) -> String {
        // Perspective can change between chapters or framing sections. Inspect a
        // local window instead of assigning one narrator to the entire book.
        let local = excerpt(in: text, around: anchor, before: 3_000, after: 1_000)
        let narration = local
            .components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.hasPrefix("–") && !trimmed.hasPrefix("—")
            }
            .joined(separator: "\n")

        let firstPerson = markerCount(
            in: narration,
            pattern: #"(?iu)\b(eu|meu|minha|comigo|pensei|senti|percebi|descobri|fiquei|andei|exclamei|perguntei|respondi)\b"#
        )
        let thirdPerson = markerCount(
            in: narration,
            pattern: #"(?iu)\b(ele|ela|seu|sua|dele|dela|lhe|pensou|sentiu|percebeu|viu|Ransom)\b"#
        )

        if firstPerson >= 4 && firstPerson >= thirdPerson {
            var result = "[Perspectiva narrativa detectada no trecho atual]\nA narração desta seção está em primeira pessoa: existe um narrador-personagem que usa ‘eu’. Esta conclusão vale para o trecho atual, não automaticamente para o livro inteiro."
            // A name can be established a few pages away in the same framing
            // section, so search a bounded neighborhood only after confirming
            // that the current passage itself is first-person.
            let nearbySection = excerpt(in: text, around: anchor, before: 30_000, after: 30_000)
            if let evidence = firstPersonNarratorEvidence(in: nearbySection) {
                result += "\nA obra identifica localmente esse narrador-personagem como \(evidence.name).\n[Prova textual local]\n\(evidence.quote)"
            } else {
                result += "\nO nome desse narrador não está confirmado no contexto local fornecido; não invente nem importe um nome de outra seção."
            }
            return result
        }

        if thirdPerson >= 3 {
            return "[Perspectiva narrativa detectada no trecho atual]\nA narração desta seção está em terceira pessoa. Não importe o narrador-personagem de outra seção. A personagem cujos pensamentos e reações são acompanhados pode ser o foco da cena (focalizador) sem ser o narrador. Diferencie também essa personagem de quem está falando no diálogo."
        }

        return "[Perspectiva narrativa detectada no trecho atual]\nO contexto local não basta para confirmar se a narração está em primeira ou terceira pessoa. Não atribua um narrador pelo autor, pelo título ou por outra parte do livro; descreva apenas o que a fonte permite afirmar."
    }

    private func markerCount(in text: String, pattern: String) -> Int {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return 0 }
        return expression.numberOfMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        )
    }

    private func firstPersonNarratorEvidence(in text: String) -> (name: String, quote: String)? {
        // A nearby character addressing the first-person speaker by name is
        // usable evidence. This is deliberately generic and book-independent.
        let pattern = #"(?isu)(?:respondi eu|disse eu|perguntei|exclamei|falei|murmurei).{0,700}?(?:Ora,\s*)?([\p{Lu}][\p{L}'’-]{2,30}),\s+você\b"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
              ),
              let nameRange = Range(match.range(at: 1), in: text),
              let quoteRange = Range(match.range(at: 0), in: text) else {
            return nil
        }
        let name = String(text[nameRange])
        let fullQuote = String(text[quoteRange])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let quote = fullQuote.count > 760
            ? String(fullQuote.suffix(760))
            : fullQuote
        return (name, quote)
    }

    private func epubAnchorOffset(in fullText: String, visibleText: String) -> Int {
        for annotation in epubAnnotations ?? [] {
            let sample = String(annotation.quote.prefix(60))
            guard !sample.isEmpty,
                  visibleText.localizedCaseInsensitiveContains(sample),
                  let range = fullText.range(of: annotation.quote) else { continue }
            return fullText.distance(from: fullText.startIndex, to: range.lowerBound)
        }
        let totalPages = max(1, epubPageCount ?? 1)
        let page = min(max(0, epubPageIndex ?? 0), totalPages - 1)
        let estimated = min(
            fullText.count,
            Int(Double(fullText.count) * Double(page) / Double(totalPages))
        )
        let blocks = visibleText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 24 }
            .sorted { $0.count > $1.count }
            .prefix(8)
        var best: (offset: Int, distance: Int)?
        for block in blocks {
            let words = block.split(whereSeparator: \.isWhitespace).prefix(18)
            guard words.count >= 5 else { continue }
            let pattern = words
                .map { NSRegularExpression.escapedPattern(for: String($0)) }
                .joined(separator: #"\s+"#)
            guard let expression = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]
            ) else { continue }
            let range = NSRange(fullText.startIndex..., in: fullText)
            for match in expression.matches(in: fullText, range: range) {
                guard let swiftRange = Range(match.range, in: fullText) else { continue }
                let offset = fullText.distance(from: fullText.startIndex, to: swiftRange.lowerBound)
                let distance = abs(offset - estimated)
                if best == nil || distance < best!.distance {
                    best = (offset, distance)
                }
            }
        }
        return best?.offset ?? estimated
    }

    private func excerpt(
        in text: String,
        around anchor: Int,
        before: Int,
        after: Int
    ) -> String {
        guard !text.isEmpty else { return "" }
        let lowerOffset = max(0, min(text.count, anchor - before))
        let upperOffset = max(lowerOffset, min(text.count, anchor + after))
        let lower = text.index(text.startIndex, offsetBy: lowerOffset)
        let upper = text.index(text.startIndex, offsetBy: upperOffset)
        return String(text[lower..<upper])
    }

    private func joinedText(_ text: String, _ recognizedInk: String?) -> String {
        let ink = recognizedInk?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !ink.isEmpty else { return text }
        return "\(text)\n\n[Escrita reconhecida do desenho]\n\(ink)"
    }
}

enum StudyArtifactKind: String, Codable {
    case summary
    case userMessage
    case assistantMessage
    case flashcards
    case question
    case feedback
    case note

    var label: String {
        switch self {
        case .summary: return "Explicação"
        case .userMessage: return "Você"
        case .assistantMessage: return "Studyh"
        case .flashcards: return "Flashcards"
        case .question: return "Questão"
        case .feedback: return "Correção"
        case .note: return "Nota"
        }
    }

    var icon: String {
        switch self {
        case .summary: return "text.alignleft"
        case .userMessage: return "person.crop.circle"
        case .assistantMessage: return "apple.intelligence"
        case .flashcards: return "rectangle.on.rectangle.angled"
        case .question: return "questionmark.circle"
        case .feedback: return "checkmark.circle"
        case .note: return "square.and.pencil"
        }
    }
}

struct StudyArtifact: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var kind: StudyArtifactKind
    var body: String
    var sourceNodeID: UUID?
    var createdAt: Date = Date()
    var sourcePageIndex: Int? = nil
    var sourceQuote: String? = nil
    var sourceURL: String? = nil
    var updatedAt: Date? = nil
    var sourceExternalID: String? = nil
}

enum FlashcardRating: String, Codable, CaseIterable, Identifiable {
    case hard
    case good
    case easy

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hard: return "Difícil"
        case .good: return "Bom"
        case .easy: return "Fácil"
        }
    }
}

struct FlashcardReview: Identifiable, Codable, Equatable {
    var id: String { key }
    var key: String
    var sourceNodeID: UUID?
    var deckID: UUID?
    var dueAt: Date
    var intervalDays: Double
    var easeFactor: Double
    var repetitions: Int
    var lastRating: FlashcardRating?
    var lastReviewedAt: Date?
    var firstReviewedAt: Date?

    init(
        key: String,
        sourceNodeID: UUID?,
        deckID: UUID? = nil,
        dueAt: Date = Date(),
        intervalDays: Double = 0,
        easeFactor: Double = 2.5,
        repetitions: Int = 0,
        lastRating: FlashcardRating? = nil,
        lastReviewedAt: Date? = nil,
        firstReviewedAt: Date? = nil
    ) {
        self.key = key
        self.sourceNodeID = sourceNodeID
        self.deckID = deckID
        self.dueAt = dueAt
        self.intervalDays = intervalDays
        self.easeFactor = easeFactor
        self.repetitions = repetitions
        self.lastRating = lastRating
        self.lastReviewedAt = lastReviewedAt
        self.firstReviewedAt = firstReviewedAt
    }
}

struct StudyHistoryEntry: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var nodeID: UUID
    var openedAt: Date = Date()
    var pageIndex: Int?
}

enum StudyActivityKind: String, Codable {
    case openedMaterial
    case createdNote
    case reviewedFlashcard
    case reviewedQuestion
    case completedTask
}

struct StudyActivityEvent: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var kind: StudyActivityKind
    var nodeID: UUID?
    var artifactID: UUID?
    var occurredAt: Date = Date()
}

enum StudyTaskPriority: String, Codable, CaseIterable, Identifiable {
    case high
    case normal
    case low

    var id: String { rawValue }

    var label: String {
        switch self {
        case .high: return "Alta"
        case .normal: return "Normal"
        case .low: return "Baixa"
        }
    }
}

struct StudyTask: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var dueDate: Date
    var priority: StudyTaskPriority = .normal
    var isCompleted: Bool = false
    var createdAt: Date = Date()
}

struct StudyNotebook: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var rtfData: Data?
    var plainText: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var sourceMaterialID: UUID?
    var sourcePageIndex: Int?
}

struct StudyFocusSession: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var startedAt: Date
    var endedAt: Date
    var plannedMinutes: Int
    var completedMinutes: Int
    var intention: String
    var materialID: UUID?
}

struct Workspace: Identifiable, Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int?
    var id: UUID
    var name: String
    var nodes: [CanvasNode]
    var cameraX: Double
    var cameraY: Double
    var cameraScale: Double
    var updatedAt: Date
    var inkStrokes: [InkStroke]?
    var studyArtifacts: [StudyArtifact]?
    var flashcardReviews: [FlashcardReview]?
    var studyHistory: [StudyHistoryEntry]?
    var examDate: Date?
    var presentationDate: Date?
    var connections: [CanvasConnection]?
    var obsidianVaultBookmark: Data?
    var obsidianVaultName: String?
    var studyActivityEvents: [StudyActivityEvent]?
    var studyTasks: [StudyTask]?
    var notebooks: [StudyNotebook]?
    var focusSessions: [StudyFocusSession]?

    init(
        id: UUID = UUID(),
        name: String,
        nodes: [CanvasNode] = [],
        cameraX: Double = 0,
        cameraY: Double = 0,
        cameraScale: Double = 1,
        updatedAt: Date = Date(),
        inkStrokes: [InkStroke]? = nil,
        studyArtifacts: [StudyArtifact]? = nil,
        flashcardReviews: [FlashcardReview]? = nil,
        studyHistory: [StudyHistoryEntry]? = nil,
        examDate: Date? = nil,
        presentationDate: Date? = nil,
        connections: [CanvasConnection]? = nil,
        obsidianVaultBookmark: Data? = nil,
        obsidianVaultName: String? = nil,
        studyActivityEvents: [StudyActivityEvent]? = nil,
        studyTasks: [StudyTask]? = nil,
        notebooks: [StudyNotebook]? = nil,
        focusSessions: [StudyFocusSession]? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.name = name
        self.nodes = nodes
        self.cameraX = cameraX
        self.cameraY = cameraY
        self.cameraScale = cameraScale
        self.updatedAt = updatedAt
        self.inkStrokes = inkStrokes
        self.studyArtifacts = studyArtifacts
        self.flashcardReviews = flashcardReviews
        self.studyHistory = studyHistory
        self.examDate = examDate
        self.presentationDate = presentationDate
        self.connections = connections
        self.obsidianVaultBookmark = obsidianVaultBookmark
        self.obsidianVaultName = obsidianVaultName
        self.studyActivityEvents = studyActivityEvents
        self.studyTasks = studyTasks
        self.notebooks = notebooks
        self.focusSessions = focusSessions
    }
}

struct WorkspaceRemovalImpact: Equatable {
    var artifacts = 0
    var derivedNodes = 0
    var reviews = 0
    var historyEntries = 0
    var activityEvents = 0
    var focusSessions = 0
    var notebooks = 0

    var linkedRecordCount: Int {
        artifacts + derivedNodes + reviews + historyEntries + activityEvents + focusSessions + notebooks
    }
}

extension Workspace {
    func removalImpact(for nodeIDs: Set<UUID>) -> WorkspaceRemovalImpact {
        WorkspaceRemovalImpact(
            artifacts: (studyArtifacts ?? []).filter { $0.sourceNodeID.map(nodeIDs.contains) == true }.count,
            derivedNodes: nodes.filter { $0.sourceMaterialID.map(nodeIDs.contains) == true && !nodeIDs.contains($0.id) }.count,
            reviews: (flashcardReviews ?? []).filter { $0.sourceNodeID.map(nodeIDs.contains) == true }.count,
            historyEntries: (studyHistory ?? []).filter { nodeIDs.contains($0.nodeID) }.count,
            activityEvents: (studyActivityEvents ?? []).filter { $0.nodeID.map(nodeIDs.contains) == true }.count,
            focusSessions: (focusSessions ?? []).filter { $0.materialID.map(nodeIDs.contains) == true }.count,
            notebooks: (notebooks ?? []).filter { $0.sourceMaterialID.map(nodeIDs.contains) == true }.count
        )
    }

    @discardableResult
    mutating func removeNodesPreservingDependentContent(_ nodeIDs: Set<UUID>) -> WorkspaceRemovalImpact {
        let impact = removalImpact(for: nodeIDs)
        nodes.removeAll { nodeIDs.contains($0.id) }
        connections?.removeAll { nodeIDs.contains($0.fromNodeID) || nodeIDs.contains($0.toNodeID) }

        for index in nodes.indices where nodes[index].sourceMaterialID.map(nodeIDs.contains) == true {
            nodes[index].sourceMaterialID = nil
        }
        if var artifacts = studyArtifacts {
            for index in artifacts.indices where artifacts[index].sourceNodeID.map(nodeIDs.contains) == true {
                artifacts[index].sourceNodeID = nil
            }
            studyArtifacts = artifacts
        }
        if var reviews = flashcardReviews {
            for index in reviews.indices where reviews[index].sourceNodeID.map(nodeIDs.contains) == true {
                reviews[index].sourceNodeID = nil
            }
            flashcardReviews = reviews
        }
        studyHistory?.removeAll { nodeIDs.contains($0.nodeID) }
        if var events = studyActivityEvents {
            for index in events.indices where events[index].nodeID.map(nodeIDs.contains) == true {
                events[index].nodeID = nil
            }
            studyActivityEvents = events
        }
        if var sessions = focusSessions {
            for index in sessions.indices where sessions[index].materialID.map(nodeIDs.contains) == true {
                sessions[index].materialID = nil
            }
            focusSessions = sessions
        }
        if var savedNotebooks = notebooks {
            for index in savedNotebooks.indices where savedNotebooks[index].sourceMaterialID.map(nodeIDs.contains) == true {
                savedNotebooks[index].sourceMaterialID = nil
                savedNotebooks[index].sourcePageIndex = nil
            }
            notebooks = savedNotebooks
        }
        return impact
    }
}

enum WorkspaceDocumentError: Error, Equatable, LocalizedError {
    case invalidSchemaVersion
    case unsupportedSchemaVersion(found: Int, supported: Int)

    var errorDescription: String? {
        switch self {
        case .invalidSchemaVersion:
            return "A versão do workspace é inválida."
        case let .unsupportedSchemaVersion(found, supported):
            return "Este workspace usa a versão \(found), mas o aplicativo suporta até a versão \(supported)."
        }
    }
}

enum WorkspaceDocumentCodec {
    private struct Header: Decodable {
        var schemaVersion: Int

        private enum CodingKeys: String, CodingKey {
            case schemaVersion
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard container.contains(.schemaVersion) else {
                schemaVersion = 0
                return
            }
            guard try !container.decodeNil(forKey: .schemaVersion),
                  let version = try? container.decode(Int.self, forKey: .schemaVersion),
                  version >= 0 else {
                throw WorkspaceDocumentError.invalidSchemaVersion
            }
            schemaVersion = version
        }
    }

    static func decode(_ data: Data, using decoder: JSONDecoder) throws -> Workspace {
        let version = try decoder.decode(Header.self, from: data).schemaVersion
        guard version <= Workspace.currentSchemaVersion else {
            throw WorkspaceDocumentError.unsupportedSchemaVersion(
                found: version,
                supported: Workspace.currentSchemaVersion
            )
        }

        var workspace = try decoder.decode(Workspace.self, from: data)
        workspace.schemaVersion = Workspace.currentSchemaVersion
        return workspace
    }

    static func encode(_ workspace: Workspace, using encoder: JSONEncoder) throws -> Data {
        var current = workspace
        current.schemaVersion = Workspace.currentSchemaVersion
        return try encoder.encode(current)
    }
}

enum WorkspaceIndexError: Error, Equatable, LocalizedError {
    case invalidSchemaVersion
    case unsupportedSchemaVersion(found: Int, supported: Int)

    var errorDescription: String? {
        switch self {
        case .invalidSchemaVersion:
            return "A versão do índice é inválida."
        case let .unsupportedSchemaVersion(found, supported):
            return "Este índice usa a versão \(found), mas o aplicativo suporta até a versão \(supported)."
        }
    }
}

struct WorkspaceIndex: Codable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = currentSchemaVersion
    var workspaceIDs: [UUID]
    var selectedID: UUID?

    init(workspaceIDs: [UUID], selectedID: UUID?) {
        self.workspaceIDs = workspaceIDs
        self.selectedID = selectedID
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, workspaceIDs, selectedID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.schemaVersion) {
            guard try !container.decodeNil(forKey: .schemaVersion),
                  let version = try? container.decode(Int.self, forKey: .schemaVersion),
                  version >= 0 else {
                throw WorkspaceIndexError.invalidSchemaVersion
            }
            guard version <= Self.currentSchemaVersion else {
                throw WorkspaceIndexError.unsupportedSchemaVersion(
                    found: version,
                    supported: Self.currentSchemaVersion
                )
            }
            schemaVersion = version
        } else {
            schemaVersion = 0
        }
        workspaceIDs = try container.decode([UUID].self, forKey: .workspaceIDs)
        selectedID = try container.decodeIfPresent(UUID.self, forKey: .selectedID)
    }
}
