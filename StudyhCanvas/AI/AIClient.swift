import Foundation
import AppKit
import Vision
#if canImport(FoundationModels)
import FoundationModels
#endif

struct AIClient {
    enum ClientError: LocalizedError {
        case missingKey
        case badURL
        case http(Int, String)
        case emptyReply
        case localUnavailable(String)

        var errorDescription: String? {
            switch self {
            case .missingKey:
                return "Configure a chave da API em Ajustes."
            case .badURL:
                return "URL da API inválida. Use HTTPS ou HTTP apenas com localhost/127.0.0.1."
            case .http(let code, let body):
                return "A API respondeu \(code): \(body)"
            case .emptyReply:
                return "A API não devolveu texto."
            case .localUnavailable(let reason):
                return reason
            }
        }
    }

    @MainActor
    func study(
        action: StudyAssistantAction,
        query: String = "",
        context: String,
        settings: AISettings
    ) async throws -> String {
        let prompt = action.prompt(query: query, context: context)
        if settings.provider == .appleLocal {
            #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                let model = SystemLanguageModel.default
                guard model.isAvailable else {
                    throw ClientError.localUnavailable(localUnavailableMessage(model.availability))
                }
                let session = LanguageModelSession(
                    model: model,
                    instructions: StudyAssistantAction.systemPrompt
                )
                let response = try await session.respond(to: String(prompt.prefix(8_000)))
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { throw ClientError.emptyReply }
                return text
            }
            #endif
            throw ClientError.localUnavailable(
                "O assistente local requer macOS 26 ou posterior e Apple Intelligence."
            )
        }
        if settings.provider == .codexCLI || settings.provider == .opencodeCLI {
            let cliPrompt = """
            \(StudyAssistantAction.systemPrompt)

            \(prompt)
            """
            return try await runLocalCommand(
                prompt: String(cliPrompt.prefix(8_000)),
                settings: settings
            )
        }

