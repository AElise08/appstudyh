import Foundation

struct MarkdownTask: Identifiable, Equatable {
    var id: String { "\(nodeID.uuidString):\(lineNumber)" }
    let nodeID: UUID
    let lineNumber: Int
    let title: String
    let isCompleted: Bool
    let dueDate: Date?
}

enum MarkdownTaskParser {
    static func tasks(in body: String, nodeID: UUID) -> [MarkdownTask] {
        let lines = body.components(separatedBy: .newlines)
        var fenced = false
        var result: [MarkdownTask] = []
        for (index, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                fenced.toggle()
                continue
            }
            guard !fenced,
                  let expression = try? NSRegularExpression(pattern: #"^\s*[-*+]\s+\[([ xX])\]\s+(.+)$"#),
                  let match = expression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let stateRange = Range(match.range(at: 1), in: line),
                  let titleRange = Range(match.range(at: 2), in: line) else { continue }
            let rawTitle = String(line[titleRange])
            result.append(MarkdownTask(
                nodeID: nodeID,
                lineNumber: index,
                title: removingDueDate(from: rawTitle),
                isCompleted: line[stateRange].lowercased() == "x",
                dueDate: dueDate(in: rawTitle)
            ))
        }
        return result
    }

    static func toggled(_ task: MarkdownTask, in body: String) -> String {
        var lines = body.components(separatedBy: .newlines)
        guard lines.indices.contains(task.lineNumber) else { return body }
        let replacement = task.isCompleted ? "[ ]" : "[x]"
        lines[task.lineNumber] = lines[task.lineNumber].replacingOccurrences(
            of: #"\[[ xX]\]"#,
            with: replacement,
            options: .regularExpression,
            range: lines[task.lineNumber].startIndex..<lines[task.lineNumber].endIndex
        )
        return lines.joined(separator: "\n")
    }

    private static func dueDate(in title: String) -> Date? {
        let patterns = [#"📅\s*(\d{4}-\d{2}-\d{2})"#, #"@due\((\d{4}-\d{2}-\d{2})\)"#]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  let match = expression.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
                  let range = Range(match.range(at: 1), in: title) else { continue }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            if let date = formatter.date(from: String(title[range])) { return date }
        }
        return nil
    }

