# lib/cohorts.sh — COORTES de placar (times oficiais × convidados).
#
# Maratona convida times "extra-oficiais" (o Ribas chama de CCL, café com leite): eles competem na
# mesma prova, mas **não podem aparecer no placar público** e os times regulares não podem nem
# saber que existem. Os próprios convidados veem TODOS. Quando a organização libera os resultados,
# todos aparecem juntos. Nada disso é um `if ccl` no código: é uma COORTE com política.
#
#   contests/<c>/cohorts.json   (ausente = comportamento de sempre, custo zero)
#   { "version":1, "results_released":false,
#     "cohorts":[
#       {"id":"oficial","name":"Oficiais","default":true,"public":true},
#       {"id":"ccl","name":"Café com Leite","regex":"ccl","public":false,
#        "unranked":true,"sees":["oficial","ccl"]} ] }
#
# PERTENCIMENTO: `.team.cohort` do account.json VENCE; senão a 1ª coorte cujo `regex` casa o
# login; senão a `default`. (O regex é materializável em campo pela aba de coortes, igual ao que
# a aba Times já faz com sede/país.)
# VISÃO = conjunto de coortes que um login pode ver. Elas são DERIVADAS, não configuradas:
#   `public` = as coortes public:true (ou TODAS, depois de results_released);
#   uma visão por coorte não-pública = o `sees` dela (default: as públicas + ela mesma).
# O placar de cada visão é um TXT próprio (var/placar[-view-<id>].txt) — ver server/score/build.sh.
#
# PORQUE O CORTE SOBE ATÉ `sc_users`: no TXT do placar a posição é a ORDEM DAS LINHAS, então
# filtrar linhas dá posição certa de graça — mas a ESTRELA de first-to-solve é um mínimo global
# (`FTSMIN` em updatescore-icpc.sh, sobre a saída de sc_users). Filtrar só no TXT deixaria o
# placar público exibindo a estrela de um problema que, para ele, ninguém resolveu primeiro.

ch_file(){ printf '%s/%s/cohorts.json' "$CONTESTSDIR" "$1"; }

