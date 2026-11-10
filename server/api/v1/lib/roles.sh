# lib/roles.sh — os PAPÉIS a partir do registro único (server/etc/roles.tsv; ver o cabeçalho dele). Sourceada no
# prelúdio (lib/sources.sh) ANTES do auth.sh, e sozinha pelos geradores de placar/relatório (server/score/*).
# ZERO fork: o TSV é lido uma vez com `read` (11 linhas) e vira os mapas abaixo.
#
#   ROLE_SUFFIXES        — os sufixos, na ordem do registro
#   ROLE_RE              — '[.](admin|judge|…)$' : a regra "é conta de papel?" p/ grep -E, awk, gawk e o test() do jq.
#                          NUNCA escreva a lista à mão: passe "$ROLE_RE" (awk -v re=…, jq --arg re …).
#   ROLE_JQ / ROLE_JQ_ORG / ROLE_JQ_SALA — `(endswith(".admin") or …)` p/ jq sem regex (caminho quente)
#   ROLE_NAV[suf] ROLE_CLASS[suf] ROLE_SCOPED[suf] ROLE_CAN[suf]
#   role_of <login>          → ecoa o sufixo de papel ("" = time)
#   role_suffix_to <var> <login> → o mesmo, sem subshell (nameref)
#   is_reserved_role_login <login> → rc 0 se é conta de papel
#   role_class <login>       → org | sala | time
#   role_scoped <login>      → rc 0 se o papel do login tem escopo (chave válida do staff-filters.json)
#   role_can <cap> [login]   → rc 0 se o papel (do login; padrão: a sessão) tem a capacidade (admin = tudo)
#   role_is <login> <suf…>   → rc 0 se o login tem um desses sufixos
#   role_glob_scoped         → globs "*.<suf>" dos papéis com escopo (p/ find -name)
ROLES_TSV="${ROLES_TSV:-${BASH_SOURCE[0]%/*}/../../../etc/roles.tsv}"
declare -gA ROLE_NAV=() ROLE_CLASS=() ROLE_SCOPED=() ROLE_CAN=()
declare -ga ROLE_SUFFIXES=()
_roles_load() {
  local suf nav cls esc pode
  [[ -r "$ROLES_TSV" ]] || { printf 'roles.sh: registro ausente: %s\n' "$ROLES_TSV" >&2; return 1; }
  while IFS=$'\t' read -r suf nav cls esc pode || [[ -n "$suf" ]]; do
    [[ -z "$suf" || "$suf" == \#* ]] && continue
    [[ "$suf" =~ ^[a-z]+$ ]] || continue
    ROLE_SUFFIXES+=("$suf"); ROLE_NAV[$suf]="$nav"; ROLE_CLASS[$suf]="$cls"
    ROLE_SCOPED[$suf]="$esc"; ROLE_CAN[$suf]=" $pode "
  done < "$ROLES_TSV"
  # `[.]` e não `\.`: o `awk -v re=…` interpreta escape e transformaria `\.` em "qualquer caractere"; `[.]` vale igual
  # em grep -E, awk, gawk, o test() do jq (Oniguruma), Python e JS
  local IFS='|'; ROLE_RE="[.](${ROLE_SUFFIXES[*]})\$"
  # o mesmo SEM regex, p/ jq em caminho quente (o jq recompila regex a cada test(): ver lib/anomalies.sh). Uma expressão
  # booleana sobre a STRING de entrada: `.login | '"$ROLE_JQ"'`. Por classe: ROLE_JQ_ORG / ROLE_JQ_SALA.
  local s a="" o="" l=""
  for s in "${ROLE_SUFFIXES[@]}"; do
    a+="${a:+ or }endswith(\".$s\")"
    [[ "${ROLE_CLASS[$s]}" == org ]] && o+="${o:+ or }endswith(\".$s\")"
    [[ "${ROLE_CLASS[$s]}" == sala ]] && l+="${l:+ or }endswith(\".$s\")"
  done
  ROLE_JQ="($a)"; ROLE_JQ_ORG="(${o:-false})"; ROLE_JQ_SALA="(${l:-false})"
}
_roles_load
role_suffix_to() { local -n __rs_ref="$1"; local __rs_s="${2##*.}"; __rs_ref=""
  [[ "$2" == *.* && -n "${ROLE_CLASS[$__rs_s]+x}" ]] && __rs_ref="$__rs_s"; return 0; }
role_of() { local s; role_suffix_to s "$1"; printf '%s' "$s"; }
is_reserved_role_login() { local s; role_suffix_to s "$1"; [[ -n "$s" ]]; }
role_class() { local s; role_suffix_to s "$1"; printf '%s' "${s:+${ROLE_CLASS[$s]}}"; [[ -n "$s" ]] || printf 'time'; }
role_scoped() { local s; role_suffix_to s "$1"; [[ -n "$s" && "${ROLE_SCOPED[$s]}" == sim ]]; }
role_can() { local s; role_suffix_to s "${2:-${SESSION_LOGIN:-}}"; [[ -n "$s" ]] || return 1
  [[ "${ROLE_CAN[$s]}" == *" * "* || "${ROLE_CAN[$s]}" == *" $1 "* ]]; }
role_is() { local s x; role_suffix_to s "$1"; shift; [[ -n "$s" ]] || return 1
  for x in "$@"; do [[ "$s" == "$x" ]] && return 0; done; return 1; }
role_glob_scoped() { local s; for s in "${ROLE_SUFFIXES[@]}"; do [[ "${ROLE_SCOPED[$s]}" == sim ]] && printf '*.%s\n' "$s"; done; }
