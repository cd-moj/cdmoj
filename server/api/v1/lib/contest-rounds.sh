# lib/contest-rounds.sh — RODADAS de um contest (aquecimento → prova oficial).
#
# O MESMO contest roda várias rodadas em sequência: um aquecimento (dress rehearsal) com poucos
# problemas e depois a prova oficial, sem recriar nada — a configuração (contas, senhas, sedes,
# cores de balão, TL, linguagens, pool de juízes, papéis) é justamente o que se quer preservar.
#
# PRINCÍPIO: a rodada ATIVA continua sendo o `conf` (CONTEST_START/END/FREEZE_TIME/PROBS). Nada
# no caminho quente (placar, gates, daemon, juiz) fica "consciente de rodada" — trocar de rodada
# é ARQUIVAR + ZERAR + REAPONTAR. Tentar filtrar por janela em vez de arquivar quebraria feio:
# a tentativa do aquecimento viraria penalidade da prova (metrics `counted`), o AC do aquecimento
# viraria `first_ac_epoch`, o `tempo = sub_epoch - CONTEST_START` colapsaria tudo no minuto 0 e o
# balão do aquecimento (id = md5(contest+login+cid)) SUPRIMIRIA o da prova.
#
# `rounds.json` é o PLANO; para a rodada ativa o `conf` é a verdade (rd_sync_active espelha
# conf→json antes de qualquer leitura, então editar em ⚙️ Configurações / 📚 Problemas nunca
# divergem do plano).
#
#   contests/<c>/rounds.json                  {version,active,rounds:[…]}
#   contests/<c>/rounds/<slug>/               ARQUIVO da rodada (auditoria posterior)
#     relatorio/                              site estático do report-gen — é o que se SERVE
#     users/<login>/{history,metrics.json,submissions,mojlog,results}
#     review/ print-requests/ clarifications/ news.json news-files/ backups/ jplag/ docs/
#     placar*.txt statistics.cache.json time-overrides.json resources.json
#     access.log admin-audit.log editor-log offline-log   (CÓPIAS: append-only, precisam continuar)
#     conf.snapshot machines.json meta.json
#
# Requer: lib/users.sh, lib/contest-create.sh, lib/print.sh (balões), lib/contest-gate.sh.

rd_file(){       printf '%s/%s/rounds.json' "$CONTESTSDIR" "$1"; }
rd_base(){       printf '%s/%s/rounds'      "$CONTESTSDIR" "$1"; }
rd_archive_dir(){ printf '%s/%s/rounds/%s'  "$CONTESTSDIR" "$1" "$2"; }   # <c> <slug>
# slug: a-z 0-9 - _ (até 32) — vira nome de diretório em rounds/. O regex é LITERAL de
# propósito: em `: "${VAR:=…{0,31}$}"` o primeiro `}` fecha a expansão e o regex sai truncado.
rd_valid_slug(){ [[ "$1" =~ ^[a-z0-9][a-z0-9_-]{0,31}$ ]]; }

# rd_get <c> -> rounds.json (default coerente se não existir)
rd_get(){
  local f; f="$(rd_file "$1")"
  if [[ -s "$f" ]] && jq -e '.rounds' "$f" >/dev/null 2>&1; then cat "$f"
  else printf '{"version":1,"active":"","rounds":[]}'; fi
}
rd_save(){  # rd_save <c> <json>  (atômico)
  local f; f="$(rd_file "$1")"
  printf '%s\n' "$2" > "$f.tmp" && mv -f "$f.tmp" "$f"
}