# ch_get <c> -> cohorts.json normalizado (default coerente quando não existe)
ch_get(){
  local f; f="$(ch_file "$1")"
  if [[ -s "$f" ]] && jq -e '.cohorts' "$f" >/dev/null 2>&1; then
    jq -c '{version:(.version // 1), results_released:(.results_released == true),
            cohorts:[ (.cohorts // [])[] | {
              id:(.id // ""), name:(.name // .id // ""), regex:(.regex // ""),
              public:(.public != false), unranked:(.unranked == true),
              default:(.default == true), sees:(.sees // []) } | select(.id != "") ]}' "$f" 2>/dev/null \
      || printf '{"version":1,"results_released":false,"cohorts":[]}'
  else printf '{"version":1,"results_released":false,"cohorts":[]}'; fi
}
ch_save(){ local f; f="$(ch_file "$1")"; printf '%s\n' "$2" > "$f.tmp" && mv -f "$f.tmp" "$f"; }

# ch_enabled <c> — 0 (true) só quando há coorte NÃO-pública configurada. Enquanto não houver,
# todo o resto do sistema segue o caminho de sempre (um placar, um /contest/teams inteiro).
ch_enabled(){
  local j; j="$(ch_get "$1")"
  jq -e '[.cohorts[] | select(.public == false)] | length > 0' <<<"$j" >/dev/null 2>&1
}
ch_released(){ jq -e '.results_released == true' <<<"$(ch_get "$1")" >/dev/null 2>&1; }

# ch_default <c> -> id da coorte default (a 1ª marcada, senão a 1ª da lista, senão "oficial")
ch_default(){
  jq -r 'first(.cohorts[] | select(.default) | .id) // (.cohorts[0].id) // "oficial"' <<<"$(ch_get "$1")"
}

# ch_of <c> <login> -> id da coorte deste login (campo vence regex; regex vence default)
ch_of(){
  local c="$1" l="$2" ex j
  j="$(ch_get "$c")"
  ex="$(jq -r '.team.cohort // ""' "$CONTESTSDIR/$c/users/$l/account.json" 2>/dev/null)"
  if [[ -n "$ex" ]] && jq -e --arg i "$ex" 'any(.cohorts[]; .id == $i)' <<<"$j" >/dev/null 2>&1; then
    printf '%s' "$ex"; return 0
  fi
  # `.regex` BINDADO antes do test: $l|test(.regex) leria .regex de $l (armadilha de contexto
  # de args do jq); try/catch protege de regex inválido.
  jq -r --arg l "$l" '
    (first(.cohorts[] | .regex as $rr | select($rr != "" and (try ($l|test($rr;"i")) catch false)) | .id))
    // (first(.cohorts[] | select(.default) | .id)) // (.cohorts[0].id) // ""' <<<"$j"
}

# ch_view_cohorts <c> <view> -> ids das coortes visíveis nessa visão (uma por linha).
# view "public" = as públicas (ou TODAS se os resultados foram liberados); qualquer outro id =
# uma coorte não-pública, e a visão dela é o `sees` (default: públicas + ela mesma).
ch_view_cohorts(){
  local c="$1" v="${2:-public}" j; j="$(ch_get "$c")"
  jq -r --arg v "$v" '
    ([.cohorts[] | select(.public) | .id]) as $pub
    | if $v == "public" or $v == "" then
        (if .results_released then [.cohorts[].id] else $pub end)
      else
        ((first(.cohorts[] | select(.id == $v))) as $co
         | if $co == null then $pub
           elif ($co.sees | length) > 0 then $co.sees
           else ($pub + [$co.id]) end)
      end
    | unique | .[]' <<<"$j"
}

# ch_view_for_login <c> <login> -> visão que ESTE login deve receber.
# Privilegiado (admin/juiz/monitor/staff) e pós-liberação: "all" (tudo).
ch_view_for_login(){
  local c="$1" l="$2" co
  ch_enabled "$c" || { printf 'public'; return 0; }
  ch_released "$c" && { printf 'all'; return 0; }
  case "$l" in *.admin|*.judge|*.cjudge|*.staff|*.cstaff|*.mon) printf 'all'; return 0;; esac
  co="$(ch_of "$c" "$l")"
  # membro de coorte pública vê a visão pública; de coorte privada, a visão dela
  if [[ -n "$co" ]] && jq -e --arg i "$co" 'any(.cohorts[]; .id == $i and .public == false)' \
       <<<"$(ch_get "$c")" >/dev/null 2>&1; then printf '%s' "$co"; else printf 'public'; fi
}

# ch_views <c> -> visões que precisam de placar próprio (uma por linha).
# Sem coorte privada: só "public" (= o placar de hoje). Com: "public" + uma por coorte privada.
# "all" só existe como visão quando há coorte privada (é o placar completo).
ch_views(){
  local c="$1"
  ch_enabled "$c" || { printf 'public\n'; return 0; }
  printf 'public\n'
  jq -r '.cohorts[] | select(.public == false) | .id' <<<"$(ch_get "$c")"
  printf 'all\n'
}

# ch_cohorts_of_view <c> <view> -> string "id id id" p/ MOJ_COHORTS (vazio = todas)
ch_cohorts_of_view(){
  local c="$1" v="$2"
  [[ "$v" == all ]] && { printf ''; return 0; }
  ch_view_cohorts "$c" "$v" | tr '\n' ' ' | sed 's/ *$//'
}

# ch_view_file <c> <view> [full] -> caminho do TXT do placar dessa visão
ch_view_file(){
  local c="$1" v="$2" full="${3:-}" sfx=""
  [[ -n "$full" ]] && sfx="-full"
  if [[ "$v" == public || -z "$v" ]]; then printf '%s/%s/var/placar%s.txt' "$CONTESTSDIR" "$c" "$sfx"
  else printf '%s/%s/var/placar-view-%s%s.txt' "$CONTESTSDIR" "$c" "$v" "$sfx"; fi
}

# ch_unranked_of_view <c> <view> -> ids das coortes que aparecem SEM consumir posição oficial
# (convenção ICPC de time extra-oficial: aparece intercalado, a numeração pula).
ch_unranked_of_view(){
  local c="$1" v="$2" want
  want="$(ch_cohorts_of_view "$c" "$v")"
  jq -r --arg want "$want" '
    ($want | split(" ") | map(select(length > 0))) as $w
    | .cohorts[] | select(.unranked) | .id as $i
    | select(($w | length) == 0 or ($w | index($i)) != null) | $i' <<<"$(ch_get "$c")"
}

# ch_valid_id <id> — id de coorte (vira nome de arquivo do placar da visão)
ch_valid_id(){ [[ "$1" =~ ^[a-z0-9][a-z0-9_-]{0,23}$ ]]; }
