# lib/site-lock.sh — TRAVA DE SEDE POR IP (opt-in por contest: SITE_LOCK=1 no conf).
#
# O problema: a máquina de prova fecha o firewall e só libera o IP do MOJ, e o /etc/hosts só
# resolve o subdomínio da prova — mas `curl --resolve moj…:443:<IP>` (ou `-k https://<IP>/`)
# chega ao site base pelo MESMO IP e entra no treino ou noutro contest com a conta do aluno
# (backups que ele subiu antes, fontes antigos, juiz do treino). Nem gate de UA nem isolamento
# por subdomínio seguram isso: o UA é do cliente e o subdomínio ele escolhe. O único dado que
# ele NÃO controla é o IP de origem (a saída NAT da sede).
#
# A trava: todo login de competidor num contest com SITE_LOCK reivindica o IP de origem para
# aquele contest até CONTEST_END + SITE_LOCK_GRACE (renovado a cada login). Enquanto a
# reivindicação vale, QUALQUER pedido daquele IP a outro alvo (treino, índice, gestão de
# problemas, outro contest) leva 403 `site_locked` — inclusive sessão do treino aberta ANTES
# da prova (sessão do MOJ não expira). Conta de PAPEL (.admin/.judge/.staff…) é isenta: a
# organização da sede segue usando o resto. Mais de um contest pode reivindicar o mesmo IP
# (duas provas na mesma sede): cada um vale para si.
#
# AUDITORIA (pedido do Ribas: toda reivindicação e todo bloqueio têm de ficar claros p/ o
# .admin): a 1ª reivindicação de um IP por um contest vai ao admin-audit.log daquele contest
# (`site-lock-claim ip= login= until=`); cada bloqueio vai como `site-lock-block ip= target=
# route= login=` — com teto de 1 linha por (ip, alvo) a cada 5 min (um laço de curl não pode
# inundar o log), e o contador `blocked` da reivindicação sobe sempre. O painel Pessoas ›
# Sessões & anomalias mostra a tabela de IPs presos e os bloqueios; o preflight avisa gate
# ligado sem trava.
#
# Estado: run/site-lock/<ip> — TSV, UMA linha por contest que reivindicou o IP:
#   ip \t contest \t until \t first \t last \t logins \t blocked \t last_block \t last_target
# Escrita sob flock por IP (fd dinâmico). A leitura do router é builtin (zero fork) e só
# acontece quando o arquivo do IP existe: para todo o resto do mundo custa um [[ -f ]].

sl_dir(){ printf '%s/site-lock' "${RUNDIR:-/home/ribas/moj/run}"; }
sl_file(){ printf '%s/%s' "$(sl_dir)" "$1"; }
sl_enabled(){ local v; v="$(conf_value "$1" SITE_LOCK)"; [[ "$v" == 1 || "$v" == y || "$v" == true ]]; }
sl_grace(){ local g; g="$(conf_value "$1" SITE_LOCK_GRACE)"; [[ "$g" =~ ^[0-9]+$ ]] && printf '%s' "$g" || printf '3600'; }

_sl_lock(){ local fd d; d="$(sl_dir)"; mkdir -p "$d/.blk" 2>/dev/null; chmod 700 "$d" 2>/dev/null
  exec {fd}>"$d/.$1.lock" 2>/dev/null || { printf ''; return 1; }
  flock "$fd" 2>/dev/null || { printf ''; return 1; }; printf '%s' "$fd"; }
_sl_unlock(){ [[ -n "${1:-}" ]] && eval "exec ${1}>&-" 2>/dev/null; return 0; }

# sl_claim <contest> <ip> <login> -> ecoa "new"|"renewed"|"" (sem reivindicação: contest sem
# trava, acabado, IP vazio ou conta de papel). Audita a reivindicação NOVA.
sl_claim(){
  local c="$1" ip="$2" lg="${3:-}" end until now="$EPOCHSECONDS" fd f tmp found=0 line
  local ipf="${ip//[^0-9a-fA-F.:]/}"
  [[ -n "$ipf" && -n "$c" ]] || { printf ''; return 0; }
  is_reserved_role_login "$lg" && { printf ''; return 0; }
  sl_enabled "$c" || { printf ''; return 0; }
  end="$(conf_value "$c" CONTEST_END)"; [[ "$end" =~ ^[0-9]+$ ]] || end=0
  if (( end > 0 )); then
    (( end + $(sl_grace "$c") >= now )) || { printf ''; return 0; }   # prova acabada: nada a prender
    until=$(( end + $(sl_grace "$c") ))
  else until=$(( now + 86400 )); fi
  fd="$(_sl_lock "$ipf")" || fd=""
  f="$(sl_file "$ipf")"; tmp="$(mktemp "$(sl_dir)/.$ipf.XXXXXX" 2>/dev/null)" || { _sl_unlock "$fd"; printf ''; return 0; }
  {
    if [[ -f "$f" ]]; then
      while IFS=$'\t' read -r _ip _c _u _first _last _n _b _lb _lt; do
        [[ -n "$_c" ]] || continue
        if [[ "$_c" == "$c" ]]; then
          found=1; printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$ipf" "$c" "$until" "${_first:-$now}" "$now" "$(( ${_n:-0} + 1 ))" "${_b:-0}" "${_lb:-0}" "${_lt:-}"
        else
          printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$_ip" "$_c" "$_u" "$_first" "$_last" "${_n:-0}" "${_b:-0}" "${_lb:-0}" "${_lt:-}"
        fi
      done < "$f"
    fi
    (( found )) || printf '%s\t%s\t%s\t%s\t%s\t1\t0\t0\t\n' "$ipf" "$c" "$until" "$now" "$now"
  } > "$tmp"
  mv -f "$tmp" "$f" 2>/dev/null || rm -f "$tmp"
  _sl_unlock "$fd"
  if (( found )); then printf 'renewed'
  else
    audit_log_to "$c" site-lock-claim "ip=$ipf login=${lg:--} until=$until"
    printf 'new'
  fi
}