        let url = try validatedAPIURL(settings.endpoint)
        let key = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ClientError.missingKey }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": settings.model,
            "temperature": 0.3,
            "messages": [
                ["role": "system", "content": StudyAssistantAction.systemPrompt],
                ["role": "user", "content": String(prompt.prefix(16_000))]
            ]
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw ClientError.http(code, String((String(data: data, encoding: .utf8) ?? "").prefix(400)))
        }
        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        let text = decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, !text.isEmpty else { throw ClientError.emptyReply }
        return text
    }

    @MainActor
    func complete(
        mode: AIMode,
        selection: String,
        surrounding: String,
        settings: AISettings,
        imageData: Data? = nil
    ) async throws -> String {
        if settings.provider == .appleLocal {
            return try await completeLocally(
                mode: mode,
                selection: selection,
                surrounding: surrounding,
                imageData: imageData
            )
        }
        if settings.provider == .codexCLI || settings.provider == .opencodeCLI {
            var localSelection = selection
            if let imageData {
                let recognized = await recognizeText(in: imageData)
                if recognized.isEmpty {
                    localSelection += "\n\n[Há um desenho selecionado, mas não foi possível reconhecer texto nele. Peça ao aluno para descrevê-lo ou escrever a expressão.]"
                } else {
                    localSelection += "\n\n[Texto reconhecido localmente no desenho]\n\(recognized)"
                }
            }
            let prompt = PedagogicalPrompt.userMessage(
                mode: mode,
                selection: localSelection,
                surrounding: surrounding
            )
            let cliPrompt = """
            \(PedagogicalPrompt.system)

            \(prompt)
            """
            let text = try await runLocalCommand(
                prompt: String(cliPrompt.prefix(8_000)),
                settings: settings
            )
            return PedagogicalResponseGuard.sanitize(
                text,
                mode: mode,
                context: localSelection + "\n" + surrounding
            )
        }

        let url = try validatedAPIURL(settings.endpoint)
        let key = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ClientError.missingKey }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60

        let prompt = PedagogicalPrompt.userMessage(
            mode: mode,
            selection: String(selection.prefix(8_000)),
            surrounding: String(surrounding.prefix(6_000))
        )
        let userContent: Any
        if let imageData {
            userContent = [
                ["type": "text", "text": prompt],
                [
                    "type": "image_url",
                    "image_url": [
                        "url": "data:image/png;base64,\(imageData.base64EncodedString())",
                        "detail": "high"
                    ]
                ]
            ]
        } else {
            userContent = prompt
        }

        let body: [String: Any] = [
            "model": settings.model,
            "temperature": 0.3,
            "messages": [
                ["role": "system", "content": PedagogicalPrompt.system],
                ["role": "user", "content": userContent]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if !(200..<300).contains(code) {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw ClientError.http(code, String(text.prefix(400)))
        }

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        let text = decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, !text.isEmpty else { throw ClientError.emptyReply }
        return PedagogicalResponseGuard.sanitize(
            text,
            mode: mode,
            context: selection + "\n" + surrounding
        )
    }

    @MainActor
    private func completeLocally(
        mode: AIMode,
        selection: String,
        surrounding: String,
        imageData: Data?
    ) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard model.isAvailable else {
                throw ClientError.localUnavailable(localUnavailableMessage(model.availability))
            }

            var localSelection = selection
            if let imageData {
                let recognized = await recognizeText(in: imageData)
                if recognized.isEmpty {
                    localSelection += "\n\n[Há um desenho selecionado, mas não foi possível reconhecer texto nele. Peça ao aluno para descrevê-lo ou escrever a expressão.]"
                } else {
                    localSelection += "\n\n[Texto reconhecido localmente no desenho]\n\(recognized)"
                }
            }

            let prompt = PedagogicalPrompt.userMessage(
                mode: mode,
                selection: localSelection,
                surrounding: surrounding
            )
            let session = LanguageModelSession(
                model: model,
                instructions: PedagogicalPrompt.system
            )
            let response = try await session.respond(to: String(prompt.prefix(8_000)))
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw ClientError.emptyReply }
            return PedagogicalResponseGuard.sanitize(
                text,
                mode: mode,
                context: localSelection + "\n" + surrounding
            )
        }
        #endif
        throw ClientError.localUnavailable(
            "O modelo local requer macOS 26 ou posterior e Apple Intelligence habilitado."
        )
    }

    @MainActor
    private func runLocalCommand(prompt: String, settings: AISettings) async throws -> String {
        guard settings.provider != .opencodeCLI else {
            throw ClientError.localUnavailable(
                "O backend OpenCode está desabilitado porque o CLI instalado não oferece um modo somente leitura verificável. Use Apple local, Codex CLI ou API externa."
            )
        }
        guard let commandName = settings.provider.commandName else {
            throw ClientError.localUnavailable("Nenhum comando local foi selecionado.")
        }
        guard let executable = resolveExecutable(
            preferredPath: settings.commandPath,
            commandName: commandName
        ) else {
            let setup = commandName == "codex"
                ? "Instale o Codex CLI ou informe o caminho do executável em Ajustes. Depois, execute “codex login” no Terminal."
                : "Instale o OpenCode ou informe o caminho do executável em Ajustes. Configure um provedor com “opencode providers”."
            throw ClientError.localUnavailable(setup)
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("studyh-\(UUID().uuidString).txt")
        let safePrompt = """
        Responda somente com texto para um aplicativo de estudos. Não altere arquivos nem execute ações no computador. Use o contexto fornecido como fonte principal para explicar o que acontece no material, mas use também seu conhecimento geral quando a pergunta pedir uma comparação, uma referência filosófica, histórica ou científica, uma definição ou uma conexão que não esteja escrita no trecho. Separe claramente “O trecho mostra” de “Conhecimento externo” e nunca apresente uma analogia como prova de que o autor teve aquela influência. Não invente citações, obras ou fontes; se não tiver segurança sobre um nome ou atribuição, diga isso.

        \(prompt)
        """
        let selectedModel = settings.codexModel
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var arguments = [
            "exec", "--ephemeral", "--sandbox", "read-only",
            "--skip-git-repo-check", "--color", "never",
            "--cd", "/tmp", "--output-last-message", outputURL.path,
        ]
        if !selectedModel.isEmpty {
            arguments += ["--model", selectedModel]
        }
        arguments.append(String(safePrompt.prefix(8_000)))

        let stdout = Pipe()
        let stderr = Pipe()
        let stdoutBuffer = PipeBuffer()
        let stderrBuffer = PipeBuffer()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            stdoutBuffer.append(handle.availableData)
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            stderrBuffer.append(handle.availableData)
        }
        let process = Process()
        let cancellation = LocalProcessCancellation(process: process)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = stdout
            process.standardError = stderr
            process.terminationHandler = { process in
                defer { try? FileManager.default.removeItem(at: outputURL) }
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                stdoutBuffer.append(stdout.fileHandleForReading.readDataToEndOfFile())
                stderrBuffer.append(stderr.fileHandleForReading.readDataToEndOfFile())
                let outputFile = try? String(contentsOf: outputURL, encoding: .utf8)
                let standardOutput = stdoutBuffer.string
                let standardError = stderrBuffer.string
                if cancellation.wasCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                let rawResponse = outputFile?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? (outputFile ?? "")
                    : standardOutput
                let response = Self.stripTerminalFormatting(rawResponse)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard process.terminationStatus == 0 else {
                    let detail = standardError.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(throwing: ClientError.localUnavailable(
                        detail.isEmpty ? "O comando local terminou com erro." : detail
                    ))
                    return
                }
                guard !response.isEmpty else {
                    continuation.resume(throwing: ClientError.emptyReply)
                    return
                }
                continuation.resume(returning: response)
            }
            do {
                try process.run()
                cancellation.terminateIfCancelled()
            } catch {
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                try? FileManager.default.removeItem(at: outputURL)
                if cancellation.wasCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    continuation.resume(throwing: ClientError.localUnavailable(
                        "Não consegui iniciar \(commandName): \(error.localizedDescription)"
                    ))
                }
            }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    private func validatedAPIURL(_ endpoint: String) throws -> URL {
        guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              !host.isEmpty,
              scheme == "https" || (scheme == "http" && (host == "localhost" || host == "127.0.0.1")) else {
            throw ClientError.badURL
        }
        return url
    }

    private func resolveExecutable(preferredPath: String, commandName: String) -> URL? {
        let fileManager = FileManager.default
        let preferred = preferredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidates: [String] = []
        if !preferred.isEmpty { candidates.append(preferred) }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        candidates += commandName == "codex"
            ? [
                home + "/.local/bin/codex",
                "/opt/homebrew/bin/codex",
                "/usr/local/bin/codex"
            ]
            : [
                home + "/.opencode/bin/opencode",
                "/opt/homebrew/bin/opencode",
                "/usr/local/bin/opencode"
            ]
        return candidates
            .map { URL(fileURLWithPath: $0) }
            .first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    private static func stripTerminalFormatting(_ text: String) -> String {
        text.replacingOccurrences(
            of: "\u{1B}\\[[0-9;]*[A-Za-z]",
            with: "",
            options: .regularExpression
        )
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func localUnavailableMessage(_ availability: SystemLanguageModel.Availability) -> String {
        switch availability {
        case .available:
            return "O modelo local está disponível. Tente novamente."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Ative o Apple Intelligence nos Ajustes do Sistema para usar o modelo local."
        case .unavailable(.modelNotReady):
            return "O modelo local da Apple ainda está sendo preparado. Tente novamente mais tarde."
        case .unavailable(.deviceNotEligible):
            return "Este Mac não é compatível com o modelo local da Apple. Selecione API externa nos Ajustes."
        @unknown default:
            return "O modelo local da Apple não está disponível agora."
        }
    }
    #endif

    @MainActor
    private func recognizeText(in imageData: Data) async -> String {
        guard let image = NSImage(data: imageData) else { return "" }
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return "" }
        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["pt-BR", "en-US"]
            let handler = VNImageRequestHandler(cgImage: cgImage)
            try? handler.perform([request])
            return (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        }.value
    }
}

