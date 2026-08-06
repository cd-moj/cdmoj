# lib/invite-notify.sh — o mojinho avisa quem tem CONVITE DE TIME pendente.
#
# PORQUÊ: o convite era MUDO. `reg_team_invite` só põe o login em `teams[t].invited[]` e o
# convidado descobre se — e quando — abrir a página de inscrição. Quem não aceita NÃO entra como
# membro (`reg_kind_of` devolve `invited`, que não é inscrito), então convite esquecido = time
# incompleto e atraso no dia da prova.
#
# Três disparos, todos passando pelo mesmo cano:
#   1. CONVITE   — DM na hora em que o capitão convida (handlers/treino/contest-registration.sh)
#   2. LEMBRETE  — botão do painel Pessoas › Inscrições (handlers/contest/admin/registrations.sh)
#   3. ÚLTIMO AVISO — varredura automática (inv_sweep_all, chamada no poll do bot por /ops/alerts)
#
# A entrega é a fila de alertas que já existe: `alert_dm` (lib/alerts.sh) grava no outbox com o
# chat_id JÁ resolvido e `group:false` (mensagem de uma pessoa nunca vai ao grupo de admins).
#
# CONTABILIDADE em arquivo IRMÃO do roster — `contests/<c>/var/invites.json`:
#   { "version":1, "items": { "<team>|<login>": {at, by, dm, warn} } }
#   at   = quando o convite foi visto pela 1ª vez     · by   = capitão
#   dm   = último aviso de QUALQUER tipo (é o que dá o intervalo mínimo entre pings)
#   warn = o ÚLTIMO AVISO AUTOMÁTICO já disparado (é o que garante "uma vez por convite").
# São dois campos de propósito: se o lembrete manual do painel carimbasse `warn`, um clique do
# admin três dias antes CANCELARIA o aviso automático da véspera — justo o mais valioso.
# NÃO cabe no registrations.json: `reg_get` normaliza o roster para {version,teams,entries} e
# DESCARTA qualquer chave desconhecida — a contabilidade seria apagada no `reg_save` seguinte.
# `inv_reconcile` casa o arquivo com a realidade (poda convite que sumiu, adota convite que já
# existia com `at` = agora): auto-curável, sem migração.
#
# Escrita: o CALLER segura o flock do roster (reg_lock_file), como no resto da inscrição.
# Depende de lib/registration.sh (reg_get/reg_window/…), lib/telegram.sh e lib/alerts.sh.

: "${REG_REMIND_LEAD:=86400}"       # s antes do fechamento p/ o último aviso (24 h)
: "${REG_REMIND_MIN_GAP:=21600}"    # s mínimos entre o DM do convite e o último aviso (6 h)
: "${INVITE_SWEEP_THROTTLE:=300}"   # s entre varreduras (o poll do bot é o relógio)
: "${MOJ_PUBLIC_BASE:=https://moj.naquadah.com.br}"

inv_file(){ printf '%s/%s/var/invites.json' "$CONTESTSDIR" "$1"; }

# reg_remind_on <c> — 0 quando o aviso AUTOMÁTICO está ligado. Default LIGADO (contest com
# inscrição quer que o convite chegue); `REG_REMIND=n` no conf é o desligar, pelo painel.
reg_remind_on(){
  local v; v="$( ( REG_REMIND=""; source "$CONTESTSDIR/$1/conf" 2>/dev/null; printf '%s' "${REG_REMIND:-}" ) )"
  [[ "$v" == n ]] && return 1 || return 0
}

