# GET /contest/doc?contest=<c>[&type=<info-sheet|contest|times>&lang=<pt|en>&fmt=<pdf|html>]
# SEM `type`  -> LISTA os documentos que o login pode baixar (JSON).
# COM `type`  -> baixa o arquivo.
# ACESSO (cortado AQUI, nunca só na UI):
#   admin / juiz-chefe  -> sempre (mesmo antes de publicar; é a revisão deles)
#   .cstaff / .staff / times / demais -> SÓ se o documento estiver PUBLICADO
# O caderno da prova é conteúdo de PROVA: antes de publicar ninguém além de admin/chief vê.
require_auth_contest "$(param contest)"
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
source "$_DIR/lib/contest-docs.sh"

t="$(param type)"; l="$(param lang)"; f="$(param fmt)"

# --- listagem (é o que a sede e a aba só-leitura consomem) ---------------------------
if [[ -z "$t" ]]; then
  idx="$(doc_index "$contest")"; [[ -n "$idx" ]] || idx='[]'   # já traz .published
  all=false; is_admin_or_chief && all=true
  body="$(jq -cn --argjson d "$idx" --argjson all "$all" \
    '{success:true, can_manage:$all, docs: ($d | map(select($all or .published)))}')"
  [[ -n "$body" ]] || fail 500 "Falha ao montar a resposta" "build_fail"
  emit_json 200 OK; printf '%s\n' "$body"; exit 0
fi

case "$t" in info-sheet|contest|times) ;; *) fail 400 "type inválido" "type_invalid";; esac
[[ "$l" == pt || "$l" == en ]] || fail 400 "lang deve ser pt|en" "lang_invalid"
case "$f" in pdf|html) ;; *) f=pdf;; esac

if ! is_admin_or_chief; then
  jq -e --arg k "$t.$l" '((.published // []) | index($k)) != null' <<<"$(doc_conf_get "$contest")" >/dev/null 2>&1 \
    || fail 404 "Documento não disponível" "not_published"
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
