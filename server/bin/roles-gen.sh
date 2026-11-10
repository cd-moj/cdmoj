#!/bin/bash
# roles-gen.sh — GERA web/shared/roles.js a partir do registro único server/etc/roles.tsv (09/11/2026).
#   bash server/bin/roles-gen.sh          → reescreve o arquivo
#   bash server/bin/roles-gen.sh --stdout → só imprime (o smoke-roles-registry.sh compara com o versionado)
# Mexeu no roles.tsv? Rode isto e versione os dois juntos.
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
source "$ROOT/server/api/v1/lib/roles.sh"
gen() {
  printf '%s\n' "// shared/roles.js — GERADO por server/bin/roles-gen.sh a partir de server/etc/roles.tsv. NÃO EDITE À MÃO."
  printf '%s\n' "// Os papéis do MOJ são o SUFIXO do login (fulano.staff). Login sem sufixo do registro = time."
  printf 'export const ROLES = %s;\n' "$(for s in "${ROLE_SUFFIXES[@]}"; do
      jq -cn --arg s "$s" --arg n "${ROLE_NAV[$s]}" --arg c "${ROLE_CLASS[$s]}" --arg e "${ROLE_SCOPED[$s]}" --arg p "${ROLE_CAN[$s]}" \
        '{suffix:$s, nav:$n, cls:$c, scoped:($e == "sim"), can:($p|split(" ")|map(select(length>0)))}'
    done | jq -cs .)"
  printf 'export const ROLE_RE = /%s/;\n' "${ROLE_RE//\//\\/}"
  printf '%s\n' "const BY = Object.fromEntries(ROLES.map((r) => [r.suffix, r]));"
  printf '%s\n' "// roleOf('x.staff') → 'staff'; time → ''"
  printf '%s\n' "export const roleOf = (login) => { const m = ROLE_RE.exec(String(login || '')); return m ? m[1] : ''; };"
  printf '%s\n' "export const isRoleAccount = (login) => ROLE_RE.test(String(login || ''));"
  printf '%s\n' "// 'org' | 'sala' | 'time'"
  printf '%s\n' "export const roleClass = (login) => { const r = BY[roleOf(login)]; return r ? r.cls : 'time'; };"
  printf '%s\n' "export const roleScoped = (login) => !!(BY[roleOf(login)] || {}).scoped;"
  printf '%s\n' "export const roleCan = (login, cap) => { const r = BY[roleOf(login)]; return !!r && (r.can.includes('*') || r.can.includes(cap)); };"
  printf '%s\n' "// sufixos com escopo (staff-filters.json): .staff .cstaff .foto …"
  printf '%s\n' "export const SCOPED_SUFFIXES = ROLES.filter((r) => r.scoped).map((r) => r.suffix);"
}
if [[ "${1:-}" == --stdout ]]; then gen; else gen > "$ROOT/web/shared/roles.js"; echo "web/shared/roles.js gerado"; fi
