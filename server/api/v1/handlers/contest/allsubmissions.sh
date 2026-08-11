# GET /contest/allsubmissions?contest=<id>   (Bearer, admin/chief/judge/mon) -> TXT
# TODAS as submissões do contest, com 9 campos por linha:
#   tempo:username:problemid:lang:verdict:epoch:subid:fullname:univ
# admin/chief = visão completa. Juiz puro (.judge) e monitor (.mon) = ANÔNIMA: campos 2
# (username), 8 (fullname) e 9 (univ) VAZIOS, aridade 9 mantida (parser do front é
# posicional). O corte é AQUI (cliente hostil via curl não descobre quem submeteu);
# anonimato é só desta rota — placar/estatísticas têm as próprias regras.
# Fonte: emit_history_stream (fan-out em users/*/history). fullname vem dos account.json
# (local primeiro; USERS_FROM cobre participantes compartilhados). univ = vazio.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
# is_judge inclui .admin/.cjudge — testar is_admin_or_chief PRIMEIRO (padrão review/list)
FULL=0
if is_admin_or_chief; then FULL=1
elif is_judge || is_mon; then FULL=0
else fail 403 "Judge/monitor only" "judge_required"; fi

emit_text

if (( FULL == 0 )); then
  # Anônimo: zera o login e nem monta o mapa de nomes. O sort por epoch é OBRIGATÓRIO:
  # o fan-out emite as linhas agrupadas POR USUÁRIO — a contiguidade re-identificaria
  # os times (canal lateral).
  emit_history_stream "$contest" | awk -F: -v OFS=: '{ $2=""; print $0 "::" }' | sort -t: -k6,6n
  exit 0
fi

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
