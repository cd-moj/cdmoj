# GET/POST /contest/admin/finish?contest=<id>   (admin DO contest)
#
# ENCERRAR O EVENTO — o espelho pós-prova do preflight. O painel é todo PRÉ-prova; depois do
# fim o organizador tinha de caçar chave por chave em 4 telas (e o botão de descongelar só
# existia na página da cerimônia de revelação). Aqui:
#
#   GET  -> checklist do que ainda está fechado, no MESMO formato do preflight
#           ({checks:[{id,level,label,detail}], summary}) — o front deep-linka pelo id.
#   POST {action:"finish"} -> AGE em duas coisas (decisão do dono da plataforma):
#           1. descongela o placar (FREEZE_TIME=0) — o build repõe as métricas porque o conf
#              fica mais novo que var/.metrics-stamp, e apaga o placar-full;
#           2. publica todo documento JÁ GERADO que ainda não estava publicado.
#         O resto (relatório de correção p/ os times, código alheio, coortes, estatísticas)
#         continua sendo escolha explícita — aparece no checklist com "resolver →", nunca
#         é ligado por este botão.
#
# Só depois do fim PARA TODOS (inclusive prorrogação de sede): 409 contest_running.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
# GET (checklist) é leitura e vale p/ o juiz-chefe também — na Maratona 29/08 o cartão da
# Central "sumia" p/ o .cjudge porque o 403 daqui era engolido pelo front. AGIR (POST)
# segue exclusivo do admin; o front lê can_act p/ esconder o botão.
if [[ "$REQUEST_METHOD" == GET ]]; then
  is_admin_or_chief || fail 403 "Apenas admin ou juiz-chefe do contest" "admin_required"
else
  is_admin || fail 403 "Apenas o admin do contest" "admin_required"
fi
source "$_LIBDIR/contest-gate.sh"
source "$_LIBDIR/contest-create.sh"
source "$_LIBDIR/contest-docs.sh"

cdir="$CONTESTSDIR/$contest"
now="$EPOCHSECONDS"
FREEZE_TIME=""; SHOWLOG=""; SHOWCODE=""; CONTEST_END=0
load_contest_conf "$contest"

_docs_pending_json(){   # [{type,lang}] dos gerados-e-não-publicados
  local t l out='[]'
  while IFS=$'\t' read -r t l; do
    [[ -n "$t" ]] || continue
    out="$(jq -c --arg t "$t" --arg l "$l" '. + [{type:$t, lang:$l}]' <<<"$out")"
  done < <(doc_pending "$contest")
  printf '%s' "$out"
}

if [[ "$REQUEST_METHOD" != POST ]]; then
  CHECKS='[]'
  add(){ CHECKS="$(jq -c --arg i "$1" --arg lv "$2" --arg lb "$3" --arg d "$4" \
        '. + [{id:$i, level:$lv, label:$lb, detail:$d}]' <<<"$CHECKS")"; }

  # --- fim da prova -----------------------------------------------------------
  if contest_over_for_all "$contest"; then
    add fim ok "Prova encerrada" "terminou em $(fmt_epoch "$(contest_end_all "$contest")" '%d/%m/%Y %H:%M' "$contest")"
  else
    add fim warn "Prova ainda em andamento" "o encerramento só roda depois do fim para TODAS as sedes"
  fi

  # --- o que o botão resolve --------------------------------------------------
  if [[ "${FREEZE_TIME:-0}" =~ ^[0-9]+$ ]] && (( FREEZE_TIME > 0 )); then
    add freeze fail "Placar CONGELADO" "o público vê o placar de $(fmt_epoch "$FREEZE_TIME" '%H:%M' "$contest") — encerrar o evento abre o resultado final"
  else
    add freeze ok "Placar aberto" "sem congelamento em vigor"
  fi
  pend="$(_docs_pending_json)"; npend="$(jq -r 'length' <<<"$pend")"
  if (( npend > 0 )); then
    add docs fail "$npend documento(s) gerado(s) sem publicar" \
      "$(jq -r 'map(.type + "." + .lang) | join(", ")' <<<"$pend")"
  else
    add docs ok "Documentos publicados" "nada gerado esperando publicação"
  fi

  # --- informativos: o botão NÃO mexe, mas o organizador precisa ver ----------
  if [[ "$(showlog_effective "$contest")" == 1 ]]; then
    add show_log ok "Times veem o relatório de correção" "SHOWLOG ligado"
  else
    add show_log warn "Times NÃO veem o relatório de correção" "em modo prova é o padrão; depois costuma-se liberar em ⚙️ Regras"
  fi
  if [[ "${SHOWCODE:-0}" == 1 ]]; then
    add show_code ok "Código visível entre os times" "SHOWCODE ligado"
  else
    add show_code warn "Cada time vê só o próprio código" "libere em ⚙️ Regras se quiser abrir as soluções"
  fi
  source "$_LIBDIR/cohorts.sh" 2>/dev/null || true
  if declare -F ch_released >/dev/null 2>&1 && ! ch_released "$contest"; then
    add cohorts warn "Coortes não liberadas" "convidados/extra-oficiais seguem fora do placar público (Pessoas › Coortes)"
  fi
  add report ok "Relatório final" "baixe o pacote offline em Operação › Situação"

  ok_json '{checks:$c, summary:{ok:$o, warn:$w, fail:$f}, can_finish:$cf, can_act:$ca, pending_docs:$pd}' \
    --argjson c "$CHECKS" \
    --argjson o "$(jq -r '[.[]|select(.level=="ok")]|length' <<<"$CHECKS")" \
    --argjson w "$(jq -r '[.[]|select(.level=="warn")]|length' <<<"$CHECKS")" \
    --argjson f "$(jq -r '[.[]|select(.level=="fail")]|length' <<<"$CHECKS")" \
    --argjson cf "$(contest_over_for_all "$contest" && echo true || echo false)" \
    --argjson ca "$(is_admin && echo true || echo false)" \
    --argjson pd "$pend"
  exit 0