enum StudyAssistantAction: Equatable {
    case summary
    case ask
    case flashcards
    case question

    static let systemPrompt = """
    Você é o assistente de estudos do Studyh. Use a fonte fornecida como base para explicar o material, mas não limite artificialmente a resposta quando o estudante pedir conhecimento externo, uma comparação ou uma referência. Nesses casos, separe o que o trecho afirma do que é uma conexão feita com conhecimento geral e admita qualquer incerteza.
    Resumos podem ser diretos e completos. Flashcards devem ser claros, atômicos e fiéis à fonte. Em matemática, física e engenharia, priorize significado das fórmulas, variáveis, hipóteses, unidades, condições de uso e interpretação física; não crie flashcards de mera aritmética. Questões nunca devem exibir a resposta ao estudante; no modo de geração, uma linha técnica de gabarito pode ser incluída para o aplicativo verificar a resposta e será ocultada pela interface.
    Use linguagem simples, frases curtas e explique termos difíceis. Quando o estudante pedir “explica”, fale sobre o trecho da página atual e conecte a explicação às marcações/notas fornecidas; não dê uma sinopse genérica do livro.
    Em ficção e diálogos, identifique quem está falando, a quem responde e o que ocorreu nas páginas anteriores. Diferencie claramente a voz do narrador, a personagem focal acompanhada pela narração e a fala direta dos personagens. A perspectiva narrativa pode mudar entre partes e capítulos: use somente [Perspectiva narrativa detectada no trecho atual] e nunca projete sobre a página o narrador de outra seção ou o nome do autor. Em terceira pessoa, não chame a personagem focal de narrador. Em primeira pessoa, só diga o nome do narrador-personagem quando a fonte trouxer prova textual local. Diferencie claramente a crença de um personagem, a reação de outro personagem e a posição sugerida pela narrativa. Quando o estudante perguntar “qual filósofo apoia isso?”, “com que ideia isso se parece?” ou fizer outra pergunta externa, responda com conhecimento geral e use o rótulo “Conhecimento externo”. Diga se é uma semelhança temática ou uma influência documentada; não invente uma ligação autoral. Nunca transforme uma fala de personagem em conselho de autoajuda ou mensagem positiva sem apoio explícito no contexto.
    Se uma pergunta pedir a solução pronta de um exercício, peça primeiro a tentativa do aluno e ofereça apenas orientação conceitual.
    Responda em português, sem alertas genéricos e sem inventar fatos. Não faça buscas na rede nem invente links ou bibliografias; conexões externas devem vir apenas do conhecimento já disponível no modelo e ser apresentadas com a incerteza apropriada. Quando a pergunta usar “depois”, “em seguida”, “posteriormente” ou pedir o discurso seguinte, procure primeiro a seção de continuação fornecida; não repita o trecho anterior. Se a continuação não estiver disponível na fonte, diga isso claramente. Quando a pergunta mencionar texto “destacado”, “marcado” ou “sublinhado”, trate a seção [Destaque(s) atual(is) que o estudante pode estar mencionando] como a seleção exata do estudante. Explique esse trecho e suas notas; não diga que a fonte não indica o destaque se essa seção estiver presente.
    """

