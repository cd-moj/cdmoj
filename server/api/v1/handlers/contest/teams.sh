# GET /contest/teams?contest=<id>   (público; contest SECRETO exige sessão — gate do placar)
# DIRETÓRIO DE TIMES p/ o placar mesclar: por login não-privilegiado, os campos explícitos
# do account.json `.team` + se há brasão (logo.png) e foto (photo.png) no dir do usuário.
# O NOME do time NÃO vai aqui — é o `fullname`, que o TXT do placar já carrega.
#   -> {teams:{<login>:{univ_short?,univ_full?,flag?,region?,has_logo,has_photo}}}
# Só entram logins com ALGO a dizer (campo de time, foto ou brasão) — payload enxuto.
# Agregação dir-a-dir (sem ARG_MAX). Precedência no front: isto > teams-meta (regex) > vazio.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_not_secret_or_auth "$contest"

# COORTES: este endpoint é PÚBLICO e lista login por login — é a maior superfície de
# vazamento de time convidado. Quando há coorte não-pública, só saem os logins das coortes
# que o chamador pode ver (a visão dele, exatamente como no placar).
source "$_LIBDIR/cohorts.sh"
CH_WANT=""     # vazio = todas (contest sem coortes)
CH_JSON='{"cohorts":[]}'
if ch_enabled "$contest"; then
  CH_JSON="$(jq -c '{cohorts:[ (.cohorts // [])[] | {id:(.id//""), regex:(.regex//""),
                     default:(.default == true)} | select(.id != "") ]}' \
               "$CONTESTSDIR/$contest/cohorts.json" 2>/dev/null)"
  [[ -n "$CH_JSON" ]] || CH_JSON='{"cohorts":[]}'
  chview=public
  load_session 2>/dev/null && [[ "$SESSION_CONTEST" == "$contest" ]] \
    && chview="$(ch_view_for_login "$contest" "$SESSION_LOGIN")"
  CH_WANT=" $(ch_cohorts_of_view "$contest" "$chview") "
  [[ "$chview" == all ]] && CH_WANT=""
fi

cdir="$CONTESTSDIR/$contest"
teams="$( { find "$cdir/users" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | while IFS= read -r d; do
    login="${d##*/}"
    case "$login" in *.admin|*.judge|*.cjudge|*.staff|*.cstaff|*.mon|.removed-users) continue;; esac
    hp=false; [[ -s "$d/photo.png" ]] && hp=true
    hl=false; [[ -s "$d/logo.png" ]] && hl=true
    if [[ -f "$d/account.json" ]]; then
      jq -c --arg l "$login" --argjson hp "$hp" --argjson hl "$hl" \
        --argjson CH "$CH_JSON" --arg want "$CH_WANT" '
        (.team // {}) as $tm
        # coorte do login (campo vence regex, senão a default) — mesma regra do sc_users, e
        # resolvida DENTRO deste jq: um fork por login num endpoint público seria caro.
        | (($tm.cohort // "") as $c
           | if $c != "" then $c
             else ((first($CH.cohorts[] | .regex as $rr
                          | select($rr != "" and (try ($l|test($rr;"i")) catch false)) | .id))
                   // (first($CH.cohorts[] | select(.default) | .id)) // "") end) as $coh
        | if $want != "" and (($want | contains(" " + $coh + " ")) | not) then empty
          else
            ({univ_short:($tm.univ_short // ""), univ_full:($tm.univ_full // ""),
              flag:($tm.flag // ""), region:($tm.region // "")}
             | with_entries(select(.value != ""))) as $fields
            | if ($fields|length) > 0 or $hp or $hl
              then {($l): ($fields + {has_photo:$hp, has_logo:$hl})} else empty end
          end' "$d/account.json" 2>/dev/null
    elif [[ "$hp" == true || "$hl" == true ]]; then
      # participante compartilhado (USERS_FROM) sem account local: só os assets
      jq -cn --arg l "$login" --argjson hp "$hp" --argjson hl "$hl" \
        '{($l): {has_photo:$hp, has_logo:$hl}}'
    fi
  done; } | jq -cs 'add // {}')"
[[ -n "$teams" ]] || teams='{}'

ok_json '{teams:$t}' --argjson t "$teams"
