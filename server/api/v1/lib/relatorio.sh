# lib/relatorio.sh — relatório periódico de submissões (mojinho → grupo dos professores).
#
# O ritual: a cada QUARTIL do semestre, um painel no grupo do Telegram com o top-10 de
# contests por submissões desde o início do semestre, o treino livre, usuários ativos e
# as comparações com o ano anterior. Sem cron: o relógio é o poll do bot em /ops/alerts
# (rel_sched_check, com stamp/throttle no handler). On-demand via POST /ops/relatorio.
#
# Config em contests/treino/var/relatorio.json (JSON puro, escrita atômica, NUNCA
# *sourced*): {inicio, fim, configured_by, configured_at, sent:{"1":E,…},
#              chat_id?, chat_set_by?, chat_set_at?, last_auto?:{k,id,dest,at,outcome}}.
# Em `sent`, valor 0 = quartil PRÉ-MARCADO ao configurar (já estava vencido; não houve
# envio) — configurar no meio do semestre não dispara relatórios retroativos.
# DESTINO (2026-09-14, relatório preso no grupo errado): `chat_id` é o grupo registrado por
# `/relatorio aqui` DENTRO do grupo; com ele o envio automático vai só para lá (alert_dm com
# chats:[chat_id], group:false). Sem `chat_id`, cai no ALERT_GROUP_CHAT do bot (alert_group),
# que a API não enxerga. ENTREGA ≠ ENFILEIRAMENTO: `sent[k]` só é marcado quando o bot
# confirma a entrega (POST /ops/alerts {ack}); enquanto o item está na fila/inflight,
# `last_auto` = {k,id,dest,at,outcome:"queued"} e o sweep não duplica. Trilha em
# run/alerts/relatorio.log (uma linha por evento) — o sweep deixou de ser mudo.
#
# Sourced sob demanda (padrão invite-notify.sh); defaults abaixo p/ teste isolado.
: "${CONTESTSDIR:=/home/ribas/moj/contests}"
: "${REL_CACHE_TTL:=600}"
[[ -n "${SCOREDIR:-}" ]] || SCOREDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../score" && pwd)"

rel_conf_file(){ printf '%s/treino/var/relatorio.json' "$CONTESTSDIR"; }
rel_cache_file(){ printf '%s/treino/var/relatorio-cache.json' "$CONTESTSDIR"; }
# cache PRÓPRIO do envio automático: o on-demand sobrescreveria o do quartil (janelas
# diferentes) entre dois sweeps e o exact-match nunca fecharia.
rel_cache_file_auto(){ printf '%s/treino/var/relatorio-cache-auto.json' "$CONTESTSDIR"; }
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
  # ⚠ o nome do tmp é resolvido ANTES do jq: ${BASHPID} no alvo de redirect de comando EXTERNO
  # expande no FILHO (pid diferente do mv) — o /relatorio config dava 500 "cannot stat" (bash 5.3)
  ( flock -w 5 9 || exit 1
    tmp="$cf.tmp.$BASHPID"
    jq -cn --argjson i "$i" --argjson f "$f" --arg by "$by" \
       --argjson t "$EPOCHSECONDS" --argjson sent "$sent" \
       '{inicio:$i, fim:$f, configured_by:$by, configured_at:$t, sent:$sent}' > "$tmp" \
      && mv -f "$tmp" "$cf"
  ) 9>"$cf.lock"
}

# rel_log <texto> — trilha do agendador/entrega (run/alerts/relatorio.log; append, nunca falha)
rel_log(){ local d="${RUNDIR:-/home/ribas/moj/run}/alerts"; mkdir -p "$d" 2>/dev/null; printf '%s\t%s\n' "$EPOCHSECONDS" "$*" >> "$d/relatorio.log" 2>/dev/null || true; }
# _rel_conf_edit <filtro-jq> [args…] — reescreve o relatorio.json sob flock (cria se não existe)
_rel_conf_edit(){
  local cf filt="$1"; shift; cf="$(rel_conf_file)"; mkdir -p "${cf%/*}" 2>/dev/null
  ( flock -w 5 9 || exit 1
    tmp="$cf.tmp.$BASHPID"
    { [[ -s "$cf" ]] && cat "$cf" || printf '{}'; } | jq -c "$filt" "$@" > "$tmp" \
      && mv -f "$tmp" "$cf"
  ) 9>"$cf.lock"
}
# rel_chat_set <chat_id> <login> / rel_chat_get — grupo de destino do envio automático
rel_chat_set(){ _rel_conf_edit '. + {chat_id:$c, chat_set_by:$by, chat_set_at:$t}' --argjson c "$1" --arg by "$2" --argjson t "$EPOCHSECONDS"; }
rel_chat_get(){ jq -r '.chat_id // empty' <<<"$(rel_conf_get)"; }
# rel_unmark <k> — desmarca sent[k..4] e o last_auto: o próximo sweep reenvia (/relatorio refazer)
rel_unmark(){ local k="$1" j ks='[]'; for (( j=k; j<=4; j++ )); do ks="$(jq -c --arg j "$j" '. + [$j]' <<<"$ks")"; done
  _rel_conf_edit '.sent = ((.sent // {}) | with_entries(select(.key as $k | ($ks | index($k)) == null))) | del(.last_auto)' --argjson ks "$ks"; }
