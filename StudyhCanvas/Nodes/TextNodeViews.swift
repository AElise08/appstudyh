import SwiftUI
import AppKit
import Vision

struct NoteNodeView: View {
    @Binding var node: CanvasNode
    @State private var mode: NoteMode = .text
    @State private var editingLinkedCard = false

    var body: some View {
        if node.sourceArtifactKind != nil {
            linkedCard
        } else {
            regularNote
        }
    }

    private var linkedCard: some View {
        VStack(spacing: 0) {
            HStack {
                Label(
                    node.sourceArtifactKind == .flashcards ? "Flashcard vinculado" : "Nota vinculada",
                    systemImage: node.sourceArtifactKind == .flashcards ? "rectangle.on.rectangle.angled" : "link"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                Spacer()
                Button(editingLinkedCard ? "Concluir" : "Editar") {
                    editingLinkedCard.toggle()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            Divider()
            if editingLinkedCard {
                TextEditor(text: $node.noteBody)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
            } else {
                if node.obsidian?.attachmentType == "image",
                   let path = node.sourceURL,
                   let image = NSImage(contentsOfFile: path) {
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding(10)
                    }
                } else {
                    ScrollView {
                        Text(node.noteBody)
                            .font(.body)
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(14)
                    }
                }
            }
        }
        .background(node.sourceArtifactKind == .flashcards ? Color.purple.opacity(0.06) : Color.yellow.opacity(0.06))
    }

    private var regularNote: some View {
        VStack(spacing: 0) {
            Picker("Modo da nota", selection: $mode) {
                Text("Texto").tag(NoteMode.text)
                Text("Desenho").tag(NoteMode.drawing)
            }
            .pickerStyle(.segmented)
            .padding(7)

            if mode == .text {
                TextEditor(text: $node.noteBody)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .overlay(alignment: .bottomLeading) {
                        Text("Texto / Markdown")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(8)
                            .allowsHitTesting(false)
                    }
            } else {
                DrawingPad(
                    strokes: $node.inkStrokes,
                    recognizedText: $node.inkRecognizedText
                )
            }
        }
    }
}

struct CalcNodeView: View {
    @Binding var node: CanvasNode
    @State private var showingPreview = true
    @State private var mode: ScratchMode = .text

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Picker("Modo da resolução", selection: $mode) {
                    Text("Desenho").tag(ScratchMode.drawing)
                    Text("Equações").tag(ScratchMode.text)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 230)
                Spacer()
                Menu("Estrutura") {
                    Button("Resolução de engenharia") { insertTemplate(engineeringTemplate) }
                    Button("Cálculo diferencial / integral") { insertTemplate(calculusTemplate) }
                    Button("Análise dimensional") { insertTemplate(dimensionsTemplate) }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Text("Resolva; selecione e use Verificar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)

            if mode == .drawing {
                DrawingPad(
                    strokes: $node.inkStrokes,
                    recognizedText: $node.inkRecognizedText
                )
            } else {
                HStack(spacing: 6) {
                    ForEach(["∫", "∂", "Δ", "Σ", "√", "→"], id: \.self) { symbol in
                        Button(symbol) { appendSymbol(symbol) }
                            .buttonStyle(.borderless)
                            .font(.system(.body, design: .serif))
                            .help("Inserir \(symbol)")
                    }
                    Spacer()
                    Toggle("Prévia", isOn: $showingPreview)
                        .toggleStyle(.button)
                        .controlSize(.small)
                        .padding(.trailing, 8)
                }
                TextEditor(text: $node.calcBody)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .overlay(alignment: .topLeading) {
                        if node.calcBody.isEmpty {
                            Text("Use Estrutura para começar ou escreva suas equações e etapas.")
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                                .padding(14)
                                .allowsHitTesting(false)
                        }
                    }
                if showingPreview {
                    Divider()
                    ScrollView(.horizontal) {
                        Text(SimpleMathFormatter.display(node.calcBody))
                            .font(.system(.body, design: .serif))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .frame(minHeight: 56, maxHeight: 110)
                    .background(Color(nsColor: .controlBackgroundColor))
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var engineeringTemplate: String {
        """
        DADOS E UNIDADES

        OBJETIVO

        HIPÓTESES

        MODELO / EQUAÇÕES

        DESENVOLVIMENTO

        VERIFICAÇÃO DIMENSIONAL

        RESULTADO E INTERPRETAÇÃO
        """
    }

    private var calculusTemplate: String {
        """
        FUNÇÃO E DOMÍNIO

        O QUE DEVE SER CALCULADO

        CONDIÇÕES / LIMITES

        DERIVADA OU INTEGRAL

        DESENVOLVIMENTO

        VERIFICAÇÃO
        """
    }

    private var dimensionsTemplate: String {
        """
        GRANDEZAS

        UNIDADES NO SI

        EQUAÇÃO

        DIMENSÃO DO LADO ESQUERDO

        DIMENSÃO DO LADO DIREITO

        CONCLUSÃO
        """
    }

    private func insertTemplate(_ template: String) {
        mode = .text
        let existing = node.calcBody.trimmingCharacters(in: .whitespacesAndNewlines)
        node.calcBody = existing.isEmpty ? template : "\(existing)\n\n────────\n\n\(template)"
    }

    private func appendSymbol(_ symbol: String) {
        node.calcBody += symbol
    }
}

private enum NoteMode: Hashable { case text, drawing }
private enum ScratchMode: Hashable { case drawing, text }

private struct DrawingPad: View {
    @Binding var strokes: [InkStroke]?
    @Binding var recognizedText: String?
    @State private var activePoints: [InkPoint] = []
    @State private var recognizing = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button("Desfazer") { _ = strokes?.popLast() }
                    .disabled(strokes?.isEmpty != false)
                Button {
                    recognizeWriting()
                } label: {
                    if recognizing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Ler escrita", systemImage: "text.viewfinder")
                    }
                }
                .disabled(strokes?.isEmpty != false || recognizing)
                Spacer()
                if strokes?.isEmpty == false {
                    Button("Limpar", role: .destructive) {
                        strokes = []
                        recognizedText = nil
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)

            GeometryReader { geometry in
                Canvas { context, _ in
                    for stroke in (strokes ?? []) + activeStroke {
                        guard let first = stroke.points.first else { continue }
                        var path = Path()
                        path.move(to: first.cgPoint)
                        for point in stroke.points.dropFirst() {
                            path.addLine(to: point.cgPoint)
                        }
                        context.stroke(
                            path,
                            with: .color(.primary),
                            style: StrokeStyle(
                                lineWidth: stroke.width,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
                .contentShape(Rectangle())
                .gesture(drawingGesture)
                .overlay(alignment: .topLeading) {
                    if strokes?.isEmpty != false, activePoints.isEmpty {
                        Text("Desenhe com o mouse ou trackpad")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(10)
                            .allowsHitTesting(false)
                    }
                }
                .onAppear { recognitionCanvasSize = geometry.size }
                .onChange(of: geometry.size) { _, size in recognitionCanvasSize = size }
            }

            if let recognizedText, !recognizedText.isEmpty {
                Divider()
                HStack(alignment: .firstTextBaseline) {
                    Text("Texto reconhecido")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("Corrija se necessário", text: recognizedTextBinding)
                        .textFieldStyle(.plain)
                }
                .padding(8)
            }
        }
    }

    @State private var recognitionCanvasSize: CGSize = CGSize(width: 600, height: 400)

    private var activeStroke: [InkStroke] {
        activePoints.isEmpty ? [] : [InkStroke(points: activePoints)]
    }

    private var recognizedTextBinding: Binding<String> {
        Binding(
            get: { recognizedText ?? "" },
            set: { recognizedText = $0 }
        )
    }

    private var drawingGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let point = InkPoint(x: value.location.x, y: value.location.y)
                if let last = activePoints.last,
                   hypot(point.x - last.x, point.y - last.y) < 0.7 { return }
                activePoints.append(point)
            }
            .onEnded { _ in
                guard activePoints.count > 1 else {
                    activePoints = []
                    return
                }
                var saved = strokes ?? []
                saved.append(InkStroke(points: activePoints))
                strokes = saved
                activePoints = []
            }
    }

    private func recognizeWriting() {
        let savedStrokes = strokes ?? []
        guard !savedStrokes.isEmpty else { return }
        recognizing = true
        let image = InkTextRecognizer.image(from: savedStrokes, size: recognitionCanvasSize)
        Task {
            recognizedText = await InkTextRecognizer.recognize(image)
            recognizing = false
        }
    }
}

private enum InkTextRecognizer {
    @MainActor
    static func image(from strokes: [InkStroke], size: CGSize) -> CGImage? {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
        NSColor.black.setStroke()
        for stroke in strokes {
            guard let first = stroke.points.first else { continue }
            let path = NSBezierPath()
            path.lineWidth = max(2, stroke.width)
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: first.cgPoint)
            for point in stroke.points.dropFirst() { path.line(to: point.cgPoint) }
            path.stroke()
        }
        image.unlockFocus()
        var rect = CGRect(origin: .zero, size: size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    static func recognize(_ image: CGImage?) async -> String {
        guard let image else { return "" }
        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["pt-BR", "en-US"]
            let handler = VNImageRequestHandler(cgImage: image)
            try? handler.perform([request])
            return (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        }.value
    }
}

private enum SimpleMathFormatter {
    private static let replacements: [(String, String)] = [
        ("\\times", "×"), ("\\cdot", "·"), ("\\pm", "±"),
        ("\\Delta", "Δ"), ("\\theta", "θ"), ("\\sigma", "σ"),
        ("\\epsilon", "ε"), ("\\sqrt", "√"), ("\\leq", "≤"),
        ("\\geq", "≥"), ("\\neq", "≠"), ("\\approx", "≈"),
        ("^2", "²"), ("^3", "³"), ("^-1", "⁻¹")
    ]

    static func display(_ source: String) -> String {
        var result = source
        for (latex, symbol) in replacements {
            result = result.replacingOccurrences(of: latex, with: symbol)
        }
        result = result.replacingOccurrences(of: "$", with: "")
        return result.isEmpty ? "A prévia da notação aparece aqui." : result
    }
}
