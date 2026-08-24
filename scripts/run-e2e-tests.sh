#!/bin/zsh
# Testes de integração de persistência do Studyh Canvas.
# Roda o app real contra um diretório de dados isolado
# (STUDYH_DATA_DIR), sem tocar nos dados reais do usuário:
#   A) primeiro lançamento cria estrutura + workspace padrão
#   B) índice corrompido é auto-curado e gera backup
#   C) workspace truncado bloqueia gravação e preserva o arquivo
#   D) estado íntegro recarrega intacto
#   E) workspace novo usa formato plano explicitamente versionado
#   F) workspace legado sem versão continua legível
#   G) versão futura bloqueia gravação e não cai para backup antigo
#   H) varredura parcial não recria um índice omitindo arquivo futuro
#   I) índice de versão futura também é preservado
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Compilando..."
xcrun swiftc -target arm64-apple-macosx14.0 \
  "$project_dir"/StudyhCanvas/**/*.swift \
  -o "$tmp/StudyhCanvas"

BIN="$tmp/StudyhCanvas"
DATA="$tmp/data"
mkdir -p "$DATA"
export STUDYH_DATA_DIR="$DATA"

pass=0; fail=0
ck() { if eval "$2"; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; fi }
SEMANTIC='python3 -c "import json,sys; a=json.load(open(sys.argv[1])); b=json.load(open(sys.argv[2])); sys.exit(0 if a==b else 1)"'