rel_set_last_auto(){ _rel_conf_edit '.last_auto = $o' --argjson o "$1"; }
# rel_ack <id> <ok:true|false> <erro> — o bot confirmou (ou não) a entrega do item <id>:
# entregue ⇒ sent[1..k] marcados; falhou ⇒ outcome "failed: …" e o quartil continua devido
# (o próximo sweep reenfileira — quem conserta o destino é /relatorio aqui).
rel_ack(){
  local id="$1" ok="$2" err="${3:-}" la k j ks=()
  la="$(jq -c '.last_auto // {}' <<<"$(rel_conf_get)")"
  [[ "$(jq -r '.id // empty' <<<"$la")" == "$id" ]] || return 0
  k="$(jq -r '.k' <<<"$la")"
  if [[ "$ok" == true ]]; then
    for (( j=1; j<=k; j++ )); do ks+=("$j"); done; rel_mark_sent "${ks[@]}"
    _rel_conf_edit '.last_auto.outcome = "delivered" | .last_auto.delivered_at = $t' --argjson t "$EPOCHSECONDS"
    rel_log "k=$k id=$id delivered"
  else
    _rel_conf_edit '.last_auto.outcome = ("failed: " + $e)' --arg e "$err"
    rel_log "k=$k id=$id FAILED: $err"
  fi
}