fi

# ---------------------------------------------------------------------------
# POST — encerra de fato
# ---------------------------------------------------------------------------
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
[[ "$(jq -r '.action // ""' <<<"$body")" == finish ]] || fail 400 "action deve ser finish" "action_invalid"
contest_over_for_all "$contest" \
  || fail 409 "A prova ainda não terminou para todas as sedes" "contest_running"

# uma vez só (duplo-clique/concorrência), como o relatório
mkdir -p "$cdir/var" 2>/dev/null
exec 9>"$cdir/var/.finish.lock"
flock -n 9 || fail 429 "Encerramento já está em andamento" "busy"

done_list='[]'; skipped='[]'
_done(){ done_list="$(jq -c --arg i "$1" --arg d "$2" '. + [{item:$i, detail:$d}]' <<<"$done_list")"; }
_skip(){ skipped="$(jq -c --arg i "$1" --arg r "$2" '. + [{item:$i, reason:$r}]' <<<"$skipped")"; }

# 1) placar: descongela (idempotente — sem freeze só registra que já estava aberto)
if [[ "${FREEZE_TIME:-0}" =~ ^[0-9]+$ ]] && (( FREEZE_TIME > 0 )); then
  # PRESERVA o freeze antes de zerar (2026-08-31): o relatório estático é histórico e tem
  # de contar o congelamento — sem isto, a LATAM perdeu o freeze das 18h no report
  # os placar*.txt DESTE instante são o placar CONGELADO — a cópia é o que permite ao
  # relatório histórico mostrar o freeze depois que o build regravar tudo completo
  mkdir -p "$CONTESTSDIR/$contest/var/frozen-final" 2>/dev/null
  ( set +o noglob 2>/dev/null; shopt -s nullglob
    for _pf in "$CONTESTSDIR/$contest/var"/placar*.txt; do
      cp -f "$_pf" "$CONTESTSDIR/$contest/var/frozen-final/${_pf##*/}" 2>/dev/null
    done )
  _fftmp="$CONTESTSDIR/$contest/var/.freeze-final.tmp.${BASHPID}"
  jq -cn --argjson f "$FREEZE_TIME" --argjson at "$EPOCHSECONDS" --arg by "$SESSION_LOGIN" \
    '{freeze:$f, cleared_at:$at, by:$by}' > "$_fftmp" 2>/dev/null \
    && mv -f "$_fftmp" "$CONTESTSDIR/$contest/var/freeze-final.json" || rm -f "$_fftmp"
  cc_set_conf_var "$contest" FREEZE_TIME 0 && _done placar "placar descongelado (resultado final público)" \
    || _skip placar "falha ao gravar o conf"
  # score_kick_rebuild, não touch solto: um build EM VOO terminaria depois desta escrita e
  # carimbaria tudo "fresco" com os metrics pré-mudança — o placar ficava congelado p/
  # sempre (corrida de mtime, Maratona 29/08; ver o helper em lib/common.sh).
  score_kick_rebuild "$contest"
else
  _skip placar "já estava aberto"
fi

# 2) documentos gerados e não publicados
npub=0
while IFS=$'\t' read -r t l; do
  [[ -n "$t" ]] || continue
  # o editorial é a solução da prova: mesma trava do painel (já passamos pelo fim-para-todos,
  # então aqui ela só vale como cinto de segurança se o gate mudar)
  if [[ "$t" == editorial ]] && ! contest_over_for_all "$contest"; then
    _skip "$t.$l" "editorial só depois do fim"; continue
  fi
  if doc_publish "$contest" "$t" "$l"; then npub=$(( npub + 1 )); _done "$t.$l" "documento publicado"
  else _skip "$t.$l" "falha ao publicar"; fi
done < <(doc_pending "$contest")
(( npub > 0 )) || _skip documentos "nada gerado esperando publicação"

audit_log_to "$contest" finish-event "docs=$npub freeze=${FREEZE_TIME:-0}"
ok_json '{finished:true, done:$d, skipped:$s}' --argjson d "$done_list" --argjson s "$skipped"
