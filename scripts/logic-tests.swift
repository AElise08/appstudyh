
// MARK: - Pontes de acesso para testes (mesmo arquivo => private acessível)
private extension EPUBBookLoader {
    static func testBodyContent(from html: String) -> String { bodyContent(from: html) }
    static func testSanitize(_ html: String, relativeTo chapter: URL, in directory: URL) -> String {
        sanitize(html, relativeTo: chapter, in: directory)
    }
}

// MARK: - Studyh Logic Test Suite

var failures: [String] = []
var passes = 0

func check(_ name: String, _ condition: Bool) {
    if condition {
        passes += 1
    } else {
        failures.append(name)
        print("FAIL: \(name)")
    }
}

// 1. WorkspaceIndex
do {
    let legacy = "{\"workspaceIDs\":[\"11111111-2222-3333-4444-555555555555\"],\"selectedID\":null}"
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let idx = try decoder.decode(WorkspaceIndex.self, from: Data(legacy.utf8))
    check("indice legado decodifica", idx.workspaceIDs.count == 1 && idx.schemaVersion == 0)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let round = try decoder.decode(WorkspaceIndex.self, from: try encoder.encode(idx))
    check("indice roundtrip preserva dados", round.workspaceIDs == idx.workspaceIDs)
    let fresh = WorkspaceIndex(workspaceIDs: idx.workspaceIDs, selectedID: nil)
    let freshData = try encoder.encode(fresh)
    check("indice novo usa versao atual", try decoder.decode(WorkspaceIndex.self, from: freshData).schemaVersion == WorkspaceIndex.currentSchemaVersion)

    let future = "{\"schemaVersion\":2,\"workspaceIDs\":[],\"selectedID\":null}"
    do {
        _ = try decoder.decode(WorkspaceIndex.self, from: Data(future.utf8))
        check("indice futuro e rejeitado", false)
    } catch let error as WorkspaceIndexError {
        check("indice futuro e rejeitado", error == .unsupportedSchemaVersion(found: 2, supported: 1))
    }

    let invalid = "{\"schemaVersion\":null,\"workspaceIDs\":[],\"selectedID\":null}"
    do {
        _ = try decoder.decode(WorkspaceIndex.self, from: Data(invalid.utf8))
        check("indice invalido e rejeitado", false)
    } catch let error as WorkspaceIndexError {
        check("indice invalido e rejeitado", error == .invalidSchemaVersion)
    }
} catch {
    check("indice decode inesperado: \(error)", false)
}

// 1b. Documento de workspace versionado
do {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let original = Workspace(name: "Workspace versionado", cameraX: 42, cameraY: -7, cameraScale: 1.5)
    let currentData = try WorkspaceDocumentCodec.encode(original, using: encoder)
    var object = try JSONSerialization.jsonObject(with: currentData) as! [String: Any]

    check("workspace novo usa versao atual", object["schemaVersion"] as? Int == Workspace.currentSchemaVersion)
    check("workspace versionado preserva formato plano", object["id"] != nil && object["name"] != nil && object["workspace"] == nil)

    object.removeValue(forKey: "schemaVersion")
    let legacyData = try JSONSerialization.data(withJSONObject: object)
    let legacy = try WorkspaceDocumentCodec.decode(legacyData, using: decoder)
    check("workspace legado sem versao decodifica", legacy.id == original.id && legacy.name == original.name)
    check("workspace legado normaliza versao em memoria", legacy.schemaVersion == Workspace.currentSchemaVersion)

    object["campoFuturoDesconhecido"] = "preservar compatibilidade aditiva"
    let additiveData = try JSONSerialization.data(withJSONObject: object)
    check("workspace ignora campo desconhecido", try WorkspaceDocumentCodec.decode(additiveData, using: decoder).id == original.id)

    object["schemaVersion"] = Workspace.currentSchemaVersion + 1
    let futureData = try JSONSerialization.data(withJSONObject: object)
    do {
        _ = try WorkspaceDocumentCodec.decode(futureData, using: decoder)
        check("workspace futuro e rejeitado", false)
    } catch let error as WorkspaceDocumentError {
        check(
            "workspace futuro e rejeitado",
            error == .unsupportedSchemaVersion(
                found: Workspace.currentSchemaVersion + 1,
                supported: Workspace.currentSchemaVersion
            )
        )
    }

    for invalidVersion: Any in [-1, "1", NSNull()] {
        object["schemaVersion"] = invalidVersion
        let invalidData = try JSONSerialization.data(withJSONObject: object)
        do {
            _ = try WorkspaceDocumentCodec.decode(invalidData, using: decoder)
            check("workspace rejeita versao invalida \(invalidVersion)", false)
        } catch let error as WorkspaceDocumentError {
            check("workspace rejeita versao invalida \(invalidVersion)", error == .invalidSchemaVersion)
        }
    }
} catch {
    check("workspace versionado inesperado: \(error)", false)
}

