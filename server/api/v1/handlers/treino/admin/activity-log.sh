# GET /treino/admin/activity-log[?since=&until=&kinds=&action=&user=&limit=&format=csv]  (.admin)
# Feed cronológico COMPLETO do treino livre, juntando SEIS fontes no instante exato:
#   - var/access.log                   (logins: epoch\tlogin\tip\tua_b64)         -> kind=login
#   - users/<login>/history            (1 SUBMISSÃO por linha, no sub_epoch)      -> kind=submit
#   - users/<login>/results/<id>.json  (VEREDICTO do juiz, no finalized_at)       -> kind=verdict
#   - var/activity-YYYY-MM.log         (LEITURAS: problem-view/log-view/
#                                       source-download; epoch\tlogin\tev\tdet\tip) -> kind=read
#   - var/admin-audit.log              (ações de admin/autoria)                   -> kind=admin
#   - idem, ações de MÁQUINA (tl-report/calib-report) — EXCLUÍDAS por default     -> kind=calib
# kinds= lista csv (default: tudo MENOS calib). format=csv baixa o range inteiro p/ análise
# (Content-Disposition; sem o teto de `limit`). Mesma arquitetura anti-ARG_MAX do
# contest/admin/audit-log.sh: fontes -> NDJSON em arquivo -> UMA passada de jq --slurpfile;
# corpo ANTES do header (falha = 500 honesto, nunca 200 vazio).
require_auth_contest treino
is_admin || fail 403 "Apenas admin" "admin_required"

since="$(param since)"; [[ "$since" =~ ^[0-9]+$ ]] || since=0
until_="$(param until)"; [[ "$until_" =~ ^[0-9]+$ ]] || until_=9999999999
limit="$(param limit)"; [[ "$limit" =~ ^[0-9]+$ ]] || limit=500
(( limit > 5000 )) && limit=5000
action="$(param action)"; user="$(param user)"; kinds="$(param kinds)"
fmt="$(param format)"
SRC_MAX=20000
RES_MAX=8000
if [[ "$fmt" == csv ]]; then SRC_MAX=200000; RES_MAX=50000; limit=1000000; fi

cdir="$CONTESTSDIR/treino"
EV="$(mktemp)" || fail 500 "Falha ao criar temporário" "tmp_failed"
trap 'rm -f "$EV"' EXIT

read_tail() { [[ -f "$1" ]] && tail -n "$SRC_MAX" "$1" 2>/dev/null || true; }
since_tsv() { awk -F'\t' -v s="$since" -v u="$until_" 'NF && $1+0 >= s && $1+0 <= u'; }

