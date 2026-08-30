# GET/POST /contest/nutella?contest=<id> — integração NUTELLABOOT (máquinas mlinux).
#
# GET  -> {configured, url, status, data} — o panorama coletado (var/nutella.cache.json).
#         admin/juiz-chefe: tudo; .cstaff/.staff: `sedes[]` FILTRADO ao escopo de sede
#         (tokens region: do staff-filters) — agregados global/by_node vão inteiros (não
#         carregam MAC de outra sede); demais papéis: 403.
# POST {action:"config", url?, key?}    (admin)  chave em secrets/ (600), URL no conf.
# POST {action:"collect"}               (admin)  dispara o nutella-gen.sh destacado.
# POST {action:"push-roster"}           (admin)  PUT do roster do STORE em cada imagem
#                                                (correlação p/ provas futuras).
# POST {action:"command", op, image, mac?}       admin: qualquer imagem, image:"all" =
#         frota; .cstaff/.staff: SÓ imagem da própria sede (fail-CLOSED: sem escopo
#         explícito no staff-filters = 403 — comando é AÇÃO, não leitura; diverge de
#         propósito do "ausente = vê tudo" das rotas de leitura). `op` validado contra o
#         catálogo `allowed` da imagem AO VIVO. Tudo auditado (nutella-*).
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
{ is_admin_or_chief || is_cstaff || is_staff; } || fail 403 "Apenas organização/staff do contest" "role_required"

source "$_LIBDIR/nutella.sh"
cdir="$CONTESTSDIR/$contest"
CACHE="$cdir/var/nutella.cache.json"
STF="$cdir/var/nutella.status.json"

# sedes visíveis do papel escopado (vazio = sem restrição). Falha fechada nos COMANDOS.
_nb_scope_json(){   # ecoa array JSON de nomes de sede (minúsculos) ou "null" (sem escopo)
  local regs
  if is_admin_or_chief; then printf 'null'; return 0; fi
  if regs="$(nb_staff_regions "$contest")"; then
    printf '%s\n' "$regs" | jq -Rcs 'split("\n") | map(select(length > 0) | ascii_downcase)'
  else
    printf 'null'
  fi
}

