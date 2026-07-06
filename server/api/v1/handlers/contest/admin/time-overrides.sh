# GET/POST /contest/admin/time-overrides?contest=<c>   (admin DO contest)
# PRORROGAÇÃO de vigência por sede/grupo: regras [{regex, end, reason?}] testadas contra o
# login — a 1ª que casa define o fim EFETIVO daquele grupo (só ESTENDE o CONTEST_END; nunca
# encurta). Caso de uso: queda de energia numa sede -> só os times daquele regex ganham
# minutos extras de prova (o submit e o countdown respeitam via contest_end_effective).
# Persiste em contests/<c>/time-overrides.json (POST substitui a lista). Auditado.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"
source "$_LIBDIR/contest-gate.sh"

tf="$CONTESTSDIR/$contest/time-overrides.json"

if [[ "${REQUEST_METHOD:-GET}" == GET ]]; then
  rules='[]'; [[ -f "$tf" ]] && jq -e . "$tf" >/dev/null 2>&1 && rules="$(jq -c '.' "$tf")"
  CONTEST_END=0; load_contest_conf "$contest"
  regions='[]'; rf="$CONTESTSDIR/$contest/regions.json"
  [[ -f "$rf" ]] && jq -e . "$rf" >/dev/null 2>&1 && regions="$(jq -c '.' "$rf")"
  ok_json '{rules:$r, contest_end:$e, regions:$rg}' \
    --argjson r "$rules" --argjson e "${CONTEST_END:-0}" --argjson rg "$regions"
  exit 0
fi

require_method POST
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
rules="$(jq -c '.rules // []' <<<"$body")"
jq -e 'type=="array"' >/dev/null 2>&1 <<<"$rules" || fail 422 "rules inválido" "rules_invalid"

# validação: regex string não-vazia (e compilável), end epoch>0, reason opcional; máx 50 regras.
clean="$(jq -c '
  map(select(type=="object"))
  | map({ regex:  (.regex // "" | tostring),
          end:    (.end | if type=="number" then floor else -1 end),
          reason: ((.reason // "") | tostring | .[0:200]) })
  | map(select(.regex != "" and (.regex|length) <= 200 and .end > 0))
  | .[0:50]' <<<"$rules" 2>/dev/null)"
[[ -n "$clean" ]] || fail 422 "rules inválido" "rules_invalid"
# cada regex precisa COMPILAR (regra quebrada silenciaria as demais no gate). Sem -e:
# `test` false é regex válida (exit 0); só o erro de compilação (exit != 0) reprova.
while IFS= read -r rr; do
  jq -n --arg r "$rr" '"x" | test($r)' >/dev/null 2>&1 \
    || fail 422 "regex inválida: $rr" "regex_invalid"
done < <(jq -r '.[].regex' <<<"$clean")

tmp="$tf.tmp"
printf '%s\n' "$clean" > "$tmp" && mv -f "$tmp" "$tf"
n="$(jq -r 'length' <<<"$clean")"
audit_log_to "$contest" time-overrides "regras=$n $clean"
ok_json '{saved:true, rules:$r}' --argjson r "$clean"
