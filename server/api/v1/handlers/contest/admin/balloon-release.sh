# /contest/admin/balloon-release?contest=<c>   (admin ou juiz-chefe) — a VÁLVULA da espera do balão do 1º da sede
# (09/11/2026). O balão espera a CERTEZA de quem foi o primeiro da sede (lib/print.sh, `.balloon-hold`, sem teto):
# uma run travada (juiz parado, revisão esquecida) seguraria os balões do par para sempre.
#   GET  -> {held:[{login, short, region, sub_epoch, since, pend}], released:[{region, problem, at, by}]}
#   POST {region, problem} -> libera o par: os balões retidos saem SEM a faixa no próximo reconcile. Auditado.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin_or_chief || fail 403 "Só o admin ou o juiz-chefe" "chief_required"
source "$_LIBDIR/print.sh"
dir="$(pr_dir "$contest")"; hold="$dir/.balloon-hold"; rel="$dir/.balloon-release"

if [[ "${REQUEST_METHOD:-GET}" == GET ]]; then
  # os dois arquivos crescem com o evento (uma linha por balão retido/par liberado): --slurpfile, nunca argv (ARG_MAX)
  hf=/dev/null; rf=/dev/null
  [[ -s "$hold" ]] && jq -e . "$hold" >/dev/null 2>&1 && hf="$hold"
  [[ -s "$rel" ]] && jq -e . "$rel" >/dev/null 2>&1 && rf="$rel"
  ok_json '{held:$h, released:$r}' --slurpfile h "$hf" --slurpfile r "$rf"
  exit 0
fi
require_method POST
body="$(read_body)"
jq -e 'type == "object"' >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
reg="$(jq -r '.region // ""' <<<"$body")"; prob="$(jq -r '.problem // ""' <<<"$body")"
[[ -n "$reg" && -n "$prob" && ${#reg} -le 200 && ${#prob} -le 200 && "$reg$prob" != *$'\n'* ]] || fail 422 "Informe region e problem" "pair_invalid"
# só um par que está esperando agora (liberar outro seria tirar a faixa de um primeiro lugar que nem existe ainda)
jq -e --arg r "$reg" --arg p "$prob" 'select(.region == $r and .problem == $p)' "$hold" >/dev/null 2>&1 \
  || fail 404 "Nenhum balão esperando nesse par (sede × problema)" "not_held"
mkdir -p "$dir"
jq -cn --arg r "$reg" --arg p "$prob" --arg by "$SESSION_LOGIN" --argjson at "$EPOCHSECONDS" \
  '{region:$r, problem:$p, at:$at, by:$by}' >> "$rel"
rm -f "$dir/.balloon-stamp"                       # o próximo reconcile reavalia já
audit_log_to "$contest" balloon-release "region=${reg//[$'\t\n']/ } problema=$prob by=$SESSION_LOGIN"
ok_json '{released:true, region:$r, problem:$p}' --arg r "$reg" --arg p "$prob"