inv_get(){  # <c> -> contabilidade normalizada (sempre válida, mesmo sem arquivo)
  local f; f="$(inv_file "$1")"
  if [[ -s "$f" ]] && jq -e '.items' "$f" >/dev/null 2>&1; then
    jq -c '{version:(.version // 1),
            items:((.items // {}) | with_entries(.value |= {
                     at:(.at // 0), by:(.by // ""), dm:(.dm // 0), warn:(.warn // 0)}))}' "$f" 2>/dev/null \
      || printf '{"version":1,"items":{}}'
  else printf '{"version":1,"items":{}}'; fi
}

inv_save(){  # <c> <json>
  local f; f="$(inv_file "$1")"
  mkdir -p "$CONTESTSDIR/$1/var" 2>/dev/null
  printf '%s\n' "$2" > "$f.tmp" && mv -f "$f.tmp" "$f"
}

# inv_reconcile <c> [<at-dos-novos>] — casa o invites.json com os convites que existem AGORA.
# O `at` default é 0 = DESCONHECIDO: só quem SABE que o convite acabou de nascer (o handler do
# team-invite) passa o epoch. Adotar convite antigo com `at=agora` faria o painel mostrar "há 0
# min" p/ um convite de três dias — mentira pior que campo vazio.
# Os dois JSONs vão por --slurpfile (arquivo), NUNCA por --argjson: roster de contest grande passa
# de 128 KiB por argumento e o jq morreria com "Argument list too long" — mascarado pelo
# 2>/dev/null, viraria resultado vazio mudo.
inv_reconcile(){
  local c="$1" now="${2:-0}" rf jf out
  rf="$(mktemp)"; jf="$(mktemp)"
  reg_get "$c" > "$rf"; inv_get "$c" > "$jf"
  out="$(jq -cn --slurpfile r "$rf" --slurpfile i "$jf" --argjson now "$now" '
      [ (($r[0].teams // {}) | to_entries[]) | .key as $tm | (.value.captain // "") as $cap
        | (.value.invited // [])[] | {k:($tm + "|" + .), by:$cap} ] as $cur
      | ([$cur[].k]) as $ks
      | ($i[0] // {version:1, items:{}})
      | .items |= with_entries(select(.key as $k | ($ks | index($k)) != null))
      | reduce $cur[] as $e (.;
          if (.items | has($e.k)) then .
          else .items[$e.k] = {at:$now, by:$e.by, dm:0, warn:0} end)' 2>/dev/null)"
  rm -f "$rf" "$jf"
  [[ -n "$out" ]] || return 1
  inv_save "$c" "$out"
}

# inv_pending <c> -> TSV "<team>\t<login>\t<at>\t<dm>\t<warn>" de cada convite PENDENTE
inv_pending(){
  local c="$1" rf jf
  rf="$(mktemp)"; jf="$(mktemp)"
  reg_get "$c" > "$rf"; inv_get "$c" > "$jf"
  jq -rn --slurpfile r "$rf" --slurpfile i "$jf" '
      ($i[0].items // {}) as $m
      | (($r[0].teams // {}) | to_entries[]) | .key as $tm
      | (.value.invited // [])[] | . as $l
      | ($m[$tm + "|" + $l] // {}) as $e
      | [$tm, $l, ($e.at // 0), ($e.dm // 0), ($e.warn // 0)] | @tsv' 2>/dev/null
  rm -f "$rf" "$jf"
}

# inv_stamp <c> <team> <login> <invite|remind|lastcall> — carimba o aviso (cria a entrada se
# faltar). `dm` sempre; `warn` só no automático.
inv_stamp(){
  local c="$1" k="$2|$3" kind="$4" now="$EPOCHSECONDS" out
  out="$(inv_get "$c" | jq -c --arg k "$k" --argjson now "$now" \
        --argjson auto "$( [[ "$4" == lastcall ]] && echo true || echo false )" '
      .items[$k] = ((.items[$k] // {at:0, by:"", dm:0, warn:0})   # at=0: idade desconhecida
                    | .dm = $now
                    | (if $auto then .warn = $now else . end))')"
  [[ -n "$out" ]] && inv_save "$c" "$out"
}

# --- mensagem --------------------------------------------------------------
# O bot manda parse_mode:HTML ⇒ nome de time/contest PRECISA ser escapado: um time "A & B"
# derruba a mensagem inteira (400 do Telegram) e a DM some sem deixar rastro.
inv_html_escape(){ printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'; }

inv_link(){ printf '%s/contests/inscricao/?c=%s' "${MOJ_PUBLIC_BASE%/}" "$1"; }

# inv_lang <c> -> pt|en (LOCALE do contest; o resto do MOJ segue a mesma precedência)
inv_lang(){
  local v; v="$( ( LOCALE=""; source "$CONTESTSDIR/$1/conf" 2>/dev/null; printf '%s' "${LOCALE:-}" ) )"
  [[ "${v,,}" == en* ]] && printf 'en' || printf 'pt'
}
inv_contest_name(){
  local v; v="$( ( CONTEST_NAME=""; source "$CONTESTSDIR/$1/conf" 2>/dev/null; printf '%s' "${CONTEST_NAME:-}" ) )"
  printf '%s' "${v:-$1}"
}
_inv_when(){  # <epoch> <lang> -> data curta legível
  [[ "$1" =~ ^[0-9]+$ ]] && (( $1 > 0 )) || return 0
  if [[ "$2" == en ]]; then date -d "@$1" '+%b %d, %H:%M' 2>/dev/null
  else date -d "@$1" '+%d/%m às %H:%M' 2>/dev/null; fi
}
_inv_left(){  # <segundos> <lang> -> "~5 h" / "~40 min"
  local s="$1" h=$(( $1 / 3600 ))
  if (( h >= 1 )); then printf '~%s h' "$h"
  else printf '~%s min' "$(( s / 60 ))"; fi
}

_inv_msg_pt(){  # <kind> <time> <contest> <link> <quando> <faltam>
  local kind="$1" team="$2" nm="$3" link="$4" when="$5" left="$6" dl=""
  if [[ "$kind" != invite ]]; then
    printf '⏰ <b>%s</b> — as inscrições fecham %s%s e você ainda tem um <b>convite de time pendente</b> do <b>%s</b>.\n\nAceite ou recuse: %s\n\nQuem não aceita o convite não entra no time.' \
      "$nm" "${when:-em breve}" "${left:+ (faltam $left)}" "$team" "$link"
  else
    # ⚠ `${when:+$'\n\n'…}` NÃO funciona: bash não faz ANSI-C quoting dentro de ${…}
    [[ -n "$when" ]] && dl=$'\n\n'"⏳ As inscrições fecham $when."
    printf '🎫 O time <b>%s</b> convidou você para o <b>%s</b>.\n\nAceite ou recuse aqui: %s%s' \
      "$team" "$nm" "$link" "$dl"
  fi
}
_inv_msg_en(){
  local kind="$1" team="$2" nm="$3" link="$4" when="$5" left="$6" dl=""
  if [[ "$kind" != invite ]]; then
    printf '⏰ <b>%s</b> — registration closes %s%s and you still have a <b>pending team invite</b> from <b>%s</b>.\n\nAccept or decline: %s\n\nIf you do not accept, you will not be on the team.' \
      "$nm" "${when:-soon}" "${left:+ (in $left)}" "$team" "$link"
  else
    [[ -n "$when" ]] && dl=$'\n\n'"⏳ Registration closes $when."
    printf '🎫 <b>%s</b> invited you to their team in <b>%s</b>.\n\nAccept or decline here: %s%s' \
      "$team" "$nm" "$link" "$dl"
  fi
}

# inv_msg <c> <invite|remind|lastcall> <nome-do-time> <closes_at> -> texto HTML da DM
# (`remind` = o botão do painel; usa o mesmo texto do aviso automático)
#
# IDIOMA: contest em pt manda só português; contest com `LOCALE=en` manda **inglês E português**
# no mesmo texto. A DM não tem seletor de idioma como a web, e contest `en` é justamente o que
# mistura gente de fora com brasileiros (o esquenta da maratona é `LOCALE=en` e a maioria dos
# convidados é do Brasil): mandar só inglês deixaria a maioria sem entender.
inv_msg(){
  local c="$1" kind="$2" team="$3" cl="$4" lang nm link when whenen left leften now="$EPOCHSECONDS"
  lang="$(inv_lang "$c")"
  nm="$(inv_html_escape "$(inv_contest_name "$c")")"
  team="$(inv_html_escape "$team")"
  link="$(inv_link "$c")"
  [[ "$cl" =~ ^[0-9]+$ ]] || cl=0
  when="$(_inv_when "$cl" pt)"; whenen="$(_inv_when "$cl" en)"
  if (( cl > now )); then left="$(_inv_left $(( cl - now )) pt)"; leften="$(_inv_left $(( cl - now )) en)"
  else left=""; leften=""; fi
  if [[ "$lang" == en ]]; then
    printf '%s\n\n———\n\n%s' \
      "$(_inv_msg_en "$kind" "$team" "$nm" "$link" "$whenen" "$leften")" \
      "$(_inv_msg_pt "$kind" "$team" "$nm" "$link" "$when" "$left")"
  else
    _inv_msg_pt "$kind" "$team" "$nm" "$link" "$when" "$left"
  fi
}

# --- envio -----------------------------------------------------------------
# inv_chat_of <c> <login> -> chat_id do Telegram (vazio = não vinculado). O vínculo é do overlay
# do TREINO — quem se inscreve é a conta da FONTE (USERS_FROM), então é lá que se procura.
inv_chat_of(){ tg_id_of_login "$(reg_source_of "$1")" "$2" 2>/dev/null; }

# inv_notify <c> <team> <login> <invite|remind|lastcall> -> ecoa sent | no_telegram | enqueue_failed
# BEST-EFFORT: quem chama nunca deve desfazer o convite porque a DM não saiu.
inv_notify(){
  local c="$1" tm="$2" who="$3" kind="$4" chat name cl txt st op lt anc rnd
  chat="$(inv_chat_of "$c" "$who")"
  [[ -n "$chat" ]] || { printf 'no_telegram'; return 1; }
  name="$(reg_get "$c" | jq -r --arg t "$tm" '.teams[$t].name // ""')"
  IFS=$'\t' read -r st op cl lt anc rnd < <(reg_window "$c")
  txt="$(inv_msg "$c" "$kind" "$name" "${cl:-0}")"
  alert_dm "$txt" "$chat" loud >/dev/null || { printf 'enqueue_failed'; return 1; }
  inv_stamp "$c" "$tm" "$who" "$kind"
  printf 'sent'
}

# --- varredura: o ÚLTIMO AVISO --------------------------------------------
# inv_sweep_contest <c> -> ecoa quantas DMs enfileirou.
# Só quando: inscrição ligada, REG_REMIND != n, janela open|late, prazo conhecido e faltando no
# máximo REG_REMIND_LEAD. UMA vez por convite (`warn`), e nunca a menos de REG_REMIND_MIN_GAP do
# DM do convite — convite feito na véspera não leva dois pings seguidos.
inv_sweep_contest(){
  local c="$1" now="$EPOCHSECONDS" n=0 st op cl lt anc rnd tm who at dm warn
  reg_enabled "$c" || { printf '0'; return 0; }
  reg_remind_on "$c" || { printf '0'; return 0; }
  IFS=$'\t' read -r st op cl lt anc rnd < <(reg_window "$c")
  case "$st" in open|late) ;; *) printf '0'; return 0 ;; esac
  [[ "$cl" =~ ^[0-9]+$ ]] || { printf '0'; return 0; }
  # cl == 0 = janela SEM prazo (aquecimento sem prova planejada): não há "último aviso"
  (( cl > 0 && cl > now && cl - now <= REG_REMIND_LEAD )) || { printf '0'; return 0; }

  mkdir -p "$CONTESTSDIR/$c/var" 2>/dev/null
  exec 8>"$(reg_lock_file "$c")" || { printf '0'; return 0; }
  flock 8
  inv_reconcile "$c"
  while IFS=$'\t' read -r tm who at dm warn; do
    [[ -n "$tm" && -n "$who" ]] || continue
    [[ "$warn" =~ ^[0-9]+$ ]] || warn=0; [[ "$dm" =~ ^[0-9]+$ ]] || dm=0
    (( warn > 0 )) && continue                              # já avisado
    (( dm > 0 && now - dm < REG_REMIND_MIN_GAP )) && continue
    [[ "$(inv_notify "$c" "$tm" "$who" lastcall)" == sent ]] && n=$(( n + 1 ))
  done < <(inv_pending "$c")
  flock -u 8; exec 8>&-
  # (a lib também roda fora da API — no smoke — onde audit_log_to não existe)
  (( n > 0 )) && declare -F audit_log_to >/dev/null 2>&1 && audit_log_to "$c" reg-invite-lastcall "n=$n"
  printf '%s' "$n"
}

# inv_sweep_all — varre os contests COM roster. O glob corta os ~1500 contests para os poucos
# com inscrição ligada antes de carregar lib pesada (padrão do preflight): esta função roda a
# cada poll do bot e não pode custar caro.
inv_sweep_all(){
  local rosters=() f c n total=0
  mapfile -t rosters < <( set +o noglob; shopt -s nullglob
                          for f in "$CONTESTSDIR"/*/registrations.json; do printf '%s\n' "$f"; done )
  (( ${#rosters[@]} )) || return 0
  declare -F reg_get >/dev/null 2>&1 || source "$_DIR/lib/registration.sh"
  for f in "${rosters[@]}"; do
    c="${f%/registrations.json}"; c="${c##*/}"
    [[ -n "$c" ]] || continue
    n="$(inv_sweep_contest "$c" 2>/dev/null)"
    [[ "$n" =~ ^[0-9]+$ ]] && total=$(( total + n ))
  done
  printf '%s' "$total"
}