# sl_check <ip> <alvo> -> ecoa o contest que PRENDE este IP quando o alvo não é ele (vazio =
# livre). Só builtins. Alvo vazio (rota sem contest: treino/índice/problemas) = bloqueado.
sl_check(){
  local ipf="${1//[^0-9a-fA-F.:]/}" tgt="${2:-}" f now="$EPOCHSECONDS" claimant=""
  [[ -n "$ipf" ]] || return 0
  f="$(sl_file "$ipf")"; [[ -f "$f" ]] || return 0
  while IFS=$'\t' read -r _ip _c _u _rest; do
    [[ -n "$_c" && "$_u" =~ ^[0-9]+$ ]] || continue
    (( _u >= now )) || continue
    [[ "$_c" == "$tgt" ]] && return 0          # o alvo é um dos donos: livre
    [[ -n "$claimant" ]] || claimant="$_c"
  done < "$f"
  printf '%s' "$claimant"
}

# sl_record_block <contest-dono> <ip> <alvo> <rota> [login] — contador + auditoria (teto 5 min
# por ip+alvo: o laço de curl de um aluno não inunda o admin-audit.log)
sl_record_block(){
  local c="$1" ipf="${2//[^0-9a-fA-F.:]/}" tgt="${3:-}" route="${4:-}" lg="${5:-}" now="$EPOCHSECONDS"
  local d fd f tmp stamp last=0
  d="$(sl_dir)"; f="$(sl_file "$ipf")"; [[ -f "$f" ]] || return 0
  fd="$(_sl_lock "$ipf")" || fd=""
  tmp="$(mktemp "$d/.$ipf.XXXXXX" 2>/dev/null)" || { _sl_unlock "$fd"; return 0; }
  while IFS=$'\t' read -r _ip _c _u _first _last _n _b _lb _lt; do
    [[ -n "$_c" ]] || continue
    if [[ "$_c" == "$c" ]]; then printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$_ip" "$_c" "$_u" "$_first" "$_last" "${_n:-0}" "$(( ${_b:-0} + 1 ))" "$now" "${tgt:--}"
    else printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$_ip" "$_c" "$_u" "$_first" "$_last" "${_n:-0}" "${_b:-0}" "${_lb:-0}" "${_lt:-}"; fi
  done < "$f" > "$tmp"
  mv -f "$tmp" "$f" 2>/dev/null || rm -f "$tmp"
  _sl_unlock "$fd"
  stamp="$d/.blk/${ipf}_${tgt//[^A-Za-z0-9._@#+-]/_}"
  [[ -f "$stamp" ]] && last="$(<"$stamp")"; [[ "$last" =~ ^[0-9]+$ ]] || last=0
  if (( now - last >= 300 )); then
    printf '%s' "$now" > "$stamp" 2>/dev/null
    audit_log_to "$c" site-lock-block "ip=$ipf target=${tgt:--} route=${route:--} login=${lg:--}"
  fi
  return 0
}

# sl_release <contest> <ip> — tira a reivindicação deste contest (as de outros ficam)
sl_release(){
  local c="$1" ipf="${2//[^0-9a-fA-F.:]/}" f fd tmp
  f="$(sl_file "$ipf")"; [[ -f "$f" ]] || return 0
  fd="$(_sl_lock "$ipf")" || fd=""
  tmp="$(mktemp "$(sl_dir)/.$ipf.XXXXXX" 2>/dev/null)" || { _sl_unlock "$fd"; return 0; }
  awk -F'\t' -v c="$c" '$2 != c' "$f" > "$tmp" 2>/dev/null
  if [[ -s "$tmp" ]]; then mv -f "$tmp" "$f"; else rm -f "$tmp" "$f"; fi
  _sl_unlock "$fd"; return 0
}

# sl_list <contest> -> JSON [{ip,until,first,last,logins,blocked,last_block,last_target,active}]
sl_list(){
  local d; d="$(sl_dir)"
  [[ -d "$d" ]] || { printf '[]'; return 0; }
  ( set +o noglob; shopt -s nullglob; cat "$d"/* 2>/dev/null ) \
    | awk -F'\t' -v c="$1" '$2 == c' \
    | jq -Rn --argjson now "$EPOCHSECONDS" '[ inputs | split("\t") | select(length >= 7)
        | {ip:.[0], until:(.[2]|tonumber? // 0), first:(.[3]|tonumber? // 0), last:(.[4]|tonumber? // 0),
           logins:(.[5]|tonumber? // 0), blocked:(.[6]|tonumber? // 0), last_block:(.[7]|tonumber? // 0),
           last_target:(.[8] // "")} | . + {active:(.until >= $now)} ] | sort_by(-.blocked, -.last)' 2>/dev/null \
    || printf '[]'
}
