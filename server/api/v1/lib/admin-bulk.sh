# lib/admin-bulk.sh — AÇÃO DE VÁRIOS ALVOS no painel do treino (/treino/admin/logout-user, lock-user, logout-ip).
# Sourced sob demanda pelos três handlers (não é do prelúdio).
#
# POR QUE EXISTE (16/10/2026): um `.admin` comum deslogou 1.310 logins de uma vez — ele mesmo, o super-admin e os
# outros `.admin` no meio — com a busca vazia, o "todos" e um clique. Nenhuma das rotas tinha teto, prévia,
# confirmação nem protegia conta de papel, e o audit gravava a lista PEDIDA numa linha de dezenas de KB. As regras:
#   · NUNCA entram: a conta de quem chama (`self`), super-admin (`superadmin`) e conta de papel (`role`,
#     is_reserved_role_login) — saem em `skipped` com o motivo;
#   · deslogar 1 alvo: executa direto (a tela confirma); 2..ADMIN_BULK_SMALL (20): `.admin` comum ou super, com
#     PRÉVIA + plan_id + o número digitado; acima: só o super (403 bulk_superadmin_only); teto ADMIN_BULK_MAX (5000)
#     por chamada. Travar e deslogar por IP são só do super e SEMPRE pedem a prévia (os handlers decidem isso);
#   · a PRÉVIA é a resposta 200 sem plan_id (ou com dry_run:true): quantas contas, quantas sessões, amostra, pulados;
#   · plan_id = sha1(ação | quem chama | ENTRADA depois das exclusões) — NUNCA o estado vivo das sessões: com aula
#     rolando, aluno entra e sai entre a prévia e o executar, e um hash disso daria plan_changed p/ sempre;
#   · confirm = o número de contas da prévia, comparado com a contagem NA HORA de executar: exato até 20 contas,
#     ±5 % (mín. 5) acima — é o que pega o "achei que eram 3, eram 1.310";
#   · executou: o DETALHE (afetados + pulados) vai p/ contests/treino/var/admin-actions/, o audit leva uma linha
#     curta, e ação de mais de 1 alvo, travar e IP AVISAM os super-admins (DM do mojinho; sem Telegram vinculado,
#     o grupo).
# A varredura de sessões é UMA passada, com os padrões por ARQUIVO (grep -f): o diretório de sessões passa de 20 mil
# arquivos (o "nova senha" de 38 s de 19/09/2026) e 5000 logins em argv estourariam o xargs.
: "${ADMIN_BULK_SMALL:=20}"
: "${ADMIN_BULK_MAX:=5000}"

# ab_input_logins <body-json> <out> — os logins pedidos ({login} | {logins:[…]}), únicos, um por linha.
ab_input_logins(){
  local body="$1" out="$2" l
  jq -r 'if (.logins|type) == "array" then .logins[] elif .login then .login else empty end | tostring' \
    <<<"$body" 2>/dev/null | awk 'NF && !s[$0]++' > "$out"
  [[ -s "$out" ]] || fail 400 "Informe login ou logins" "missing"
  while IFS= read -r l; do valid_id "$l" || fail 400 "Login inválido" "login_invalid"; done < "$out"
}

# ab_exclude <in> <keep> <skipped> — quem NUNCA entra vai p/ <skipped> (TSV login\tmotivo); o resto p/ <keep>.
# Super-admin antes de papel: ele também é `.admin`, e o motivo mais específico ajuda quem lê a prévia.
ab_exclude(){
  local in="$1" keep="$2" sk="$3" l list
  list="$(conf_value treino SUPERADMINS)"; list="${list//\\/}"; list=" ${list//,/ } "
  : > "$keep"; : > "$sk"
  while IFS= read -r l; do
    [[ -n "$l" ]] || continue
    if [[ "$l" == "$SESSION_LOGIN" ]]; then printf '%s\tself\n' "$l" >> "$sk"
    elif [[ "$l" == *.admin && "$list" == *" $l "* ]]; then printf '%s\tsuperadmin\n' "$l" >> "$sk"
    elif is_reserved_role_login "$l"; then printf '%s\trole\n' "$l" >> "$sk"
    else printf '%s\n' "$l" >> "$keep"; fi
  done < "$in"
}

