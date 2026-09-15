# GET /contest/statement?contest=<id>&problem=<letra|problem_id>&format=html|pdf&lang=pt|en|es   (Bearer)
# Serve UM enunciado da prova, cru (text/html ou application/pdf).
# IDIOMA (2026-09-15): `lang` (default = o idioma padrão do contest) tem de estar na allowlist
# (400 `lang_invalid`) E na lista que o contest OFERECE (`STATEMENT_LANGS`; fora dela = 404, como
# um problema inexistente); o arquivo é `enunciados/<skey>.<lang>.<fmt>` com fallback p/ o PT
# (`<skey>.<fmt>`) — tradução ausente nunca é erro, é o PT. ETag pelo arquivo RESOLVIDO.
#
# POR QUE EXISTE: o /contest/problems mandava todos os enunciados em base64 dentro da lista —
# num contest de PDF, 3,8 MB por time (base64 de PDF não comprime), e 2000 times abrindo a prova
# no mesmo segundo são ~5 GB de uma vez para entregar 12 enunciados que cada um lê de um em um.
# Aqui é sob demanda: a pessoa abre a sanfona ou clica em HTML/PDF. Mesma doutrina do
# /contest/doc (documentos da prova só baixam quando alguém clica no link).
#
# O GATE É O MESMO da lista (`can_see_problems`): .staff nunca vê enunciado, competidor só
# depois do início, admin/juiz sempre. Aqui a resposta é **404**, não 403 — pedir o enunciado
# direto não pode nem confirmar que o problema existe antes de a prova abrir.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"

source "$_LIBDIR/contest-gate.sh"
can_see_problems "$contest" || fail 404 "Not found" "statement_notfound"

ref="$(param problem)"
[[ -n "$ref" ]] || fail 400 "Missing problem" "problem_missing"
fmt="$(param format)"; [[ -n "$fmt" ]] || fmt=html
[[ "$fmt" == html || "$fmt" == pdf ]] || fail 400 "Invalid format" "format_invalid"
source "$_LIBDIR/contest-statement.sh"
OFFERED="$(cs_langs "$contest")"
lang="$(param lang)"
if [[ -z "$lang" ]]; then lang="$(cs_default "$contest" "$OFFERED")"
else stmt_lang_ok "$lang" || fail 400 "Invalid lang" "lang_invalid"; fi
[[ " $OFFERED " == *" $lang "* ]] || fail 404 "Not found" "statement_notfound"

CONTEST_ID="$contest"; PROBS=()
load_contest_conf "$contest"

# resolve a chave do enunciado pela LETRA (short_name, o que a tela e a CLI conhecem) ou pelo
# problem_id canônico. A chave nunca vem do cliente: sai sempre do PROBS do conf — é o que
# impede um `problem=../../etc/passwd` de virar caminho.
STATEMENT=""
for (( i=0; i<${#PROBS[@]}; i+=5 )); do
  pid="${PROBS[$((i+4))]}"
  [[ "$pid" == *"#"* ]] || pid="${PROBS[$((i+1))]//\//#}"
  if [[ "$ref" == "${PROBS[$((i+3))]}" || "$ref" == "$pid" ]]; then
    STATEMENT="${PROBS[$((i+4))]}"; break
  fi
done
[[ -n "$STATEMENT" ]] || fail 404 "Not found" "statement_notfound"

src="$(cs_file "$contest" "$STATEMENT" "$lang" "$fmt")" || fail 404 "Not found" "statement_notfound"

# ETag por mtime+tamanho: o enunciado não muda durante a prova, e quem recarrega a página (ou
# reabre a sanfona) recebe 304 em vez de MB. `private` porque a visibilidade é por login e por
# FASE da prova — um intermediário não pode guardar isto para outro.
et="\"$(stat -c '%Y-%s' "$src" 2>/dev/null)\""
if [[ -n "${HTTP_IF_NONE_MATCH:-}" && "${HTTP_IF_NONE_MATCH}" == "$et" ]]; then
  printf 'Status: 304 Not Modified\r\nETag: %s\r\nCache-Control: private, max-age=60\r\n\r\n' "$et"
  exit 0
fi

if [[ "$fmt" == pdf ]]; then ct='application/pdf'; else ct='text/html; charset=utf-8'; fi
# X-MOJ-Statement-Lang = o idioma do ARQUIVO servido (pt quando a tradução pedida não existe)
served="$lang"; [[ "$src" == *"/$STATEMENT.$fmt" ]] && served=pt
printf 'Status: 200 OK\r\nContent-Type: %s\r\nETag: %s\r\nX-MOJ-Statement-Lang: %s\r\nCache-Control: private, max-age=60\r\n\r\n' "$ct" "$et" "$served"
cat "$src"