// 2. ParseDeck
let deckBody = "Frente: Capital do Brasil?\nVerso: Brasília\n\nFrente: 2+2\nVerso: 4"
fileprivate let deck = StudyFlashcard.parseDeck(deckBody)
check("parseDeck conta cartoes", deck?.count == 2)
check("parseDeck frente", deck?.first?.front == "Capital do Brasil?")
check("parseDeck verso", deck?.first?.back == "Brasília")
check("parseDeck invalido retorna nil", StudyFlashcard.parseDeck("sem cartoes aqui") == nil)

// 3. Chaves SRS
if let card = deck?.first {
    let newKey = flashcardKey(front: card.front, back: card.back)
    check("chave SRS estavel", flashcardKey(front: card.front, back: card.back) == newKey)
    let legacyFull = legacyFlashcardKey(front: card.front, back: card.back)
    check("chave nova difere da legada", newKey != legacyFull)
    let storedReview = FlashcardReview(key: legacyFull, sourceNodeID: nil)
    let matches = storedReview.key == card.id || storedReview.key == card.legacyID || storedReview.key == card.legacyFullID
    check("progresso antigo migra", matches)
}

// 4. Normalizacao
check("normalizacao de texto", normalizedFlashcardText("  Café   COM leite ") == "cafe com leite")

// 5. Multipla escolha
let questionBody = """
**Pergunta:** Qual é a função da mitocôndria?
A) Fotossíntese
B) Respiração celular
C) Digestão
D) Transporte
Gabarito: B
"""
fileprivate let parsedQuestion = MultipleChoiceQuestion.parse(questionBody)
check("questao opcoes", parsedQuestion?.options.count == 4)
check("questao gabarito", parsedQuestion?.correctLabel == "B")
check("questao enunciado", parsedQuestion?.stem.contains("mitocôndria") == true)

// 6. Gabarito oculto
let visible = visibleQuestionBody(questionBody)
check("gabarito oculto ao estudante", !visible.lowercased().contains("gabarito"))
check("enunciado preservado", visible.contains("mitocôndria"))

// 7. bodyContent
let sampleHTML = "<html><head><style>p{}</style></head><body><h1>Título</h1><p>Parágrafo.</p></body></html>"
check("bodyContent extrai corpo", EPUBBookLoader.testBodyContent(from: sampleHTML).contains("<h1>Título</h1>"))
check("bodyContent sem body devolve original", EPUBBookLoader.testBodyContent(from: "<div>só isso</div>").contains("só isso"))

