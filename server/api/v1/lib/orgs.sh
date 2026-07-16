# lib/orgs.sh — ORGS MOJ-nativas: dono do ACESSO e da trava de "público" dos problemas.
# Uma org agrupa problemas (o <org> do id <org>#<prob>). MEMBROS escrevem em QUALQUER problema dela;
# ADMINS gerem membros/admins e a trava public_allowed (privada por PADRÃO -> os problemas nunca
# ficam públicos: camada anti-vazamento de prova). Cada usuário tem uma org IMPLÍCITA <login>
# (sempre privada). É o motor de permissão de acesso a problema + as coleções-curso.
# Registro atômico (temp+mv, umask 077), espelhando o padrão de collection_* em lib/problems.sh.
: "${CONTESTSDIR:=/home/ribas/moj/contests}"
ORGS_REGISTRY="$CONTESTSDIR/treino/var/orgs.json"

_orgs_read(){ local c; c="$(cat "$ORGS_REGISTRY" 2>/dev/null)"; [[ -n "$c" ]] || c='{}'; printf '%s' "$c"; }
org_exists(){ [[ -f "$ORGS_REGISTRY" ]] && jq -e --arg n "$1" 'has($n)' >/dev/null 2>&1 < "$ORGS_REGISTRY"; }
org_title(){ local t; [[ -f "$ORGS_REGISTRY" ]] && t="$(jq -r --arg n "$1" '.[$n].title // $n' "$ORGS_REGISTRY" 2>/dev/null)"; printf '%s' "${t:-$1}"; }
org_members(){ local m; m="$(jq -c --arg n "$1" '.[$n].members // []' "$ORGS_REGISTRY" 2>/dev/null)"; printf '%s' "${m:-[]}"; }
org_admins(){  local a; a="$(jq -c --arg n "$1" '.[$n].admins  // []' "$ORGS_REGISTRY" 2>/dev/null)"; printf '%s' "${a:-[]}"; }
# acesso de ESCRITA a um problema da org = membros ∪ admins (co-organizadores também editam)
org_access(){ jq -cn --argjson m "$(org_members "$1")" --argjson a "$(org_admins "$1")" '($m+$a)|unique'; }
# org_is_member <org> <login> -> 0 se login pode ESCREVER (membro ou admin da org). SEM atalho de .admin.
org_is_member(){ jq -e --arg u "$2" 'index($u)' >/dev/null 2>&1 <<<"$(org_access "$1")"; }
# org_is_admin <org> <login> -> 0 se login é admin da org (gere membros/trava). SEM atalho de .admin.
org_is_admin(){ jq -e --arg u "$2" 'index($u)' >/dev/null 2>&1 <<<"$(org_admins "$1")"; }
# org_public_allowed <org> -> 0 se a org PERMITE que seus problemas fiquem públicos.
org_public_allowed(){ [[ -f "$ORGS_REGISTRY" ]] && jq -e --arg n "$1" '.[$n].public_allowed==true' >/dev/null 2>&1 < "$ORGS_REGISTRY"; }
org_is_implicit(){ [[ -f "$ORGS_REGISTRY" ]] && jq -e --arg n "$1" '.[$n].implicit==true' >/dev/null 2>&1 < "$ORGS_REGISTRY"; }
# org_can_manage <org> <login> — admin da org OU admin global do treino (.admin). Gestão de membros/trava.
org_can_manage(){
  { declare -F is_admin >/dev/null && is_admin; } && return 0
  org_is_admin "$1" "$2"
}
# org_list_for <login> -> JSON array de nomes de org de que o login é membro/admin (inclui a implícita).
org_list_for(){ _orgs_read | jq -c --arg u "$1" '[to_entries[]|select(((.value.members//[])+(.value.admins//[]))|index($u))|.key]|sort'; }

