# GET /problems/status  (Bearer) -> painel de status dos problemas do setter (dono + colaborador).
# Agrega, por id VISÍVEL: validação (run/validation), calibração + time_limits + "precisa recalibrar"
# (run/tl x tl_checksum do índice) e "sendo calibrado AGORA" (filas de calibração). A FRONTEIRA de
# acesso é owners_visible — problema PRIVADO de terceiro NUNCA aparece (a API garante, não a UI).
# Custo: sem hash de pacote por request — stale sai da comparação de dois checksums já materializados
# (o do pacote atual vem carimbado no índice por gen-problem-owners.sh; o calibrado, de run/tl). A
# VIABILIDADE (judgeable/not_judgeable, 2b) lê o `conf` de cada problema sem fork — é a gestão de
# problemas, do lado de dentro da fronteira do pacote — e o topo traz `judge_capacity` p/ o editor.
require_method GET
require_auth
source "$_DIR/lib/problems.sh"
source "$_DIR/lib/tl-store.sh"
source "$_DIR/lib/calib-expect.sh"   # sumário das soluções/validador (run/calib-summary.json)
source "$_DIR/lib/problem-issues.sh" # sumário das issues abertas (treino/var/problem-issues-summary.json)
source "$_DIR/../../judge-gw/sched-lib.sh"

# 1) FRONTEIRA DE SEGURANÇA (owners_visible) + estreitamento a dono/colaborador (tira público-só:
#    só REMOVE do conjunto já filtrado, nunca alarga).
# Índice quebrado NÃO pode virar "board vazio": era indistinguível de "você não tem problema
# nenhum" (o `moj board` e a aba Painel mostravam zero, com 200, calados).
vis="$(owners_visible)" \
  || fail 503 "Índice de problemas indisponível (a regeração falhou) — tente de novo em instantes" "index_unavailable"
