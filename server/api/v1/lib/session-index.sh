# lib/session-index.sh — ÍNDICE de sessões por login + chave de MÁQUINA + sessão única.
#
# Por que existe: a sessão do MOJ não expira, e até 02/09/2026 um login novo em outra máquina
# NÃO derrubava a anterior — um time podia ficar logado em N máquinas (auditoria da Maratona
# 2026). Para derrubar a anterior no login sem varrer o $SESSIONDIR inteiro (global, milhares
# de arquivos, inaceitável no pico de 2000 logins/min), cada sessão criada entra num índice
# por login: $SESSIONDIR/.idx/<contest>/<login> = um token por linha (append de 37 bytes é
# atômico). O dotdir é INVISÍVEL ao glob `$SESSIONDIR/*` dos varredores de sempre
# (remove_contest_sessions, logout-mismatch, treino) — eles seguem apagando arquivos e a
# entrada obsoleta é PODADA na leitura (token sem arquivo, ou com LOGIN/CONTEST diferentes).
#
# CHAVE DE MÁQUINA (sess_machine_key): o navegador do mlinux manda
# `MLinux/<imagem>/<machine_id>/<boot_id>` no User-Agent ⇒ `m:<machine_id>/<boot_id>` —
# o boot_id é OBRIGATÓRIO na chave porque o machine_id pode ser CLONADO (Salvador: 24 máquinas
# com o mesmo /etc/machine-id na Maratona 2026). Navegador comum ⇒ `ip:<ip>`. A MESMA regra
# mora em jq no motor de anomalias (lib/anomalies.sh, `mkey`) — mexeu numa, mexa na outra.
#
# SESSÃO ÚNICA (sess_revoke_others): só com o gate de UA ligado p/ aquele login (ug_expected
# não vazio) e `single_session` no ua-gate.json (default true). Login em CHAVE diferente da
# sessão antiga ⇒ a antiga morre (troca de máquina por defeito continua funcionando: o time
# loga na nova e a velha perde a sessão); mesma chave (recarga do navegador) ⇒ fica.
# Concorrência: append + leitura + revogação correm sob flock por (contest,login), com fd
# DINÂMICO (o 9 já é o lock de 15 handlers) — dois logins simultâneos do mesmo time não se
# revogam mutuamente nem sobrevivem os dois.
#
# SESSÕES ANTERIORES AO ÍNDICE: o índice só é confiável depois de SEMEADO (marcador
# .idx/<c>/.seeded). Sem marcador, quem precisa dele semeia UMA vez (varredura completa sob
# flock -n em .seed.lock; quem não pegar o lock segue sem revogar dessa vez). Só apêndice —
# nunca truncar: um login em voo não pode ser perdido. Reexecutável: server/bin/session-index-seed.sh.
#
# EVENTOS (sess_event): contests/<c>/var/session-events.log — TSV
#   epoch \t login \t evento(revoke|logout|mismatch-logout) \t old_key \t new_key \t tok8 [\t quem]
# É a trilha que o painel "Sessões & anomalias" mostra. Entra no arquivamento de rodada.

_sidx_dir(){ printf '%s/.idx/%s' "$SESSIONDIR" "$1"; }
_sidx_file(){ printf '%s/.idx/%s/%s' "$SESSIONDIR" "$1" "$2"; }

# sess_machine_key <ip> <ua> -> "m:<mid>/<boot>" | "ip:<ip>"   (bash puro, zero fork)
sess_machine_key(){
  local ip="${1:-}" ua="${2:-}"
  if [[ "$ua" =~ MLinux/[^/]+/([0-9a-f]{32})/([0-9]+) ]]; then
    printf 'm:%s/%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
  else
    printf 'ip:%s' "$ip"
  fi
}

# sess_index_add <contest> <login> <token> — entrada no índice (append atômico)
sess_index_add(){
  local c="$1" l="$2" t="$3" d
  [[ -n "$c" && -n "$l" && -n "$t" ]] || return 0
  valid_id "$c" && valid_id "$l" || return 0
  d="$(_sidx_dir "$c")"
  [[ -d "$d" ]] || { mkdir -p "$d" 2>/dev/null; chmod 700 "$d" 2>/dev/null; }
  printf '%s\n' "$t" >> "$d/$l" 2>/dev/null || true
}

# sess_lock <contest> <login> -> ecoa o fd do lock (dinâmico); sess_unlock <fd>
sess_lock(){
  local c="$1" l="$2" d fd
  d="$(_sidx_dir "$c")"; mkdir -p "$d" 2>/dev/null
  exec {fd}>"$d/$l.lock" 2>/dev/null || { printf ''; return 1; }
  flock "$fd" 2>/dev/null || { printf ''; return 1; }
  printf '%s' "$fd"
}
sess_unlock(){ [[ -n "${1:-}" ]] && eval "exec ${1}>&-" 2>/dev/null; return 0; }