// 8. Sanitizacao de EPUB
do {
    let tmpDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("studyh-sanitize-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: tmpDir.appendingPathComponent("cover.jpg").path, contents: Data([0xFF, 0xD8]))
    let chapter = tmpDir.appendingPathComponent("ch1.xhtml")

    let dirty = "<p>Olá</p><script>alert('x')</script>" +
        "<div onmouseover=\"evil()\">trecho</div>" +
        "<img src=\"cover.jpg\">" +
        "<a href=\"https://evil.example\">link ruim</a>" +
        "<iframe src=\"https://evil.example\"></iframe>"
    let cleaned = EPUBBookLoader.testSanitize(dirty, relativeTo: chapter, in: tmpDir)

    check("script removido", !cleaned.contains("alert") && !cleaned.lowercased().contains("<script"))
    check("iframe removido", !cleaned.lowercased().contains("iframe"))
    check("atributo on removido", !cleaned.contains("onmouseover"))
    check("imagem local preservada", cleaned.contains("cover.jpg"))
    check("link remoto removido", !cleaned.contains("evil.example"))
    check("texto preservado", cleaned.contains("Olá") && cleaned.contains("trecho"))

    try? FileManager.default.removeItem(at: tmpDir)
} catch {
    check("sanitizacao inesperado: \(error)", false)
}

// 9. PedagogicalResponseGuard
let guarded = PedagogicalResponseGuard.sanitize(
    "O trecho mostra que a água ferve a 100 °C.",
    mode: .explain,
    context: "A água ferve a 100 °C ao nível do mar."
)
check("guard devolve resposta", !guarded.isEmpty)

// 10. Contexto de progresso do EPUB
let visiblePage = "Esta frase única está exatamente na página que o estudante está lendo agora."
var progressNode = CanvasNode(kind: .epub, frame: .default(for: .epub, origin: .zero))
progressNode.epubText = String(repeating: "conteúdo anterior já lido. ", count: 500)
    + "\n\n" + visiblePage
    + "\n\nSEGREDO POSTERIOR QUE AINDA NÃO FOI LIDO."
progressNode.epubVisibleText = visiblePage
progressNode.epubPageIndex = 8
progressNode.epubPageCount = 20
let progressContext = progressNode.epubProgressContext
check("contexto inclui pagina visivel", progressContext.contains(visiblePage))
check("contexto exclui texto posterior", !progressContext.contains("SEGREDO POSTERIOR"))
let flashcardPrompt = StudyAssistantAction.flashcards.prompt(query: "", context: progressContext)
check("flashcards proibem conhecimento posterior", flashcardPrompt.contains("Nunca use acontecimentos") && flashcardPrompt.contains("treinamento"))

// 10b. Proveniência dos cartões da Mesa
do {
    let artifactID = UUID()
    let materialID = UUID()
    let linkedCard = CanvasNode(
        kind: .note,
        title: "Flashcard vinculado",
        frame: .default(for: .note, origin: .zero),
        noteBody: "Pergunta e resposta",
        sourceArtifactID: artifactID,
        sourceArtifactCardIndex: 2,
        sourceArtifactKind: .flashcards,
        sourceMaterialID: materialID,
        sourcePageIndex: 7,
        sourceQuote: "Trecho de origem"
    )
    let decoded = try JSONDecoder().decode(CanvasNode.self, from: JSONEncoder().encode(linkedCard))
    check("cartao da Mesa preserva origem", decoded.sourceArtifactID == artifactID && decoded.sourceMaterialID == materialID)
    check("cartao da Mesa preserva local exato", decoded.sourcePageIndex == 7 && decoded.sourceQuote == "Trecho de origem")
} catch {
    check("proveniencia da Mesa: \(error)", false)
}

// 11. Limite estrito em todos os formatos
var pdfProgress = CanvasNode(kind: .pdf, frame: .default(for: .pdf, origin: .zero))
pdfProgress.pdfVisibleText = "CONTEÚDO PDF LIDO"
pdfProgress.pdfText = "CONTEÚDO PDF LIDO\nSEGREDO PDF FUTURO"
check("flashcard PDF usa somente pagina atual", pdfProgress.flashcardContext.contains("CONTEÚDO PDF LIDO") && !pdfProgress.flashcardContext.contains("SEGREDO PDF FUTURO"))

var webProgress = CanvasNode(kind: .web, frame: .default(for: .web, origin: .zero))
webProgress.webVisibleText = "PÁGINA WEB INTEIRA COM CONTEÚDO NÃO SELECIONADO"
check("flashcard web exige selecao", webProgress.flashcardContext.isEmpty)
webProgress.webSelectedText = "TRECHO WEB ESCOLHIDO"
check("flashcard web limita selecao", webProgress.flashcardContext.contains("TRECHO WEB ESCOLHIDO") && !webProgress.flashcardContext.contains("NÃO SELECIONADO"))

var slidesProgress = CanvasNode(
    kind: .slides,
    frame: .default(for: .slides, origin: .zero),
    slidesPages: ["SLIDE LIDO", "SEGREDO DO PRÓXIMO SLIDE"],
    slidesPageIndex: 0
)
check("flashcard slides usa somente slide atual", slidesProgress.flashcardContext.contains("SLIDE LIDO") && !slidesProgress.flashcardContext.contains("SEGREDO"))

// 12. Baralhos independentes e compatibilidade
let deckA = UUID()
let deckB = UUID()
let sameMaterial = UUID()
let reviewA = FlashcardReview(key: "mesmo-cartao", sourceNodeID: sameMaterial, deckID: deckA)
let reviewB = FlashcardReview(key: "mesmo-cartao", sourceNodeID: sameMaterial, deckID: deckB)
check("baralhos possuem identidade independente", reviewA.deckID != reviewB.deckID)
do {
    let data = try JSONEncoder().encode(FlashcardReview(key: "legado", sourceNodeID: sameMaterial))
    let decoded = try JSONDecoder().decode(FlashcardReview.self, from: data)
    check("review legado sem baralho decodifica", decoded.deckID == nil)
} catch {
    check("review legado decodifica: \(error)", false)
}

// 13. Busca global e filtros
let searchableNode = CanvasNode(
    kind: .epub,
    title: "Biologia",
    frame: .default(for: .epub, origin: .zero),
    epubText: "A mitocôndria participa da respiração celular.",
    epubPageIndex: 2,
    epubPageCount: 10
)
let searchableNote = StudyArtifact(
    kind: .note,
    body: "[Biologia · pág. 3]\nRevisar a função da mitocôndria.",
    sourceNodeID: searchableNode.id,
    sourcePageIndex: 2
)
let searchableDeck = StudyArtifact(
    kind: .flashcards,
    body: "Frente: Função da mitocôndria?\nVerso: Respiração celular.",
    sourceNodeID: searchableNode.id,
    sourcePageIndex: 2
)
let searchableWorkspace = Workspace(
    name: "Ciências",
    nodes: [searchableNode],
    studyArtifacts: [searchableNote, searchableDeck]
)
let allSearch = StudySearchIndex.search(query: "mitocondria", workspaces: [searchableWorkspace], workspaceID: nil, category: .all)
let noteSearch = StudySearchIndex.search(query: "mitocondria", workspaces: [searchableWorkspace], workspaceID: nil, category: .notes)
check("busca encontra livro e nota", allSearch.count == 2)
check("filtro de busca mostra somente nota", noteSearch.count == 1 && noteSearch.first?.category == .notes)
check("filtro por materia exclui outra", StudySearchIndex.search(query: "mitocondria", workspaces: [searchableWorkspace], workspaceID: UUID(), category: .all).isEmpty)

// 14. Exportação Obsidian
do {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("studyh-obsidian-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let exported = try ObsidianExporter.export([searchableWorkspace], to: directory)
    let indexURL = exported.appendingPathComponent("Studyh Index.md")
    let materialURL = exported.appendingPathComponent("Ciências/Biologia.md")
    let markdown = try String(contentsOf: materialURL, encoding: .utf8)
    check("obsidian cria indice", FileManager.default.fileExists(atPath: indexURL.path))
    check("obsidian cria nota por material", markdown.contains("studyh_material_id") && markdown.contains("mitocôndria"))
    check("obsidian exporta flashcard compativel", markdown.contains("Função da mitocôndria?:: Respiração celular."))
    try? FileManager.default.removeItem(at: directory)
} catch {
    check("exportacao obsidian: \(error)", false)
}

// 15. Importação de vault Obsidian e Meu Progresso
do {
    let vault = FileManager.default.temporaryDirectory
        .appendingPathComponent("studyh-vault-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
    let mainMarkdown = """
    ---
    title: Resistência dos Materiais
    tags: [engenharia, prova]
    status: estudando
    priority: alta
    exam: 2026-09-10
    ---
    Relacionado a [[2026-08-22]].
    - [ ] Resolver lista 📅 2026-08-25
    Tensão normal:: Força dividida pela área.
    """
    let dailyMarkdown = """
    # Diário
    - [x] Ler o capítulo
    Voltar para [[Principal]].
    """
    try mainMarkdown.write(to: vault.appendingPathComponent("Principal.md"), atomically: true, encoding: .utf8)
    try dailyMarkdown.write(to: vault.appendingPathComponent("2026-08-22.md"), atomically: true, encoding: .utf8)
    try Data([0x89, 0x50, 0x4e, 0x47]).write(to: vault.appendingPathComponent("figura.png"))
    let canvas = """
    {"nodes":[
      {"id":"a","type":"file","file":"Principal.md","x":20,"y":30,"width":300,"height":220,"color":"2"},
      {"id":"b","type":"file","file":"2026-08-22.md","x":420,"y":30,"width":300,"height":220}
    ],"edges":[{"id":"e1","fromNode":"a","toNode":"b","label":"continua"}]}
    """
    try canvas.write(to: vault.appendingPathComponent("Plano.canvas"), atomically: true, encoding: .utf8)

    var importedWorkspace = Workspace(name: "Engenharia")
    let firstImport = try ObsidianImporter.importVault(at: vault, into: &importedWorkspace)
    let firstNodeCount = importedWorkspace.nodes.count
    let secondImport = try ObsidianImporter.importVault(at: vault, into: &importedWorkspace)
    check("obsidian importa markdown e imagem", firstImport.notes == 2 && firstImport.attachments == 1)
    check("obsidian importa tarefa e flashcard", firstImport.tasks == 2 && firstImport.flashcards == 1)
    check("obsidian cria wikilink e canvas", (importedWorkspace.connections ?? []).contains { $0.kind == .wikilink } && (importedWorkspace.connections ?? []).contains { $0.kind == .canvas })
    check("obsidian reconecta sem duplicar nos", importedWorkspace.nodes.count == firstNodeCount && secondImport.notes == 2)
    check("obsidian reconecta sem duplicar baralho", importedWorkspace.studyArtifacts?.filter { $0.sourceExternalID != nil }.count == 1)
    let principal = importedWorkspace.nodes.first { $0.obsidian?.relativePath == "Principal.md" }
    let daily = importedWorkspace.nodes.first { $0.obsidian?.relativePath == "2026-08-22.md" }
    check("frontmatter preserva prioridade e status", principal?.obsidian?.priority == "alta" && principal?.obsidian?.status == "estudando")
    check("daily note reconhecida", daily?.obsidian?.isDailyNote == true)
    check("canvas preserva posicao e cor", principal?.frame.x == 20 && principal?.obsidian?.color == "2")
    check("frontmatter define prova", importedWorkspace.examDate != nil)

    let progress = ProgressMetrics.snapshot(for: importedWorkspace, now: Date(timeIntervalSince1970: 0))
    check("progresso conta tarefas abertas e concluidas", progress.tasks.count == 2 && progress.tasks.filter(\.isCompleted).count == 1)
    check("progresso conta flashcard novo", progress.flashcardCount == 1 && progress.newCount == 1)
    if let openTask = progress.tasks.first(where: { !$0.isCompleted }), let principal {
        let toggled = MarkdownTaskParser.toggled(openTask, in: principal.noteBody)
        check("tarefa markdown pode ser concluida", toggled.contains("- [x] Resolver lista"))
    } else {
        check("tarefa markdown encontrada", false)
    }
    try? FileManager.default.removeItem(at: vault)
} catch {
    check("importacao obsidian: \(error)", false)
}

// 16. Pomodoro baseado em tempo absoluto
MainActor.assumeIsolated {
    let timer = FocusTimerController()
    let workspaceID = UUID()
    let materialID = UUID()
    let start = Date(timeIntervalSince1970: 1_000)
    timer.start(workspaceID: workspaceID, materialID: materialID, at: start)
    _ = timer.tick(at: start.addingTimeInterval(90))
    check("pomodoro calcula saldo pelo relogio", timer.remainingSeconds == 24 * 60 - 30)

    let completion = timer.tick(at: start.addingTimeInterval(1_600))
    check("pomodoro conclui depois de sleep longo", completion?.workspaceID == workspaceID && completion?.materialID == materialID)
    check("pomodoro registra prazo real", completion?.endedAt == start.addingTimeInterval(25 * 60))

    timer.reset()
    timer.start(workspaceID: workspaceID, materialID: nil, at: start)
    timer.pause(at: start.addingTimeInterval(61))
    let pausedRemaining = timer.remainingSeconds
    _ = timer.tick(at: start.addingTimeInterval(600))
    check("pomodoro pausado preserva saldo", timer.remainingSeconds == pausedRemaining && pausedRemaining == 1_439)

    let resumedAt = start.addingTimeInterval(600)
    timer.start(workspaceID: workspaceID, materialID: nil, at: resumedAt)
    let resumedCompletion = timer.tick(at: resumedAt.addingTimeInterval(TimeInterval(pausedRemaining)))
    check("pomodoro retomado usa novo prazo", resumedCompletion?.completedMinutes == 25)
}

// 17. Remoção referencialmente segura
do {
    let materialID = UUID()
    let otherMaterialID = UUID()
    let deckID = UUID()
    var material = CanvasNode(kind: .pdf, frame: .default(for: .pdf, origin: .zero))
    material.id = materialID
    var other = CanvasNode(kind: .pdf, frame: .default(for: .pdf, origin: .zero))
    other.id = otherMaterialID
    let derived = CanvasNode(
        kind: .note,
        frame: .default(for: .note, origin: .zero),
        sourceMaterialID: materialID
    )
    let artifact = StudyArtifact(id: deckID, kind: .flashcards, body: "Frente: A\nVerso: B", sourceNodeID: materialID)
    var workspace = Workspace(
        name: "Remoção",
        nodes: [material, other, derived],
        studyArtifacts: [artifact],
        flashcardReviews: [FlashcardReview(key: "a", sourceNodeID: materialID, deckID: deckID)],
        studyHistory: [StudyHistoryEntry(nodeID: materialID)],
        studyActivityEvents: [StudyActivityEvent(kind: .openedMaterial, nodeID: materialID)],
        focusSessions: [StudyFocusSession(
            startedAt: Date(), endedAt: Date(), plannedMinutes: 25,
            completedMinutes: 25, intention: "", materialID: materialID
        )]
    )
    let impact = workspace.removeNodesPreservingDependentContent([materialID])
    check("remocao informa dependencias", impact.linkedRecordCount == 6)
    check("remocao preserva outros materiais", workspace.nodes.contains { $0.id == otherMaterialID })
    check("remocao desvincula no derivado", workspace.nodes.first { $0.id == derived.id }?.sourceMaterialID == nil)
    check("remocao desvincula artefato e review", workspace.studyArtifacts?.first?.sourceNodeID == nil && workspace.flashcardReviews?.first?.sourceNodeID == nil)
    check("remocao elimina historico orfao", workspace.studyHistory?.isEmpty == true)
    check("remocao preserva eventos e sessoes sem material", workspace.studyActivityEvents?.first?.nodeID == nil && workspace.focusSessions?.first?.materialID == nil)
}

// 18. Plano diário, cobertura, prática e retenção
do {
    let materialID = UUID()
    let deckA = StudyArtifact(
        kind: .flashcards,
        body: (1...15).map { "Frente: A\($0)\nVerso: R\($0)" }.joined(separator: "\n\n"),
        sourceNodeID: materialID
    )
    let deckB = StudyArtifact(
        kind: .flashcards,
        body: (1...15).map { "Frente: B\($0)\nVerso: R\($0)" }.joined(separator: "\n\n"),
        sourceNodeID: materialID
    )
    let plan = ProgressMetrics.flashcardPlan(artifacts: [deckA, deckB], reviews: [])
    check("plano limita novos globalmente", plan.reduce(0) { $0 + $1.new } == ProgressMetrics.dailyNewCardLimit)

    let now = Date()
    var node = CanvasNode(kind: .pdf, frame: .default(for: .pdf, origin: .zero), pdfPageIndex: 8, pdfPageCount: 20)
    node.visitedUnitIndices = [0, 1, 8]
    let reviews = [
        FlashcardReview(key: "hard", sourceNodeID: materialID, lastRating: .hard, lastReviewedAt: now),
        FlashcardReview(key: "good", sourceNodeID: materialID, lastRating: .good, lastReviewedAt: now),
        FlashcardReview(key: "easy", sourceNodeID: materialID, lastRating: .easy, lastReviewedAt: now)
    ]
    let metricsWorkspace = Workspace(
        name: "Métricas",
        nodes: [node],
        flashcardReviews: reviews,
        studyActivityEvents: [
            StudyActivityEvent(kind: .openedMaterial, occurredAt: now),
            StudyActivityEvent(kind: .reviewedFlashcard, occurredAt: now),
            StudyActivityEvent(kind: .reviewedQuestion, occurredAt: now)
        ]
    )
    let metrics = ProgressMetrics.snapshot(for: metricsWorkspace, now: now)
    check("metricas separam posicao e cobertura", metrics.completedUnits == 9 && metrics.coveredUnits == 3 && metrics.coverableUnits == 20)
    check("pratica ignora simples abertura", metrics.practiceToday == 2)
    check("retencao usa ultima avaliacao", abs((metrics.retentionFraction ?? 0) - (2.0 / 3.0)) < 0.001)
}

// 19. Cadernos na busca, exportação e remoção segura
do {
    let materialID = UUID()
    var material = CanvasNode(kind: .pdf, title: "Termodinâmica", frame: .default(for: .pdf, origin: .zero))
    material.id = materialID
    let notebook = StudyNotebook(
        title: "Caderno de calor",
        plainText: "Entalpia e transferência térmica",
        sourceMaterialID: materialID,
        sourcePageIndex: 4
    )
    var notebookWorkspace = Workspace(name: "Engenharia", nodes: [material], notebooks: [notebook])
    let results = StudySearchIndex.search(query: "entalpia", workspaces: [notebookWorkspace], workspaceID: nil, category: .notes)
    let foundNotebook = results.first.map {
        if case .notebook(let id) = $0.destination { return id == notebook.id }
        return false
    } ?? false
    check("busca encontra caderno", foundNotebook && results.first?.pageIndex == 4)

    let unlinkedNote = StudyArtifact(kind: .note, body: "Hipótese órfã preservada")
    notebookWorkspace.studyArtifacts = [unlinkedNote]
    let noteResults = StudySearchIndex.search(query: "órfã", workspaces: [notebookWorkspace], workspaceID: nil, category: .notes)
    let foundUnlinkedNote = noteResults.first.map {
        if case .artifact(let id, sourceNodeID: nil) = $0.destination { return id == unlinkedNote.id }
        return false
    } ?? false
    check("busca encontra nota sem material", foundUnlinkedNote)

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("studyh-notebook-export-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let exported = try ObsidianExporter.export([notebookWorkspace], to: directory)
    let notebookFile = exported.appendingPathComponent("Engenharia/Caderno - Caderno de calor.md")
    let markdown = try String(contentsOf: notebookFile, encoding: .utf8)
    check("obsidian exporta caderno", markdown.contains("studyh_notebook_id") && markdown.contains("Entalpia"))

    let impact = notebookWorkspace.removeNodesPreservingDependentContent([materialID])
    check("remocao contabiliza caderno", impact.notebooks == 1)
    check("remocao preserva caderno sem vinculo", notebookWorkspace.notebooks?.first?.sourceMaterialID == nil && notebookWorkspace.notebooks?.first?.sourcePageIndex == nil)
    try? FileManager.default.removeItem(at: directory)
} catch {
    check("integracao de caderno: \(error)", false)
}

// 20. Frames da mesa, blocos do caderno, kanban e notas espelhadas
do {
    var pdfMaterial = CanvasNode(kind: .pdf, title: "Apostila", frame: CanvasRect(x: 0, y: 0, width: 300, height: 400))
    pdfMaterial.pdfPageCount = 4
    pdfMaterial.pdfPageIndex = 2
    pdfMaterial.visitedUnitIndices = [0, 1]
    var outsideMaterial = CanvasNode(kind: .pdf, title: "Fora", frame: CanvasRect(x: 5_000, y: 5_000, width: 300, height: 400))
    outsideMaterial.pdfPageCount = 4
    outsideMaterial.visitedUnitIndices = [0, 1, 2]
    var frame = StudyFrame(title: "Unidade 3 da prova", rect: CanvasRect(x: -50, y: -50, width: 500, height: 600))
    frame.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    let frameWorkspace = Workspace(
        name: "Frames",
        nodes: [pdfMaterial, outsideMaterial],
        frames: [frame]
    )
    let frameSnapshot = ProgressMetrics.snapshot(for: frameWorkspace)
    check("frame cobre apenas materiais internos", frameSnapshot.frameSnapshots.first?.covered == 2 && frameSnapshot.frameSnapshots.first?.total == 4)
    check("cobertura geral nao muda com frames", frameSnapshot.coveredUnits == 5 && frameSnapshot.coverableUnits == 8)

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let roundtrip = try decoder.decode(Workspace.self, from: encoder.encode(frameWorkspace))
    check("frames sobrevivem ao ciclo json", roundtrip.frames == frameWorkspace.frames)

    let legacyNodeJSON = """
    {"id":"\(UUID().uuidString)","kind":"note","title":"Nota antiga","frame":{"x":0,"y":0,"width":280,"height":220},"zIndex":0,"noteBody":"conteúdo","pdfPageIndex":0,"pdfSelectedText":"","pdfVisibleText":"","webURL":"https://example.com","webSelectedText":"","calcBody":""}
    """
    let legacyNode = try decoder.decode(CanvasNode.self, from: Data(legacyNodeJSON.utf8))
    check("no legado decodifica sem linkedNoteID", legacyNode.linkedNoteID == nil)

    let cardBody = NotebookBlockConverter.flashcardBody(from: "O que é entalpia?\nFunção de estado termodinâmico")
    check("bloco vira flashcard de duas linhas", cardBody != nil && StudyFlashcard.parseDeck(cardBody ?? "")?.count == 1)
    let inlineBody = NotebookBlockConverter.flashcardBody(from: "O que é entropia — medida de desordem")
    let inlineCards = inlineBody.flatMap { StudyFlashcard.parseDeck($0) }
    check("bloco vira flashcard inline", inlineCards?.first?.front == "O que é entropia" && inlineCards?.first?.back == "medida de desordem")
    check("bloco vazio nao vira flashcard", NotebookBlockConverter.flashcardBody(from: "   ") == nil)
    check("bloco vira título de tarefa", NotebookBlockConverter.taskTitle(from: "Fazer lista 3\n de cálculo") == "Fazer lista 3")
    check("bloco vira questão", NotebookBlockConverter.questionBody(from: "Explique o ciclo de Carnot.") == "Explique o ciclo de Carnot.")

    let now = Date()
    let boardTasks = [
        StudyTask(title: "baixa", dueDate: now, priority: .low),
        StudyTask(title: "alta", dueDate: now.addingTimeInterval(10), priority: .high),
        StudyTask(title: "alta antiga", dueDate: now, priority: .high),
        StudyTask(title: "feita", dueDate: now, priority: .high, isCompleted: true)
    ]
    let board = StudyTaskBoard.columns(for: boardTasks)
    check("kanban agrupa por prioridade", board[.high]?.map(\.title) == ["alta antiga", "alta"] && board[.low]?.count == 1 && board[.normal]?.isEmpty == true)
    check("kanban ignora concluídas", board.values.flatMap { $0 }.contains { $0.title == "feita" } == false)

    var mirrorWorkspace = Workspace(name: "Espelho")
    let note = StudyArtifact(kind: .note, body: "[Apostila · pág. 3]\nFórmula importante")
    mirrorWorkspace.studyArtifacts = [note]
    let mirrorNode = CanvasNode(kind: .note, title: "Nota", frame: .default(for: .note, origin: .zero), noteBody: note.body, linkedNoteID: note.id)
    mirrorWorkspace.nodes.append(mirrorNode)
    let mirrorEncoded = try decoder.decode(Workspace.self, from: encoder.encode(mirrorWorkspace))
    check("nota espelhada mantém vínculo", mirrorEncoded.nodes.first?.linkedNoteID == note.id && mirrorEncoded.nodes.first?.noteBody == note.body)
} catch {
    check("frames e blocos: \(error)", false)
}

// 21. Associação, caça-palavras e exportação HTML
do {
    let deckCards = (1...7).map { StudyFlashcard(front: "Termo \($0)", back: "Definição \($0)") }
    let game = MatchingGame.make(from: deckCards)
    check("associação limita pares", game?.pairs.count == 6)
    check("associação embaralha sem perder cartas", game?.fronts.count == 6 && game?.backs.count == 6)
    let firstPair = game?.pairs.first
    check("associação valida par correto", game?.match(front: firstPair?.front ?? "", back: firstPair?.back ?? "") == true)
    check("associação rejeita par trocado", game?.match(front: firstPair?.front ?? "", back: game?.pairs.last?.back ?? "") == false)
    check("associação exige três cartas", MatchingGame.make(from: Array(deckCards.prefix(2))) == nil)
    let duplicateDeck = [
        StudyFlashcard(front: "Mesmo", back: "A"),
        StudyFlashcard(front: "Mesmo", back: "B"),
        StudyFlashcard(front: "Outro", back: "C")
    ]
    check("associação remove frentes duplicadas", MatchingGame.make(from: duplicateDeck) == nil)

    check("normalização remove acentos", WordSearchPuzzle.normalize("Coração") == "CORACAO")
    check("normalização recusa palavras curtas", WordSearchPuzzle.normalize("calor") != nil && WordSearchPuzzle.normalize("sol") == nil)
    let puzzle = WordSearchPuzzle.make(from: ["entalpia", "entropia", "adiabática", "isotérmica", "quântica"])
    check("caça-palavras é gerado", puzzle != nil)
    if let puzzle {
        check("caça-palavras posiciona todas as palavras", puzzle.placements.count == 5 && Set(puzzle.placements.map(\.word)).count == 5)
        var allPlacedCorrectly = true
        for placement in puzzle.placements {
            let spelled = placement.cells.map { puzzle.grid[$0.row][$0.col] }
            if String(spelled) != placement.word { allPlacedCorrectly = false }
        }
        check("caça-palavras soletra palavras no grid", allPlacedCorrectly)
        let first = puzzle.placements[0]
        let lastCell = first.cells.last!
        check("caça-palavras reconhece seleção direta", puzzle.word(from: first.start, to: lastCell) == first.word)
        check("caça-palavras reconhece seleção invertida", puzzle.word(from: lastCell, to: first.start) == first.word)
        check("caça-palavras rejeita linha torta", puzzle.word(from: WordSearchPuzzle.Coordinate(row: 0, col: 0), to: WordSearchPuzzle.Coordinate(row: 1, col: 3)) == nil)
        check("caça-palavras usa oito direções", WordSearchPuzzle.Direction.allCases.count == 8)
        var seenDirections = Set<WordSearchPuzzle.Direction>()
        var sawReversed = false
        let reversedDirections: Set<WordSearchPuzzle.Direction> = [.left, .up, .upLeft, .downLeft]
        for _ in 0..<40 {
            guard let sample = WordSearchPuzzle.make(from: ["entalpia", "entropia", "adiabática", "isotérmica", "quântica"]) else { continue }
            for placement in sample.placements {
                seenDirections.insert(placement.direction)
                if reversedDirections.contains(placement.direction) { sawReversed = true }
            }
        }
        check("caça-palavras sorteia todas as direções", seenDirections == Set(WordSearchPuzzle.Direction.allCases))
        check("caça-palavras usa direções invertidas", sawReversed)
    }

    let vocabulary = WordSearchPuzzle.vocabulary(from: [
        StudyArtifact(kind: .flashcards, body: "Frente: entalpia é\n\nVerso: função de estado")
    ])
    check("vocabulário vem das frentes dos flashcards", vocabulary.contains("entalpia"))

    var htmlWorkspace = Workspace(name: "Revisão <Teste>")
    let material = CanvasNode(kind: .pdf, title: "Apostila", frame: .default(for: .pdf, origin: .zero))
    htmlWorkspace.nodes.append(material)
    htmlWorkspace.studyArtifacts = [
        StudyArtifact(kind: .flashcards, body: "Frente: O que é <entalpia>?\n\nVerso: Função de estado & energia", sourceNodeID: material.id),
        StudyArtifact(kind: .question, body: "Explique o ciclo de Carnot.\n\nGabarito: duas isotermas e duas adiabáticas.")
    ]
    let html = StudyHTMLExporter.export(workspace: htmlWorkspace)
    check("html contém flashcards", html.contains("O que é &lt;entalpia&gt;?") && html.contains("Função de estado &amp; energia"))
    check("html escapa nome da matéria", html.contains("Revisão &lt;Teste&gt;") && !html.contains("<Teste>"))
    check("html separa gabarito", html.contains("Ver gabarito") && html.contains("duas isotermas"))
    check("html é página autônoma", html.hasPrefix("<!DOCTYPE html>") && html.contains("viewport"))
}


print("\n===== RESULTADO =====")
print("Passaram: \(passes) | Falharam: \(failures.count)")
if failures.isEmpty {
    print("TODOS OS TESTES PASSARAM")
} else {
    for failure in failures { print(" - \(failure)") }
    exit(1)
}