# estreita ao que o login OPERA (tira os só-públicos): dono, colaborador ou MEMBRO da org
vis="$(jq -c --arg me "$SESSION_LOGIN" --argjson orgs "$(my_orgs_json)" \
   '.problems |= map(select(.owner==$me or ((.collaborators // [])|index($me)|type=="number")
       or (((.repo // (.id|split("#")[0])) as $r | $orgs|index($r))|type=="number")))' <<<"$vis" 2>/dev/null)"
[[ -n "$vis" ]] || fail 503 "Falha ao filtrar o índice de problemas" "index_unavailable"
# ?id=<id> estreita a UM problema (a confirmação de "publicar" pergunta as pendências dele). Só
# REMOVE do conjunto já filtrado: id que o login não opera sai vazio, igual a inexistente.
one="$(param id)"
if [[ -n "$one" ]]; then
  vis="$(jq -c --arg id "$one" '.problems |= map(select(.id == $id))' <<<"$vis" 2>/dev/null)"
  [[ -n "$vis" ]] || fail 503 "Falha ao filtrar o índice de problemas" "index_unavailable"
fi

# 2) SENDO CALIBRADO AGORA (uma varredura das filas -> conjunto pequeno).
# A guarda de vazio é OBRIGATÓRIA (o $sup abaixo já tinha; este não): um `--argjson CAL ""` mata o jq
# grande lá embaixo, o `|| fallback` devolve {total:0, problems:[]} e o board fica MUDO com 200. Era
# exatamente isto que acontecia sempre que NINGUÉM estava calibrando (ou seja: quase sempre).
calib="$(calibrating_set)"; [[ -n "$calib" ]] || calib='[]'
# linguagens que ALGUM juiz suporta (registry .langs) — p/ NÃO marcar "falha" uma solução good cuja
# linguagem juiz nenhum roda (ex.: apl = limitação de plataforma/deploy, não defeito do problema).
sup="$(find "${REGISTRYDIR:-$RUNDIR/registry}" -maxdepth 1 -name '*.json' -exec cat {} + 2>/dev/null | jq -sc '[.[]|.langs//[]|.[]]|unique' 2>/dev/null)"
[[ -n "$sup" ]] || sup='[]'

# 2b) VIABILIDADE: o problema cabe em ALGUM dos juízes da plataforma? A MESMA regra do escalonador
#     (sched_judgeable → _eff_width: CPUNEEDED, SAMENUMA e MEMLIMITMB como largura) contra os juízes vistos
#     nos últimos 7 dias. Incidente de 30/09/2026: 15 problemas com MEMLIMITMB=262144 (256 GB) eram
#     impossíveis desde o escalonador por largura, e só apareceram quando uma lista travou. O conf é lido
#     sem fork (_pkg_par_v); só os NÃO julgáveis viram linha. Sem juiz conhecido, não se afirma nada.
REGISTRYDIR="${REGISTRYDIR:-$RUNDIR/registry}" sched_cap_load
capj="$(sched_cap_json)"
njmap="$(mktemp)"; trap 'rm -f "$njmap"' EXIT
{ if (( SCAP_N > 0 )); then
    while IFS= read -r pid; do
      [[ -n "$pid" ]] || continue
      _pkg_par_v "$pid"; sched_judgeable "$_PP_K" "$_PP_NUMA" "$_PP_MEM"
      [[ -n "$_NJ_CODE" ]] && printf '%s\t%s\t%s\t%s\n' "$pid" "$_NJ_CODE" "$_NJ_NEED" "$_NJ_MAX"
    done < <(jq -r '.problems[].id // empty' <<<"$vis" 2>/dev/null)
  fi; } | jq -Rn '[ inputs | split("\t") | select(length >= 4)
                   | {key:.[0], value:{code:.[1], need:(.[2]|tonumber? // .[2]), max:(.[3]|tonumber? // .[3])}} ]
                 | from_entries' > "$njmap" 2>/dev/null
[[ -s "$njmap" ]] || echo '{}' > "$njmap"

# 3+4) SUMÁRIOS agregados de TL e validação (run/{tl,validation}-summary.json) — mantidos
# POR EVENTO pelos escritores (tl_store_record / judge/update-report); rebuild só a frio.
# Antes eram ~2·N forks de `cat` POR REQUEST (4s p/ ~900 visíveis). Os sumários têm TODOS os
# ids da plataforma, mas são arquivos INTERNOS: o jq abaixo só projeta linhas dos ids de $vis
# (a fronteira segue owners_visible; nada de terceiro sai na resposta).
tl_summary_ensure; val_summary_ensure; calx_summary_ensure
tlmap="$TL_SUMMARY"; valmap="$VAL_SUMMARY"; calmap="$CAL_SUMMARY"
[[ -s "$calmap" ]] || calmap=/dev/null   # sem sumário ainda = nenhum problema conferido (não é erro)
pi_summary_ensure; issmap="$PI_SUMMARY"; [[ -s "$issmap" ]] || issmap=/dev/null

# 5) JOIN + AGREGADOS. JSON grande (vis) via stdin; mapas via --slurpfile; conjunto calib via
#    --argjson (é pequeno) — nada de JSON grande no argv (ARG_MAX).
# O CORPO É MONTADO ANTES DO CABEÇALHO: com o `emit_json 200` já enviado, o único destino de um jq
# quebrado era um board VAZIO (o antigo `|| jq -cn '{total:0,…}'`) — silencioso e indistinguível de
# "você não tem problema nenhum". Agora falha vira 500 COM a mensagem do jq.
out="$(jq -c --slurpfile TL "$tlmap" --slurpfile VAL "$valmap" --slurpfile CX "$calmap" --slurpfile ISS "$issmap" \
          --slurpfile NJ "$njmap" --argjson CAL "$calib" --argjson SUP "$sup" --argjson CAPJ "$capj" '
  ($TL[0] // {}) as $tl | ($VAL[0] // {}) as $val | ($CX[0] // {}) as $cx | ($ISS[0] // {}) as $iss
  | ($NJ[0] // {}) as $njm
  | ($SUP | map(if . == "py2" or . == "py3" then "py" else . end)) as $supn
  | ($CAL | map({(.):true}) | add // {}) as $calset
  | (.generated_at // 0) as $idx_at
  | [ .problems[]
      | .id as $id
      | ($val[$id]) as $v | ($tl[$id]) as $t
      | (($v.checks // []) | any(.name=="good_sol_accepts" and (.ok|not))) as $gsbad
      | (if $v==null then "none" elif ($v.ok==true) then "ok" else "error" end) as $vstate
      | ($t.calibrated // false) as $cal
      # STALE = checksum calibrado != checksum do pacote NO ÍNDICE. Mas o índice de donos regenera
      # em BACKGROUND (≤30 min): quem edita e recalibra na mesma janela via o painel gritar "precisa
      # recalibrar" para sempre — o calibrado já é o novo, o índice ainda tem o velho. Se a calibração
      # é MAIS NOVA que o índice, o tl_checksum de lá é sabidamente velho: não dá p/ concluir stale.
      | (($t.at // 0) > ($idx_at // 0)) as $tl_newer_than_index
      | (($t.checksum // "") != "" and (.tl_checksum // "") != "" and ($t.checksum != .tl_checksum)
         and ($tl_newer_than_index | not)) as $stale
      # linguagens good SEM TL servido = solução good que não calibrou (o TL servido é a UNIÃO entre
      # hosts, então ausente = falhou em TODOS os juízes). Só vale p/ calibração ATUAL (senão é "stale").
      | ([ (.good_langs // [])[] | (if .=="py3" or .=="py2" then "py" else . end)
           | select(. as $g | ($SUP|index($g)) and (($t.tl // {})|has($g)|not)) ] | unique) as $miss
      | ($cal and ($stale|not) and ($miss|length>0)) as $gsnotl
      | (($vstate=="error") or $gsbad) as $err
      | (.public and ($cal|not)) as $pubuncal            # público mas SEM calibração (sem TL p/ o aluno)
      | (.public and ($vstate=="none")) as $pubunval     # público mas SEM relatório de validação
      # SOLUÇÕES x o que a categoria delas tem de fazer (lib/calib-expect.sh, gravado pelo
      # /judge/calib-report). `stale` = o pacote mudou depois (problem_commit) ou o TL está velho;
      # `partial` = há solução do pacote sem resultado (calibração rápida só roda as good).
      | ($cx[$id]) as $cs
      | (if $cs == null then "none" elif (($cs.stale // false) or $stale) then "stale"
         elif (($cs.bad // 0) > 0) then "bad" elif (($cs.missing // 0) > 0) then "partial"
         elif (($cs.note // 0) > 0) then "note" else "ok" end) as $sstate
      # ENTRADAS: o validador de entrada que a calibração rodou (none = o pacote não tem validador)
      | ($cs.validator // {}) as $cv
      | (if $cs == null or (($cs.stale // false) or $stale) then "unknown" else ($cv.state // "unknown") end) as $istate
      | ($sstate == "bad") as $solbad
      | ($istate == "invalid" or $istate == "error") as $inbad
      # ISSUES abertas (lib/problem-issues.sh): a revisão da banca — aberta = o problema não está pronto
      | (($iss[$id] // 0) | tonumber? // 0) as $nis
      # NÃO JULGÁVEL com os juízes de hoje: a largura/memória (2b, a regra do escalonador) ou NENHUMA das
      # linguagens declaradas roda em juiz algum (o problema "só-X" com X fora dos juízes)
      | ((.languages // []) | map(if . == "py2" or . == "py3" then "py" else . end)) as $pl
      | (($pl | length) > 0 and ($supn | length) > 0 and ($pl | all(. as $l | ($supn | index($l)) == null))) as $langbad
      | (if $njm[$id] != null then $njm[$id]
         elif $langbad then {code:"langs", need:($pl | join(" ")), max:""} else null end) as $nj
      | (if $nj != null then ("not_judgeable:" + ([$nj.code, ($nj.need | tostring), (($nj.max // "") | tostring)] | join(",")))
         else null end) as $njcode
      | ($err or $gsnotl or $pubuncal or $pubunval or $solbad or $inbad or ($nis > 0) or ($nj != null)) as $review
      # `untitled` = não há título em lugar nenhum (nem no pacote, nem no enunciado — o índice então
      # carimba o slug). O Painel marca esses p/ o dono nomear; não é erro, é um "por nomear".
      | ((((.title // "") == "") or ((.title // "") == (.prob // ""))) ) as $untitled
      | { id:$id, title:(.title // .prob // $id), untitled:$untitled, owner:.owner, author:.author, public:.public,
          collaborators:(.collaborators // []),
          validated:$vstate,
          calibrated:$cal,
          sols:{state:$sstate, bad:($cs.bad // 0), note:($cs.note // 0), missing:($cs.missing // 0),
                total:($cs.total // 0), at:($cs.at // null)},
          inputs:{state:$istate, invalid:($cv.invalid // 0), total:($cv.total // 0)},
          open_issues:$nis,
          judgeable:(if $nj != null then ($nj + {ok:false}) else {ok:true} end),
          being_calibrated:(($calset[$id]) // false),
          stale:$stale,
          needs_recalibration:($cal and $stale),
          good_sol_no_tl:$gsnotl,
          good_sol_missing_langs:$miss,
          public_unvalidated:$pubunval,
          error:$err,
          needs_review:$review,
          review_reasons:([ (if $vstate=="error" then "validation_failed" else empty end),
                            (if $gsbad then "good_sol_rejected" else empty end),
                            (if $gsnotl then ("good_sol_no_tl:" + ($miss|join(","))) else empty end),
                            (if $pubuncal then "public_uncalibrated" else empty end),
                            (if $pubunval then "public_unvalidated" else empty end),
                            (if $solbad then ("sols_divergent:" + (($cs.bad // 0)|tostring)) else empty end),
                            (if $inbad then (if $istate == "error" then "inputs_error"
                                             else ("inputs_invalid:" + (($cv.invalid // 0)|tostring)) end)
                             else empty end),
                            (if $nis > 0 then ("issues_open:" + ($nis|tostring)) else empty end),
                            (if $njcode != null then $njcode else empty end) ]),
          # PENDÊNCIAS p/ o problema estar PRONTO (o selo do editor, o card "prontos" do Painel e a
          # confirmação de publicar). Diferente de review_reasons, entra também o que NÃO foi conferido
          # (pacote/soluções sem resultado): pronto é afirmação, não ausência de alarme.
          pending:([ (if $njcode != null then $njcode else empty end),
                     (if $vstate=="error" then "package_failed" elif $vstate=="none" then "package_unchecked" else empty end),
                     (if ($cal|not) then "uncalibrated" elif $stale then "needs_recalibration" else empty end),
                     (if $gsnotl then ("good_no_tl:" + ($miss|join(","))) else empty end),
                     (if $solbad then ("sols_divergent:" + (($cs.bad // 0)|tostring))
                      elif ($sstate == "none" or $sstate == "stale" or $sstate == "partial") and $cal and ($stale|not)
                        then "sols_unchecked" else empty end),
                     (if $inbad then (if $istate == "error" then "inputs_error"
                                      else ("inputs_invalid:" + (($cv.invalid // 0)|tostring)) end)
                      else empty end),
                     (if $nis > 0 then ("issues_open:" + ($nis|tostring)) else empty end) ]),
          error_reasons:([ (if $vstate=="error" then "validation_failed" else empty end),
                           (if $gsbad then "good_sol_rejected" else empty end) ]),
          # TL EFETIVO: o `tl` do sumário é o CALIBRADO CRU (a projeção só lê hosts[].tl) — sem
          # o overlay, o Painel mostrava um número que o juiz não usa. O override vem CARIMBADO
          # no índice de donos (gen-problem-owners.sh), então isto não abre pacote nenhum: o
          # Painel é rota quente e lista os 1400 problemas de um .admin.
          # ⚠ `$ovr`/`$cal` são ligados ANTES do reduce: lá dentro o `.` é o ACUMULADOR, não o
          # problema (a mesma armadilha de escopo do jq que já mordeu o gate de UA).
          time_limits:( (.tl_override // {}) as $ovr | ($t.tl // {}) as $cal
                        | if ($ovr|length) == 0 then $cal
                          else ((($cal|keys) + ($ovr|keys)) | unique) as $ks
                               | reduce $ks[] as $k ({};
                                   .[$k] = ($ovr[$k] // $ovr["default"] // $cal[$k]))
                               | with_entries(select(.value != null) | .value |= tostring)
                          end ),
          time_limits_calibrated:($t.tl // {}),
          tl_override:(.tl_override // {}),
          updated_at:($t.at // null),
          validated_at:($v.at // null),
          render_warnings:($v.render_warnings // "") }
      | . + {ready:((.pending | length) == 0)} ] as $rows
  | { success:true, total:($rows|length),
      counts:{
        validated:          ([$rows[]|select(.validated=="ok")]|length),
        validation_error:   ([$rows[]|select(.validated=="error")]|length),
        unvalidated:        ([$rows[]|select(.validated=="none")]|length),
        calibrated:         ([$rows[]|select(.calibrated)]|length),
        uncalibrated:       ([$rows[]|select(.calibrated|not)]|length),
        being_calibrated:   ([$rows[]|select(.being_calibrated)]|length),
        needs_recalibration:([$rows[]|select(.needs_recalibration)]|length),
        good_sol_no_tl:     ([$rows[]|select(.good_sol_no_tl)]|length),
        public_unvalidated: ([$rows[]|select(.public_unvalidated)]|length),
        needs_review:       ([$rows[]|select(.needs_review)]|length),
        ready:              ([$rows[]|select(.ready)]|length),
        sols_divergent:     ([$rows[]|select(.sols.state=="bad")]|length),
        sols_unchecked:     ([$rows[]|select(.pending|index("sols_unchecked"))]|length),
        inputs_invalid:     ([$rows[]|select(.inputs.state=="invalid" or .inputs.state=="error")]|length),
        issues_open:        ([$rows[]|select(.open_issues > 0)]|length),
        not_judgeable:      ([$rows[]|select(.judgeable.ok|not)]|length),
        errors:             ([$rows[]|select(.error)]|length) },
      calibrating_ids:[$rows[]|select(.being_calibrated)|.id],
      attention_ids:  [$rows[]|select(.needs_review or .needs_recalibration)|.id],
      judge_capacity: $CAPJ,
      problems:$rows }' <<<"$vis" 2>&1)" \
  || fail 500 "Falha ao montar o painel: $(printf '%s' "$out" | head -c 200)" "status_failed"
[[ -n "$out" ]] || fail 500 "Painel vazio (o jq não produziu saída)" "status_failed"
emit_json 200 OK
printf '%s' "$out"
