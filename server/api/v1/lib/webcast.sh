# lib/webcast.sh — CHAVES do webcast (o pacote de placar que alimenta o sistema Animeitor).
#
# O Animeitor não tem sessão: ele busca uma URL em loop. Quem autoriza é a CHAVE na URL —
# mesmo desenho do `webcastcode` do BOCA (lá a chave mora em `private/webcast.sep`, aqui em
# `contests/<c>/webcast.json`). Cada chave declara a VISÃO de placar que serve (geral ou uma
# coorte), que é o análogo do "site/faixa de usuários" que a linha do webcast.sep restringia.
#
# ⚠ A chave dá o placar DESCONGELADO (é o ponto do protocolo: o Animeitor é quem anima a
# virada). Chave vazada durante a prova = resultado vazado — por isso ela é longa, revogável,
# e a página do .animeitor mostra último acesso/IP. Ver docs/WEBCAST.md.
#
# webcast.json:
#   {version:1, keys:[{id, key, view, label, created_by, created_at,
#                      revoked_at, fetches, last_at, last_ip}]}

wc_file(){ printf '%s/%s/webcast.json' "$CONTESTSDIR" "$1"; }

wc_get(){  # <c> -> JSON normalizado (nunca vazio)
  local f; f="$(wc_file "$1")"
  [[ -s "$f" ]] || { printf '%s' '{"version":1,"keys":[]}'; return 0; }
  jq -c '{version:(.version // 1),
          keys:[ (.keys // [])[] | {
            id:(.id // ""), key:(.key // ""), view:(.view // "public"),
            label:(.label // ""), created_by:(.created_by // ""),
            created_at:(.created_at // 0), revoked_at:(.revoked_at // 0),
            fetches:(.fetches // 0), last_at:(.last_at // 0), last_ip:(.last_ip // "") }
          | select(.key != "") ]}' "$f" 2>/dev/null \
    || printf '%s' '{"version":1,"keys":[]}'
}

_wc_save(){  # <c> <json> — grava atômico, 600 (a chave é segredo)
  local f; f="$(wc_file "$1")"
  ( umask 077; printf '%s\n' "$2" > "$f.tmp" ) && mv -f "$f.tmp" "$f" && chmod 600 "$f" 2>/dev/null
}

# wc_newkey -> chave nova (prefixo mojwc_, como os mojb_/mojw_ dos outros tokens de máquina).
# Só [A-Za-z0-9] depois do prefixo: vai em query string, tem de sobreviver a copiar/colar.
wc_newkey(){
  local s; s="$(head -c 48 /dev/urandom 2>/dev/null | base64 | tr -dc 'A-Za-z0-9' | head -c 32)"
  [[ ${#s} -eq 32 ]] || s="$(date +%s%N)$RANDOM$RANDOM"
  printf 'mojwc_%s' "$s"
}

# wc_create <c> <view> <label> <by> -> ecoa a chave criada
wc_create(){
  local c="$1" view="$2" label="$3" by="$4" k j
  k="$(wc_newkey)"
  j="$(wc_get "$c")"
  j="$(jq -c --arg k "$k" --arg v "$view" --arg l "$label" --arg by "$by" --argjson t "$EPOCHSECONDS" \
        '.keys += [{id:($k[6:14]), key:$k, view:$v, label:$l, created_by:$by, created_at:$t,
                    revoked_at:0, fetches:0, last_at:0, last_ip:""}]' <<<"$j")" || return 1
  _wc_save "$c" "$j" || return 1
  printf '%s' "$k"
}

# wc_revoke <c> <id> -> 0 se revogou
wc_revoke(){
  local c="$1" id="$2" j n
  j="$(wc_get "$c")"
  n="$(jq -c --arg i "$id" --argjson t "$EPOCHSECONDS" \
        '(.keys[] | select(.id == $i and .revoked_at == 0) | .revoked_at) |= $t' <<<"$j")" || return 1
  [[ "$n" == "$j" ]] && return 1
  _wc_save "$c" "$n"
}

# wc_lookup <c> <chave> -> ecoa a VISÃO da chave válida (rc!=0 se não existe/revogada).
# Comparação em tempo ~constante contra TODAS as chaves (não sai no 1º acerto): o tempo de
# resposta não conta quantas chaves existem nem quantos caracteres bateram.
wc_lookup(){
  local c="$1" got="$2" line k v hit=""
  [[ "$got" == mojwc_* && ${#got} -le 64 ]] || return 1
  while IFS=$'\t' read -r k v; do
    [[ -n "$k" ]] || continue
    if _wc_eq "$k" "$got"; then hit="$v"; fi
  done < <(jq -r '.keys[] | select(.revoked_at == 0) | [.key, .view] | @tsv' <<<"$(wc_get "$c")" 2>/dev/null)
  [[ -n "$hit" ]] || return 1
  printf '%s' "$hit"
}

# comparação em tempo ~constante (cópia do _worker_token_eq — esta lib roda solta no
# webcast-gen/handler público, sem depender de lib/worker-auth.sh)
_wc_eq(){
  local a="$1" b="$2" i d=0 n=${#1}
  [[ ${#a} -eq ${#b} ]] || d=1
  (( ${#b} > n )) && n=${#b}
  for (( i=0; i<n; i++ )); do [[ "${a:i:1}" == "${b:i:1}" ]] || d=1; done
  return $d
}

# wc_touch <c> <chave> <ip> — contabiliza um acesso BEM-SUCEDIDO (flock; sem log infinito:
# o Animeitor bate de segundos em segundos, um arquivo de log cresceria sem fim).
wc_touch(){
  local c="$1" k="$2" ip="$3" f lock
  f="$(wc_file "$c")"; lock="$CONTESTSDIR/$c/var/.webcast.lock"
  mkdir -p "$CONTESTSDIR/$c/var" 2>/dev/null
  ( flock -w 5 9 || exit 0
    local j n
    j="$(wc_get "$c")"
    n="$(jq -c --arg k "$k" --arg ip "$ip" --argjson t "$EPOCHSECONDS" \
          '(.keys[] | select(.key == $k)) |= (.fetches += 1 | .last_at = $t | .last_ip = $ip)' <<<"$j")" \
      && _wc_save "$c" "$n"
  ) 9>"$lock" 2>/dev/null || true
}

# wc_deny_log <c> <chave-recebida> <ip> — tentativa RECUSADA (essa sim vira log: é o que
# interessa investigar). Guarda só o prefixo da chave — o resto seria segredo alheio no disco.
wc_deny_log(){
  local c="$1" k="$2" ip="$3" f="$CONTESTSDIR/$1/var/webcast-denied.log"
  mkdir -p "$CONTESTSDIR/$c/var" 2>/dev/null
  printf '%s\t%s\t%s\n' "$EPOCHSECONDS" "${k:0:14}" "${ip:-?}" >> "$f" 2>/dev/null || true
}
