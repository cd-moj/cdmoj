# POST /contest/admin/users-bulk?contest=<id>  (admin DO contest)
# Carga de usuários em LOTE (contests grandes: subir competidores DEPOIS da criação):
#   {users:[{login,password?,fullname?,email?}], on_existing?: "skip"|"update"}  (default skip)
# Regras: ≤5000; login valid_id; senha vazia = gerada (cc_genpass); campos sem ':'.
# on_existing=update troca senha/nome/email de conta existente, MAS conta PRIVILEGIADA
# existente (is_reserved_role_login) NUNCA é tocada (skipped: privileged — não resetar
# admin/juízes em massa); CRIAR privilegiada nova é permitido (staff em lote, como o user-add).
# Legado: passwd reescrito UMA vez; store v2: um account.json por conta.
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

V2=0; store_v2 "$contest" && V2=1
pwfile="$CONTESTSDIR/$contest/passwd"

# logins existentes (uma leitura)
declare -A EXIST
if (( V2 )); then
  while IFS= read -r l; do [[ -n "$l" ]] && EXIST["$l"]=1; done < <(list_users "$contest")
elif [[ -f "$pwfile" ]]; then
  while IFS=: read -r l _; do [[ -n "$l" ]] && EXIST["$l"]=1; done < "$pwfile"
fi

tmpd="$(mktemp -d)" || fail 500 "tmp" "tmp"
: > "$tmpd/created.jsonl"; : > "$tmpd/updated.jsonl"; : > "$tmpd/skipped.jsonl"
: > "$tmpd/upd.map"; : > "$tmpd/new.lines"     # legado: substituições (login\tlinha) + anexos
declare -A SEEN
skipj(){ jq -cn --arg l "$1" --arg r "$2" '{login:$l,reason:$r}' >> "$tmpd/skipped.jsonl"; }
credj(){ jq -cn --arg l "$1" --arg p "$2" --arg f "$3" --arg e "$4" '{login:$l,password:$p,fullname:$f,email:$e}'; }

while IFS= read -r u; do
  [[ -n "$u" ]] || continue
  login="$(jq -r '.login // ""' <<<"$u")"
  pass="$(jq -r '.password // ""' <<<"$u")"
  full="$(jq -r '.fullname // ""' <<<"$u")"
  email="$(jq -r '.email // ""' <<<"$u")"
  # saneamento: tab/newline quebrariam o merge e o próprio passwd
  full="${full//$'\t'/ }"; full="${full//$'\n'/ }"; email="${email//$'\t'/ }"; email="${email//$'\n'/ }"
  { [[ -n "$login" ]] && valid_id "$login"; } || { skipj "${login:-?}" invalid; continue; }
  case "$pass$full$email" in *:*) skipj "$login" invalid; continue;; esac
  [[ -n "${SEEN[$login]:-}" ]] && { skipj "$login" duplicate; continue; }
  SEEN["$login"]=1
  [[ -z "$full" ]] && full="$login"

  if [[ -n "${EXIST[$login]:-}" ]]; then
    [[ "$onex" == skip ]] && { skipj "$login" exists; continue; }
    is_reserved_role_login "$login" && { skipj "$login" privileged; continue; }
    [[ -z "$pass" ]] && pass="$(cc_genpass)"
    if (( V2 )); then
      account_merge "$contest" "$login" '.password=$p|.fullname=$f|.email=$e|.updated_at=$t' \
        --arg p "$pass" --arg f "$full" --arg e "$email" --argjson t "$EPOCHSECONDS" || { skipj "$login" invalid; continue; }
    else
      if [[ -n "$email" ]]; then printf '%s\t%s:%s:%s:%s\n' "$login" "$login" "$pass" "$full" "$email" >> "$tmpd/upd.map"
      else printf '%s\t%s:%s:%s\n' "$login" "$login" "$pass" "$full" >> "$tmpd/upd.map"; fi
    fi
    credj "$login" "$pass" "$full" "$email" >> "$tmpd/updated.jsonl"
  else
    [[ -z "$pass" ]] && pass="$(cc_genpass)"
    if (( V2 )); then
      # criação inline (mesmo shape do user_create em lib/users.sh)
      d="$(user_dir "$contest" "$login")"
      mkdir -p "$d/submissions" "$d/mojlog" "$d/results" || { skipj "$login" invalid; continue; }
      jq -cn --arg l "$login" --arg p "$pass" --arg n "$full" --arg e "$email" --argjson t "$EPOCHSECONDS" \
        '{login:$l,password:$p,fullname:$n,email:$e,created_at:$t,updated_at:$t,status:"active",uname_changes:[]}' \
        > "$d/account.json" || { skipj "$login" invalid; continue; }
      : > "$d/history"
    else
      if [[ -n "$email" ]]; then printf '%s:%s:%s:%s\n' "$login" "$pass" "$full" "$email" >> "$tmpd/new.lines"
      else printf '%s:%s:%s\n' "$login" "$pass" "$full" >> "$tmpd/new.lines"; fi
    fi
    credj "$login" "$pass" "$full" "$email" >> "$tmpd/created.jsonl"
  fi
done < <(jq -c '(.users // [])[]' <<<"$body")

if (( V2 )); then
  :   # account.json é a fonte — nada global a regenerar
else
  # merge numa passada: substitui as linhas com update e anexa as criadas (ordem do lote)
  tmp="$(mktemp "${pwfile}.XXXXXX")" || { rm -rf "$tmpd"; fail 500 "tmp" "tmp"; }
  if [[ -f "$pwfile" ]]; then
    # NÃO usar NR==FNR: se upd.map estiver VAZIO, o awk trata o passwd como mapa e some com
    # tudo. Discrimina pelo nome do arquivo (FILENAME) — robusto p/ primeiro arquivo vazio.
    awk -F'\t' -v MAP="$tmpd/upd.map" '
      FILENAME==MAP { i=index($0,"\t"); m[substr($0,1,i-1)]=substr($0,i+1); next }
      { n=index($0,":"); l=substr($0,1,n-1)
        if (l in m) { print m[l]; delete m[l] } else print }' \
      "$tmpd/upd.map" "$pwfile" > "$tmp"
  fi
  cat "$tmpd/new.lines" >> "$tmp"
  cat "$tmp" > "$pwfile" && rm -f "$tmp" || { rm -f "$tmp"; rm -rf "$tmpd"; fail 500 "Falha ao gravar" "write_fail"; }
fi

audit_log_to "$contest" users-bulk \
  "created=$(grep -c . "$tmpd/created.jsonl" 2>/dev/null) updated=$(grep -c . "$tmpd/updated.jsonl" 2>/dev/null) skipped=$(grep -c . "$tmpd/skipped.jsonl" 2>/dev/null) on_existing=$onex"
ok_json '{created:($c[0] // []), updated:($u[0] // []), skipped:($s[0] // []),
          counts:{created:(($c[0] // [])|length), updated:(($u[0] // [])|length), skipped:(($s[0] // [])|length)}}' \
  --slurpfile c <(jq -cs '.' "$tmpd/created.jsonl") \
  --slurpfile u <(jq -cs '.' "$tmpd/updated.jsonl") \
  --slurpfile s <(jq -cs '.' "$tmpd/skipped.jsonl")
rm -rf "$tmpd"
