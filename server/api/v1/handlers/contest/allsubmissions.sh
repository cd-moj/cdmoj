# GET /contest/allsubmissions?contest=<id>   (Bearer, admin) -> TXT
# TODAS as submissões do contest, com 9 campos por linha:
#   tempo:username:problemid:lang:verdict:epoch:subid:fullname:univ
# Fonte: emit_history_stream (fan-out em users/*/history). fullname vem dos account.json
# (local primeiro; USERS_FROM cobre participantes compartilhados). univ = vazio.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin_or_chief || fail 403 "Admin/juiz-chefe only" "admin_required"

emit_text

# Mapa login -> fullname via arquivo temp (batch jq; nunca --argjson de mapa grande).
NAMES="$(mktemp)"; trap 'rm -f "$NAMES"' EXIT
d="$CONTESTSDIR/$contest/users"
[[ -d "$d" ]] && find "$d" -mindepth 2 -maxdepth 2 -name account.json -print0 2>/dev/null \
  | xargs -0 -r jq -r '[.login//"", .fullname//""] | @tsv' >> "$NAMES" 2>/dev/null
src="$(_users_source "$contest")"
if [[ "$src" != "$contest" ]]; then
  find "$CONTESTSDIR/$src/users" -mindepth 2 -maxdepth 2 -name account.json -print0 2>/dev/null \
    | xargs -0 -r jq -r '[.login//"", .fullname//""] | @tsv' >> "$NAMES" 2>/dev/null
fi

emit_history_stream "$contest" | awk -F: -v nf="$NAMES" '
  BEGIN {
    while ((getline line < nf) > 0) {
      i = index(line, "\t"); k = substr(line, 1, i-1)
      if (!(k in name)) name[k] = substr(line, i+1)   # local vence a fonte
    }
  }
  {
    full = (($2 in name) ? name[$2] : "")
    print $0 ":" full ":"
  }
'
