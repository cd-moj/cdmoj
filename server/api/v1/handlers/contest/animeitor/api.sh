# GET/POST /contest/animeitor/api?contest=<id>      (Bearer: .animeitor ou admin do contest)
# A integração com a API do ANIMEITOR (telão): o MOJ empurra evento, placares/sedes, runs e relógio.
# Doc: docs/ANIMEITOR.md · lib: lib/animeitor.sh · alimentador: server/daemons/animeitor-feed.sh.
#
#   GET                  -> {configured, has_cred, user, url, event, moj_base_url, enabled, feed, secret_contest,
#                            contests (o que está salvo; null = ainda vale a proposta), managed, status, clock,
#                            feeder_alive_at (batimento do processo alimentador), now}
#   GET ?proposal=1      -> + proposal {teams_total, contests:[{name, source, n, codes, kind, sites}]}
#   GET ?links=1         -> + links {public:[…], revelation:[…]}  (os de revelação são CREDENCIAL)
#   POST {action:"config", url?, user?, token?, event?, moj_base_url?}   token write-only (secrets/, 600)
#   POST {action:"test"}                 -> prova a credencial (GET /internal/events) e diz se o evento existe
#   POST {action:"save", contests:[…]|null}   grava os placares/sedes revisados (null = voltar à proposta)
#   POST {action:"publish", adopt?}      -> cria/atualiza evento + placares + sedes LÁ (idempotente)
#   POST {action:"push-runs", full?}     -> manda as runs (delta; full = tudo de novo)
#   POST {action:"start"|"stop"}         -> liga/desliga o alimentador deste contest (relógio + runs)
#   POST {action:"reveal-release"|"reveal-recall"}  -> libera/recolhe os links do REVELEITOR p/ as sedes: com
#                            ele liberado, .cstaff/.staff leem os DA SEDE DELES em GET /contest/animeitor/reveal
#   POST {action:"reset", confirm:"<evento>"}  -> APAGA o evento lá (só evento criado por este contest)
# `.cstaff`/`.staff` não entram aqui (403): a tela deles é só a galeria da sede.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
{ is_animeitor || is_admin; } || fail 403 "Apenas a conta de placar (.animeitor) ou o admin" "animeitor_required"
source "$_LIBDIR/cohorts.sh"
source "$_LIBDIR/animeitor.sh"
cdir="$CONTESTSDIR/$contest"
ACTIVE="${RUNDIR:-/home/ribas/moj/run}/animeitor/active"