    private static func removingDueDate(from title: String) -> String {
        title.replacingOccurrences(of: #"\s*(?:📅\s*\d{4}-\d{2}-\d{2}|@due\(\d{4}-\d{2}-\d{2}\))"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct MaterialProgressSnapshot: Identifiable {
    let id: UUID
    let title: String
    let kind: NodeKind
    let completed: Int?
    let total: Int?
    let noteCount: Int
    let dueCards: Int
    let covered: Int?

    var fraction: Double? {
        guard let completed, let total, total > 0 else { return nil }
        return min(1, Double(completed) / Double(total))
    }
}

struct FrameProgressSnapshot: Identifiable {
    let id: UUID
    let title: String
    let covered: Int
    let total: Int

    var fraction: Double? {
        total > 0 ? Double(covered) / Double(total) : nil
    }
}

struct WorkspaceProgressSnapshot {
    let completedUnits: Int
    let totalUnits: Int
    let materials: [MaterialProgressSnapshot]
    let tasks: [MarkdownTask]
    let noteCount: Int
    let markingCount: Int
    let deckCount: Int
    let flashcardCount: Int
    let dueCount: Int
    let newCount: Int
    let questionCount: Int
    let activitiesToday: Int
    let focusedMinutesToday: Int
    let recentActivity: [StudyActivityEvent]
    let coveredUnits: Int
    let coverableUnits: Int
    let practiceToday: Int
    let retentionFraction: Double?
    let frameSnapshots: [FrameProgressSnapshot]

    var fraction: Double? {
        totalUnits > 0 ? Double(completedUnits) / Double(totalUnits) : nil
    }

    var coverageFraction: Double? {
        coverableUnits > 0 ? Double(coveredUnits) / Double(coverableUnits) : nil
    }
}

struct FlashcardPlanItem: Equatable {
    let artifactID: UUID
    let due: Int
    let new: Int

    var total: Int { due + new }
}

enum ProgressMetrics {
    static let dailyNewCardLimit = 20

    static func snapshot(for workspace: Workspace, now: Date = Date(), calendar: Calendar = .current) -> WorkspaceProgressSnapshot {
        let artifacts = workspace.studyArtifacts ?? []
        let reviews = workspace.flashcardReviews ?? []
        var completedUnits = 0
        var totalUnits = 0
        var materialSnapshots: [MaterialProgressSnapshot] = []
        var allTasks: [MarkdownTask] = []
        var flashcardCount = 0
        var dueCount = 0
        var newCount = 0
        var coveredUnits = 0
        var coverableUnits = 0
        var coverageByNode: [UUID: (covered: Int, total: Int)] = [:]

        for deck in artifacts where deck.kind == .flashcards {
            let counts = flashcardCounts(for: deck, reviews: reviews, now: now)
            flashcardCount += counts.total
            dueCount += counts.due
            newCount += counts.new
        }

        for node in workspace.nodes {
            if node.kind == .note { allTasks += MarkdownTaskParser.tasks(in: node.noteBody, nodeID: node.id) }
            guard node.isStudyMaterial else { continue }
            let progress: (Int?, Int?)
            switch node.kind {
            case .epub:
                progress = (node.epubPageCount.map { min($0, (node.epubPageIndex ?? 0) + 1) }, node.epubPageCount)
            case .pdf:
                progress = (node.pdfPageCount.map { min($0, node.pdfPageIndex + 1) }, node.pdfPageCount)
            case .slides:
                let total = node.slidesPages?.count
                progress = (total.map { min($0, (node.slidesPageIndex ?? 0) + 1) }, total)
            case .web:
                progress = (nil, nil)
            case .note, .calc:
                progress = (nil, nil)
            }
            if let completed = progress.0, let total = progress.1, total > 0 {
                completedUnits += completed
                totalUnits += total
            }
            let covered = node.visitedUnitIndices.map { indices in
                Set(indices.filter { $0 >= 0 && $0 < (progress.1 ?? 0) }).count
            }
            if let covered, let total = progress.1, total > 0 {
                coveredUnits += covered
                coverableUnits += total
                coverageByNode[node.id] = (covered, total)
            }
            let nodeArtifacts = artifacts.filter { $0.sourceNodeID == node.id }
            let decks = nodeArtifacts.filter { $0.kind == .flashcards }
            let nodeDue = decks.reduce(0) { result, deck in
                result + flashcardCounts(for: deck, reviews: reviews, now: now).due
            }
            materialSnapshots.append(MaterialProgressSnapshot(
                id: node.id,
                title: node.title,
                kind: node.kind,
                completed: progress.0,
                total: progress.1,
                noteCount: nodeArtifacts.filter { $0.kind == .note }.count + (node.epubAnnotations ?? []).filter { $0.note?.isEmpty == false }.count,
                dueCards: nodeDue,
                covered: covered
            ))
        }

        let activities = (workspace.studyActivityEvents ?? []).sorted { $0.occurredAt > $1.occurredAt }
        let frameSnapshots = (workspace.frames ?? []).map { frame -> FrameProgressSnapshot in
            let frameRect = frame.rect.cgRect
            var covered = 0
            var total = 0
            for node in workspace.nodes where node.isStudyMaterial {
                guard frameRect.intersects(node.frame.cgRect),
                      let nodeCoverage = coverageByNode[node.id] else { continue }
                covered += nodeCoverage.covered
                total += nodeCoverage.total
            }
            return FrameProgressSnapshot(id: frame.id, title: frame.title, covered: covered, total: total)
        }
        return WorkspaceProgressSnapshot(
            completedUnits: completedUnits,
            totalUnits: totalUnits,
            materials: materialSnapshots,
            tasks: allTasks,
            noteCount: artifacts.filter { $0.kind == .note }.count + workspace.nodes.filter {
                $0.kind == .note && $0.sourceArtifactKind != .flashcards && !$0.noteBody.isEmpty
            }.count,
            markingCount: workspace.nodes.reduce(0) { $0 + ($1.epubAnnotations?.count ?? 0) },
            deckCount: artifacts.filter { $0.kind == .flashcards }.count,
            flashcardCount: flashcardCount,
            dueCount: dueCount,
            newCount: newCount,
            questionCount: artifacts.filter { $0.kind == .question }.count,
            activitiesToday: activities.filter { calendar.isDate($0.occurredAt, inSameDayAs: now) }.count,
            focusedMinutesToday: (workspace.focusSessions ?? [])
                .filter { calendar.isDate($0.endedAt, inSameDayAs: now) }
                .reduce(0) { $0 + $1.completedMinutes },
            recentActivity: Array(activities.prefix(12)),
            coveredUnits: coveredUnits,
            coverableUnits: coverableUnits,
            practiceToday: activities.filter {
                calendar.isDate($0.occurredAt, inSameDayAs: now)
                    && ($0.kind == .reviewedFlashcard || $0.kind == .reviewedQuestion)
            }.count,
            retentionFraction: retentionFraction(reviews: reviews),
            frameSnapshots: frameSnapshots
        )
    }

    static func retentionFraction(reviews: [FlashcardReview]) -> Double? {
        let rated = reviews.compactMap(\.lastRating)
        guard !rated.isEmpty else { return nil }
        let successful = rated.filter { $0 == .good || $0 == .easy }.count
        return Double(successful) / Double(rated.count)
    }

    static func flashcardCounts(
        for artifact: StudyArtifact,
        reviews: [FlashcardReview],
        now: Date = Date()
    ) -> (total: Int, due: Int, new: Int) {
        let cards = StudyFlashcard.parseDeck(artifact.body) ?? []
        var due = 0
        var new = 0
        for card in cards {
            let review = reviews.first {
                ($0.key == card.id || $0.key == card.legacyID || $0.key == card.legacyFullID)
                    && $0.sourceNodeID == artifact.sourceNodeID
                    && ($0.deckID == artifact.id || $0.deckID == nil)
            }
            if let review {
                if review.dueAt <= now { due += 1 }
            } else {
                new += 1
            }
        }
        return (cards.count, due, new)
    }

    static func flashcardPlan(
        artifacts: [StudyArtifact],
        reviews: [FlashcardReview],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [FlashcardPlanItem] {
        let introducedToday = reviews.filter { review in
            let first = review.firstReviewedAt ?? review.lastReviewedAt
            return first.map { calendar.isDate($0, inSameDayAs: now) } == true
        }.count
        var remainingNew = max(0, dailyNewCardLimit - introducedToday)
        return artifacts
            .filter { $0.kind == .flashcards }
            .sorted { $0.createdAt < $1.createdAt }
            .map { artifact in
                let counts = flashcardCounts(for: artifact, reviews: reviews, now: now)
                let allowedNew = min(counts.new, remainingNew)
                remainingNew -= allowedNew
                return FlashcardPlanItem(artifactID: artifact.id, due: counts.due, new: allowedNew)
            }
    }
}

enum NotebookBlockConverter {
    static func flashcardBody(from paragraph: String) -> String? {
        let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var front = trimmed
        var back = ""
        for separator in ["\n", " — ", ": "] {
            if let range = trimmed.range(of: separator) {
                front = String(trimmed[..<range.lowerBound])
                back = String(trimmed[range.upperBound...])
                break
            }
        }
        front = front.trimmingCharacters(in: .whitespacesAndNewlines)
        back = back.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !front.isEmpty else { return nil }
        if back.isEmpty {
            guard let sentenceEnd = front.range(of: ". ") else { return nil }
            back = String(front[sentenceEnd.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            front = String(front[..<sentenceEnd.lowerBound])
            guard !back.isEmpty else { return nil }
        }
        return "Frente: \(front)\n\nVerso: \(back)"
    }

    static func questionBody(from paragraph: String) -> String? {
        let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func taskTitle(from paragraph: String) -> String? {
        let firstLine = paragraph
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstLine, !firstLine.isEmpty else { return nil }
        return String(firstLine.prefix(120))
    }
}

enum StudyTaskBoard {
    static func columns(for tasks: [StudyTask]) -> [StudyTaskPriority: [StudyTask]] {
        var result: [StudyTaskPriority: [StudyTask]] = [.high: [], .normal: [], .low: []]
        for task in tasks where !task.isCompleted {
            result[task.priority, default: []].append(task)
        }
        for (priority, columnTasks) in result {
            result[priority] = columnTasks.sorted {
                if $0.dueDate != $1.dueDate { return $0.dueDate < $1.dueDate }
                return $0.createdAt < $1.createdAt
            }
        }
        return result
    }
}

struct MatchingGame {
    struct Pair: Identifiable, Equatable {
        let id: String
        let front: String
        let back: String
    }

    let pairs: [Pair]
    let fronts: [String]
    let backs: [String]
    private let frontToPair: [String: String]
    private let backToPair: [String: String]

    static func make(from cards: [StudyFlashcard], limit: Int = 6) -> MatchingGame? {
        var seenFronts = Set<String>()
        var seenBacks = Set<String>()
        var pairs: [Pair] = []
        for card in cards {
            let front = card.front.trimmingCharacters(in: .whitespacesAndNewlines)
            let back = card.back.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !front.isEmpty, !back.isEmpty,
                  !seenFronts.contains(front), !seenBacks.contains(back) else { continue }
            seenFronts.insert(front)
            seenBacks.insert(back)
            pairs.append(Pair(id: card.id, front: front, back: back))
            if pairs.count == limit { break }
        }
        guard pairs.count >= 3 else { return nil }
        return MatchingGame(
            pairs: pairs,
            fronts: pairs.map(\.front).shuffled(),
            backs: pairs.map(\.back).shuffled(),
            frontToPair: Dictionary(uniqueKeysWithValues: pairs.map { ($0.front, $0.id) }),
            backToPair: Dictionary(uniqueKeysWithValues: pairs.map { ($0.back, $0.id) })
        )
    }

    func match(front: String, back: String) -> Bool {
        guard let frontID = frontToPair[front] else { return false }
        return frontID == backToPair[back]
    }
}

struct WordSearchPuzzle {
    enum Direction: CaseIterable {
        case right
        case left
        case down
        case up
        case downRight
        case downLeft
        case upRight
        case upLeft

        var delta: (row: Int, col: Int) {
            switch self {
            case .right: return (0, 1)
            case .left: return (0, -1)
            case .down: return (1, 0)
            case .up: return (-1, 0)
            case .downRight: return (1, 1)
            case .downLeft: return (1, -1)
            case .upRight: return (-1, 1)
            case .upLeft: return (-1, -1)
            }
        }
    }

    struct Coordinate: Equatable, Hashable {
        let row: Int
        let col: Int
    }

    struct Placement: Equatable {
        let word: String
        let start: Coordinate
        let direction: Direction

        var cells: [Coordinate] {
            let delta = direction.delta
            return (0..<word.count).map { offset in
                Coordinate(row: start.row + delta.row * offset, col: start.col + delta.col * offset)
            }
        }
    }

    let size: Int
    let grid: [[Character]]
    let placements: [Placement]

    static func normalize(_ word: String) -> String? {
        let folded = word.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
        let letters = folded.filter { $0.isASCII && $0.isLetter }
        guard letters.count >= 4, letters.count <= 12 else { return nil }
        return letters.uppercased()
    }

    static func vocabulary(from artifacts: [StudyArtifact]) -> [String] {
        var words: [String] = []
        for artifact in artifacts where artifact.kind == .flashcards {
            for card in StudyFlashcard.parseDeck(artifact.body) ?? [] {
                words.append(contentsOf: card.front.components(separatedBy: CharacterSet.alphanumerics.inverted))
            }
        }
        return words
    }

    static func make(from rawWords: [String], size: Int = 12, maxWords: Int = 6) -> WordSearchPuzzle? {
        var seen = Set<String>()
        var words: [String] = []
        for raw in rawWords {
            guard let normalized = normalize(raw), !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            words.append(normalized)
        }
        guard words.count >= 3, words.allSatisfy({ $0.count <= size }) else { return nil }
        words = Array(words.shuffled().prefix(maxWords)).sorted { $0.count > $1.count }

        var grid = Array(repeating: Array(repeating: Character(" "), count: size), count: size)
        var placements: [Placement] = []
        for word in words {
            var placed = false
            for _ in 0..<400 {
                let direction = Direction.allCases.randomElement() ?? .right
                let delta = direction.delta
                let rowRange: ClosedRange<Int>
                switch delta.row {
                case 1: rowRange = 0...(size - word.count)
                case -1: rowRange = (word.count - 1)...(size - 1)
                default: rowRange = 0...(size - 1)
                }
                let colRange: ClosedRange<Int>
                switch delta.col {
                case 1: colRange = 0...(size - word.count)
                case -1: colRange = (word.count - 1)...(size - 1)
                default: colRange = 0...(size - 1)
                }
                let start = Coordinate(
                    row: Int.random(in: rowRange),
                    col: Int.random(in: colRange)
                )
                guard canPlace(word, at: start, direction: direction, in: grid, size: size) else { continue }
                for (offset, letter) in word.enumerated() {
                    grid[start.row + delta.row * offset][start.col + delta.col * offset] = letter
                }
                placements.append(Placement(word: word, start: start, direction: direction))
                placed = true
                break
            }
            guard placed else { return nil }
        }
        let alphabet = Array("ABCDEFGHIJLMNOPQRSTUVXZ")
        for row in grid.indices {
            for col in grid[row].indices where grid[row][col] == " " {
                grid[row][col] = alphabet.randomElement() ?? "A"
            }
        }
        return WordSearchPuzzle(size: size, grid: grid, placements: placements)
    }

    private static func canPlace(
        _ word: String,
        at start: Coordinate,
        direction: Direction,
        in grid: [[Character]],
        size: Int
    ) -> Bool {
        let delta = direction.delta
        for (offset, letter) in word.enumerated() {
            let row = start.row + delta.row * offset
            let col = start.col + delta.col * offset
            guard row >= 0, row < size, col >= 0, col < size else { return false }
            let cell = grid[row][col]
            if cell != " ", cell != letter { return false }
        }
        return true
    }

    func word(from start: Coordinate, to end: Coordinate) -> String? {
        let deltaRow = end.row - start.row
        let deltaCol = end.col - start.col
        let straight = deltaRow == 0 || deltaCol == 0 || abs(deltaRow) == abs(deltaCol)
        guard straight, deltaRow != 0 || deltaCol != 0 else { return nil }
        let steps = max(abs(deltaRow), abs(deltaCol))
        let stepRow = deltaRow / steps
        let stepCol = deltaCol / steps
        var letters: [Character] = []
        for offset in 0...steps {
            let row = start.row + stepRow * offset
            let col = start.col + stepCol * offset
            guard row >= 0, row < size, col >= 0, col < size else { return nil }
            letters.append(grid[row][col])
        }
        let candidate = String(letters)
        if let placement = placements.first(where: { $0.word == candidate }) {
            return placement.word
        }
        if let placement = placements.first(where: { $0.word == String(candidate.reversed()) }) {
            return placement.word
        }
        return nil
    }

    func cells(for word: String) -> [Coordinate] {
        placements.first(where: { $0.word == word })?.cells ?? []
    }
}

enum StudyHTMLExporter {
    static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    static func export(workspace: Workspace, generatedAt: Date = Date()) -> String {
        let materialTitleByID = Dictionary(uniqueKeysWithValues: workspace.nodes.map { ($0.id, $0.title) })
        let artifacts = workspace.studyArtifacts ?? []

        var deckSections: [String] = []
        for deck in artifacts where deck.kind == .flashcards {
            guard let cards = StudyFlashcard.parseDeck(deck.body), !cards.isEmpty else { continue }
            let deckTitle = deck.sourceNodeID.flatMap { materialTitleByID[$0] } ?? "Baralho"
            let cardsHTML = cards.map { card in
                """
                <details class="card"><summary>\(escapeHTML(card.front))</summary><div class="back">\(escapeHTML(card.back))</div></details>
                """
            }.joined(separator: "\n")
            deckSections.append("<h3>\(escapeHTML(deckTitle))</h3>\n\(cardsHTML)")
        }

        var questionSections: [String] = []
        for question in artifacts where question.kind == .question {
            let lines = question.body.components(separatedBy: .newlines)
            var visible: [String] = []
            var answer: [String] = []
            for line in lines {
                let normalized = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "**", with: "")
                    .lowercased()
                if normalized.hasPrefix("gabarito") {
                    answer.append(line)
                } else {
                    visible.append(line)
                }
            }
            let visibleHTML = escapeHTML(visible.joined(separator: "\n"))
            let answerHTML = answer.isEmpty
                ? ""
                : "<details class=\"answer\"><summary>Ver gabarito</summary><p>\(escapeHTML(answer.joined(separator: "\n")))</p></details>"
            questionSections.append("<div class=\"question\"><p>\(visibleHTML)</p>\(answerHTML)</div>")
        }

        let decksHTML = deckSections.isEmpty
            ? "<p>Nenhum flashcard ainda. Crie flashcards no Estudar para revisá-los aqui.</p>"
            : deckSections.joined(separator: "\n")
        let questionsHTML = questionSections.isEmpty
            ? "<p>Nenhuma questão ainda. Crie questões no Estudar para praticá-las aqui.</p>"
            : questionSections.joined(separator: "\n")

        let formatter = ISO8601DateFormatter()
        return """
        <!DOCTYPE html>
        <html lang="pt-BR">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Studyh — \(escapeHTML(workspace.name))</title>
        <style>
        body { font-family: -apple-system, system-ui, sans-serif; max-width: 720px; margin: 0 auto; padding: 24px; background: #101418; color: #eef2f5; }
        h1 { font-size: 1.5rem; } h2 { font-size: 1.2rem; margin-top: 2rem; border-bottom: 1px solid #2a323b; padding-bottom: 6px; }
        h3 { font-size: 1rem; color: #9fb0bf; }
        .meta { color: #7a8894; font-size: .85rem; }
        details.card, .question, details.answer { background: #1a212a; border: 1px solid #2a323b; border-radius: 10px; padding: 12px 14px; margin: 8px 0; }
        summary { cursor: pointer; font-weight: 600; }
        .back, .question p { white-space: pre-wrap; margin: 8px 0 0; }
        details.answer summary { color: #8fd48f; font-weight: 500; font-size: .9rem; }
        </style>
        </head>
        <body>
        <h1>Studyh — \(escapeHTML(workspace.name))</h1>
        <p class="meta">Revisão gerada em \(formatter.string(from: generatedAt)). Toque em um flashcard para ver o verso.</p>
        <h2>Flashcards</h2>
        \(decksHTML)
        <h2>Questões</h2>
        \(questionsHTML)
        </body>
        </html>
        """
    }
}