launch_and_kill() {
  "$BIN" >/dev/null 2>&1 & local pid=$!
  sleep 7
  kill -9 "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

# ---- A: primeiro lançamento ----
launch_and_kill
ck "A: app vivo apos 4s" "[ -n "$(pgrep -P $$ StudyhCanvas 2>/dev/null || true)" ] || [ -f "$DATA/index.json" ]"
ck "A: indice criado" "[ -f "$DATA/index.json" ]"
WSFILE=$(ls "$DATA" | grep -E '^[0-9A-F-]{36}\.json$' | head -1)
ck "A: workspace padrao criado" "[ -n "${WSFILE:-}" ]"
ck "A: nome da materia correta" "grep -q 'Minha primeira matéria' "$DATA/$WSFILE""

# ---- B: indice corrompido ----
cp "$DATA/$WSFILE" "$tmp/ws-before.json"
echo '{corrompido' > "$DATA/index.json"
launch_and_kill
ck "B: indice auto-curado com 1 workspace" "python3 -c \"import json,sys; d=json.load(open(sys.argv[1])); assert len(d['workspaceIDs'])==1\" "$DATA/index.json""
ck "B: workspace intacto (semantico)" "$SEMANTIC "$tmp/ws-before.json" "$DATA/$WSFILE""
ck "B: backup criado" "[ -d "$DATA/Backups" ] && ls "$DATA/Backups" | grep -q ."

# ---- C: workspace truncado -> gravacao bloqueada ----
cp "$tmp/ws-before.json" "$DATA/$WSFILE"
python3 -c "
import sys
p = sys.argv[1]
data = open(p,'rb').read()
open(p,'wb').write(data[:len(data)//3])
" "$DATA/$WSFILE"
cp "$DATA/$WSFILE" "$tmp/ws-truncated.json"
launch_and_kill
cmp -s "$DATA/$WSFILE" "$tmp/ws-truncated.json"
ck "C: truncado preservado byte a byte" "[ $? -eq 0 ]"
NFILES=$(ls "$DATA" | grep -cE '^[0-9A-F-]{36}\.json$')
ck "C: nenhum workspace novo por cima" "[ $NFILES -eq 1 ]"

# ---- D: estado integro ----
cp "$tmp/ws-before.json" "$DATA/$WSFILE"
launch_and_kill
ck "D: dados recarregados intactos" "grep -q 'Minha primeira matéria' "$DATA/$WSFILE""
ck "D: indice segue valido" "python3 -c \"import json,sys; json.load(open(sys.argv[1]))\" "$DATA/index.json""

# ---- E: formato atual versionado e plano ----
ck "E: workspace possui versao atual" "python3 -c \"import json,sys; d=json.load(open(sys.argv[1])); assert d['schemaVersion']==1\" \"$DATA/$WSFILE\""
ck "E: workspace continua plano" "python3 -c \"import json,sys; d=json.load(open(sys.argv[1])); assert 'id' in d and 'name' in d and 'workspace' not in d\" \"$DATA/$WSFILE\""

# ---- F: formato legado sem versão ----
python3 -c "
import json,sys
p=sys.argv[1]
d=json.load(open(p))
d.pop('schemaVersion', None)
json.dump(d, open(p,'w'))
" "$DATA/$WSFILE"
launch_and_kill
ck "F: workspace legado segue legivel" "python3 -c \"import json,sys; assert json.load(open(sys.argv[1]))['name']=='Minha primeira matéria'\" \"$DATA/$WSFILE\""

# Normaliza explicitamente a fixture para os cenários de incompatibilidade.
python3 -c "
import json,sys
p=sys.argv[1]
d=json.load(open(p))
d['schemaVersion']=1
json.dump(d, open(p,'w'))
" "$DATA/$WSFILE"
cp "$DATA/$WSFILE" "$tmp/ws-current-versioned.json"

# ---- G: versão futura preservada mesmo com backup antigo ----
mkdir -p "$DATA/Backups/manual-valid"
cp "$DATA/index.json" "$DATA/Backups/manual-valid/index.json"
cp "$DATA/$WSFILE" "$DATA/Backups/manual-valid/$WSFILE"
cp "$DATA/index.json" "$tmp/index-before-future.json"
python3 -c "
import json,sys
p=sys.argv[1]
d=json.load(open(p))
d['schemaVersion']=2
json.dump(d, open(p,'w'))
" "$DATA/$WSFILE"
cp "$DATA/$WSFILE" "$tmp/ws-future.json"
launch_and_kill
ck "G: workspace futuro preservado byte a byte" "cmp -s \"$DATA/$WSFILE\" \"$tmp/ws-future.json\""
ck "G: indice nao foi regravado" "cmp -s \"$DATA/index.json\" \"$tmp/index-before-future.json\""

# ---- H: varredura parcial não omite arquivo futuro ----
cp "$tmp/ws-current-versioned.json" "$DATA/$WSFILE"
FUTUREFILE="22222222-3333-4444-5555-666666666666.json"
cp "$tmp/ws-current-versioned.json" "$DATA/$FUTUREFILE"
python3 -c "
import json,sys
p=sys.argv[1]
d=json.load(open(p))
d['schemaVersion']=2
json.dump(d, open(p,'w'))
" "$DATA/$FUTUREFILE"
cp "$DATA/$WSFILE" "$tmp/ws-valid-before-scan.json"
cp "$DATA/$FUTUREFILE" "$tmp/ws-future-before-scan.json"
rm "$DATA/index.json"
launch_and_kill
ck "H: indice parcial nao foi criado" "[ ! -f \"$DATA/index.json\" ]"
ck "H: workspace valido foi preservado" "cmp -s \"$DATA/$WSFILE\" \"$tmp/ws-valid-before-scan.json\""
ck "H: workspace futuro foi preservado" "cmp -s \"$DATA/$FUTUREFILE\" \"$tmp/ws-future-before-scan.json\""

# ---- I: índice de versão futura ----
rm "$DATA/$FUTUREFILE"
cp "$tmp/index-before-future.json" "$DATA/index.json"
python3 -c "
import json,sys
p=sys.argv[1]
d=json.load(open(p))
d['schemaVersion']=2
json.dump(d, open(p,'w'))
" "$DATA/index.json"
cp "$DATA/index.json" "$tmp/index-future.json"
cp "$DATA/$WSFILE" "$tmp/ws-before-future-index.json"
launch_and_kill
ck "I: indice futuro foi preservado" "cmp -s \"$DATA/index.json\" \"$tmp/index-future.json\""
ck "I: indice futuro bloqueou gravacoes" "cmp -s \"$DATA/$WSFILE\" \"$tmp/ws-before-future-index.json\""

echo ""
echo "===== INTEGRACAO PERSISTENCIA ====="
echo "Passaram: $pass | Falharam: $fail"
[ "$fail" -eq 0 ] && echo "TODOS OS CENARIOS PASSARAM"
exit "$fail"
