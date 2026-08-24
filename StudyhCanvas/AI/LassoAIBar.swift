import SwiftUI

struct LassoAIBar: View {
    @ObservedObject var canvas: CanvasController
    let selectedCount: Int
    var onRun: (AIMode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "circle.dashed")
                Text(selectedCount == 0
                     ? "Selecione um cartão ou use o laço"
                     : selectedCount == 1 ? "1 cartão selecionado" : "\(selectedCount) cartões selecionados")
                    .font(.subheadline)
                Spacer()
                ForEach(AIMode.allCases) { mode in
                    Button(mode.label) { onRun(mode) }
                        .help(mode.help)
                        .disabled(canvas.aiBusy || selectedCount == 0)
                        .controlSize(.small)
                }
            }

            if canvas.aiBusy {
                ProgressView("Tutor lendo o canvas…")
                    .controlSize(.small)
            } else if let error = canvas.aiError {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
                    .textSelection(.enabled)
            } else if let mode = canvas.lastAIMode, !canvas.aiPanelText.isEmpty {
                Text(mode.label.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ScrollView {
                    Text(canvas.aiPanelText)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 180)
            }
        }
        .padding(10)
        .frame(maxWidth: 560)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
    }
}
