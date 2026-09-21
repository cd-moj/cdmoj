# GET/POST /contest/nutella?contest=<id> — integração NUTELLABOOT (máquinas mlinux).
#
# GET  -> {configured, url, status, data} — o panorama coletado (var/nutella.cache.json).
#         admin/juiz-chefe: tudo; .cstaff/.staff: `sedes[]` FILTRADO ao escopo de sede
#         (tokens region: do staff-filters) — agregados global/by_node vão inteiros (não
#         carregam MAC de outra sede); demais papéis: 403.
# POST {action:"config", url?, key?, images?}  (admin)  chave em secrets/ (600), URL e a lista
#         de site-images (`NUTELLABOOT_IMAGES`) no conf. Chave `nb3a_` (admin) OU `nb3s_` (serviço
#         — a recomendada; como ela não lista `/site-images`, a lista de sedes vem do conf).
# POST {action:"collect"}               (admin)  dispara o nutella-gen.sh destacado.
# POST {action:"push-roster"}           (admin)  PUT do roster do STORE em cada imagem
#                                                (correlação p/ provas futuras).
# POST {action:"push-bindings"}         (admin)  REPUBLICA no serviço o elo máquina↔time de todo login já
#                                                feito com o UA do agente novo (o login publica sozinho —
#                                                lib/nutella-bind.sh; isto é p/ quem logou ANTES de a
#                                                integração existir, ou antes do push-roster).
# POST {action:"webhooks-install", base_url?, force?, remove?}  (admin; exige chave de ADMINISTRAÇÃO do
#         nutellaboot — webhooks são rota de console) instala em cada sede do contest o webhook de
#         alertas apontando p/ POST /hooks/nutella?contest=<c> (handlers/hooks/nutella.sh), com um
#         segredo por contest gerado AQUI (secrets/nutella-webhook.secret, 600, write-only).
#         ⚠ O PUT do serviço SUBSTITUI a lista e o GET devolve os segredos mascarados: havendo webhook
#         de OUTRO dono na sede, recusa (409) — só `force:true` passa por cima.
# POST {action:"command", op, image, mac?}       admin: qualquer imagem, image:"all" = TODAS
#         AS SEDES DO CONTEST (uma chamada por sede — nunca a frota do serviço, que tem sedes de
#         outros eventos); .cstaff/.staff: SÓ imagem da própria sede (fail-CLOSED: sem escopo
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