# ab_scan <contest> logins <arquivo-de-logins> <out> | ab_scan <contest> ip <ip> <out> — UMA passada, só leitura.
# <out> = TSV  arquivo-da-sessão \t login \t ip  (uma linha por SESSÃO do <contest>). Pré-filtro por texto (a linha
# `LOGIN=` nas duas grafias que o create_session usa, ou `IP=`) e confirmação por `source` no MESMO processo, com
# as variáveis da sessão LOCAIS — o molde do remove_contest_sessions_v (lib/auth.sh).
ab_scan(){
  local c="$1" mode="$2" arg="$3" out="$4" pf w q f CONTEST LOGIN IP MKEY USERFULLNAME LOGINAT UA_B64 ACTOR
  pf="$(mktemp)" || return 1
  if [[ "$mode" == ip ]]; then printf 'IP=%s\n' "$arg" > "$pf"
  else
    while IFS= read -r w; do
      [[ -n "$w" ]] || continue; printf -v q '%q' "$w"; printf 'LOGIN=%s\nLOGIN=%s\n' "$q" "$w"
    done < "$arg" > "$pf"
  fi
  : > "$out"
  if [[ -s "$pf" ]]; then
    while IFS= read -r -d '' f; do
      [[ -f "$f" ]] || continue
      CONTEST=""; LOGIN=""; IP=""; source "$f" 2>/dev/null
      [[ "$CONTEST" == "$c" && -n "$LOGIN" ]] || continue
      [[ "$mode" == ip && "$IP" != "$arg" ]] && continue
      printf '%s\t%s\t%s\n' "${f##*/}" "$LOGIN" "$IP" >> "$out"
    done < <(find "$SESSIONDIR" -maxdepth 1 -type f -print0 2>/dev/null | xargs -0 -r grep -lxZF -f "$pf" 2>/dev/null)
  fi
  rm -f "$pf"
}

# ab_plan_id <ação> <arquivo|texto> — a assinatura da ENTRADA (lista de logins depois das exclusões, ou o IP).
ab_plan_id(){
  { printf '%s|%s|' "$1" "$SESSION_LOGIN"
    if [[ -f "$2" ]]; then LC_ALL=C sort -u "$2"; else printf '%s' "$2"; fi; } | sha1sum | cut -c1-16
}

# ab_limits <n> — o teto e a escada: acima do teto ninguém; acima de ADMIN_BULK_SMALL só o super.
ab_limits(){
  local n="$1"
  (( n <= ADMIN_BULK_MAX )) || fail 422 "No máximo $ADMIN_BULK_MAX contas por vez" "bulk_too_big"
  if (( n > ADMIN_BULK_SMALL )) && ! is_superadmin; then
    fail 403 "Mais de $ADMIN_BULK_SMALL contas de uma vez é só com o super-admin da plataforma" "bulk_superadmin_only"
  fi
}

# ab_skipped_json <skipped> — {skipped:[{login,reason}] (até 50), skipped_count, skipped_by_reason:{…}}
ab_skipped_json(){
  jq -Rn '[inputs | split("\t") | select(length >= 2) | {login: .[0], reason: .[1]}] as $s
    | {skipped: $s[:50], skipped_count: ($s | length),
       skipped_by_reason: (reduce $s[] as $x ({}; .[$x.reason] += 1))}' < "$1"
}

# ab_preview_json <ação> <plan_id> <afetados> <n_sessões> <skipped> — o corpo da prévia (sem o envelope).
ab_preview_json(){
  local a="$1" pid="$2" af="$3" ns="$4" sk="$5" skj
  skj="$(ab_skipped_json "$sk")"
  jq -Rn --arg a "$a" --arg p "$pid" --argjson ns "$ns" --argjson skj "$skj" \
    '[inputs | select(length > 0)] as $u
     | {preview: true, action: $a, plan_id: $p, need: ($u | length), affected_count: ($u | length),
        sessions_count: $ns, sample: $u[:50]} + $skj' < "$af"
}

# ab_tol <n> — a folga do número digitado: nenhuma até ADMIN_BULK_SMALL; acima, ±5 % (mín. 5).
ab_tol(){ local n="$1"; if (( n <= ADMIN_BULK_SMALL )); then echo 0; else local t=$(( (n + 19) / 20 )); echo $(( t < 5 ? 5 : t )); fi; }

