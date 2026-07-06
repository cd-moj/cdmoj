# GET /contest/teams?contest=<id>   (público; contest SECRETO exige sessão — gate do placar)
# DIRETÓRIO DE TIMES p/ o placar mesclar: por login não-privilegiado, os campos explícitos
# do account.json `.team` + se há brasão (logo.png) e foto (photo.png) no dir do usuário.
#   -> {teams:{<login>:{team?,univ_short?,univ_full?,flag?,region?,has_logo,has_photo}}}
# Só entram logins com ALGO a dizer (campo de time, foto ou brasão) — payload enxuto.
# Agregação dir-a-dir (sem ARG_MAX). Precedência no front: isto > teams-meta (regex) > vazio.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_not_secret_or_auth "$contest"

cdir="$CONTESTSDIR/$contest"
teams="$( { find "$cdir/users" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | while IFS= read -r d; do
    login="${d##*/}"
    case "$login" in *.admin|*.judge|*.cjudge|*.staff|*.mon|.removed-users) continue;; esac
    hp=false; [[ -s "$d/photo.png" ]] && hp=true
    hl=false; [[ -s "$d/logo.png" ]] && hl=true
    if [[ -f "$d/account.json" ]]; then
      jq -c --arg l "$login" --argjson hp "$hp" --argjson hl "$hl" '
        (.team // {}) as $tm
        | ({team:($tm.name // ""), univ_short:($tm.univ_short // ""), univ_full:($tm.univ_full // ""),
            flag:($tm.flag // ""), region:($tm.region // "")}
           | with_entries(select(.value != ""))) as $fields
        | if ($fields|length) > 0 or $hp or $hl
          then {($l): ($fields + {has_photo:$hp, has_logo:$hl})} else empty end' \
        "$d/account.json" 2>/dev/null
    elif [[ "$hp" == true || "$hl" == true ]]; then
      # participante compartilhado (USERS_FROM) sem account local: só os assets
      jq -cn --arg l "$login" --argjson hp "$hp" --argjson hl "$hl" \
        '{($l): {has_photo:$hp, has_logo:$hl}}'
    fi
  done; } | jq -cs 'add // {}')"
[[ -n "$teams" ]] || teams='{}'

ok_json '{teams:$t}' --argjson t "$teams"