# resumo da publicação do elo no login (lib/nutella-bind.sh): contagens, nunca MAC nem login
_nb_bind_json(){
  local v en=true pub=0 q=0
  v="$(conf_value "$contest" NUTELLA_BIND)"; [[ "$v" == 0 ]] && en=false
  [[ -s "$cdir/var/nutella-macs.tsv" ]] && pub="$(wc -l < "$cdir/var/nutella-macs.tsv" | tr -d '[:space:]')"
  [[ -s "$cdir/var/nutella-bind.queue" ]] && q="$(wc -l < "$cdir/var/nutella-bind.queue" | tr -d '[:space:]')"
  { [[ -s "$cdir/var/nutella-bind.log" ]] && awk -F'\t' '{ k = ($5 ~ /^http/) ? "error" : $5; n[k]++; if ($1 > t) t = $1 }
      END { for (k in n) printf "%s\t%d\n", k, n[k]; printf "_at\t%d\n", t }' "$cdir/var/nutella-bind.log"; } \
    | jq -Rcn --argjson en "$en" --argjson pub "${pub:-0}" --argjson q "${q:-0}" '
        (reduce (inputs | split("\t") | select(length == 2)) as $r ({}; .[$r[0]] = ($r[1] | tonumber))) as $m
        | {enabled: $en, published: $pub, queued: $q, last_at: ($m._at // null),
           log: {ok: ($m.ok // 0), noroster: ($m.noroster // 0), image_unknown: ($m.image_unknown // 0),
                 retry: ($m.retry // 0), error: ($m.error // 0)}}' 2>/dev/null
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
  imgs="$(nb_images "$contest" | jq -Rcn '[inputs | select(length > 0)]' 2>/dev/null)"; [[ -n "$imgs" ]] || imgs='[]'
  kk="$(nb_key_kind "$contest")"
  bd="$(_nb_bind_json)"; jq -e . >/dev/null 2>&1 <<<"$bd" || bd='null'
  # webhook de alertas: só EXISTÊNCIA do segredo e nº de eventos recebidos (o segredo é write-only)
  _wn=0; [[ -s "$cdir/var/nutella-events.log" ]] && _wn="$(wc -l < "$cdir/var/nutella-events.log" | tr -d '[:space:]')"
  bd="$(jq -c --argjson w "$([[ -s "$cdir/secrets/nutella-webhook.secret" ]] && echo true || echo false)" --argjson n "${_wn:-0}" \
        '. as $b | {bind: $b, webhook: {installed: $w, events: $n}}' <<<"$bd")"
  if [[ ! -s "$CACHE" ]]; then
    ok_json '{configured:$c, url:$u, key_kind:$kk, images:$im, status:$st, can_admin:$a, scoped:($sc != null), bind:$bd.bind, webhook:$bd.webhook, data:null}' \
      --argjson c "$cfg" --arg u "$(nb_url "$contest")" --argjson st "$st" \
      --argjson a "$adm" --argjson sc "$scope" --arg kk "$kk" --argjson im "$imgs" --argjson bd "$bd"
    exit 0
  fi
  # o corte de escopo acontece AQUI (API, nunca UI): .cstaff/.staff levam só as sedes
  # deles em `sedes[]` (com máquinas/MACs); os agregados seguem inteiros.
  ok_json '{configured:$c, url:$u, key_kind:$kk, images:$im, status:$st, can_admin:$a, scoped:($sc != null), bind:$bd.bind, webhook:$bd.webhook,
            data:($d[0] | if $sc == null then .
                  else (.sedes |= map(select((.name | ascii_downcase) as $n | $sc | index($n)))) end)}' \
    --argjson c "$cfg" --arg u "$(nb_url "$contest")" --argjson st "$st" \
    --argjson a "$adm" --slurpfile d "$CACHE" --argjson sc "$scope" --arg kk "$kk" --argjson im "$imgs" --argjson bd "$bd"
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
      [[ "$key" =~ ^nb3[as]_[A-Za-z0-9]+$ ]] || fail 422 "chave inválida (esperado nb3s_… de serviço, ou nb3a_… de administração)" "key_invalid"
      mkdir -p "${kf%/*}" 2>/dev/null; chmod 700 "${kf%/*}" 2>/dev/null
      # escrita atômica com modo certo ANTES do conteúdo (a chave nunca fica legível a
      # mais). ⚠ o nome do tmp é resolvido FORA do subshell: $BASHPID muda lá dentro.
      tmpf="$kf.tmp.$BASHPID"
      ( umask 077; printf '%s\n' "$key" > "$tmpf" ) && mv -f "$tmpf" "$kf"
    fi
  fi
  # lista de site-images do evento (obrigatória com chave de SERVIÇO, que não lista /site-images)
  if jq -e 'has("images")' >/dev/null 2>&1 <<<"$body"; then
    imgl="$(jq -r '(.images // "") | if type == "array" then join(" ") else tostring end' <<<"$body" | tr -s ',;\n\t ' ' ')"
    imgl="${imgl# }"; imgl="${imgl% }"
    for _i in $imgl; do [[ "$_i" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || fail 422 "site-image inválida: $_i" "images_invalid"; done
    source "$_LIBDIR/contest-create.sh"
    cc_set_conf_var "$contest" NUTELLABOOT_IMAGES "$imgl"
  fi
  # publicar o elo máquina↔time no login (ligado por omissão; `bind:false` grava NUTELLA_BIND=0)
  if jq -e 'has("bind")' >/dev/null 2>&1 <<<"$body"; then
    source "$_LIBDIR/contest-create.sh"
    if [[ "$(jq -r '.bind' <<<"$body")" == false ]]; then cc_set_conf_var "$contest" NUTELLA_BIND 0; else cc_del_conf_var "$contest" NUTELLA_BIND; fi
  fi
  if [[ -n "$url" || -s "$(nb_keyfile "$contest")" ]]; then mod_enable "$contest" maquinas; fi
  audit_log_to "$contest" nutella-config "url=$([[ -n "$url" ]] && echo sim || echo nao) key=$(jq -r 'if has("key") then (if .key == "" then "removida" else "gravada" end) else "mantida" end' <<<"$body")"
  ok_json '{saved:true, configured:$c, key_kind:$kk}' --argjson c "$(nb_configured "$contest" && echo true || echo false)" \
    --arg kk "$(nb_key_kind "$contest")"
  ;;
collect)
  is_admin || fail 403 "Apenas o admin do contest" "admin_required"
  nb_configured "$contest" || fail 409 "Integração não configurada (grave a chave primeiro)" "not_configured"
  runner="$_DIR/../../score/nutella-gen.sh"
  [[ -f "$runner" ]] || fail 500 "coletor ausente" "runner_missing"
  jq -cn --argjson t "$EPOCHSECONDS" '{running:true, phase:"enfileirada", updated_at:$t}' > "$STF" 2>/dev/null
  # destacado, com os redirects NO SETSID (molde owner_rename_bg): um `nohup … &` herdava o socket do
  # CGI e, sob o fcgiwrap, o cliente podia ficar esperando a coleta. O gen tem flock próprio.
  ( setsid env CONTESTSDIR="$CONTESTSDIR" RUNDIR="${RUNDIR:-}" bash "$runner" "$contest" </dev/null >/dev/null 2>&1 & ) 2>/dev/null
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
webhooks-install)
  is_admin || fail 403 "Apenas o admin do contest" "admin_required"
  nb_configured "$contest" || fail 409 "Integração não configurada" "not_configured"
  [[ "$(nb_key_kind "$contest")" == admin ]] \
    || fail 409 "Webhooks são rota de console do nutellaboot: grave uma chave de ADMINISTRAÇÃO (nb3a_) para instalar; depois pode voltar à de serviço" "admin_key_required"
  force="$(jq -r '.force // false' <<<"$body")"; remove="$(jq -r '.remove // false' <<<"$body")"
  base="$(jq -r '.base_url // ""' <<<"$body")"; base="${base%/}"
  if [[ -z "$base" ]]; then
    # pelo subdomínio do contest a rota /hooks é barrada (isolamento): aí a URL base tem de vir no pedido
    [[ -z "${CONTEST_HOST:-}" && -n "${HTTP_HOST:-}" ]] || fail 422 "Informe base_url (a URL pública do MOJ, fora do subdomínio do contest)" "base_url_required"
    base="https://${HTTP_HOST}"
  fi
  [[ "$base" =~ ^https?://[A-Za-z0-9.-]+(:[0-9]{1,5})?$ ]] || fail 422 "base_url inválida" "base_url_invalid"
  hook="$base/api/v1/hooks/nutella?contest=$contest"
  mapfile -t _hs < <({ jq -r '.sedes[]?.id // empty' "$CACHE" 2>/dev/null; nb_images "$contest"; } | sort -u)
  (( ${#_hs[@]} )) || fail 409 "Sem sedes: colete uma vez ou informe as site-images do evento" "no_sites"
  secf="$cdir/secrets/nutella-webhook.secret"
  # 1ª passada: só LÊ — webhook alheio em qualquer sede pára tudo antes de escrever em alguma
  foreign=0; declare -A _cur=()
  for _t in "${_hs[@]}"; do
    [[ "$_t" =~ ^[A-Za-z0-9._-]+$ ]] || continue
    r="$(nb_curl "$contest" GET "/site-images/$_t/webhooks")"
    [[ "$(nb_status "$r")" == 200 ]] || fail 502 "nutellaboot recusou a leitura dos webhooks de $_t (HTTP $(nb_status "$r"))" "upstream_error"
    n="$(jq -r --arg u "$hook" '[ (.webhooks // [])[] | select(.url != $u) ] | length' <<<"$(nb_body "$r")" 2>/dev/null)"
    _cur["$_t"]="${n:-0}"; foreign=$(( foreign + ${n:-0} ))
  done
  if (( foreign > 0 )) && [[ "$force" != true ]]; then
    fail 409 "Há $foreign webhook(s) de outro dono nas sedes; o nutellaboot só sabe SUBSTITUIR a lista (force:true apaga os deles)" "foreign_webhooks"
  fi
  if [[ "$remove" != true && ! -s "$secf" ]]; then
    mkdir -p "$cdir/secrets"; chmod 700 "$cdir/secrets" 2>/dev/null
    ( umask 077; LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 48 > "$secf.tmp"; printf '\n' >> "$secf.tmp" ) && mv -f "$secf.tmp" "$secf"
  fi
  bf="$(umask 077; mktemp)"
  if [[ "$remove" == true ]]; then printf '{"webhooks":[]}' > "$bf"
  else  # o segredo entra por --rawfile: nunca em argv
    jq -cn --rawfile s "$secf" --arg u "$hook" \
      '{webhooks: [{url: $u, secret: ($s | gsub("[\\r\\n]"; "")), events: ["alert.raised", "alert.dismissed"]}]}' > "$bf"
  fi
  okn=0; badn=0; res='{}'
  for _t in "${_hs[@]}"; do
    [[ -n "${_cur[$_t]+x}" ]] || continue
    r="$(nb_curl "$contest" PUT "/site-images/$_t/webhooks" "$bf")"; st="$(nb_status "$r")"
    if [[ "$st" == 2* ]]; then okn=$((okn+1)); else badn=$((badn+1)); fi
    res="$(jq -c --arg k "$_t" --argjson s "${st:-0}" --argjson f "${_cur[$_t]}" '.[$k] = {status: $s, replaced_foreign: $f}' <<<"$res")"
  done
  rm -f "$bf"
  [[ "$remove" == true && $badn -eq 0 ]] && rm -f "$secf"
  audit_log_to "$contest" nutella-webhooks "$([[ "$remove" == true ]] && echo remove || echo install) ok=$okn failed=$badn foreign=$foreign force=$force"
  ok_json '{installed:($rm | not), url:$u, ok:$o, failed:$f, sedes:$r}' --argjson rm "$remove" --arg u "$hook" \
    --argjson o "$okn" --argjson f "$badn" --argjson r "$res"
  ;;
push-bindings)
  is_admin || fail 403 "Apenas o admin do contest" "admin_required"
  nb_configured "$contest" || fail 409 "Integração não configurada" "not_configured"
  [[ -s "$cdir/var/access.log" ]] || fail 409 "Nenhum login registrado ainda" "no_logins"
  source "$_LIBDIR/nutella-bind.sh"
  # REPLAY do access.log pela MESMA fila do login: último login de cada MAC (UA do agente novo),
  # conta de papel fora. O drenador dedupa contra o que já foi publicado e aplica a lista de sedes.
  qf="$(mktemp)"
  jq -Rrn '
    [ inputs | split("\t") | select(length >= 4)
      | (.[0] | tonumber? // 0) as $t | .[1] as $lg
      | select(($lg | test("\\.(admin|judge|cjudge|staff|cstaff|mon|animeitor)$")) | not)
      | ((.[3] | try @base64d catch "")
         | capture("MLinux/(?<img>[A-Za-z0-9._-]{1,64})/[0-9a-f]{32}/(?<boot>[0-9]{1,20})/(?<mac>[0-9a-f]{2}([-:][0-9a-f]{2}){5})")? // null) as $m
      | select($m != null) | {t: $t, lg: $lg, img: $m.img, boot: $m.boot, mac: ($m.mac | gsub(":"; "-"))} ]
    | sort_by(.t) | reduce .[] as $e ({}; .[$e.mac] = $e)
    | .[] | "\(.t)\t\(.lg)\t\(.img)\t\(.mac)\t\(.boot)"' "$cdir/var/access.log" > "$qf" 2>/dev/null
  nq="$(wc -l < "$qf" | tr -d '[:space:]')"; nq="${nq:-0}"
  if (( nq > 0 )); then
    cat "$qf" >> "$cdir/var/nutella-bind.queue"
    if [[ "${MOJ_JOBS_SYNC:-0}" == 1 ]]; then nb_bind_drain "$contest"; else nb_bind_drain_bg "$contest"; fi
  fi
  rm -f "$qf"
  audit_log_to "$contest" nutella-push-bindings "queued=$nq"
  ok_json '{queued:$q, bind:$bd}' --argjson q "$nq" --argjson bd "$(_nb_bind_json)"
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
  # SEDES-ALVO. `all` = as sedes DO CONTEST (cache da coleta; sem cache, a lista do conf) — nunca
  # a frota do serviço: o nutellaboot hospeda sedes de OUTROS eventos e `POST /commands` atinge
  # todas (além de exigir credencial de console, que a chave de serviço não tem).
  targets=()
  if [[ "$img" == all ]]; then
    while IFS= read -r _t; do [[ "$_t" =~ ^[A-Za-z0-9._-]{1,64}$ ]] && targets+=("$_t"); done \
      < <({ jq -r '.sedes[].id' "$CACHE" 2>/dev/null; nb_images "$contest"; } | awk 'NF && !seen[$0]++')
    (( ${#targets[@]} )) || fail 409 "Sem sedes conhecidas — rode a coleta ou informe as site-images" "no_cache"
  else
    targets=("$img")
  fi
  # op contra o catálogo AO VIVO (da 1ª sede-alvo; o serviço revalida em cada destino)
  r="$(nb_curl "$contest" GET "/site-images/${targets[0]}/commands")"
  [[ "$(nb_status "$r")" == 200 ]] || fail 502 "nutellaboot indisponível (catálogo)" "upstream_error"
  jq -e --arg op "$op" '(.allowed // []) | index($op) != null' <<<"$(nb_body "$r")" >/dev/null 2>&1 \
    || fail 422 "op fora do catálogo da imagem" "op_not_allowed"
  # SHAPE (NutellaBoot 3, conferido na 26tete em 21/09/2026): SEMPRE a rota DA SEDE,
  #   POST /site-images/{i}/commands  {command, target: "all" | [mac,…]}  ->  {command_id, machines}
  # Até então o comando POR MÁQUINA ia a `POST …/machines/{mac}/commands`, que NÃO EXISTE (405:
  # aquele caminho só tem o GET do long-poll da própria máquina), e o de FROTA mandava `{command}`
  # a `POST /commands`, que exige `targets` (400). O mock aceitava qualquer POST e escondeu os dois.
  bf="$(mktemp)"; resf="$(mktemp)"; : > "$resf"; okn=0; badn=0; st=""
  if [[ -n "$mac" ]]; then jq -cn --arg op "$op" --arg m "$mac" '{command: $op, target: [$m]}' > "$bf"
  else                     jq -cn --arg op "$op" '{command: $op, target: "all"}' > "$bf"; fi
  for _t in "${targets[@]}"; do
    r="$(nb_curl "$contest" POST "/site-images/$_t/commands" "$bf")"; st="$(nb_status "$r")"
    if [[ "$st" == 2* ]]; then okn=$((okn+1)); else badn=$((badn+1)); fi
    jq -cn --arg i "$_t" --arg st "$st" --arg b "$(nb_body "$r" | head -c 2000)" \
      '{key:$i, value:({status:($st|tonumber? // 0)} + (try ($b|fromjson) catch {} | if type=="object" then {command_id, machines, detail} else {} end | with_entries(select(.value != null))))}' >> "$resf"
    audit_log_to "$contest" nutella-command "op=$op image=$_t mac=${mac:-todas} status=$st by=$SESSION_LOGIN"
  done
  rm -f "$bf"
  if (( okn == 0 )); then
    det="$(jq -rs 'map(.value.detail // empty) | first // ""' "$resf" 2>/dev/null)"; rm -f "$resf"
    fail 502 "nutellaboot recusou o comando (HTTP $st)${det:+: $det}" "upstream_error"
  fi
  ok_json_slurp '{sent:true, op:$op, image:$img, mac:$mac, ok:$okn, failed:$badn, sedes:($u | from_entries),
                  upstream:(($u[0].value // null))}' u "$(cat "$resf"; rm -f "$resf")" \
    --arg op "$op" --arg img "$img" --arg mac "$mac" --argjson okn "$okn" --argjson badn "$badn"
  ;;
*)
  fail 400 "action inválida" "action_invalid"
  ;;
esac
