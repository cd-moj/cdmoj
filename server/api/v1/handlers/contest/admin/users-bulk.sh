# POST /contest/admin/users-bulk?contest=<id>  (admin DO contest)
# Carga de usuários em LOTE (contests grandes: subir competidores DEPOIS da criação):
#   {users:[{login,password?,fullname?,email?,
#            univ_short?,univ_full?,country?,region?}], on_existing?: "skip"|"update"}
# O NOME é campo ÚNICO: `fullname` é o nome do time (usuário de contest É o time). Os
# campos de TIME (opcionais) vão p/ o `.team{univ_short,univ_full,flag,region}` do
# account.json — carga ÚNICA de credenciais+país+sede+universidade (team_fields_json saneia;
# update mescla só os presentes). Regras: ≤5000; login valid_id; senha vazia = gerada
# (cc_genpass); senha/nome/email sem ':'.
# on_existing=update troca senha/nome/email de conta existente, MAS conta PRIVILEGIADA
# existente (is_reserved_role_login) NUNCA é tocada (skipped: privileged — não resetar
# admin/juízes em massa); CRIAR privilegiada nova é permitido (staff em lote, como o user-add).
# Grava um account.json por conta (users/<login>/).
# Resposta: {created:[{login,password,fullname,email}], updated:[…],
#            skipped:[{login,reason:exists|privileged|invalid|duplicate}], counts}.
require_method POST
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"
source "$_LIBDIR/contest-create.sh"

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
n="$(jq '(.users // [])|length' <<<"$body")"; [[ "$n" =~ ^[0-9]+$ ]] || n=0
(( n >= 1 )) || fail 422 "Informe users[]" "users_missing"
(( n <= 5000 )) || fail 422 "Máximo de 5000 usuários por lote" "too_many"
onex="$(jq -r '.on_existing // "skip"' <<<"$body")"; [[ "$onex" == update ]] || onex=skip

# logins existentes (uma leitura)
declare -A EXIST
while IFS= read -r l; do [[ -n "$l" ]] && EXIST["$l"]=1; done < <(list_users "$contest")

tmpd="$(mktemp -d)" || fail 500 "tmp" "tmp"
: > "$tmpd/created.jsonl"; : > "$tmpd/updated.jsonl"; : > "$tmpd/skipped.jsonl"
declare -A SEEN
skipj(){ jq -cn --arg l "$1" --arg r "$2" '{login:$l,reason:$r}' >> "$tmpd/skipped.jsonl"; }
credj(){ jq -cn --arg l "$1" --arg p "$2" --arg f "$3" --arg e "$4" '{login:$l,password:$p,fullname:$f,email:$e}'; }

while IFS= read -r u; do
  [[ -n "$u" ]] || continue
  login="$(jq -r '.login // ""' <<<"$u")"
  pass="$(jq -r '.password // ""' <<<"$u")"
  full="$(jq -r '.fullname // ""' <<<"$u")"
  email="$(jq -r '.email // ""' <<<"$u")"
  # saneamento: tab/newline quebrariam os TSVs derivados (sc_users/allsubmissions)
  full="${full//$'\t'/ }"; full="${full//$'\n'/ }"; email="${email//$'\t'/ }"; email="${email//$'\n'/ }"
  { [[ -n "$login" ]] && valid_id "$login"; } || { skipj "${login:-?}" invalid; continue; }
  case "$pass$full$email" in *:*) skipj "$login" invalid; continue;; esac
  [[ -n "${SEEN[$login]:-}" ]] && { skipj "$login" duplicate; continue; }
  SEEN["$login"]=1
  [[ -z "$full" ]] && full="$login"
  teamj="$(team_fields_json "$u")"   # campos de time saneados (só os não-vazios; '{}' = nada)

  if [[ -n "${EXIST[$login]:-}" ]]; then
    [[ "$onex" == skip ]] && { skipj "$login" exists; continue; }
    is_reserved_role_login "$login" && { skipj "$login" privileged; continue; }
    [[ -z "$pass" ]] && pass="$(cc_genpass)"
    # nome/email só sobrescrevem se VIERAM na linha (linha parcial de enriquecimento —
    # ex.: login+sede — não pode clobberar o nome do time p/ o login); a senha segue a
    # semântica documentada do update (vazia = regenerada).
    fin="$(jq -r '.fullname // ""' <<<"$u")"; ein="$(jq -r '.email // ""' <<<"$u")"
    account_merge "$contest" "$login" '.password=$p | .updated_at=$t
        | (if $f != "" then .fullname=$f else . end)
        | (if $e != "" then .email=$e else . end)
        | .team = ((.team // {}) + $tm) | if (.team|length)==0 then del(.team) else . end' \
      --arg p "$pass" --arg f "$fin" --arg e "$ein" --argjson t "$EPOCHSECONDS" \
      --argjson tm "$teamj" || { skipj "$login" invalid; continue; }
    credj "$login" "$pass" "$(account_field "$contest" "$login" '.fullname')" "$email" >> "$tmpd/updated.jsonl"
  else
    [[ -z "$pass" ]] && pass="$(cc_genpass)"
    # criação inline (mesmo shape do user_create em lib/users.sh, + .team quando veio)
    d="$(user_dir "$contest" "$login")"
    mkdir -p "$d/submissions" "$d/mojlog" "$d/results" || { skipj "$login" invalid; continue; }
    jq -cn --arg l "$login" --arg p "$pass" --arg n "$full" --arg e "$email" --argjson t "$EPOCHSECONDS" \
      --argjson tm "$teamj" \
      '{login:$l,password:$p,fullname:$n,email:$e,created_at:$t,updated_at:$t,status:"active",uname_changes:[]}
       + (if ($tm|length) > 0 then {team:$tm} else {} end)' \
      > "$d/account.json" || { skipj "$login" invalid; continue; }
    : > "$d/history"
    credj "$login" "$pass" "$full" "$email" >> "$tmpd/created.jsonl"
  fi
done < <(jq -c '(.users // [])[]' <<<"$body")

audit_log_to "$contest" users-bulk \
  "created=$(grep -c . "$tmpd/created.jsonl" 2>/dev/null) updated=$(grep -c . "$tmpd/updated.jsonl" 2>/dev/null) skipped=$(grep -c . "$tmpd/skipped.jsonl" 2>/dev/null) on_existing=$onex"
ok_json '{created:($c[0] // []), updated:($u[0] // []), skipped:($s[0] // []),
          counts:{created:(($c[0] // [])|length), updated:(($u[0] // [])|length), skipped:(($s[0] // [])|length)}}' \
  --slurpfile c <(jq -cs '.' "$tmpd/created.jsonl") \
  --slurpfile u <(jq -cs '.' "$tmpd/updated.jsonl") \
  --slurpfile s <(jq -cs '.' "$tmpd/skipped.jsonl")
rm -rf "$tmpd"
