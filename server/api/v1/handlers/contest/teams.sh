# GET /contest/teams?contest=<id>   (público; contest SECRETO exige sessão — gate do placar)
# DIRETÓRIO DE TIMES p/ o placar mesclar: por login não-privilegiado, os campos explícitos
# do account.json `.team` + se há brasão (logo.png) e foto (photo.webp, ou photo.png no
# acervo antigo) no dir do usuário.
# O NOME do time NÃO vai aqui — é o `fullname`, que o TXT do placar já carrega.
#   -> {teams:{<login>:{univ_short?,univ_full?,flag?,region?,has_logo,has_photo}}}
# Só entram logins com ALGO a dizer (campo de time, foto ou brasão) — payload enxuto.
# UMA VARREDURA, não um jq por conta (regra da casa — ver o CLAUDE.md, "listagem de MUITOS
# usuários"). Era um `jq` POR LOGIN: 137 contas = 0,67 s, ~5 ms cada — a 2000 times daria ~10 s,
# e esta rota está no caminho do placar. Agora são 5 processos, seja qual for o tamanho: um
# `find` (contas + assets de uma vez), um `awk` que monta o mapa de assets, um `jq` sobre TODAS
# as contas (login pelo `input_filename`), um p/ quem só tem asset e o `jq -s` que junta.
# ⚠ O mapa de assets entra por `--slurpfile`, que o jq parseia UMA vez; passá-lo como string e
# reconstruir dentro do filtro seria O(n²) — refeito a cada conta.
# Agregação sem ARG_MAX. Precedência no front: isto > teams-meta (regex) > vazio.
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
TD="$(mktemp -d 2>/dev/null)" || TD="${TMPDIR:-/tmp}/cteams.$$"; mkdir -p "$TD"
trap 'rm -rf "$TD"' EXIT

# 1 find p/ tudo: as contas e os assets. `%h` = dir do usuário, `%f` = nome do arquivo.
# foto é webp desde 2026-08 (photo.png = acervo antigo, ainda válido — lib/team-photo.sh)
find "$cdir/users" -mindepth 2 -maxdepth 2 -type f -size +0c \
     \( -name account.json -o -name photo.webp -o -name photo.png -o -name logo.png \) \
     -printf '%h\t%f\n' 2>/dev/null \
  | awk -F'\t' -v amap="$TD/assets.json" -v alst="$TD/accts.lst" '
      function esc(s){ gsub(/\\/,"\\\\",s); gsub(/"/,"\\\"",s); return s }
      { n=split($1,p,"/"); l=p[n]
        if (l ~ /^\./) next                                  # .removed-users e afins
        if (l ~ /\.(admin|judge|cjudge|staff|cstaff|mon|animeitor)$/) next
        seen[l]=1
        if ($2 == "account.json") { acct[l]=1; print $1 "/account.json" > alst }
        else if ($2 ~ /^photo\./)  hp[l]=1
        else if ($2 == "logo.png")  hl[l]=1 }
      END{ printf "{" > amap; sep=""
           for (l in seen) {
             printf "%s\"%s\":{\"hp\":%s,\"hl\":%s}", sep, esc(l),
                    (l in hp ? "true":"false"), (l in hl ? "true":"false") > amap
             sep="," }
           printf "}\n" > amap }'
[[ -s "$TD/assets.json" ]] || printf '{}\n' > "$TD/assets.json"
: > "$TD/accts.lst.ok"; [[ -s "$TD/accts.lst" ]] && sort "$TD/accts.lst" > "$TD/accts.lst.ok"

teams="$( { [[ -s "$TD/accts.lst.ok" ]] && xargs -a "$TD/accts.lst.ok" -d'\n' -r \
      jq -c --slurpfile A "$TD/assets.json" --argjson CH "$CH_JSON" --arg want "$CH_WANT" '
        ((input_filename | split("/"))[-2]) as $l
        | (($A[0][$l] // {}).hp == true) as $hp
        | (($A[0][$l] // {}).hl == true) as $hl
        | (.team // {}) as $tm
        # coorte do login (campo vence regex, senão a default) — mesma regra do sc_users, e
        # resolvida DENTRO deste jq: um fork por login num endpoint público seria caro.
        | (($tm.cohort // "") as $c
           | if $c != "" then $c
             else ((first($CH.cohorts[] | .regex as $rr
                          | select($rr != "" and (try ($l|test($rr;"i")) catch false)) | .id))
                   // (first($CH.cohorts[] | select(.default) | .id)) // "") end) as $coh
        | if $want != "" and (($want | contains(" " + $coh + " ")) | not) then empty
          else
            (({univ_short:($tm.univ_short // ""), univ_full:($tm.univ_full // ""),
               flag:($tm.flag // ""), region:($tm.region // "")}
              | with_entries(select(.value != "")))
             + (if $tm.ai == true then {ai:true} else {} end)) as $fields
            | if ($fields|length) > 0 or $hp or $hl
              then {($l): ($fields + {has_photo:$hp, has_logo:$hl})} else empty end
          end' 2>/dev/null
    # participante compartilhado (USERS_FROM) sem account local: só os assets. Coorte não se
    # aplica (não há `.team` p/ consultar) — é o mesmo que a versão dir-a-dir fazia.
    jq -cn --slurpfile A "$TD/assets.json" --rawfile acc "$TD/accts.lst.ok" '
      ($acc | split("\n") | map(select(length>0) | (split("/")[-2])) | map({key:., value:1})
       | from_entries) as $tem
      | ($A[0] // {}) | to_entries[]
      | select(($tem[.key] // 0) == 0 and (.value.hp or .value.hl))
      | {(.key): {has_photo:(.value.hp), has_logo:(.value.hl)}}' 2>/dev/null
  # ordena por login: a versão dir-a-dir iterava `find | sort`, então saía em ordem alfabética.
  # Manter a MESMA ordem é o que deixa a troca provável byte a byte (e o front, que usa isto
  # como mapa, não se importa — mas um diff que fecha vale mais que um "não deve importar").
  } | jq -cs 'add // {} | to_entries | sort_by(.key) | from_entries')"
[[ -n "$teams" ]] || teams='{}'

# mapa de TODOS os times/participantes: passa de 128KiB (teto do --argjson) num contest
# grande — vai por --slurpfile (ver ok_json_slurp em lib/common.sh).
ok_json_slurp '{teams:$t[0]}' t "$teams"
