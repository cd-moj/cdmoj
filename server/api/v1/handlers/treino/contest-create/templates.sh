# GET/POST /treino/contest-create/templates  (auth treino, pode criar)
# Templates NOMEADOS de contest, POR CRIADOR (contests/treino/var/contest-templates/<login>.json).
# GET            -> lista os meus; ?name=<n> -> {template:{name,spec}} (404 se não existe).
# POST {op:save, name, (template:{...} | from_contest:<cid>, include_problems?)} — o spec é
#      RELATIVIZADO + WHITELIST no servidor (nunca guarda usuários/senhas/datas absolutas/id);
#      from_contest exige DONO do contest ou admin (senão 404 — não vaza existência).
# POST {op:delete, name} | {op:rename, name, new_name}
require_auth_contest treino
source "$_LIBDIR/contest-create.sh"
cc_can_create "$SESSION_LOGIN" || fail 403 "Sem permissão para criar contest" "create_forbidden"
TF="$(cc_tpl_file "$SESSION_LOGIN")"

if [[ "${REQUEST_METHOD:-GET}" == GET ]]; then
  name="$(param name)"
  cur="$(cc_tpl_read "$SESSION_LOGIN")"
  if [[ -n "$name" ]]; then
    jq -e --arg n "$name" '.templates|has($n)' >/dev/null 2>&1 <<<"$cur" || fail 404 "Template não encontrado" "notfound"
    ok_json '{template:{name:$n, spec:($t.templates[$n].spec // {}), created_at:($t.templates[$n].created_at // 0), updated_at:($t.templates[$n].updated_at // 0)}}' \
      --arg n "$name" --argjson t "$cur"
    exit 0
  fi
  ok_json '{templates:$l, total:($l|length)}' --argjson l "$(jq -c '
    [ .templates | to_entries[]
      | {name:.key, created_at:(.value.created_at // 0), updated_at:(.value.updated_at // 0),
         mode:(.value.spec.mode // null), duration:(.value.spec.duration // null),
         has_problems:(((.value.spec.problems // [])|length) > 0)} ]
    | sort_by(.name)' <<<"$cur")"
  exit 0
fi

require_method POST
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
op="$(jq -r '.op // empty' <<<"$body")"
name="$(jq -r '.name // empty' <<<"$body")"
cc_tpl_valid_name "$name" || fail 422 "Nome de template inválido (1–80 chars)" "name_invalid"
cur="$(cc_tpl_read "$SESSION_LOGIN")"

tpl_write(){ # grava $1 (JSON completo do arquivo) atômico
  mkdir -p "$(dirname "$TF")"
  local tmp; tmp="$(mktemp "$TF.XXXXXX")" || fail 500 "tmp" "tmp"
  printf '%s' "$1" > "$tmp" && mv -f "$tmp" "$TF" || { rm -f "$tmp"; fail 500 "Falha ao gravar" "write_fail"; }
}

case "$op" in
  save)
    src=""
    from="$(jq -r '.from_contest // empty' <<<"$body")"
    incp="$(jq -r 'if .include_problems==true then "1" else "0" end' <<<"$body")"
    if [[ -n "$from" ]]; then
      valid_id "$from" || fail 422 "from_contest inválido" "from_invalid"
      cdir="$CONTESTSDIR/$from"
      cowner="$(head -1 "$cdir/owner" 2>/dev/null)"
      { [[ -f "$cdir/created-by" && -f "$cdir/conf" ]] && { is_admin || [[ -n "$cowner" && "$cowner" == "$SESSION_LOGIN" ]]; }; } \
        || fail 404 "Contest não encontrado" "notfound"
      src="$(cc_export_spec "$from" none)" || fail 500 "Falha ao ler o contest" "export_fail"
    else
      src="$(jq -c '.template // empty' <<<"$body")"
      [[ -n "$src" ]] || fail 422 "Informe template{} ou from_contest" "template_missing"
      # template vindo do formulário: se tiver problemas, preserva (equivale a include_problems)
      [[ "$(jq -r '(.problems // [])|length' <<<"$src")" -gt 0 ]] && incp=1
    fi
    spec="$(cc_tpl_relativize "$incp" <<<"$src")"
    [[ -n "$spec" ]] || fail 422 "Template vazio/inválido" "template_invalid"
    (( ${#spec} <= CC_TPL_MAX_SPEC_BYTES )) || fail 422 "Template grande demais" "template_big"
    n_have="$(jq -r '.templates|length' <<<"$cur")"
    jq -e --arg n "$name" '.templates|has($n)' >/dev/null 2>&1 <<<"$cur" || \
      (( n_have < CC_TPL_MAX_PER_USER )) || fail 422 "Limite de $CC_TPL_MAX_PER_USER templates" "too_many"
    new="$(jq -c --arg n "$name" --argjson s "$spec" --argjson t "$EPOCHSECONDS" '
      .templates[$n] = {created_at:((.templates[$n].created_at) // $t), updated_at:$t, spec:$s}' <<<"$cur")"
    tpl_write "$new"
    audit_log contest-template "op=save name=$name from=${from:-form}"
    ok_json '{saved:true, name:$n}' --arg n "$name"
    ;;
  delete)
    jq -e --arg n "$name" '.templates|has($n)' >/dev/null 2>&1 <<<"$cur" || fail 404 "Template não encontrado" "notfound"
    tpl_write "$(jq -c --arg n "$name" 'del(.templates[$n])' <<<"$cur")"
    audit_log contest-template "op=delete name=$name"
    ok_json '{deleted:true, name:$n}' --arg n "$name"
    ;;
  rename)
    newname="$(jq -r '.new_name // empty' <<<"$body")"
    cc_tpl_valid_name "$newname" || fail 422 "new_name inválido" "newname_invalid"
    jq -e --arg n "$name" '.templates|has($n)' >/dev/null 2>&1 <<<"$cur" || fail 404 "Template não encontrado" "notfound"
    jq -e --arg n "$newname" '.templates|has($n)' >/dev/null 2>&1 <<<"$cur" && fail 409 "Já existe template com esse nome" "name_taken"
    tpl_write "$(jq -c --arg o "$name" --arg n "$newname" '.templates[$n]=.templates[$o] | del(.templates[$o])' <<<"$cur")"
    audit_log contest-template "op=rename name=$name new=$newname"
    ok_json '{renamed:true, name:$n}' --arg n "$newname"
    ;;
  *) fail 400 "op inválida (save|delete|rename)" "op_invalid" ;;
esac