# ab_confirm <ação> <plan_id> <body-json> <afetados> <n_sessões> <skipped> — o portão da execução.
#   sem plan_id ou com dry_run:true → responde a PRÉVIA (200) e SAI;
#   plan_id de outra entrada → 409 plan_changed (com a prévia nova);
#   confirm fora da folga → 409 confirm_required ({need}, e a prévia nova).
# Volta 0 quando pode executar.
ab_confirm(){
  local a="$1" pid="$2" body="$3" af="$4" ns="$5" sk="$6" got conf dry need tol pv
  dry="$(jq -r '.dry_run == true' <<<"$body" 2>/dev/null)"
  got="$(jq -r '.plan_id // "" | tostring' <<<"$body" 2>/dev/null)"
  pv="$(ab_preview_json "$a" "$pid" "$af" "$ns" "$sk")"
  if [[ "$dry" == true || -z "$got" ]]; then ok_json '$p' --argjson p "$pv"; exit 0; fi
  [[ "$got" == "$pid" ]] || FAIL_EXTRA="{\"preview\":$pv}" fail 409 "A lista mudou desde a prévia — confira a nova prévia" "plan_changed"
  conf="$(jq -r '.confirm // "" | tostring' <<<"$body" 2>/dev/null)"; conf="${conf//[^0-9]/}"
  need="$(grep -c . "$af" 2>/dev/null)"; need="${need//[^0-9]/}"; need="${need:-0}"
  tol="$(ab_tol "$need")"
  if [[ -z "$conf" ]] || (( conf - need > tol || need - conf > tol )); then
    FAIL_EXTRA="{\"need\":$need,\"preview\":$pv}" fail 409 "Digite o número de contas ($need) para confirmar" "confirm_required"
  fi
  return 0
}

# ab_detail <ação> <afetados> <skipped> <n_sessões> [extra-json] — grava o DETALHE da execução e ecoa o caminho
# relativo a contests/treino/var/ (é o que o audit e o aviso citam). O tmp é resolvido em variável ANTES do jq
# (`${BASHPID}` no alvo de redirect de comando externo expande no filho — CLAUDE.md).
ab_detail(){
  local a="$1" af="$2" sk="$3" ns="$4" ex="${5:-}" d name tmp
  [[ -n "$ex" ]] || ex='{}'
  d="$CONTESTSDIR/treino/var/admin-actions"; mkdir -p "$d" 2>/dev/null || return 0
  name="$EPOCHSECONDS-$a-${BASHPID}.json"; tmp="$d/.$name.tmp"
  { jq -Rn '[inputs | select(length > 0)]' < "$af"
    jq -Rn '[inputs | split("\t") | select(length >= 2) | {login: .[0], reason: .[1]}]' < "$sk"; } \
    | jq -cs --arg a "$a" --arg by "$SESSION_LOGIN" --arg ip "$(client_ip)" --argjson at "$EPOCHSECONDS" \
        --argjson ns "$ns" --argjson ex "$ex" \
        '{at: $at, by: $by, ip: $ip, action: $a, affected: .[0], skipped: .[1], sessions_removed: $ns} + $ex' \
        > "$tmp" 2>/dev/null && mv -f "$tmp" "$d/$name" || { rm -f "$tmp"; return 0; }
  printf 'admin-actions/%s' "$name"
}

# ab_notify <texto-html> — avisa os super-admins: DM do mojinho a cada um com Telegram vinculado; sem nenhum
# vinculado, o grupo dos admins. Nunca falha a ação (o aviso é rede de segurança, não condição).
ab_notify(){
  local text="$1" list l id chats=""
  list="$(conf_value treino SUPERADMINS)"; list="${list//\\/}"; list="${list//,/ }"
  for l in $list; do
    id="$(tg_id_of_login treino "$l" 2>/dev/null)"; [[ -n "$id" ]] && chats+="$id"$'\n'
  done
  if [[ -n "$chats" ]]; then alert_dm "$text" "$chats" loud >/dev/null 2>&1 || true
  else alert_group "$text" loud >/dev/null 2>&1 || true; fi
  return 0
}

# ab_html <texto> — escapa &<> p/ o HTML do Telegram.
ab_html(){ local s="$1"; s="${s//&/&amp;}"; s="${s//</&lt;}"; s="${s//>/&gt;}"; printf '%s' "$s"; }
