# GET/POST /contest/admin/staff-filters?contest=<c>   (admin DO contest)
# Escopo de cada usuário .staff e .cstaff (sedes distribuídas): lista de entradas onde
# cada uma é "region:<nome>" (casa com o .team.region do aluno — o jeito por-sede sem
# regex) OU uma regex no login do aluno (clássico). Lista vazia/ausente = vê TUDO.
# O escopo do .staff governa a fila/ações; o do .cstaff governa a fila (leitura), as
# ETIQUETAS de credenciais e a CERIMÔNIA de revelação da sede — configure-o sempre.
# Semear a partir de regions.json (a UI insere region:<nome>).
# Persiste em contests/<c>/print-requests/staff-filters.json. Auditado (staff-filters).
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"
source "$_LIBDIR/print.sh"

dir="$(pr_dir "$contest")"
ff="$dir/staff-filters.json"

if [[ "${REQUEST_METHOD:-GET}" == GET ]]; then
  staff="$(pr_staff_logins "$contest" | jq -R -s '
    split("\n") | map(select(length>0) | split("\t") | {login:.[0], fullname:.[1], disabled:(.[2]=="true")})')"
  [[ -n "$staff" ]] || staff='[]'
  filters='{}'; [[ -f "$ff" ]] && jq -e . "$ff" >/dev/null 2>&1 && filters="$(cat "$ff")"
  regions='[]'; rf="$CONTESTSDIR/$contest/regions.json"
  [[ -f "$rf" ]] && jq -e . "$rf" >/dev/null 2>&1 && regions="$(jq -c '.' "$rf")"
  ok_json '{staff:$s, filters:$f, regions:$r}' --argjson s "$staff" --argjson f "$filters" --argjson r "$regions"
  exit 0
fi

require_method POST
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
filters="$(jq -c '.filters // {}' <<<"$body")"
jq -e 'type=="object"' >/dev/null 2>&1 <<<"$filters" || fail 422 "filters inválido" "filters_invalid"

# logins .staff/.cstaff válidos (só esses podem ser chaves); valores = regex não-vazias (caps).
valid_staff="$(pr_staff_logins "$contest" | jq -R -s 'split("\n") | map(select(length>0) | split("\t")[0])')"
clean="$(jq -c --argjson valid "$valid_staff" '
  to_entries
  | map(select(.key as $k | $valid | index($k)))
  | map({ key: .key,
          value: ((.value // []) | map(select(type=="string" and (.|length>0) and (.|length<=200))) | unique | .[0:50]) })
  | map(select((.value | length) > 0))
  | from_entries' <<<"$filters")"
[[ -n "$clean" ]] || clean='{}'

mkdir -p "$dir"
tmp="$ff.tmp"
printf '%s' "$clean" > "$tmp" && mv -f "$tmp" "$ff"
n="$(jq -r 'keys | length' <<<"$clean")"
audit_log_to "$contest" staff-filters "staff=$n regras=$clean"
ok_json '{saved:true, filters:$f}' --argjson f "$clean"