# rd_sync_active <c> — espelha a rodada ATIVA do conf para o rounds.json (janela + problemas).
# Sem rodada nenhuma (contest comum), CRIA a rodada implícita "oficial" a partir do conf: assim
# qualquer contest existente ganha rodadas sem migração.
rd_sync_active(){
  local c="$1" j act cs ce fz nm probs
  j="$(rd_get "$c")"
  act="$(jq -r '.active // ""' <<<"$j")"
  eval "$( declare -A ULIMITS 2>/dev/null || true
    . "$CONTESTSDIR/$c/conf" 2>/dev/null
    printf 'cs=%q ce=%q fz=%q nm=%q rs=%q rn=%q' \
      "${CONTEST_START:-0}" "${CONTEST_END:-0}" "${FREEZE_TIME:-0}" \
      "${CONTEST_NAME:-$c}" "${ROUND:-}" "${ROUND_NAME:-}" )"
  [[ -n "$act" ]] || act="${rs:-}"
  if [[ -z "$act" ]]; then                     # contest sem rodadas: adota a corrente como oficial
    act=oficial
    j="$(jq -c --arg s "$act" '.active=$s' <<<"$j")"
  fi
  probs="$(cc_probs_json "$c")"; [[ -n "$probs" ]] || probs='[]'
  jq -c --arg s "$act" --arg dn "${rn:-Prova oficial}" \
     --argjson cs "${cs:-0}" --argjson ce "${ce:-0}" --argjson fz "${fz:-0}" \
     --argjson p "$probs" '
     .active = $s
     | .rounds = (if ((.rounds // []) | map(.slug) | index($s)) == null
                  then ((.rounds // []) + [{slug:$s, name:$dn, kind:"official", state:"active"}])
                  else (.rounds // []) end)
     | .rounds = [ .rounds[] | if .slug == $s
         then (. + {state:"active", start:$cs, end:$ce, freeze:$fz, problems:$p})
         else . end ]' <<<"$j"
}

# rd_active <c> -> slug da rodada ativa
rd_active(){ rd_sync_active "$1" | jq -r '.active // ""'; }

# rd_round <c> <slug> -> objeto da rodada (vazio se não existe)
rd_round(){ rd_sync_active "$1" | jq -c --arg s "$2" '(.rounds // [])[] | select(.slug == $s)'; }

# rd_next <c> -> slug da PRÓXIMA rodada planejada (a 1ª `pending` na ordem do array)
rd_next(){ rd_sync_active "$1" | jq -r 'first((.rounds // [])[] | select(.state == "pending") | .slug) // ""'; }

# ---------- bloqueadores da promoção -------------------------------------------------------
# rd_jobs_in_flight <c> -> nº de jobs deste contest no spool / fila / atribuídos.
# O daemon lê o conf NO CONSUMO do spool: um job que atravessa a troca usaria o CONTEST_START
# novo (tempo errado), a matriz de auto-veredicto nova, e o `ingest_result` sem a linha
# provisória RECRIA a submissão no history da rodada nova. Por isso a promoção recusa.
rd_jobs_in_flight(){
  local c="$1" n=0 f
  ( set +o noglob; shopt -s nullglob
    for f in "${SPOOLDIR:-$RUNDIR/spool/submissions}/$c:"*; do [[ -e "$f" ]] && printf 'x\n'; done
    for f in "${QUEUEDIR:-$RUNDIR/queue}"/*/*.json "${ASSIGNEDDIR:-$RUNDIR/assigned}"/*/*.json; do
      [[ -f "$f" ]] || continue
      [[ "$(jq -r '.contest // ""' "$f" 2>/dev/null)" == "$c" ]] && printf 'x\n'
    done ) | wc -l | tr -d '[:space:]'
}

# rd_review_pending <c> -> nº de itens de correção manual ainda não liberados
rd_review_pending(){
  local d="$CONTESTSDIR/$1/review" n=0
  [[ -d "$d" ]] || { printf 0; return; }
  n="$(find "$d" -maxdepth 1 -name '*.json' -print0 2>/dev/null \
       | xargs -0 -r jq -r 'select((.status // "open") != "released") | "x"' 2>/dev/null | wc -l)"
  printf '%s' "${n//[^0-9]/}"
}

# rd_promote_blockers <c> -> [{code,detail}] — o checklist que a UI mostra ao vivo
rd_promote_blockers(){
  local c="$1" out='[]' n next uf
  _add(){ out="$(jq -c --argjson o "$out" --arg k "$1" --arg d "$2" '$o + [{code:$k, detail:$d}]' <<<'null')"; }

  next="$(rd_next "$c")"
  [[ -n "$next" ]] || _add no_next_round "nenhuma rodada planejada: crie a próxima antes de promover"

  # (ERA um bloqueador: "USERS_FROM ⇒ arquivar mexeria no store de outro contest". Não mexe —
  #  o arquivamento itera `$cdir/users/*/`, que são os diretórios LOCAIS deste contest, e a
  #  fonte nunca é aberta. O guard impedia justamente o caso real: esquenta com as contas do
  #  treino, aquecimento de dias e depois a prova. O smoke prova que o store do treino sai
  #  intacto da promoção.)

  if declare -F contest_over_for_all >/dev/null && ! contest_over_for_all "$c"; then
    _add round_running "a rodada ativa ainda não terminou (inclusive prorrogações por sede)"
  fi
  n="$(rd_jobs_in_flight "$c")"
  (( n > 0 )) && _add jobs_in_flight "$n job(s) deste contest no spool/fila do juiz — espere drenar"
  n="$(rd_review_pending "$c")"
  (( n > 0 )) && _add review_pending "$n submissão(ões) na correção manual sem veredicto liberado"
  if declare -F count_pending >/dev/null; then
    n="$(count_pending "$c")"; n="${n//[^0-9]/}"
    (( ${n:-0} > 0 )) && _add pending_verdicts "${n} submissão(ões) ainda sem veredicto no history"
  fi
  if declare -F daemon_judged_alive >/dev/null && ! daemon_judged_alive; then
    _add judged_down "o daemon de julgamento não está vivo — nada drenaria a fila"
  fi
  printf '%s' "$out"
}

# ---------- aplicar uma rodada ao conf ------------------------------------------------------
# rd_apply <c> <slug> — grava janela + PROBS + ROUND/ROUND_NAME da rodada no conf.
# CC_KEEP_STATEMENTS=1: não deixa o cc_build_probs re-baixar o enunciado do banco por cima do
# que o admin subiu à mão (o caderno final da prova!).
rd_apply(){
  local c="$1" s="$2" r
  r="$(rd_round "$c" "$s")"; [[ -n "$r" ]] || return 1
  rd_apply_obj "$c" "$r"
}

# rd_apply_obj <c> <round-json> — a versão que recebe o OBJETO. Editar a rodada ATIVA tem de
# passar por aqui: `rd_apply <slug>` releria a rodada com `rd_round`, que passa pelo
# rd_sync_active e RE-ESPELHA a janela do conf por cima — a edição virava no-op.
rd_apply_obj(){
  local c="$1" r="$2" probs cs ce fz nm s
  [[ -n "$r" ]] || return 1
  s="$(jq -r '.slug // ""' <<<"$r")"; [[ -n "$s" ]] || return 1
  cs="$(jq -r '.start // 0' <<<"$r")"; ce="$(jq -r '.end // 0' <<<"$r")"
  fz="$(jq -r '.freeze // 0' <<<"$r")"; nm="$(jq -r '.name // .slug' <<<"$r")"
  probs="$(jq -c '.problems // []' <<<"$r")"
  cc_set_conf_var "$c" CONTEST_START "$cs"
  cc_set_conf_var "$c" CONTEST_END   "$ce"
  if [[ "$fz" =~ ^[0-9]+$ && "$fz" -gt 0 ]]; then cc_set_conf_var "$c" FREEZE_TIME "$fz"
  else cc_del_conf_var "$c" FREEZE_TIME; fi
  cc_set_conf_var "$c" ROUND "$s"
  cc_set_conf_var "$c" ROUND_NAME "$nm"
  cc_set_conf_var "$c" ROUND_KIND "$(jq -r '.kind // "official"' <<<"$r")"
  if [[ "$probs" != '[]' ]]; then
    CC_KEEP_STATEMENTS=1 cc_set_probs "$c" "$probs" || return 1
    # a rodada nova tem OUTRA lista de problemas: derruba o cache de /contest/problems
    touch "$CONTESTSDIR/$c/var/.problems-dirty" 2>/dev/null
  fi
  return 0
}

# ---------- mapa de máquinas (IP + UA) ------------------------------------------------------
# É no aquecimento que os times ligam as máquinas de verdade — então é ali que se descobre, por
# IP e UA, de onde vem cada time. Fonte: contests/<c>/var/access.log (TSV epoch login ip ua_b64,
# escritor único em handlers/auth/login.sh), recortado pela JANELA da rodada. Nada novo a capturar.
# rd_machines <c> [<slug>] -> {window, by_login:[…], by_ip:[…], uas:[…], ua_suggestion}
rd_machines(){
  local c="$1" s="${2:-}" r cs ce log prev stored
  [[ -n "$s" ]] || s="$(rd_active "$c")"
  r="$(rd_round "$c" "$s")"; [[ -n "$r" ]] || r='{}'
  # rodada ARQUIVADA: o machines.json gravado na promoção É o artefato de auditoria (foi medido
  # com o log e a janela vivos). Só recomputa se ele não existir (arquivo antigo).
  stored="$(rd_archive_dir "$c" "$s")/machines.json"
  if [[ "$(jq -r '.state // ""' <<<"$r")" == archived && -s "$stored" ]] \
     && jq -e '(.by_login | length) > 0' "$stored" >/dev/null 2>&1; then
    cat "$stored"; return 0
  fi
  cs="$(jq -r '.start // 0' <<<"$r")"; ce="$(jq -r '.end // 0' <<<"$r")"
  [[ "$cs" =~ ^[0-9]+$ ]] || cs=0; [[ "$ce" =~ ^[0-9]+$ ]] || ce=0
  (( ce > 0 )) || ce=$EPOCHSECONDS
  log="$CONTESTSDIR/$c/var/access.log"
  # arquivada: usa o access.log copiado no arquivo (o vivo segue crescendo com a rodada nova)
  [[ "$(jq -r '.state // ""' <<<"$r")" == archived && -s "$(rd_archive_dir "$c" "$s")/access.log" ]] \
    && log="$(rd_archive_dir "$c" "$s")/access.log"

  local tmpj; tmpj="$(mktemp)" || return 1
  # TSV -> NDJSON só das linhas na janela (awk: nada de jq por linha)
  if [[ -s "$log" ]]; then
    awk -F'\t' -v a="$cs" -v b="$ce" 'NF>=3 && $1+0>=a && $1+0<=b {
        gsub(/"/,"",$2); gsub(/"/,"",$3); gsub(/"/,"",$4)
        printf "{\"t\":%d,\"login\":\"%s\",\"ip\":\"%s\",\"ua64\":\"%s\"}\n", $1, $2, $3, $4 }' \
      "$log" > "$tmpj"
  fi
  # identidade dos times (nome + sede) p/ o painel não mostrar só login
  local tmpu; tmpu="$(mktemp)" || { rm -f "$tmpj"; return 1; }
  { local d af; d="$(users_dir "$c")"
    ( set +o noglob; shopt -s nullglob
      for af in "$d"/*/account.json; do
        jq -c --arg l "$(basename "$(dirname "$af")")" \
          '{key:$l, value:{name:(.fullname // .team.name // $l), region:((.team.region) // "")}}' "$af" 2>/dev/null
      done ); } | jq -cs 'from_entries' > "$tmpu"
  [[ -s "$tmpu" ]] || printf '{}' > "$tmpu"

  # rodada anterior (a última arquivada) p/ marcar quem MUDOU de máquina
  prev="$(rd_sync_active "$c" | jq -r --arg s "$s" \
      'last((.rounds // [])[] | select(.state == "archived" and .slug != $s) | .slug) // ""')"
  local tmpp; tmpp="$(mktemp)"; printf '{}' > "$tmpp"
  if [[ -n "$prev" && -s "$(rd_archive_dir "$c" "$prev")/machines.json" ]]; then
    jq -c '[ (.by_login // [])[] | {key:.login, value:{ips:(.ips // []), uas:(.uas // [])}} ] | from_entries' \
      "$(rd_archive_dir "$c" "$prev")/machines.json" > "$tmpp" 2>/dev/null || printf '{}' > "$tmpp"
  fi

  # UA ESPERADO por time (gate de navegador por sede): resolvido em LOTE — ver lib/ua-gate.sh.
  # É o que deixa o painel de Máquinas mostrar "esperado × visto" e consertar a sala no
  # aquecimento, antes de o gate barrar alguém na prova.
  local tmpe; tmpe="$(mktemp)"; printf '{}' > "$tmpe"
  if declare -F ug_expected_map >/dev/null; then
    ug_expected_map "$c" "$(jq -rc '[.[].login] | unique' <<<"$(jq -sc '.' "$tmpj" 2>/dev/null || echo '[]')" 2>/dev/null || echo '[]')" \
      "$(jq -c 'with_entries(.value |= .region)' "$tmpu" 2>/dev/null || echo '{}')" > "$tmpe" 2>/dev/null \
      || printf '{}' > "$tmpe"
    [[ -s "$tmpe" ]] || printf '{}' > "$tmpe"
  fi
  jq -sc --slurpfile users "$tmpu" --slurpfile prev "$tmpp" --slurpfile exp "$tmpe" \
     --arg round "$s" --arg prev_round "$prev" --argjson cs "$cs" --argjson ce "$ce" '
    ($users[0] // {}) as $U | ($prev[0] // {}) as $P | ($exp[0] // {}) as $E
    | (group_by(.login) | map({
        login: .[0].login,
        name:  (($U[.[0].login].name) // .[0].login),
        region:(($U[.[0].login].region) // ""),
        logins: length,
        first: (map(.t) | min), last: (map(.t) | max),
        ips: (map(.ip) | unique),
        uas: (map(.ua64) | unique),
        pairs: (group_by(.ip + "|" + .ua64) | map({ip:.[0].ip, ua64:.[0].ua64,
                 n:length, first:(map(.t)|min), last:(map(.t)|max)}))
      })) as $BY
    | ($BY | map(.login as $l | . + {
        ua_expected: ($E[$l] // ""),
        # o time casa o esperado se ALGUM dos UAs vistos contém a substring (case-insensitive)
        ua_match: (($E[$l] // "") == "" or
                   any(.uas[]; (. | @base64d | ascii_downcase)
                       | contains(($E[$l] // "") | ascii_downcase))),
        multi_ip: ((.ips|length) > 1),
        changed: ( ($P[$l] != null) and
                   (((.ips - ($P[$l].ips // [])) | length) > 0 or
                    ((.uas - ($P[$l].uas // [])) | length) > 0) )
      })) as $BY2
    | ([ .[] | .ip ] | unique | map(. as $ip | {
         ip: $ip,
         logins: ([ $BY2[] | select(.ips | index($ip)) | .login ] | unique)
       }) | map(. + {shared: ((.logins|length) > 1)})) as $BYIP
    | { round: $round, prev_round: $prev_round, window: {start:$cs, end:$ce},
        by_login: ($BY2 | sort_by(.name)),
        by_ip: $BYIP,
        uas: ([ .[] | .ua64 ] | unique | map({ua64:., n:0})),
        totals: { logins: ($BY2|length), ips: ($BYIP|length),
                  changed: ([$BY2[] | select(.changed)] | length),
                  shared_ips: ([$BYIP[] | select(.shared)] | length),
                  ua_mismatch: ([$BY2[] | select(.ua_match == false)] | length) } }' "$tmpj"
  rm -f "$tmpj" "$tmpu" "$tmpp" "$tmpe"
}

# ---------- promoção -----------------------------------------------------------------------
# rd_promote <c> <to-slug> <by> — arquiva a rodada ativa e coloca a próxima no ar.
# ORDEM IMPORTA: o relatório estático sai ANTES de qualquer mv (ele lê o estado vivo).
# Ecoa {from,to,archived:{…}} em caso de sucesso.
rd_promote(){
  local c="$1" to="$2" by="${3:-}" from ad cdir="$CONTESTSDIR/$1"
  from="$(rd_active "$c")"
  [[ -n "$from" && -n "$to" && "$from" != "$to" ]] || return 1
  rd_valid_slug "$from" && rd_valid_slug "$to" || return 1
  ad="$(rd_archive_dir "$c" "$from")"
  [[ -e "$ad" ]] && return 2                          # já arquivado: nunca sobrescreve auditoria
  # A rodada que sai é fotografada AQUI, antes de qualquer escrita no conf: depois do rd_apply o
  # espelho conf→json (rd_sync_active) carimbaria a janela da rodada NOVA sobre ela — e o arquivo
  # (e o mapa de máquinas, que recorta o access.log pela janela) sairia com a janela errada.
  local from_obj; from_obj="$(rd_round "$c" "$from")"
  [[ -n "$from_obj" ]] || return 1
  mkdir -p "$ad" || return 1

  # 1. fecha o livro de balões e refaz os derivados, p/ o relatório sair coerente
  declare -F pr_reconcile_balloons >/dev/null && pr_reconcile_balloons "$c" >/dev/null 2>&1 || true
  bash "${SCOREDIR:-$_DIR/../../score}/build.sh" "$c" >/dev/null 2>&1 || true
  bash "${SCOREDIR:-$_DIR/../../score}/stats-gen.sh" "$c" >/dev/null 2>&1 || true

  # 2. relatório estático da rodada (é o que fica SERVÍVEL depois) — antes de mover nada
  bash "${SCOREDIR:-$_DIR/../../score}/report-gen.sh" "$c" "$ad/relatorio" \
    >/dev/null 2>"$cdir/var/round-report.err" || true

  # 3. contagens + mapa de máquinas ANTES do reset (dependem do estado vivo)
  local nusers nsubs
  nusers="$(list_users "$c" | wc -l | tr -d '[:space:]')"
  nsubs="$( ( set +o noglob; shopt -s nullglob; cat "$cdir"/users/*/history 2>/dev/null ) | wc -l | tr -d '[:space:]')"
  rd_machines "$c" "$from" > "$ad/machines.json" 2>/dev/null || printf '{}' > "$ad/machines.json"
  cp -f "$cdir/conf" "$ad/conf.snapshot" 2>/dev/null || true
  # meta.json: o arquivo tem de se explicar sozinho quando alguém abrir o tar.gz meses depois
  jq -cn --arg c "$c" --argjson r "$from_obj" --arg by "$by" \
     --argjson at "$EPOCHSECONDS" --argjson nu "${nusers:-0}" --argjson ns "${nsubs:-0}" \
     --argjson rep "$([[ -s "$ad/relatorio/index.html" ]] && printf true || printf false)" \
     '{contest:$c, round:($r.slug), name:($r.name), kind:($r.kind),
       start:($r.start), end:($r.end), freeze:($r.freeze // 0),
       promoted_at:$at, promoted_by:$by, users:$nu, submissions:$ns, report:$rep,
       note:"arquivo da rodada: relatorio/ é o site estático (sem código-fonte); users/ tem o bruto"}' \
     > "$ad/meta.json" 2>/dev/null || true

  # 4. dados de rodada: MOVE (mesmo filesystem). Config fica onde está.
  local d u
  mkdir -p "$ad/users"
  ( set +o noglob; shopt -s nullglob
    for d in "$cdir"/users/*/; do
      u="$(basename "$d")"
      mkdir -p "$ad/users/$u"
      for x in history metrics.json submissions mojlog results; do
        [[ -e "$d$x" ]] && mv -f "$d$x" "$ad/users/$u/$x" 2>/dev/null
      done
      # store vazio de volta (o daemon e o submit esperam os dirs prontos)
      mkdir -p "$d/submissions" "$d/mojlog" "$d/results"; : > "$d/history"
    done )
  for x in review clarifications news-files backups jplag docs; do
    [[ -e "$cdir/$x" ]] && mv -f "$cdir/$x" "$ad/$x" 2>/dev/null
  done
  for x in news.json resources.json time-overrides.json; do
    [[ -e "$cdir/$x" ]] && mv -f "$cdir/$x" "$ad/$x" 2>/dev/null
  done
  # print-requests: PRESERVA o staff-filters.json (é config: o escopo de cada sede)
  if [[ -d "$cdir/print-requests" ]]; then
    mv -f "$cdir/print-requests" "$ad/print-requests" 2>/dev/null
    mkdir -p "$cdir/print-requests"
    [[ -f "$ad/print-requests/staff-filters.json" ]] \
      && cp -f "$ad/print-requests/staff-filters.json" "$cdir/print-requests/staff-filters.json"
  fi
  # docs: templates e capa são CONFIG — voltam; os PDFs gerados ficam no arquivo
  if [[ -d "$ad/docs" ]]; then
    mkdir -p "$cdir/docs"
    ( set +o noglob; shopt -s nullglob
      for f in "$ad/docs"/*.md "$ad/docs"/cover.*.pdf; do cp -f "$f" "$cdir/docs/" 2>/dev/null; done )
    [[ -f "$ad/docs/config.json" ]] && jq -c 'del(.published)' "$ad/docs/config.json" \
      > "$cdir/docs/config.json" 2>/dev/null
  fi
  # placar/estatística da rodada: MOVE (viram o retrato). placar-custom.txt é ENTRADA humana: fica.
  # Os placares POR VISÃO (coortes com ranking próprio: times × individual, convidados) entram
  # junto — sem eles o arquivo da rodada perde justamente os placares separados.
  for x in placar.txt placar-full.txt statistics.cache.json; do
    [[ -e "$cdir/var/$x" ]] && mv -f "$cdir/var/$x" "$ad/$x" 2>/dev/null
  done
  ( set +o noglob; shopt -s nullglob
    for f in "$cdir"/var/placar-view-*.txt; do mv -f "$f" "$ad/${f##*/}" 2>/dev/null; done )
  # append-only: COPIA (a trilha do contest precisa continuar; o access.log é a fonte do
  # mapa de máquinas e tem de atravessar as rodadas)
  for x in access.log admin-audit.log editor-log offline-log; do
    [[ -e "$cdir/var/$x" ]] && cp -f "$cdir/var/$x" "$ad/$x" 2>/dev/null
  done
  rm -f "$cdir/var/.metrics-stamp" "$cdir/var/.pending-count" "$cdir/var/round-report.err" 2>/dev/null

  # 5. rodada nova no ar
  rd_apply "$c" "$to" || return 1
  touch "$cdir/var/.score-dirty" 2>/dev/null || true

  # 6. rounds.json: arquiva a anterior (com as contagens) e ativa a nova
  # `rd_get` (cru), NÃO rd_sync_active: o espelho só é correto DEPOIS que .active aponta p/ a
  # rodada nova. A entrada da rodada que saiu vem do retrato tirado no começo.
  local j
  j="$(rd_get "$c")"
  j="$(jq -c --arg f "$from" --arg t "$to" --arg by "$by" --argjson at "$EPOCHSECONDS" \
        --argjson nu "${nusers:-0}" --argjson ns "${nsubs:-0}" --argjson fo "$from_obj" '
        .active = $t
        | .rounds = [ .rounds[]
            | if .slug == $f then ($fo + {state:"archived", promoted_at:$at, promoted_by:$by,
                                        published:(.published // false),
                                        stats:{users:$nu, submissions:$ns}})
              elif .slug == $t then (. + {state:"active"})
              else . end ]' <<<"$j")"
  rd_save "$c" "$j"

  jq -cn --arg f "$from" --arg t "$to" --argjson nu "${nusers:-0}" --argjson ns "${nsubs:-0}" \
    '{from:$f, to:$t, archived:{users:$nu, submissions:$ns}}'
}
