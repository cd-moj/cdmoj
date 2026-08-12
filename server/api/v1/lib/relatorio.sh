# lib/relatorio.sh — relatório periódico de submissões (mojinho → grupo dos professores).
#
# O ritual: a cada QUARTIL do semestre, um painel no grupo do Telegram com o top-10 de
# contests por submissões desde o início do semestre, o treino livre, usuários ativos e
# as comparações com o ano anterior. Sem cron: o relógio é o poll do bot em /ops/alerts
# (rel_sched_check, com stamp/throttle no handler). On-demand via POST /ops/relatorio.
#
# Config em contests/treino/var/relatorio.json (JSON puro, escrita atômica, NUNCA
# *sourced*): {inicio, fim, configured_by, configured_at, sent:{"1":E,…}}.
# Em `sent`, valor 0 = quartil PRÉ-MARCADO ao configurar (já estava vencido; não houve
# envio) — configurar no meio do semestre não dispara relatórios retroativos.
#
# Sourced sob demanda (padrão invite-notify.sh); defaults abaixo p/ teste isolado.
: "${CONTESTSDIR:=/home/ribas/moj/contests}"
: "${REL_CACHE_TTL:=600}"
[[ -n "${SCOREDIR:-}" ]] || SCOREDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../score" && pwd)"

rel_conf_file(){ printf '%s/treino/var/relatorio.json' "$CONTESTSDIR"; }
rel_cache_file(){ printf '%s/treino/var/relatorio-cache.json' "$CONTESTSDIR"; }
rel_conf_get(){ jq -c . "$(rel_conf_file)" 2>/dev/null || printf '{}'; }

# rel_quartil_bounds <inicio> <fim> -> "b1 b2 b3 b4" (b_k = inicio + k*(fim-inicio)/4; b4 = fim)
rel_quartil_bounds(){
  local i="$1" f="$2" len=$(( $2 - $1 ))
  printf '%s %s %s %s' $(( i + len/4 )) $(( i + len/2 )) $(( i + 3*len/4 )) "$f"
}

# rel_quartil_now <inicio> <fim> <now> -> 0..4 (0 = antes do início; k = quartil corrente;
# 4 também quando now >= fim — o chamador anota "(encerrado)").
rel_quartil_now(){
  local i="$1" f="$2" now="$3" b k
  (( now < i )) && { printf 0; return; }
  read -r -a b <<<"$(rel_quartil_bounds "$i" "$f")"
  for k in 1 2 3; do (( now < b[k-1] )) && { printf '%s' "$k"; return; }; done
  printf 4
}

# rel_conf_set <inicio> <fim> <login> — grava o semestre; quartis JÁ vencidos entram em
# sent com valor 0 (pré-marcados). Atômico + flock (corrida config × sweep).
rel_conf_set(){
  local i="$1" f="$2" by="$3" cf b sent k
  cf="$(rel_conf_file)"; mkdir -p "${cf%/*}" 2>/dev/null
  read -r -a b <<<"$(rel_quartil_bounds "$i" "$f")"
  sent='{}'
  for k in 1 2 3 4; do
    (( EPOCHSECONDS >= b[k-1] )) && sent="$(jq -c --arg k "$k" '. + {($k): 0}' <<<"$sent")"
  done
  ( flock -w 5 9 || exit 1
    jq -cn --argjson i "$i" --argjson f "$f" --arg by "$by" \
       --argjson t "$EPOCHSECONDS" --argjson sent "$sent" \
       '{inicio:$i, fim:$f, configured_by:$by, configured_at:$t, sent:$sent}' > "$cf.tmp.$$" \
      && mv -f "$cf.tmp.$$" "$cf"
  ) 9>"$cf.lock"
}

# rel_mark_sent <k>... — merge em .sent com o epoch de agora; NÃO sobrescreve marca existente.
rel_mark_sent(){
  local cf add k
  cf="$(rel_conf_file)"; [[ -f "$cf" ]] || return 1
  add='{}'
  for k in "$@"; do add="$(jq -c --arg k "$k" --argjson t "$EPOCHSECONDS" '. + {($k): $t}' <<<"$add")"; done
  ( flock -w 5 9 || exit 1
    jq -c --argjson add "$add" '.sent = ($add + (.sent // {}))' "$cf" > "$cf.tmp.$$" \
      && mv -f "$cf.tmp.$$" "$cf"
  ) 9>"$cf.lock"
}

