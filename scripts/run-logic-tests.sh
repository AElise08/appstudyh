#!/bin/zsh
# Testes de lógica do Studyh Canvas.
# Concatena os fontes relevantes em um único arquivo (dá acesso a membros
# privados) junto com a suíte de asserções, compila e roda.
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat \
  "$project_dir/StudyhCanvas/Models/WorkspaceModels.swift" \
  "$project_dir/StudyhCanvas/AI/PedagogicalPrompt.swift" \
  "$project_dir/StudyhCanvas/AI/AISettings.swift" \
  "$project_dir/StudyhCanvas/AI/AIClient.swift" \
  "$project_dir/StudyhCanvas/Nodes/PDFNodeView.swift" \
  "$project_dir/StudyhCanvas/Study/AppleBooksImporter.swift" \
  "$project_dir/StudyhCanvas/Nodes/TextNodeViews.swift" \
  "$project_dir/StudyhCanvas/Nodes/WebNodeView.swift" \
  "$project_dir/StudyhCanvas/Nodes/NodeChrome.swift" \
  "$project_dir/StudyhCanvas/Nodes/SlidesImporter.swift" \
  "$project_dir/StudyhCanvas/Nodes/SlidesNodeView.swift" \
  "$project_dir/StudyhCanvas/Study/StudyDeskView.swift" \
  "$project_dir/StudyhCanvas/Study/ProgressMetrics.swift" \
  "$project_dir/StudyhCanvas/Study/StudyWidgetsSidebar.swift" \
  "$project_dir/StudyhCanvas/Study/ObsidianImporter.swift" \
  "$project_dir/StudyhCanvas/Study/GlobalSearchView.swift" \
  "$project_dir/StudyhCanvas/Study/ObsidianExporter.swift" \
  "$project_dir/scripts/logic-tests.swift" \
  > "$tmp/main.swift"

xcrun swiftc -target arm64-apple-macosx14.0 "$tmp/main.swift" -o "$tmp/run-tests"
"$tmp/run-tests"