results_ndjson() {
  local d="$cdir/users"; [[ -d "$d" ]] || return 0
  find "$d" -mindepth 3 -maxdepth 3 -path '*/results/*.json' -printf '%T@\t%p\n' 2>/dev/null \
    | sort -rn | head -n "$RES_MAX" | cut -f2- | tr '\n' '\0' \
    | xargs -0 -r -n 200 jq -c --argjson since "$since" --argjson until "$until_" '
        select(type=="object" and (.finalized_at // 0) >= $since and (.finalized_at // 0) <= $until
               and (.finalized_at // 0) > 0)
        | { time:(.finalized_at), who:(.login//"?"), kind:"verdict", action:(.verdict//""),
            details:("\(.problem_id//"") (\(.lang//"")) #\(.id//"")"
                     + (if .host then " · juiz:\(.host)" else "" end)), ip:"" }'
}

{
  # ADMIN × CALIB — a mesma fonte, separada pelo tipo da ação (o ruído de máquina dominava)
  read_tail "$cdir/var/admin-audit.log" | since_tsv | jq -R -c '
    select(length>0) | split("\t")
    | { time:(.[0]|tonumber? // 0), who:(.[1]//"?"),
        kind:(if ((.[2]//"") | IN("tl-report","calib-report")) then "calib" else "admin" end),
        action:(.[2]//""), details:(.[3]//""), ip:"" }'

  # LOGIN — access.log (ua corrompido não mata a fonte: streaming linha a linha)
  read_tail "$cdir/var/access.log" | since_tsv | jq -R -c '
    select(length>0) | split("\t")
    | { time:(.[0]|tonumber? // 0), who:(.[1]//"?"), kind:"login", action:"login",
        details:((.[3]//"") | try @base64d catch ""), ip:(.[2]//"") }'

  # SUBMISSÃO — store por-usuário (formato global de 7 campos; verdict pode ter ":")
  emit_history_sorted treino "$SRC_MAX" \
    | awk -F: -v s="$since" -v u="$until_" 'NF>=7 && $(NF-1)+0 >= s && $(NF-1)+0 <= u' \
    | jq -R -c '
        select(length>0) | split(":") | select(length>=7)
        | { time:(.[-2]|tonumber? // 0), who:(.[1]//"?"), kind:"submit",
            action:"submissão", details:("\(.[2]//"") (\(.[3]//"")) #\(.[-1]//"")"), ip:"" }'

  # VEREDICTO — results/<id>.json (finalized_at cobre todo caminho de finalização)
  results_ndjson

  # LEITURA — activity-YYYY-MM.log (mensais; o range decide quais importam)
  set +o noglob; shopt -s nullglob
  for af in "$cdir/var"/activity-*.log; do
    read_tail "$af" | since_tsv | jq -R -c '
      select(length>0) | split("\t")
      | { time:(.[0]|tonumber? // 0), who:(.[1]//"?"), kind:"read",
          action:(.[2]//""), details:(.[3]//""), ip:(.[4]//"") }'
  done
  shopt -u nullglob
  true
} > "$EV" 2>/dev/null

FILTER='
  $ev
  | map(select((.time // 0) > 0 and (.time) >= $since and (.time) <= $until))
  | (($ks | split(",")) | map(select(length>0))) as $kl
  | (if ($kl|length)==0 then map(select(.kind != "calib"))
     else map(select(.kind as $k | ($kl|index($k)) != null)) end)
  | (if $act=="" then . else map(select(((.action//"")|ascii_downcase)|contains($act|ascii_downcase))) end)
  | (if $usr=="" then . else map(select(((.who//"")|ascii_downcase)|contains($usr|ascii_downcase))) end)
  | sort_by(-.time) | .[:$lim]'

if [[ "$fmt" == csv ]]; then
  body="$(jq -rn --slurpfile ev "$EV" \
    --argjson since "$since" --argjson until "$until_" --arg ks "$kinds" \
    --arg act "$action" --arg usr "$user" --argjson lim "$limit" "
    ${FILTER}
    | ([\"epoch\",\"datahora\",\"tipo\",\"quem\",\"acao\",\"detalhes\",\"ip\"] | @csv),
      (.[] | [ .time, (.time|todate), .kind, (.who//\"\"), (.action//\"\"), (.details//\"\"), (.ip//\"\") ] | @csv)" 2>/dev/null)"
  [[ -n "$body" ]] || fail 500 "Falha ao montar o CSV de atividade" "activity_render_failed"
  printf 'Status: 200 OK\r\nContent-Type: text/csv; charset=utf-8\r\n'
  printf 'Content-Disposition: attachment; filename="atividade-treino-%s.csv"\r\n\r\n' "$(date +%Y%m%d-%H%M)"
  printf '%s\n' "$body"
  exit 0
fi

body="$(jq -cn --slurpfile ev "$EV" \
  --argjson since "$since" --argjson until "$until_" --arg ks "$kinds" \
  --arg act "$action" --arg usr "$user" --argjson lim "$limit" "
  ${FILTER}
  | {success:true, count:length, events:.}" 2>/dev/null)"
[[ -n "$body" ]] || fail 500 "Falha ao montar o feed de atividade" "activity_render_failed"
emit_json 200 OK
printf '%s\n' "$body"