    func prompt(query: String, context: String) -> String {
        let task: String
        switch self {
        case .summary:
            task = "Explique o trecho da página atual como se estivesse conversando com um estudante que acabou de lê-lo. Comece com 'Em palavras simples:'. Adapte-se ao conteúdo. Se for técnico, matemático ou de engenharia, identifique o conceito, o significado das variáveis, as hipóteses, unidades e condições de uso; interprete a equação fisicamente e aponte um erro conceitual comum, sem resolver exercícios. Se for narrativa ou diálogo, diga quem fala, para quem, quem narra e qual personagem é acompanhada, respeitando a perspectiva local. Use frases curtas e conecte as marcações/notas. Não faça uma explicação genérica de outro assunto."
        case .ask:
            task = "Responda à pergunta usando a fonte como ponto de partida. Pergunta do estudante: \(query). Se a pergunta pedir uma referência externa — por exemplo, um filósofo que defenda uma ideia parecida — não diga apenas que a resposta não está no trecho: use seu conhecimento geral, apresente os nomes e explique em uma frase a semelhança e a diferença. Separe em ‘O trecho mostra’ e ‘Conhecimento externo’. Não transforme semelhança em prova de influência do autor e não invente citações. Se ela pedir o que aconteceu depois, identifique o trecho posterior e explique em linguagem simples quem fala, para quem e qual é a ideia principal. Se ela perguntar sobre o texto destacado, comece identificando o destaque fornecido e explique o seu sentido no contexto. Não responda apenas repetindo o discurso anterior e não alegue falta do destaque quando ele estiver marcado na fonte."
        case .flashcards:
            task = "Crie 5 flashcards somente com fatos explicitamente presentes no conteúdo marcado como lido e na página visível. Nunca use acontecimentos, personagens, conceitos ou respostas posteriores ao ponto atual, mesmo que você conheça a obra por treinamento. Em conteúdo técnico, cubra conceito, variável, unidade, hipótese ou condição de aplicação; não peça apenas para executar uma conta. Se a fonte não bastar para 5 flashcards distintos, crie menos. Use exatamente o formato 'Frente: ...' e 'Verso: ...', separados por uma linha em branco."
        case .question:
            task = "Crie UMA questão somente a partir do conteúdo explicitamente marcado como lido até a página atual. Nunca use acontecimentos, conceitos ou respostas que apareçam depois desse limite, mesmo que estejam no contexto por engano. Em matemática, física ou engenharia, prefira interpretação de equação ou gráfico, escolha do modelo, unidades, hipóteses e aplicação conceitual; não reduza a questão a uma conta mecânica. Se a fonte incluir a seção [Questões já usadas; crie uma diferente], não repita nenhuma delas nem apenas troque a ordem das alternativas: escolha outro detalhe, relação ou consequência do material já lido. Respeite [Formato da próxima questão]: se for 'múltipla escolha', use exatamente 'Pergunta: ...', seguido por 'A) ...', 'B) ...', 'C) ...' e 'D) ...', e depois uma linha técnica 'Gabarito: X'. Se for 'resposta curta', use exatamente 'Pergunta: ...', depois 'Tipo: resposta curta' e uma linha técnica 'Gabarito interno: ...' com os pontos esperados. Essas linhas técnicas não serão exibidas como parte da questão. Não inclua explicação, dica ou resolução junto da pergunta."
        }
        let identityInstruction = context.contains("[Perspectiva narrativa detectada no trecho atual]")
            ? "Instrução prioritária: respeite a perspectiva do trecho atual. Ela substitui qualquer suposição baseada em outra parte do livro. Não confunda autor, narrador, personagem focal e personagem que fala."
            : ""
        return """
        Tarefa: \(task)

        \(identityInstruction)

        Fonte atual:
        \(context.isEmpty ? "(sem texto extraído)" : context)
        """
    }
}