# sess_index_seeded <contest> -> 0 se o índice já foi semeado (vale usar)
sess_index_seeded(){ [[ -e "$(_sidx_dir "$1")/.seeded" ]]; }

# sess_seed_index <contest> [--force] -> semeia o índice do contest a partir de TODO o
# $SESSIONDIR (uma vez; flock -n: se outro está semeando, retorna 1 sem esperar). Só apêndice.
sess_seed_index(){
  local c="$1" d f lfd CONTEST LOGIN n=0
  valid_id "$c" || return 1
  d="$(_sidx_dir "$c")"; mkdir -p "$d" 2>/dev/null; chmod 700 "$d" 2>/dev/null
  [[ "${2:-}" == --force ]] || { [[ -e "$d/.seeded" ]] && return 0; }
  exec {lfd}>"$d/.seed.lock" 2>/dev/null || return 1
  if ! flock -n "$lfd" 2>/dev/null; then eval "exec ${lfd}>&-"; return 1; fi
  ( set +o noglob; shopt -s nullglob
    for f in "$SESSIONDIR"/*; do
      [[ -f "$f" ]] || continue
      CONTEST=""; LOGIN=""; source "$f" 2>/dev/null
      [[ "$CONTEST" == "$c" && -n "$LOGIN" ]] || continue
      valid_id "$LOGIN" || continue
      printf '%s\n' "${f##*/}" >> "$d/$LOGIN" 2>/dev/null
    done )
  : > "$d/.seeded"
  eval "exec ${lfd}>&-"
  return 0
}

# sess_tokens_of <contest> <login> -> tokens VIVOS do login (um por linha), podando o índice.
# Sem índice semeado ⇒ nada (nunca varredura global aqui: este é o caminho quente do login).
sess_tokens_of(){
  local c="$1" l="$2" idx t f CONTEST LOGIN keep=() changed=0
  idx="$(_sidx_file "$c" "$l")"
  [[ -s "$idx" ]] || return 0
  local -A seen=()
  while IFS= read -r t; do
    [[ -n "$t" ]] || { changed=1; continue; }
    [[ -n "${seen[$t]:-}" ]] && { changed=1; continue; }
    seen[$t]=1
    valid_id "$t" || { changed=1; continue; }
    f="$SESSIONDIR/$t"
    [[ -f "$f" ]] || { changed=1; continue; }
    CONTEST=""; LOGIN=""; source "$f" 2>/dev/null
    [[ "$CONTEST" == "$c" && "$LOGIN" == "$l" ]] || { changed=1; continue; }
    keep+=("$t")
  done < "$idx"
  if (( changed )); then
    local tmp; tmp="$(mktemp "$idx.XXXXXX" 2>/dev/null)" && {
      printf '%s\n' "${keep[@]}" > "$tmp" 2>/dev/null; mv -f "$tmp" "$idx" 2>/dev/null || rm -f "$tmp"; }
  fi
  (( ${#keep[@]} )) && printf '%s\n' "${keep[@]}"
  return 0
}

# sess_event <contest> <login> <evento> <old_key> <new_key> <tok8> [quem]
sess_event(){
  local c="$1"
  mkdir -p "$CONTESTSDIR/$c/var" 2>/dev/null
  printf '%s\t%s\t%s\t%s\t%s\t%s%s\n' "$EPOCHSECONDS" "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-}" \
    "${7:+$'\t'$7}" >> "$CONTESTSDIR/$c/var/session-events.log" 2>/dev/null || true
}

# sess_revoke_others <contest> <login> <token-a-manter> <chave-nova> -> ecoa nº revogadas.
# Chamar SOB sess_lock. Só derruba sessão em chave DIFERENTE (mesma máquina = recarga: fica).
sess_revoke_others(){
  local c="$1" l="$2" keep="$3" key="$4" t f n=0 MKEY IP UA_B64
  while IFS= read -r t; do
    [[ -n "$t" && "$t" != "$keep" ]] || continue
    f="$SESSIONDIR/$t"; [[ -f "$f" ]] || continue
    MKEY=""; IP=""; UA_B64=""; source "$f" 2>/dev/null
    # sessão antiga sem MKEY (criada antes do índice): deriva da IP/UA gravados
    [[ -n "$MKEY" ]] || MKEY="$(sess_machine_key "$IP" "$(printf '%s' "$UA_B64" | base64 -d 2>/dev/null)")"
    [[ "$MKEY" == "$key" ]] && continue
    rm -f "$f" 2>/dev/null || continue
    ((n++))
    sess_event "$c" "$l" revoke "$MKEY" "$key" "${t:0:8}"
  done < <(sess_tokens_of "$c" "$l")
  (( n )) && sess_tokens_of "$c" "$l" >/dev/null   # poda o índice já (as entradas mortas)
  printf '%s' "$n"
}
