# Studyh Canvas

Workspace de estudo nativo para Mac: canvas infinito, PDFs, pesquisas, notas e folha de cálculo no mesmo espaço. A IA (Check / Explain / Next) verifica e guia sem entregar o gabarito.

## Abrir no Xcode

```bash
open StudyhCanvas.xcodeproj
```

Requer macOS 14+, Xcode 15+, Apple Silicon recomendado.

## Configurar a IA

No app: **Studyh Canvas → Ajustes**.

- URL no formato OpenAI-compatible (`…/v1/chat/completions`)
- Chave da API
- Nome do modelo

O app envia o recorte do canvas (`check` | `explain` | `next`) e o contrato pedagógico do Studyh.

Dados locais ficam em `~/Library/Application Support/Studyh/`.