enum PedagogicalResponseGuard {
    static func sanitize(_ response: String, mode: AIMode, context: String) -> String {
        guard mode == .check || mode == .nextStep else { return response }
        let normalizedContext = context.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "pt_BR")
        )
        let hasUnits = normalizedContext.range(
            of: #"\b(mm|cm|km|kg|mg|mpa|kpa|pa|newton|metros?|segundos?|volts?|watts?|joules?|graus?)\b"#,
            options: .regularExpression
        ) != nil
        let hasHypothesisContext = [
            "hipotese", "equilibrio", "corpo livre", "forca", "momento", "contorno"
        ].contains { normalizedContext.contains($0) }

        let revealMarkers = [
            "resposta correta", "resultado correto", "valor correto", "soma correta",
            "solucao correta", "correcao e", "correto seria", "correta seria",
            "deveria ser", "o certo e", "a certa e"
        ]

        let kept = response
            .components(separatedBy: .newlines)
            .filter { line in
                let folded = line.folding(
                    options: [.diacriticInsensitive, .caseInsensitive],
                    locale: Locale(identifier: "pt_BR")
                )
                if revealMarkers.contains(where: folded.contains) { return false }
                if !hasUnits, folded.contains("unidade") { return false }
                if !hasHypothesisContext, folded.contains("hipotese") { return false }
                return true
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if kept.isEmpty {
            return "Alerta: há um ponto inconsistente na tentativa.\nTente: refaça apenas a operação ou justificativa onde você chegou a esse resultado."
        }
        return kept
    }
}

enum CanvasInkSnapshot {
    static func pngData(from strokes: [InkStroke]) -> Data? {
        let points = strokes.flatMap(\.points)
        guard let first = points.first else { return nil }
        var bounds = CGRect(x: first.x, y: first.y, width: 1, height: 1)
        for point in points.dropFirst() {
            bounds = bounds.union(CGRect(x: point.x, y: point.y, width: 1, height: 1))
        }
        bounds = bounds.insetBy(dx: -24, dy: -24)
        let longest = max(bounds.width, bounds.height)
        let scale = longest > 1600 ? 1600 / longest : max(1, min(2, 900 / max(1, longest)))
        let imageSize = CGSize(
            width: max(64, bounds.width * scale),
            height: max(64, bounds.height * scale)
        )
        let image = NSImage(size: imageSize)
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: imageSize)).fill()
        NSColor.black.setStroke()
        for stroke in strokes {
            guard let start = stroke.points.first else { continue }
            let path = NSBezierPath()
            path.lineWidth = max(2, stroke.width * scale)
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: CGPoint(
                x: (start.x - bounds.minX) * scale,
                y: imageSize.height - (start.y - bounds.minY) * scale
            ))
            for point in stroke.points.dropFirst() {
                path.line(to: CGPoint(
                    x: (point.x - bounds.minX) * scale,
                    y: imageSize.height - (point.y - bounds.minY) * scale
                ))
            }
            path.stroke()
        }
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}

private final class PipeBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    var string: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private final class LocalProcessCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private var cancelled = false

    init(process: Process) {
        self.process = process
    }

    var wasCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let shouldTerminate = process.isRunning
        lock.unlock()
        if shouldTerminate { process.terminate() }
    }

    func terminateIfCancelled() {
        lock.lock()
        let shouldTerminate = cancelled && process.isRunning
        lock.unlock()
        if shouldTerminate { process.terminate() }
    }
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            var content: String?
        }
        var message: Message
    }
    var choices: [Choice]
}
