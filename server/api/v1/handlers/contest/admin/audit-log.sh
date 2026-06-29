# GET /contest/admin/audit-log?contest=<id>[&since=&action=&user=&limit=]  (admin DO contest)
# Feed cronológico UNIFICADO de tudo que aconteceu no contest, no INSTANTE EXATO de cada
# evento (trace completo), juntando 4 fontes:
#   - var/admin-audit.log  (ações de admin: epoch\twho\taction\tdetails)            -> kind=admin
#   - var/access.log       (logins: epoch\tlogin\tip\tua_b64)                       -> kind=login
#   - controle/history     (1 SUBMISSÃO por linha, no sub_epoch)                    -> kind=submit
#   - results/<id>.json    (1 VEREDICTO por correção, no finalized_at)              -> kind=verdict
# Cada submissão gera DUAS entradas: a submissão (quando o aluno enviou) e o veredicto
# (quando o juiz respondeu, com a hora exata da correção). O results/<id>.json é gravado
# por TODO caminho de finalização (daemon/ingest/rejulgar/set-verdict) — cobre tudo sem
# depender do daemon registrar nada. Filtros: since (epoch), action/user (substr), limit.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"

since="$(param since)"; [[ "$since" =~ ^[0-9]+$ ]] || since=0
limit="$(param limit)"; [[ "$limit" =~ ^[0-9]+$ ]] || limit=500
(( limit > 5000 )) && limit=5000
action="$(param action)"; user="$(param user)"
SRC_MAX=20000   # teto de linhas lidas por fonte (limita memória; feed recente)

cdir="$CONTESTSDIR/$contest"
read_tail() { [[ -f "$1" ]] && tail -n "$SRC_MAX" "$1" 2>/dev/null || true; }

admin_json="$(read_tail "$cdir/var/admin-audit.log" | jq -R -cs '
  split("\n") | map(select(length>0) | split("\t")
    | { time:(.[0]|tonumber? // 0), who:(.[1]//"?"), kind:"admin", action:(.[2]//""), details:(.[3]//"") })')"
access_json="$(read_tail "$cdir/var/access.log" | jq -R -cs '
  split("\n") | map(select(length>0) | split("\t")
    | { time:(.[0]|tonumber? // 0), who:(.[1]//"?"), kind:"login", action:"login",
        details:("\(.[2]//"") · \((.[3]//"")|@base64d)") })')"
# SUBMISSÃO: 1 entrada por linha do history, no instante em que o aluno enviou (sub_epoch,
# campo -2). A ação é "submissão" — o veredicto vira uma entrada SEPARADA (kind=verdict).
hist_json="$(read_tail "$cdir/controle/history" | jq -R -cs '
  split("\n") | map(select(length>0) | split(":") | select(length>=6)
    | { time:(.[-2]|tonumber? // 0), who:(.[1]//"?"), kind:"submit",
        action:"submissão", details:("\(.[2]//"") (\(.[3]//"")) #\(.[-1]//"")") })')"

# VEREDICTO: 1 entrada por correção finalizada, no instante EXATO da correção (finalized_at
# do results/<id>.json). Lê os mais recentes (por mtime) até RES_MAX. Cobre todo caminho de
# finalização sem reiniciar o daemon. who = aluno (p/ o filtro casar submissão+veredicto).
RES_MAX=8000
judged_json='[]'
if [[ -d "$cdir/results" ]]; then
  judged_json="$(find "$cdir/results" -maxdepth 1 -name '*.json' -printf '%T@\t%p\n' 2>/dev/null \
    | sort -rn | head -n "$RES_MAX" | cut -f2- | tr '\n' '\0' | xargs -0 -r cat 2>/dev/null \
    | jq -cs 'map(select(type=="object" and (.finalized_at//0) > 0)
        | { time:(.finalized_at), who:(.login//"?"), kind:"verdict", action:(.verdict//""),
            details:("\(.problem_id//"") (\(.lang//"")) #\(.id//"")"
                     + (if .host then " · juiz:\(.host)" else "" end)
                     + (if (.duration_s//null)!=null then " · \(.duration_s)s" else "" end)) })' 2>/dev/null)"
  [[ -n "$judged_json" ]] || judged_json='[]'
fi

[[ -n "$admin_json"  ]] || admin_json='[]'
[[ -n "$access_json" ]] || access_json='[]'
[[ -n "$hist_json"   ]] || hist_json='[]'

emit_json 200 OK
jq -cn --argjson a "$admin_json" --argjson b "$access_json" --argjson h "$hist_json" --argjson v "$judged_json" \
  --argjson since "$since" --arg act "$action" --arg usr "$user" --argjson lim "$limit" '
  ($a + $b + $h + $v)
  | map(select(.time >= $since))
  | (if $act=="" then . else map(select((.action//"")|ascii_downcase|contains($act|ascii_downcase))) end)
  | (if $usr=="" then . else map(select((.who//"")|ascii_downcase|contains($usr|ascii_downcase))) end)
  | sort_by(-.time) | .[:$lim]
  | {success:true, count:length, events:.}'
