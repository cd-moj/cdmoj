# GET /contest/classification?contest=<id> — classificação p/ as próximas fases, SÓ o publicado.
# Mesmo gate do placar (contest secreto exige sessão); o placar a consome p/ o chip de cada estágio.
# resp: {stages:[{id,name,venue,when,chip,labels:{via:{pt,en,es,short}},via_order,teams:{login:{via,sede}}}]}
# — vazio se nada publicado. Nunca expõe config, motivo de override, quem aplicou (isso é do admin/classify)
# nem os times de FORA do placar (chave `ext:`, só no classificados.html do relatório). Estágio antigo,
# sem chip/rótulos gravados, leva os do catálogo (score/classify-catalog.json).
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_not_secret_or_auth "$contest"
CF="$CONTESTSDIR/$contest/classification.json"
if [[ ! -s "$CF" ]]; then ok_json '{stages:[]}'; exit 0; fi
# PLACAR ANÔNIMO (03/10/2026): quem se classificou é desempenho individual — fora da organização, nenhum estágio
if [[ "$(conf_value "$contest" SCORE_ANON)" == 1 ]]; then
  _org=false
  load_session 2>/dev/null && [[ "$SESSION_CONTEST" == "$contest" ]] && { is_admin || is_judge || is_mon || is_animeitor; } && _org=true
  [[ "$_org" == true ]] || { ok_json '{stages:[]}'; exit 0; }
fi
# ADMIN do contest enxerga também os RASCUNHOS (marcados draft:true — o placar rende o
# chip esmaecido "(rascunho)"): é a pré-visualização de como fica antes do Publicar.
# Sessão OPCIONAL, molde do /contest/score — anônimo/competidor segue só com published.
adm=false
load_session 2>/dev/null && [[ "$SESSION_CONTEST" == "$contest" ]] && is_admin && adm=true
CAT="$_DIR/../../score/classify-catalog.json"
out="$(jq -c --argjson adm "$adm" --slurpfile c "$CAT" '{stages:[ (.stages // [])[]
  | select(.status == "published" or $adm)
  | .id as $sid
  | ((.teams // {}) | with_entries(select(.key | startswith("ext:") | not)
                                   | .value |= {via:(.via // ""), sede:(.sede // "")})) as $t
  | ((.via_order // []) + [ $t[] | .via ] | reduce .[] as $v ([]; if any(.[]; . == $v) then . else . + [$v] end)) as $order
  | {id, name:(.name // ""), venue:(.venue // ""), when:(.when // ""),
     chip:(.chip // (first($c[0].engines[] | select(.stage == $sid) | .defaults.chip) // .name // .id)),
     labels:((.labels // $c[0].vias) | with_entries(select(.key as $k | $order | any(.[]; . == $k)))),
     via_order:$order, teams:$t}
    + (if .status != "published" then {draft:true} else {} end) ]}' \
  "$CF" 2>/dev/null)"
[[ -n "$out" ]] || out='{"stages":[]}'
ok_json_slurp '$f[0]' f "$out"