# ---- escrita do registro (atômica) --------------------------------------------------------
# org_register <org> <creator> [members-csv] [admins-csv] [title] [public_allowed:true|false]
# O criador entra como membro E admin. public_allowed só LIGA (nunca desliga aqui). Idempotente.
org_register(){
  local n="$1" cr="$2" m="${3:-}" a="${4:-}" t="${5:-}" pa="${6:-false}" cur tmp
  cur="$(_orgs_read)"; mkdir -p "$(dirname "$ORGS_REGISTRY")" 2>/dev/null; tmp="$ORGS_REGISTRY.tmp.$$"
  # registro por STDIN, não --argjson (128 KiB/argumento): orgs.json cresce com os usuários
  # (toda conta ganha org implícita) — mesmo no-op silencioso do overlay authored (2026-07-16)
  ( umask 077; printf '%s' "$cur" | jq --arg n "$n" --arg cr "$cr" --arg m "$m" --arg a "$a" \
      --arg t "$t" --arg pa "$pa" --argjson now "$EPOCHSECONDS" '
      . as $cur
      | ($cur[$n] // {}) as $old
      | $cur + { ($n): ($old + {
          created_by:($old.created_by // $cr),
          title:(if $t=="" then ($old.title // $n) else $t end),
          members:((($old.members // []) + [$cr] + ($m|split(",")|map(select(length>0)))) | unique),
          admins: ((($old.admins  // []) + [$cr] + ($a|split(",")|map(select(length>0)))) | unique),
          public_allowed:(if $pa=="true" then true else ($old.public_allowed // false) end),
          at:$now }) }' ) > "$tmp" 2>/dev/null && [[ -s "$tmp" ]] && mv -f "$tmp" "$ORGS_REGISTRY" || rm -f "$tmp"
}
# ensure_implicit_org <login> — org privada do usuário (só ele; nunca libera público). Idempotente.
ensure_implicit_org(){
  local u="$1"; [[ "$u" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || return 1
  org_exists "$u" && return 0
  local cur tmp; cur="$(_orgs_read)"; mkdir -p "$(dirname "$ORGS_REGISTRY")" 2>/dev/null; tmp="$ORGS_REGISTRY.tmp.$$"
  ( umask 077; printf '%s' "$cur" | jq --arg u "$u" --argjson now "$EPOCHSECONDS" '
      . + { ($u): { created_by:$u, title:$u, members:[$u], admins:[$u],
                    public_allowed:false, implicit:true, at:$now } }' ) \
    > "$tmp" 2>/dev/null && [[ -s "$tmp" ]] && mv -f "$tmp" "$ORGS_REGISTRY"
}
_org_set_field(){  # <org> <field> <json>  (members|admins)
  local n="$1" k="$2" v="$3" cur tmp; cur="$(_orgs_read)"
  jq -e --arg n "$n" 'has($n)' >/dev/null 2>&1 <<<"$cur" || return 1
  tmp="$ORGS_REGISTRY.tmp.$$"
  ( umask 077; jq --arg n "$n" --arg k "$k" --argjson v "$v" '.[$n][$k]=$v' <<<"$cur" ) \
    > "$tmp" 2>/dev/null && mv -f "$tmp" "$ORGS_REGISTRY"
}
org_set_members(){ _org_set_field "$1" members "$2"; }
org_set_admins(){  _org_set_field "$1" admins  "$2"; }
# org_set_public_allowed <org> <true|false> — trava de público. A org IMPLÍCITA nunca libera.
# rc: 0 ok · 1 org inexistente · 2 valor inválido · 3 tentou liberar a implícita.
org_set_public_allowed(){
  local n="$1" v="$2" cur tmp
  [[ "$v" == true || "$v" == false ]] || return 2
  cur="$(_orgs_read)"; jq -e --arg n "$n" 'has($n)' >/dev/null 2>&1 <<<"$cur" || return 1
  if [[ "$v" == true ]] && jq -e --arg n "$n" '.[$n].implicit==true' >/dev/null 2>&1 <<<"$cur"; then return 3; fi
  tmp="$ORGS_REGISTRY.tmp.$$"
  ( umask 077; jq --arg n "$n" --argjson v "$v" '.[$n].public_allowed=$v' <<<"$cur" ) \
    > "$tmp" 2>/dev/null && mv -f "$tmp" "$ORGS_REGISTRY"
}
# org_delete <org> — remove a org do registro (espelha coll_delete). O HANDLER garante que está
# VAZIA e que não é a implícita; aqui é só o del atômico.
org_delete(){ local n="$1" cur tmp; cur="$(_orgs_read)"; tmp="$ORGS_REGISTRY.tmp.$$"
  ( umask 077; jq --arg n "$n" 'del(.[$n])' <<<"$cur" ) > "$tmp" 2>/dev/null && mv -f "$tmp" "$ORGS_REGISTRY"; }