# rel_due_quartil <now> -> MAIOR k (1..4) com b_k <= now e sent["k"] ausente; vazio se
# nada devido/não configurado. (Dois quartis vencidos numa parada do bot ⇒ um relatório.)
rel_due_quartil(){
  local now="$1" cj i f b k best=""
  cj="$(rel_conf_get)"
  i="$(jq -r '.inicio // empty' <<<"$cj")"; f="$(jq -r '.fim // empty' <<<"$cj")"
  [[ "$i" =~ ^[0-9]+$ && "$f" =~ ^[0-9]+$ ]] && (( i < f )) || return 0
  read -r -a b <<<"$(rel_quartil_bounds "$i" "$f")"
  for k in 1 2 3 4; do
    (( now >= b[k-1] )) || break
    [[ -z "$(jq -r --arg k "$k" '.sent[$k] // empty' <<<"$cj")" ]] && best="$k"
  done
  [[ -n "$best" ]] && printf '%s' "$best"
  return 0
}

# rel_parse_date <YYYY-MM-DD> [end] -> epoch local 00:00:00 (ou 23:59:59). rc!=0 inválida.
# Round-trip obrigatório: o GNU date NORMALIZA 2026-02-30 p/ 2 de março em vez de recusar.
rel_parse_date(){
  local d="$1" t="00:00:00" e
  [[ "${2:-}" == end ]] && t="23:59:59"
  [[ "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
  e="$(date -d "$d $t" +%s 2>/dev/null)" || return 1
  [[ "$(date -d "@$e" +%F)" == "$d" ]] || return 1
  printf '%s' "$e"
}

# rel_generate <since> <until> <cachefile> — roda score/relatorio-gen.sh sob flock, com
# cache e TTL (repetir /relatorio no grupo é instantâneo). O on-demand chama com
# until=AGORA, que muda a cada segundo — por isso o cache vale quando o since bate e o
# until pedido está a menos de TTL do until gerado (igualdade exata nunca acertaria).
rel_generate(){
  local since="$1" until="$2" cache="$3"
  _rel_cache_ok(){
    [[ -f "$cache" ]] || return 1
    (( EPOCHSECONDS - $(stat -c %Y "$cache" 2>/dev/null || echo 0) < REL_CACHE_TTL )) || return 1
    local cs cu
    read -r cs cu <<<"$(jq -r '"\(.since) \(.until)"' "$cache" 2>/dev/null)"
    [[ "$cs" == "$since" && "$cu" =~ ^[0-9]+$ ]] || return 1
    (( cu <= until && until - cu < REL_CACHE_TTL ))
  }
  _rel_cache_ok && return 0
  mkdir -p "${cache%/*}" 2>/dev/null
  ( flock -w 55 9 || exit 1
    _rel_cache_ok && exit 0     # outro processo gerou enquanto esperávamos o lock
    bash "$SCOREDIR/relatorio-gen.sh" "$since" "$until" "$cache"
  ) 9>"$cache.lock"
}

# --- formatação do painel (Telegram HTML) -----------------------------------
# ⚠ não usar ${var//&/&amp;}: no bash 5.2+ (patsub_replacement) o & do replacement vira o
# próprio casamento e "&lt;" degrada p/ "<lt;". sed com \& é portável (idem inv_html_escape).
rel_esc(){ printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'; }
rel_fmt_n(){ # milhar com ponto (a imagem é debian slim SEM locales: printf "%'d" não agrupa)
  awk -v n="$1" 'BEGIN{ s=sprintf("%d",n); r=""
    while (length(s)>3){ r="." substr(s,length(s)-2) r; s=substr(s,1,length(s)-3) }
    printf "%s%s", s, r }'
}
rel_pct(){ # (+18%) / (-7%); prev<=0 ⇒ vazio (sem base de comparação)
  local cur="$1" prev="$2"
  (( prev > 0 )) || return 0
  printf '(%+d%%)' $(( (cur - prev) * 100 / prev ))
}
_rel_bar(){ local n="$1" out="" j; for (( j=0; j<n; j++ )); do out+="▇"; done; printf '%s' "$out"; }

# rel_html <json-do-gerador> <label-html-do-período> — monta o painel. TUDO que vem de
# dado passa por rel_esc (entidade quebrada = sendMessage 400 MUDO; o tg_send descarta
# a resposta). <label> já é HTML pronto do chamador (ex.: "quartil <b>2/4</b>").
rel_html(){
  local jf="$1" label="$2"
  local since until total users treino others others_count pw pw_users ytd pytd yy py
  since="$(jq -r '.since' "$jf")";   until="$(jq -r '.until' "$jf")"
  total="$(jq -r '.window.total' "$jf")";   users="$(jq -r '.window.users' "$jf")"
  treino="$(jq -r '.window.treino' "$jf")"
  others="$(jq -r '.window.others' "$jf")"; others_count="$(jq -r '.window.others_count' "$jf")"
  pw="$(jq -r '.prev_window.total' "$jf")"; pw_users="$(jq -r '.prev_window.users' "$jf")"
  ytd="$(jq -r '.ytd.total' "$jf")";        pytd="$(jq -r '.prev_ytd.total' "$jf")"
  yy="$(date -d "@$until" +%Y)"; py=$(( yy - 1 ))

  local out=""
  out+="📊 <b>MOJ — Relatório de submissões</b>"$'\n'
  out+="Período: <b>$(date -d "@$since" +%d/%m) – $(date -d "@$until" +%d/%m/%Y)</b>"
  [[ -n "$label" ]] && out+=" · $label"
  out+=$'\n\n'

  out+="<b>Top 10 listas</b>"$'\n'
  local maxc=0 wnum cnt cid w bar line n=0
  maxc="$(jq -r '([ .window.top[].count ] | max) // 0' "$jf")"
  wnum="$(rel_fmt_n "$maxc")"; wnum=${#wnum}
  while IFS=$'\t' read -r cnt cid; do
    [[ -n "$cnt" ]] || continue
    n=$(( n + 1 ))
    w=$(( maxc > 0 ? cnt * 10 / maxc : 0 )); (( w < 1 && cnt > 0 )) && w=1
    bar="$(_rel_bar "$w")"
    (( ${#cid} > 24 )) && cid="${cid:0:23}…"
    printf -v line '%*s' "$wnum" "$(rel_fmt_n "$cnt")"
    out+="<code>$line $bar $(rel_esc "$cid")</code>"$'\n'
  done < <(jq -r '.window.top[] | [(.count|tostring), .contest] | @tsv' "$jf")
  if (( n == 0 )); then out+="<i>sem submissões em listas no período</i>"$'\n'; fi
  if (( others_count > 0 )); then
    out+="<code>outras ($others_count): $(rel_fmt_n "$others")</code>"$'\n'
  fi
  out+=$'\n'
  out+="🏋️ treino livre: <b>$(rel_fmt_n "$treino")</b>"$'\n'
  out+="Σ <b>$(rel_fmt_n "$total")</b> submissões · <b>$(rel_fmt_n "$users")</b> usuários ativos"$'\n\n'

  local p
  p="$(rel_pct "$total" "$pw")"
  out+="📈 vs mesmo período de $py: $(rel_fmt_n "$pw")"
  [[ -n "$p" ]] && out+=" <b>$p</b>"
  (( pw_users > 0 )) && out+=" · $(rel_fmt_n "$pw_users") usuários"
  out+=$'\n'
  p="$(rel_pct "$ytd" "$pytd")"
  out+="📅 $yy até agora: <b>$(rel_fmt_n "$ytd")</b> · $py: $(rel_fmt_n "$pytd")"
  [[ -n "$p" ]] && out+=" <b>$p</b>"
  printf '%s' "$out"
}

# rel_sched_check — chamado (throttled) pelo handler /ops/alerts: se um quartil venceu e
# não foi enviado, gera o relatório [inicio, b_k], enfileira SÓ PARA O GRUPO (alert_group,
# loud) e marca 1..k. `sent` só é marcado APÓS o enqueue OK (falha ⇒ retenta no próximo
# sweep). Requer lib/alerts.sh já sourced (alert_group).
rel_sched_check(){
  local cj i f k b cache html j ks=()
  k="$(rel_due_quartil "$EPOCHSECONDS")"; [[ -n "$k" ]] || return 0
  cj="$(rel_conf_get)"
  i="$(jq -r '.inicio' <<<"$cj")"; f="$(jq -r '.fim' <<<"$cj")"
  read -r -a b <<<"$(rel_quartil_bounds "$i" "$f")"
  cache="$(rel_cache_file)"
  rel_generate "$i" "${b[k-1]}" "$cache" || return 1
  html="$(rel_html "$cache" "quartil <b>$k/4</b>")"
  [[ -n "$html" ]] || return 1
  alert_group "$html" loud >/dev/null || return 1
  for (( j=1; j<=k; j++ )); do ks+=("$j"); done
  rel_mark_sent "${ks[@]}"
}
