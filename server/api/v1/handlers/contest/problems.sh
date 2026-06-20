# GET /contest/problems?contest=<id>   (Bearer)
# Lista de problemas da prova a partir de PROBS (5-tuplas) + enunciados/<key>.{html,pdf}.
# [{short_name, full_name, problem_id, statement_html_b64, statement_pdf_b64, time_limits, show}]
# Espelha old/cdmoj/server/scripts/create-problemsjson.sh (base64 dos enunciados),
# mas SEM escrever no dir do contest (codifica inline).
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"

CONTEST_ID="$contest"; PROBS=(); LANGUAGES=""
load_contest_conf "$contest"

set +o noglob
ENUN="$CONTESTSDIR/$contest/enunciados"

declare -a ITEMS
for (( i=0; i<${#PROBS[@]}; i+=5 )); do
  FROM="${PROBS[$i]}"
  PROBLEMID="${PROBS[$((i+1))]/\//.}"   # source 'a/b' -> id 'a.b'
  FULLNAME="${PROBS[$((i+2))]}"
  SHORTNAME="${PROBS[$((i+3))]}"
  STATEMENT="${PROBS[$((i+4))]}"

  args=(); filt='{short_name:$short, full_name:$full, problem_id:$id, show:true'
  for T in html pdf; do
    src="$ENUN/$STATEMENT.$T"
    if [[ -f "$src" ]]; then
      args+=( --arg "$T" "$(base64 -w0 < "$src" 2>/dev/null)" )
      filt+=", statement_${T}_b64:\$$T"
    else
      filt+=", statement_${T}_b64:null"
    fi
  done
  # enunciado pode ser uma URL externa
  if [[ "$STATEMENT" == *http* ]]; then
    args+=( --arg url "$STATEMENT" ); filt+=", url:\$url"
  fi
  filt+=", time_limits:{}}"

  ITEMS+=( "$(jq -cn --arg id "$PROBLEMID" --arg short "$SHORTNAME" \
      --arg full "$FULLNAME" "${args[@]}" "$filt")" )
done

emit_json 200 OK
if (( ${#ITEMS[@]} == 0 )); then
  jq -cn '{success:true, problems:[]}'
else
  printf '%s\n' "${ITEMS[@]}" | jq -cs '{success:true, problems:.}'
fi