_an_state(){   # o estado SEM segredo (o token nunca volta; o usuário sim — é o que o operador digitou)
  local cfg st clk user=""
  cfg="$(an_cfg "$contest")"
  st='{}'; [[ -s "$cdir/var/animeitor.status.json" ]] && st="$(cat "$cdir/var/animeitor.status.json" 2>/dev/null)"
  jq -e . >/dev/null 2>&1 <<<"$st" || st='{}'
  clk='null'
  if [[ -s "$cdir/var/animeitor.clock" ]]; then
    local a b h; read -r a b h < "$cdir/var/animeitor.clock"
    [[ "$a" =~ ^[0-9]+$ && "$b" =~ ^-?[0-9]+$ ]] && clk="$(jq -cn --argjson a "$a" --argjson b "$b" --arg h "${h:-}" '{at:$a, time_seconds:$b, http:$h}')"
  fi
  if an_has_cred "$contest"; then IFS= read -r user < "$(an_credfile "$contest")"; user="${user%%:*}"; fi
  # o PROCESSO alimentador (daemons/animeitor-feed.sh) bate o ponto a cada volta: marcador ligado com
  # o processo morto é o caso que o operador precisa VER ("liguei e o relógio não anda")
  local alive=0; [[ -r "${ACTIVE%/active}/feed.alive" ]] && read -r alive < "${ACTIVE%/active}/feed.alive"; [[ "$alive" =~ ^[0-9]+$ ]] || alive=0
  jq -cn --argjson cfg "$cfg" --argjson st "$st" --argjson clk "$clk" --arg user "$user" \
     --argjson hc "$(an_has_cred "$contest" && echo true || echo false)" \
     --argjson sec "$(contest_is_secret "$contest" && echo true || echo false)" \
     --argjson man "$(an_managed "$contest")" --argjson now "$EPOCHSECONDS" \
     --argjson feeding "$([[ -e "$ACTIVE/$contest" ]] && echo true || echo false)" --argjson alive "$alive" '
    { configured: ($hc and ($cfg.url != "")), has_cred: $hc, user: $user, url: $cfg.url, event: $cfg.event,
      moj_base_url: $cfg.moj_base_url, enabled: ($cfg.enabled and $feeding), feed: $cfg.feed, secret_contest: $sec,
      contests: $cfg.contests, reveal: $cfg.reveal,
      managed: {event: $man.event, contests: ($man.contests | to_entries | map({name: .key, sites: (.value.sites // {} | keys)}))},
      status: $st, clock: $clk, feeder_alive_at: $alive, now: $now }'
}

if [[ "${REQUEST_METHOD:-GET}" == GET ]]; then
  state="$(_an_state)"
  if [[ "$(param proposal)" == 1 ]]; then
    pf="$(mktemp)"; trap 'rm -f "$pf"' EXIT
    if an_derive "$contest" "$pf" 2>/dev/null; then state="$(jq -c --slurpfile p "$pf" '. + {proposal: $p[0]}' <<<"$state")"
    else state="$(jq -c '. + {proposal: null}' <<<"$state")"; fi
  fi
  if [[ "$(param links)" == 1 ]] && an_configured "$contest"; then
    state="$(jq -c --argjson l "$(an_links "$contest" || true)" '. + {links: $l}' <<<"$state")"
  fi
  ok_json_slurp '$s[0]' s "$state"
  exit 0
fi

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
action="$(jq -r '.action // empty' <<<"$body")"
case "$action" in
config)
  cfg="$(an_cfg "$contest")"
  if jq -e 'has("url")' >/dev/null 2>&1 <<<"$body"; then
    url="$(jq -r '.url // ""' <<<"$body")"; url="${url%/}"
    an_url_ok "$url" || fail 422 "URL inválida: a API interna do Animeitor só atende em https://" "url_invalid"
    cfg="$(jq -c --arg u "$url" '.url = $u' <<<"$cfg")"
  fi
  if jq -e 'has("moj_base_url")' >/dev/null 2>&1 <<<"$body"; then
    mb="$(jq -r '.moj_base_url // ""' <<<"$body")"; mb="${mb%/}"
    [[ -z "$mb" || "$mb" =~ ^https?://[A-Za-z0-9.-]+(:[0-9]{1,5})?$ ]] || fail 422 "URL pública do MOJ inválida" "base_url_invalid"
    cfg="$(jq -c --arg u "$mb" '.moj_base_url = $u' <<<"$cfg")"
  fi
  if jq -e 'has("event")' >/dev/null 2>&1 <<<"$body"; then
    # vazio = o nome-PADRÃO (id do contest; com rodadas, `<contest>-<rodada ativa>`) — fica vazio no arquivo
    ev="$(jq -r '.event // ""' <<<"$body")"
    [[ -z "$ev" ]] || an_name_ok "$ev" || fail 422 "Nome de evento inválido (até 64 caracteres, sem barra)" "event_invalid"
    [[ -e "$ACTIVE/$contest" ]] && [[ "$ev" != "$(jq -r .event <<<"$cfg")" ]] && fail 409 "Pare o alimentador antes de trocar o evento" "feeding"
    cfg="$(jq -c --arg e "$ev" '.event_set = $e' <<<"$cfg")"
  fi
  if jq -e 'has("token") or has("user")' >/dev/null 2>&1 <<<"$body"; then
    user="$(jq -r '.user // ""' <<<"$body")"; token="$(jq -r '.token // ""' <<<"$body")"
    cf="$(an_credfile "$contest")"
    if [[ -z "$user" && -z "$token" ]]; then rm -f "$cf"
    else
      # trocar só o usuário (token vazio) mantém o token gravado
      if [[ -z "$token" && -s "$cf" ]]; then IFS= read -r _old < "$cf"; token="${_old#*:}"; fi
      [[ "$user" =~ ^[A-Za-z0-9._@-]{1,64}$ ]] || fail 422 "Usuário inválido" "user_invalid"
      [[ "$token" =~ ^[A-Za-z0-9._~+/=-]{8,256}$ ]] || fail 422 "Token inválido (8 a 256 caracteres, sem espaço nem aspas)" "token_invalid"
      mkdir -p "$cdir/secrets"; chmod 700 "$cdir/secrets" 2>/dev/null
      tmpf="$cf.tmp.$BASHPID"
      ( umask 077; printf '%s:%s\n' "$user" "$token" > "$tmpf" ) && mv -f "$tmpf" "$cf"
    fi
  fi
  an_cfg_save "$contest" "$cfg" || fail 500 "Não consegui gravar" "save_failed"
  mod_enable "$contest" telao
  audit_log_to "$contest" animeitor-config "url=$(jq -r .url <<<"$cfg") event=$(jq -r .event <<<"$cfg") cred=$(jq -r 'if has("token") or has("user") then "alterada" else "mantida" end' <<<"$body")"
  ok_json_slurp '{saved:true} + $s[0]' s "$(_an_state)"
  ;;
test)
  an_configured "$contest" || fail 409 "Grave a URL e a credencial primeiro" "not_configured"
  r="$(an_curl "$contest" GET "/internal/events")"; st="$(an_status "$r")"
  case "$st" in
    200) ev="$(jq -r .event <<<"$(an_cfg "$contest")")"
         ok_json '{ok:true, http:200, events:$n, event_exists:$x, managed:$m}' \
           --argjson n "$(an_body "$r" | jq '(.data // []) | length' 2>/dev/null || echo 0)" \
           --argjson x "$(an_body "$r" | jq --arg e "$ev" '(.data // []) | index($e) != null' 2>/dev/null || echo false)" \
           --argjson m "$([[ "$(jq -r .event <<<"$(an_managed "$contest")")" == "$ev" ]] && echo true || echo false)" ;;
    401) fail 502 "O Animeitor recusou o usuário/token (401)" "upstream_unauthorized" ;;
    *)   fail 502 "Animeitor inacessível (HTTP ${st:-000})" "upstream_error" ;;
  esac
  ;;
save)
  cfg="$(an_cfg "$contest")"
  if [[ "$(jq -r '.contests | type' <<<"$body")" == null ]]; then cfg="$(jq -c '.contests = null' <<<"$cfg")"
  else
    jq -e '(.contests | type) == "array" and (.contests | length) <= 200' >/dev/null 2>&1 <<<"$body" || fail 422 "contests deve ser lista" "contests_invalid"
    norm="$(jq -c '
      def nm: (. // "") | tostring | gsub("[/\\n\\r\\t]"; " ") | gsub("^ +| +$"; "") | .[0:64];
      def codes: if type == "array" then map(tostring | .[0:100000]) else null end;
      def medal($d): (. // $d) | if type == "number" and . >= 0 and . <= 100000 then floor else $d end;
      [ .contests[] | { name: (.name | nm), source: {kind: ((.source.kind // "manual") | tostring), id: ((.source.id // "") | tostring)},
          codes: (.codes | codes), ouro: (.ouro | medal(1)), prata: (.prata | medal(2)), bronze: (.bronze | medal(3)),
          style: (if (.style // "") == "" then null else (.style | tostring | .[0:64]) end),
          sites: [ (.sites // [])[] | {name: (.name | nm), source: {kind: ((.source.kind // "manual") | tostring), id: ((.source.id // "") | tostring)}, codes: (.codes | codes)} | select(.name != "") ] }
        | select(.name != "") ]' <<<"$body" 2>/dev/null)" || fail 422 "contests inválido" "contests_invalid"
    jq -e '([.[].name] | unique | length) == length and all(.[]; ([.sites[].name] | unique | length) == (.sites | length))' >/dev/null 2>&1 <<<"$norm" \
      || fail 422 "Nome de placar ou de sede repetido" "name_duplicate"
    jq -e 'all(.[]; (.source.kind != "manual" or .codes != null) and all(.sites[]; .source.kind != "manual" or .codes != null))' >/dev/null 2>&1 <<<"$norm" \
      || fail 422 "Placar ou sede manual precisa de regex" "codes_missing"
    cfg="$(jq -c --argjson n "$norm" '.contests = $n' <<<"$cfg")"
  fi
  an_cfg_save "$contest" "$cfg" || fail 500 "Não consegui gravar" "save_failed"
  audit_log_to "$contest" animeitor-save "contests=$(jq -r 'if .contests == null then "proposta" else (.contests | length | tostring) end' <<<"$cfg")"
  ok_json_slurp '{saved:true} + $s[0]' s "$(_an_state)"
  ;;
publish)
  an_configured "$contest" || fail 409 "Grave a URL e a credencial primeiro" "not_configured"
  adopt=0; [[ "$(jq -r '.adopt // false' <<<"$body")" == true ]] && adopt=1
  of="$(mktemp)"; trap 'rm -f "$of"' EXIT
  an_publish "$contest" "$of" "$adopt"; prc=$?
  res="$(cat "$of" 2>/dev/null)"; jq -e . >/dev/null 2>&1 <<<"$res" || res='{"ok":false,"error":"falha"}'
  audit_log_to "$contest" animeitor-publish "ok=$(jq -r .ok <<<"$res") adopt=$adopt"
  if [[ $prc -ne 0 && "$(jq -r '.event.action // ""' <<<"$res")" == error && "$(jq -r '.event.http // ""' <<<"$res")" == 409 ]]; then
    fail 409 "$(jq -r '.event.error' <<<"$res")" "event_exists"
  fi
  ok_json_slurp '{result: $r[0]}' r "$res"
  ;;
push-runs)
  an_configured "$contest" || fail 409 "Grave a URL e a credencial primeiro" "not_configured"
  [[ "$(jq -r .event <<<"$(an_managed "$contest")")" == "$(jq -r .event <<<"$(an_cfg "$contest")")" ]] || fail 409 "Publique o evento primeiro" "not_published"
  full=""; [[ "$(jq -r '.full // false' <<<"$body")" == true ]] && full=full
  res="$(an_push_runs "$contest" "$full")"; jq -e . >/dev/null 2>&1 <<<"$res" || res='{"error":"falha"}'
  audit_log_to "$contest" animeitor-runs "full=${full:-no} $(jq -r '"sent=\(.sent // 0) added=\(.added // 0) updated=\(.updated // 0)"' <<<"$res")"
  ok_json_slurp '{runs: $r[0]}' r "$res"
  ;;
start|stop)
  if [[ "$action" == start ]]; then
    an_configured "$contest" || fail 409 "Grave a URL e a credencial primeiro" "not_configured"
    [[ "$(jq -r .event <<<"$(an_managed "$contest")")" == "$(jq -r .event <<<"$(an_cfg "$contest")")" ]] || fail 409 "Publique o evento primeiro" "not_published"
    mkdir -p "$ACTIVE" && : > "$ACTIVE/$contest" || fail 500 "Não consegui ligar" "start_failed"
    an_cfg_save "$contest" "$(jq -c '.enabled = true' <<<"$(an_cfg "$contest")")"
  else
    rm -f "$ACTIVE/$contest"
    an_cfg_save "$contest" "$(jq -c '.enabled = false' <<<"$(an_cfg "$contest")")"
  fi
  audit_log_to "$contest" animeitor-feed "$action"
  ok_json_slurp '$s[0]' s "$(_an_state)"
  ;;
reveal-release|reveal-recall)
  if [[ "$action" == reveal-release ]]; then
    an_configured "$contest" || fail 409 "Grave a URL e a credencial primeiro" "not_configured"
    [[ "$(jq -r .event <<<"$(an_managed "$contest")")" == "$(jq -r .event <<<"$(an_cfg "$contest")")" ]] || fail 409 "Publique o evento primeiro" "not_published"
    an_reveal_set "$contest" on "$SESSION_LOGIN"
  else an_reveal_set "$contest" off "$SESSION_LOGIN"; fi
  audit_log_to "$contest" animeitor-reveal "$action by=$SESSION_LOGIN"
  ok_json_slurp '$s[0]' s "$(_an_state)"
  ;;
reset)
  an_configured "$contest" || fail 409 "Grave a URL e a credencial primeiro" "not_configured"
  ev="$(jq -r .event <<<"$(an_cfg "$contest")")"
  [[ "$(jq -r '.confirm // ""' <<<"$body")" == "$ev" ]] || fail 422 "Confirme com o nome do evento" "confirm_required"
  # só apaga o que ESTE contest criou: o servidor do Animeitor é compartilhado com outros eventos
  [[ "$(jq -r .event <<<"$(an_managed "$contest")")" == "$ev" ]] || fail 409 "Este evento não foi criado por este contest" "not_managed"
  rm -f "$ACTIVE/$contest"; an_cfg_save "$contest" "$(jq -c '.enabled = false' <<<"$(an_cfg "$contest")")"
  an_reveal_set "$contest" off "$SESSION_LOGIN"          # evento apagado = links mortos: recolhe
  r="$(an_curl "$contest" DELETE "/internal/events/$(an_enc "$ev")")"; st="$(an_status "$r")"
  [[ "$st" == 204 || "$st" == 404 ]] || fail 502 "O Animeitor recusou apagar o evento (HTTP ${st:-000})" "upstream_error"
  rm -f "$cdir/var/animeitor-managed.json" "$cdir/var/animeitor-sent.tsv" "$cdir/var/animeitor.clock" "$cdir/var/animeitor.status.json"
  audit_log_to "$contest" animeitor-reset "event=$ev http=$st"
  ok_json '{reset:true, event:$e}' --arg e "$ev"
  ;;
*) fail 400 "Ação desconhecida" "action_invalid" ;;
esac
