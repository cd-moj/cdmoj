#!/bin/bash
# smoke-score-flag-title.gjs.sh — no placar, a bandeira do PRÓPRIO time vence a regra por regex do
# teams-meta (issue #21, LATAM 2026: a regra da sede "CA" = Central America no nome da sede, Canadá
# na ISO, punha "Canada" no tooltip de times com bandeira CR/GT/SV/NI). A regra segue valendo p/
# quem NÃO tem bandeira. Extrai applyTeamsDir/applyTeamsMeta do score-filters.js real e roda no gjs.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
W="$ROOT/web"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
command -v gjs >/dev/null 2>&1 || { echo "score-flag-title: gjs ausente — pulando"; exit 0; }
PASS=0; FAIL=0
check(){ if [[ "$1" == "$2" ]]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FALHOU: $3 (got '$1', want '$2')" >&2; fi; }
{ cat <<'JS'
const NAMES = { ca: 'Canada', cr: 'Costa Rica', mx: 'Mexico', 'br-pr': 'Paraná' };
function flagName(c) { c = String(c || '').toLowerCase(); return NAMES[c] || c.toUpperCase(); }
function safeRe(r) { try { return new RegExp(r); } catch (e) { return null; } }
const CONTEST = 'latam';
const teamsDir = { cclcaadsi001: { flag: 'CR', univ_short: 'TEC', region: 'CCL - Central America' }, cclmxmast001: {} };
const teamsMeta = [{ regex: '^cclcaadsi[0-9]', country: 'CA' }, { regex: '^cclmxmast[0-9]', country: 'MX' }];
JS
  # a lógica mora em score-filters.js (fonte única com a Participação Virtual); o estado entra por parâmetro
  sed -n '/^export function applyTeamsDir(/,/^}/p; /^export function applyTeamsMeta(/,/^}/p' "$W/contest/score/score-filters.js" | sed 's/^export //'
  cat <<'JS'
const p = { mode: 'icpc', teams: [
  { username: 'cclcaadsi001', flag: 'CR' },          // tem bandeira própria (TXT + diretório)
  { username: 'cclcaadsi002', flag: '' },            // sem bandeira: a regra da sede vale
  { username: 'cclmxmast001', flag: '' },
] };
applyTeamsDir(p, teamsDir, CONTEST); applyTeamsMeta(p, teamsMeta);
const t = (u) => p.teams.find(x => x.username === u);
print('cr_flag=' + t('cclcaadsi001').flag + ' cr_title=' + t('cclcaadsi001').flagTitle + ' cr_country=' + t('cclcaadsi001')._country);
print('noflag_flag=' + t('cclcaadsi002').flag + ' noflag_title=' + t('cclcaadsi002').flagTitle);
print('mx_flag=' + t('cclmxmast001').flag + ' mx_title=' + t('cclmxmast001').flagTitle);
JS
} > "$T/ft.js"
out="$(gjs "$T/ft.js" 2>&1)" || { echo "$out" >&2; echo "score-flag-title: gjs falhou"; exit 1; }
kv(){ sed -n "s/^.*\b$1=\([^ ]*\).*$/\1/p" <<<"$out" | head -1; }
check "$(kv cr_flag)" CR "time com bandeira: mantém CR"
check "$(sed -n 's/^.*cr_title=\(.*\) cr_country.*$/\1/p' <<<"$out")" "Costa Rica" "tooltip é o país da bandeira, não o da regra"
check "$(kv cr_country)" CR "filtro por país usa a bandeira do time"
check "$(kv noflag_flag)" CA "sem bandeira: a regra da sede dá a bandeira"
check "$(kv noflag_title)" Canada "…e o tooltip dela"
check "$(kv mx_flag)" MX "regra MX vale p/ quem não tem bandeira"
echo "score-flag-title: $PASS ok, $FAIL falhas"; [[ $FAIL -eq 0 ]]