# rel_mark_sent <k>... — merge em .sent com o epoch de agora; NÃO sobrescreve marca existente.
rel_mark_sent(){
  local cf add k
  cf="$(rel_conf_file)"; [[ -f "$cf" ]] || return 1
  add='{}'
  for k in "$@"; do add="$(jq -c --arg k "$k" --argjson t "$EPOCHSECONDS" '. + {($k): $t}' <<<"$add")"; done
  ( flock -w 5 9 || exit 1
    tmp="$cf.tmp.$BASHPID"
    jq -c --argjson add "$add" '.sent = ($add + (.sent // {}))' "$cf" > "$tmp" \
      && mv -f "$tmp" "$cf"
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
# cache. rc: 0 = cache pronto | 2 = GERANDO em background (tente de novo) | 1 = erro.
#
# Cache válido quando o since bate E: (a) until gerado a menos de TTL do pedido — o
# on-demand chama com until=AGORA, que muda a cada segundo, igualdade exata nunca
# acertaria; ou (b) until IGUAL — janela de until FIXO no passado (o envio de quartil) é
# IMUTÁVEL (submissão nova tem epoch de agora, fora da janela), vale em qualquer idade.
#
# ORÇAMENTO SÍNCRONO: com a base fria a varredura de todos os history pode passar de 1 min
# (medido no prod: ~70 s frio, ~3 s quente) e estouraria o curl do bot (60 s) e o nginx.
# Então a geração síncrona roda sob `timeout REL_SYNC_BUDGET` (50 s); estourou ⇒ relança
# em BACKGROUND (setsid, herdando o flock — ninguém duplica) e devolve 2: o chamador
# responde "gerando" e a próxima tentativa/sweep encontra o cache pronto.
rel_generate(){
  local since="$1" until="$2" cache="$3"
  _rel_cache_ok(){
    [[ -f "$cache" ]] || return 1
    local cs cu
    read -r cs cu <<<"$(jq -r '"\(.since) \(.until)"' "$cache" 2>/dev/null)"
    [[ "$cs" == "$since" && "$cu" =~ ^[0-9]+$ ]] || return 1
    [[ "$cu" == "$until" ]] && return 0
    (( cu <= until && until - cu < REL_CACHE_TTL ))
  }
  _rel_cache_ok && return 0
  mkdir -p "${cache%/*}" 2>/dev/null
  # limpa temporários órfãos de gerações mortas (mv atômico nunca deixa lixo em sucesso)
  find "${cache%/*}" -maxdepth 1 -name "${cache##*/}.*" ! -name '*.lock' -mmin +120 -delete 2>/dev/null
  ( flock -n 9 || exit 2        # alguém já está gerando (sync ou bg) — "tente de novo"
    _rel_cache_ok && exit 0
    timeout "${REL_SYNC_BUDGET:-50}" bash "$SCOREDIR/relatorio-gen.sh" "$since" "$until" "$cache" && exit 0
    rc=$?; (( rc == 124 )) || exit 1
    setsid bash "$SCOREDIR/relatorio-gen.sh" "$since" "$until" "$cache" </dev/null >/dev/null 2>&1 &
    exit 2
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
  # barra máx 8 e id cortado em 34: ids irmãos diferem no MEIO (…_t08_qua_… × …_t11_ter_…)
  # — corte curto demais os torna indistinguíveis (visto no top real do prod).
  local maxc=0 wnum cnt cid w bar line n=0
  maxc="$(jq -r '([ .window.top[].count ] | max) // 0' "$jf")"
  wnum="$(rel_fmt_n "$maxc")"; wnum=${#wnum}
  while IFS=$'\t' read -r cnt cid; do
    [[ -n "$cnt" ]] || continue
    n=$(( n + 1 ))
    w=$(( maxc > 0 ? cnt * 8 / maxc : 0 )); (( w < 1 && cnt > 0 )) && w=1
    bar="$(_rel_bar "$w")"
    (( ${#cid} > 34 )) && cid="${cid:0:33}…"
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
# não foi ENTREGUE, gera o relatório [inicio, b_k] e enfileira p/ o destino (chat_id registrado
# por /relatorio aqui, senão o grupo padrão do bot). `sent` é marcado pelo ACK do bot
# (rel_ack), não aqui: enquanto o item enfileirado existe (outbox/inflight), o sweep não
# duplica; item sumido sem ack (perdido) é reenfileirado. Geração em background (rc 2, base
# fria) retenta no sweep seguinte (janela de until FIXO ⇒ cache fecha por igualdade exata).
# rc: 0 ok/nada a fazer · 2 gerando · 1 falha. Requer lib/alerts.sh já sourced.
rel_sched_check(){
  local cj i f k b cache html la id d dest
  k="$(rel_due_quartil "$EPOCHSECONDS")"; [[ -n "$k" ]] || return 0
  cj="$(rel_conf_get)"
  la="$(jq -c '.last_auto // {}' <<<"$cj")"
  if [[ "$(jq -r '.k // empty' <<<"$la")" == "$k" && "$(jq -r '.outcome // empty' <<<"$la")" == queued ]]; then
    id="$(jq -r '.id' <<<"$la")"; d="$(_alert_dir)"
    [[ -e "$d/outbox/$id.json" || -e "$d/inflight/$id.json" ]] && return 0   # em voo: espera o ack
    rel_log "k=$k id=$id sumiu sem ack — reenfileirando"
  fi
  i="$(jq -r '.inicio' <<<"$cj")"; f="$(jq -r '.fim' <<<"$cj")"
  read -r -a b <<<"$(rel_quartil_bounds "$i" "$f")"
  cache="$(rel_cache_file_auto)"
  rel_generate "$i" "${b[k-1]}" "$cache"
  case $? in 0) ;; 2) rel_log "k=$k gerando em background"; return 2 ;; *) rel_log "k=$k geração FALHOU"; return 1 ;; esac
  html="$(rel_html "$cache" "quartil <b>$k/4</b>")"
  [[ -n "$html" ]] || { rel_log "k=$k html vazio"; return 1; }
  dest="$(rel_chat_get)"
  if [[ -n "$dest" ]]; then id="$(alert_dm "$html" "$dest" loud)" || { rel_log "k=$k dest=$dest enqueue FALHOU"; return 1; }
  else dest="grupo-padrao-do-bot"; id="$(alert_group "$html" loud)" || { rel_log "k=$k dest=$dest enqueue FALHOU"; return 1; }; fi
  rel_set_last_auto "$(jq -cn --argjson k "$k" --arg id "$id" --arg d "$dest" --argjson t "$EPOCHSECONDS" '{k:$k, id:$id, dest:$d, at:$t, outcome:"queued"}')"
  rel_log "k=$k dest=$dest id=$id queued"
  return 0
}