if [[ "${REQUEST_METHOD:-GET}" == GET ]]; then
  cfg=false; nb_configured "$contest" && cfg=true
  adm=false; is_admin && adm=true
  # ?catalog=<image> — proxy do catálogo de comandos da imagem (alimenta o select da UI;
  # quem manda no que PODE ser executado segue sendo o POST command, que revalida)
  catimg="$(param catalog)"
  if [[ -n "$catimg" ]]; then
    [[ "$catimg" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || fail 422 "image inválida" "image_invalid"
    [[ "$cfg" == true ]] || fail 409 "Integração não configurada" "not_configured"
    r="$(nb_curl "$contest" GET "/site-images/$catimg/commands")"
    [[ "$(nb_status "$r")" == 200 ]] || fail 502 "nutellaboot indisponível" "upstream_error"
    ok_json_slurp '{allowed:($u[0].allowed // [])}' u "$(nb_body "$r")"
    exit 0
  fi
  st='null'; [[ -s "$STF" ]] && st="$(cat "$STF" 2>/dev/null)"; [[ -n "$st" ]] || st='null'
  jq -e . >/dev/null 2>&1 <<<"$st" || st='null'
  scope="$(_nb_scope_json)"
  if [[ ! -s "$CACHE" ]]; then
    ok_json '{configured:$c, url:$u, status:$st, can_admin:$a, scoped:($sc != null), data:null}' \
      --argjson c "$cfg" --arg u "$(nb_url "$contest")" --argjson st "$st" \
      --argjson a "$adm" --argjson sc "$scope"
    exit 0
  fi
  # o corte de escopo acontece AQUI (API, nunca UI): .cstaff/.staff levam só as sedes
  # deles em `sedes[]` (com máquinas/MACs); os agregados seguem inteiros.
  ok_json '{configured:$c, url:$u, status:$st, can_admin:$a, scoped:($sc != null),
            data:($d[0] | if $sc == null then .
                  else (.sedes |= map(select((.name | ascii_downcase) as $n | $sc | index($n)))) end)}' \
    --argjson c "$cfg" --arg u "$(nb_url "$contest")" --argjson st "$st" \
    --argjson a "$adm" --slurpfile d "$CACHE" --argjson sc "$scope"
  exit 0
fi

require_method POST
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
action="$(jq -r '.action // ""' <<<"$body")"

case "$action" in
config)
  is_admin || fail 403 "Apenas o admin do contest" "admin_required"
  url="$(jq -r '.url // ""' <<<"$body")"
  if [[ -n "$url" ]]; then
    [[ "$url" =~ ^https?://[A-Za-z0-9._:-]+/?$ ]] || fail 422 "URL inválida" "url_invalid"
    source "$_LIBDIR/contest-create.sh"
    cc_set_conf_var "$contest" NUTELLABOOT_URL "${url%/}"
  fi
  if jq -e 'has("key")' >/dev/null 2>&1 <<<"$body"; then
    key="$(jq -r '.key // ""' <<<"$body")"
    kf="$(nb_keyfile "$contest")"
    if [[ -z "$key" ]]; then
      rm -f "$kf"
    else
      [[ "$key" =~ ^nb3a_[A-Za-z0-9]+$ ]] || fail 422 "chave inválida (esperado nb3a_…)" "key_invalid"
      mkdir -p "${kf%/*}" 2>/dev/null; chmod 700 "${kf%/*}" 2>/dev/null
      # escrita atômica com modo certo ANTES do conteúdo (a chave nunca fica legível a
      # mais). ⚠ o nome do tmp é resolvido FORA do subshell: $BASHPID muda lá dentro.
      tmpf="$kf.tmp.$BASHPID"
      ( umask 077; printf '%s\n' "$key" > "$tmpf" ) && mv -f "$tmpf" "$kf"
    fi
  fi
  audit_log_to "$contest" nutella-config "url=$([[ -n "$url" ]] && echo sim || echo nao) key=$(jq -r 'if has("key") then (if .key == "" then "removida" else "gravada" end) else "mantida" end' <<<"$body")"
  ok_json '{saved:true, configured:$c}' --argjson c "$(nb_configured "$contest" && echo true || echo false)"
  ;;
collect)
  is_admin || fail 403 "Apenas o admin do contest" "admin_required"
  nb_configured "$contest" || fail 409 "Integração não configurada (grave a chave primeiro)" "not_configured"
  runner="$_DIR/../../score/nutella-gen.sh"
  [[ -f "$runner" ]] || fail 500 "coletor ausente" "runner_missing"
  jq -cn --argjson t "$EPOCHSECONDS" '{running:true, phase:"enfileirada", updated_at:$t}' > "$STF" 2>/dev/null
  # destacado (molde jplag-run.sh): sobrevive ao fim da CGI; o gen tem flock próprio
  CONTESTSDIR="$CONTESTSDIR" nohup bash "$runner" "$contest" </dev/null >/dev/null 2>&1 &
  disown 2>/dev/null || true
  audit_log_to "$contest" nutella-collect "started"
  ok_json '{started:true}'
  ;;
push-roster)
  is_admin || fail 403 "Apenas o admin do contest" "admin_required"
  nb_configured "$contest" || fail 409 "Integração não configurada" "not_configured"
  [[ -s "$CACHE" ]] || fail 409 "Rode a coleta primeiro (o mapa sede→imagem vem dela)" "no_cache"
  force="$(jq -r '.force // false' <<<"$body")"
  pushed=0; failed=0; kept=0
  while IFS=$'\t' read -r img; do
    [[ "$img" =~ ^[A-Za-z0-9._-]+$ ]] || continue
    # NÃO atropela roster já povoado (o da Maratona veio do ICPC, com org ids oficiais) —
    # o push é p/ prova FUTURA nascer com a ponte pronta; force:true sobrescreve.
    if [[ "$force" != true ]]; then
      r="$(nb_curl "$contest" GET "/site-images/$img/roster")"
      if [[ "$(nb_status "$r")" == 200 ]] && jq -e '(.roster // []) | length > 0' <<<"$(nb_body "$r")" >/dev/null 2>&1; then
        kept=$((kept+1)); continue
      fi
    fi
    # roster do STORE: os times da sede desta imagem (user_id = login MOJ),
    # enriquecido com nome/univ/bandeira do account.json de cada time
    bf="$(mktemp)"
    : > "$bf.rows"
    while IFS= read -r lg; do
      af="$(account_file "$contest" "$lg")"
      [[ -f "$af" ]] || continue
      jq -c --arg l "$lg" '{user_id: $l,
        name: ((.team.name // .fullname // $l) | tostring),
        display_name: (((.team.univ_short // "") | if . == "" then "" else "[" + . + "] " end)
                       + ((.team.name // .fullname // $l) | tostring)),
        organization: {id: "", name: (.team.univ_full // .team.univ_short // "")},
        country: ((.team.flag // "") | ascii_upcase | (split("-") | .[0]))}' "$af" >> "$bf.rows" 2>/dev/null
    done < <(jq -r --arg img "$img" '.sedes[] | select(.id == $img) | .teams[]' "$CACHE" 2>/dev/null)
    jq -cs '{roster: .}' "$bf.rows" > "$bf" 2>/dev/null
    r="$(nb_curl "$contest" PUT "/site-images/$img/roster" "$bf")"
    if [[ "$(nb_status "$r")" == 2* ]]; then pushed=$((pushed+1)); else failed=$((failed+1)); fi
    rm -f "$bf" "$bf.rows"
  done < <(jq -r '.sedes[].id' "$CACHE" 2>/dev/null)
  audit_log_to "$contest" nutella-push-roster "pushed=$pushed kept=$kept failed=$failed"
  ok_json '{pushed:$p, kept:$k, failed:$f}' --argjson p "$pushed" --argjson k "$kept" --argjson f "$failed"
  ;;
command)
  nb_configured "$contest" || fail 409 "Integração não configurada" "not_configured"
  op="$(jq -r '.op // ""' <<<"$body")"
  img="$(jq -r '.image // ""' <<<"$body")"
  mac="$(jq -r '.mac // ""' <<<"$body")"
  [[ "$op" =~ ^[a-z0-9_-]{1,40}$ ]] || fail 422 "op inválida" "op_invalid"
  [[ "$img" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || fail 422 "image inválida" "image_invalid"
  [[ -z "$mac" || "$mac" =~ ^[A-Za-z0-9:-]{1,32}$ ]] || fail 422 "mac inválido" "mac_invalid"
  if ! is_admin; then
    # .cstaff/.staff: fail-CLOSED — precisa de escopo explícito e a imagem tem de ser da
    # sede dele (mapa sede→imagem sai do cache da coleta).
    [[ "$img" != all ]] || fail 403 "Frota inteira é só do admin" "admin_required"
    [[ -s "$CACHE" ]] || fail 409 "Sem coleta ainda (o mapa sede→imagem vem dela)" "no_cache"
    scope="$(_nb_scope_json)"
    [[ "$scope" != null ]] || fail 403 "Defina o escopo de sede do staff (staff-filters) antes de comandar" "command_scope_required"
    sede="$(jq -r --arg i "$img" 'first(.sedes[] | select(.id == $i) | .name) // "" | ascii_downcase' "$CACHE" 2>/dev/null)"
    [[ -n "$sede" ]] || fail 404 "Imagem desconhecida" "image_unknown"
    jq -e --arg s "$sede" 'index($s) != null' <<<"$scope" >/dev/null 2>&1 \
      || fail 403 "Esta sede não está no seu escopo" "site_forbidden"
  fi
  # op contra o catálogo AO VIVO da imagem (p/ "all", o catálogo de qualquer imagem serve
  # de allowlist — o serviço revalida no destino)
  cat_img="$img"
  if [[ "$img" == all ]]; then
    cat_img="$(jq -r '.sedes[0].id // ""' "$CACHE" 2>/dev/null)"
    [[ -n "$cat_img" ]] || fail 409 "Sem coleta ainda" "no_cache"
  fi
  r="$(nb_curl "$contest" GET "/site-images/$cat_img/commands")"
  [[ "$(nb_status "$r")" == 200 ]] || fail 502 "nutellaboot indisponível (catálogo)" "upstream_error"
  jq -e --arg op "$op" '(.allowed // []) | index($op) != null' <<<"$(nb_body "$r")" >/dev/null 2>&1 \
    || fail 422 "op fora do catálogo da imagem" "op_not_allowed"
  # shape confirmado na imagem de teste 26tete (30/08): o campo é `command`
  # (resposta: {command_id, machines}); `op` era 400 "comando não permitido".
  bf="$(mktemp)"; jq -cn --arg op "$op" '{command: $op}' > "$bf"
  if [[ "$img" == all ]]; then r="$(nb_curl "$contest" POST "/commands" "$bf")"
  elif [[ -n "$mac" ]]; then  r="$(nb_curl "$contest" POST "/site-images/$img/machines/$mac/commands" "$bf")"
  else                        r="$(nb_curl "$contest" POST "/site-images/$img/commands" "$bf")"
  fi
  rm -f "$bf"
  st="$(nb_status "$r")"
  audit_log_to "$contest" nutella-command "op=$op image=$img mac=${mac:-todas} status=$st by=$SESSION_LOGIN"
  [[ "$st" == 2* ]] || fail 502 "nutellaboot recusou o comando (HTTP $st)" "upstream_error"
  ok_json_slurp '{sent:true, op:$op, image:$img, mac:$mac, upstream:($u[0] // null)}' u "$(nb_body "$r")" \
    --arg op "$op" --arg img "$img" --arg mac "$mac"
  ;;
*)
  fail 400 "action inválida" "action_invalid"
  ;;
esac
