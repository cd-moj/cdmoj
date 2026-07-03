# GET /treino/admin/stats  (.admin) -> números p/ gráficos (logins/dia, submissões/dia, etc.)
require_auth_contest treino
is_admin || fail 403 "Apenas administradores do treino" "admin_required"
T="$CONTESTSDIR/treino"
users="$(wc -l < "$T/passwd" 2>/dev/null || echo 0)"; users="${users//[!0-9]/}"; users="${users:-0}"

# sessões ativas do treino
sess=0
set +o noglob; shopt -s nullglob
for f in "$SESSIONDIR"/*; do
  [[ -f "$f" ]] || continue
  ( CONTEST=""; source "$f" 2>/dev/null; [[ "$CONTEST" == treino ]] && exit 7; exit 0 )
  [[ $? -eq 7 ]] && ((sess++))
done
shopt -u nullglob

cut=$(( EPOCHSECONDS - 30*86400 ))
# agrupa por dia (UTC) = floor(epoch/86400)*86400; o front formata a data
loginsday="$(awk -F'\t' -v c=$cut '$1>=c{a[int($1/86400)]++} END{for(k in a) print (k*86400)"\t"a[k]}' \
  "$T/var/access.log" 2>/dev/null | sort -n \
  | jq -R -cs 'split("\n")|map(select(length>0)|split("\t")|{day:(.[0]|tonumber), count:(.[1]|tonumber)})')"
[[ -z "$loginsday" ]] && loginsday='[]'
subsday="$(emit_history_stream treino | awk -F: -v c=$cut '{ts=$6+0; if(ts<1) ts=$1+0; if(ts>=c) a[int(ts/86400)]++} END{for(k in a) print (k*86400)"\t"a[k]}' \
  | sort -n \
  | jq -R -cs 'split("\n")|map(select(length>0)|split("\t")|{day:(.[0]|tonumber), count:(.[1]|tonumber)})')"
[[ -z "$subsday" ]] && subsday='[]'

# problemas da plataforma (admin, SÓ números — nunca a lista). owners_merged é NÃO filtrado, então
# conta privados/por-autor/entrada também, sem revelar QUAIS (contar != listar; provas não vazam).
# public_by_day: [{day(epoch início-do-dia UTC),count}] como logins/submissões — o front bucketa p/ o mapa.
source "$_DIR/lib/problems.sh"
pdata="$(owners_merged | jq -c '
  .problems as $ps
  | { total:($ps|length), public:($ps|map(select(.public))|length), private:($ps|map(select(.public|not))|length),
      by_author: ($ps | group_by(.author_norm // "")
        | map({author:(.[0].author // "—"), author_norm:(.[0].author_norm // ""),
               total:length, public:(map(select(.public))|length), private:(map(select(.public|not))|length)})
        | sort_by(-.total)),
      public_by_day: ($ps | map(select(.public and (.public_at!=null)) | ((.public_at/86400)|floor)*86400)
        | group_by(.) | map({day:.[0], count:length}) | sort_by(.day)) }' 2>/dev/null)"
[[ -n "$pdata" ]] || pdata='{"total":0,"public":0,"private":0,"by_author":[],"public_by_day":[]}'

ok_json '{users:$u, active_sessions:$s,
          problems:{total:$pd.total, public:$pd.public, private:$pd.private},
          by_author:$pd.by_author, problems_public_by_day:$pd.public_by_day,
          logins_per_day:$lpd, submissions_per_day:$spd}' \
  --argjson u "$users" --argjson s "$sess" --argjson pd "$pdata" --argjson lpd "$loginsday" --argjson spd "$subsday"
