# GET /contest/doc?contest=<c>[&type=<info-sheet|contest|times|editorial>&lang=<pt|en>&fmt=<pdf|html>]
# SEM `type`  -> LISTA os documentos que o login pode baixar (JSON).
# COM `type`  -> baixa o arquivo.
# ACESSO (cortado AQUI, nunca só na UI):
#   admin / juiz-chefe               -> sempre (mesmo antes de publicar; é a revisão deles)
#   ORGANIZAÇÃO (.judge/.staff/.cstaff/.mon) -> se PUBLICADO (a sede imprime ANTES da prova)
#   TIMES / demais -> publicado E, para `contest`/`times`, só a partir do INÍCIO
#     (contest_phase != before — publicar p/ a sede não pode vazar a prova p/ time logado
#     no aquecimento); para `editorial`, só depois do FIM p/ TODOS (contest_over_for_all —
#     sede prorrogada segura o editorial). `info-sheet` é logística: publicado = visível.
require_auth_contest "$(param contest)"
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
source "$_DIR/lib/contest-docs.sh"
source "$_DIR/lib/contest-gate.sh"

# organização = vê publicado ANTES do início (impressão/entrega); time espera a fase
_doc_org=false
{ is_admin_or_chief || is_judge || is_staff || is_cstaff || is_mon; } && _doc_org=true
# _doc_phase_ok <type> -> 0 se ESTE login pode ver o tipo AGORA (fase; publicação à parte)
_doc_phase_ok(){
  [[ "$_doc_org" == true ]] && return 0
  case "$1" in
    contest|times) [[ "$(contest_phase "$contest")" != before ]] ;;
    editorial)     contest_over_for_all "$contest" ;;
    *) return 0 ;;
  esac
}

t="$(param type)"; l="$(param lang)"; f="$(param fmt)"

# --- listagem (é o que a sede e a aba só-leitura consomem) ---------------------------
if [[ -z "$t" ]]; then
  idx="$(doc_index "$contest")"; [[ -n "$idx" ]] || idx='[]'   # já traz .published
  all=false; is_admin_or_chief && all=true
  # o filtro de FASE vale na listagem também: o time nem vê a linha do que não pode baixar
  vis='[]'
  while IFS= read -r ty; do
    [[ -n "$ty" ]] || continue
    _doc_phase_ok "$ty" && vis="$(jq -c --arg t "$ty" '. + [$t]' <<<"$vis")"
  done < <(jq -r 'map(.type) | unique | .[]' <<<"$idx" 2>/dev/null)
  # `.type` BINDADO antes do pipe ($vis | index(…)): o argumento avalia contra a ENTRADA do
  # pipe (o array $vis), não contra o doc — sem o bind era "Cannot index array with string"
  body="$(jq -cn --argjson d "$idx" --argjson all "$all" --argjson vis "$vis" \
    '{success:true, can_manage:$all,
      docs: ($d | map(.type as $ty
             | select($all or (.published and (($vis | index($ty)) != null)))))}')"
  [[ -n "$body" ]] || fail 500 "Falha ao montar a resposta" "build_fail"
  emit_json 200 OK; printf '%s\n' "$body"; exit 0
fi

case "$t" in info-sheet|contest|times|editorial) ;; *) fail 400 "type inválido" "type_invalid";; esac
[[ "$l" == pt || "$l" == en ]] || fail 400 "lang deve ser pt|en" "lang_invalid"
case "$f" in pdf|html) ;; *) f=pdf;; esac

if ! is_admin_or_chief; then
  jq -e --arg k "$t.$l" '((.published // []) | index($k)) != null' <<<"$(doc_conf_get "$contest")" >/dev/null 2>&1 \
    || fail 404 "Documento não disponível" "not_published"
  _doc_phase_ok "$t" || fail 404 "Documento não disponível" "not_available_yet"
fi

file="$(doc_file "$contest" "$t" "$l" "$f")"
[[ -s "$file" ]] || fail 404 "Documento não gerado" "not_generated"

name="$contest-$t.$l.$f"
if [[ "$f" == pdf ]]; then ct="application/pdf"; disp="inline"; else ct="text/html; charset=utf-8"; disp="inline"; fi
printf 'Status: 200 OK\r\n'
printf 'Content-Type: %s\r\n' "$ct"
printf 'Content-Disposition: %s; filename="%s"\r\n' "$disp" "$name"
printf 'Content-Length: %s\r\n' "$(stat -c%s "$file" 2>/dev/null || echo 0)"
printf '\r\n'
cat "$file"
