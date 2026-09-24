# lib/calib-expect.sh — O QUE CADA CATEGORIA DE SOLUÇÃO TEM DE FAZER NA CALIBRAÇÃO (fonte única).
#
# Relato do Arthur Botelho (22/09/2026): "se uma solução TLE receber WA ou o contrário, marca ok", e o
# problema seguia "validado" com solução de veredicto errado. O juízo morava só no navegador (`solOk` do
# editor), lia a STRING do veredicto e errava em três casos:
#   - com TLE e WA na mesma solução, o TLE vence a string e o WA some;
#   - em problema pontuado a string é `Wrong,Np` e um slow que deu TLE aparecia "revisar";
#   - wrong com CE/UE/"linguagem indisponível" contava como ok (não prova nada sobre os testes).
# E nada disso chegava ao Painel. Aqui o juízo olha o CÓDIGO DE CADA TESTE (`tests[].code`) e o TL
# EFETIVO (o servido, com TLOVERRIDE): a calibração mede sem o override (MOJ_CALIBRATING=1), então uma
# good acima de um override baixo passava na calibração e tomava TLE no julgamento.
#
#   categoria │ ok (✓)                        │ note (≈ certo, outro motivo)  │ bad (✗)
#   good      │ todos AC, tempo ≤ TL efetivo  │ TLE com ALLOWTLE…=y           │ algum não-AC · tempo > TL efetivo
#   pass      │ todos AC, tempo ≤ TL efetivo  │ —                             │ algum não-AC · tempo > TL efetivo
#   slow      │ ≥1 TLE, o resto AC            │ ≥1 TLE + WA/RE/MLE em outros  │ nenhum TLE
#   wrong     │ ≥1 WA                         │ falhou só por TLE/MLE/RE      │ todos AC
#   qualquer  │ norun: CE, UE, linguagem indisponível, sem veredicto (a solução não exercitou os testes)
#
# Quem usa: handlers/problems/calib.sh (serve `expect` por solução + `summary`), handlers/judge/
# calib-report.sh (grava o sumário do Painel), lib/problems.sh (problem_commit marca stale),
# server/bin/calib-summary-rebuild.sh. A tela e a CLI só MOSTRAM `expect` — nunca reescreva a regra lá.
# ⚠ O jq mora em VARIÁVEL: o jq-portability.sh não o compila. Rode o smoke-calib-expect.sh com o jq 1.7.
: "${RUNDIR:=/home/ribas/moj/run}"; : "${CALIB_DIR:=$RUNDIR/calib}"
: "${CALX_SUM_DIR:=$RUNDIR/calib-sum}"        # um <id>.json por problema (entrada pronta do sumário)
: "${CAL_SUMMARY:=$RUNDIR/calib-summary.json}" # mapa id→entrada que o /problems/status lê (upsert por evento)

CALX_JQ='
def calx_cls: if . == "AC" or . == "AC,PE" then "AC" elif . == "WA" then "WA" elif . == "TLE" then "TLE"
  elif . == "MLE" then "MLE" elif . == "RE" or . == "RE_NZEC" or . == "TMT" then "RE"
  elif . == "UE" then "UE" else "X" end;
def calx_num: if type == "number" then . elif . == null then null else (tostring | tonumber? // null) end;
# calx($eff; $allowtle): a expectativa de UMA solução. $eff = TL efetivo {lang:"seg"}; $allowtle = bool.
def calx($eff; $allowtle):
  (.category // "") as $cat
  | [ (.tests // [])[] | {c: ((.code // "") | calx_cls), t: (.time | calx_num)} ] as $ts
  | ($ts | reduce .[] as $x ({AC: 0, WA: 0, TLE: 0, MLE: 0, RE: 0, UE: 0, X: 0}; .[$x.c] += 1)) as $n
  | ($ts | length) as $tot
  | (.verdict // "" | tostring) as $v
  | ([ $ts[] | select(.c == "AC") | (.t // 0) ] | max) as $tmax
  | ((($eff // {})[(.lang // "")] // ($eff // {})["default"]) | calx_num) as $tl
  | (($tl != null) and ($tmax != null) and ($tmax > $tl)) as $over
  | ($n.WA + $n.RE + $n.MLE) as $wrongish
  | (if ($cat | IN("good", "pass", "slow", "wrong") | not) then {state: "skip", why: "category"}
     elif ($v | test("^Compilation Error")) then {state: "norun", why: "ce"}
     elif ($v | test("not availa"; "i")) then {state: "norun", why: "lang"}
     elif ($n.UE > 0) or ($n.X > 0) then {state: "norun", why: "ue"}
     elif $tot == 0 then {state: "norun", why: "noverdict"}
     elif ($cat == "good") or ($cat == "pass") then
       (if $n.AC == $tot then (if $over then {state: "bad", why: "over_tl"} else {state: "ok", why: "all_ac"} end)
        elif ($cat == "good") and $allowtle and ($n.TLE > 0) and ($wrongish == 0) then {state: "note", why: "tle_allowed"}
        else {state: "bad", why: "failed"} end)
     elif $cat == "slow" then
       (if ($n.TLE > 0) and ($wrongish == 0) then {state: "ok", why: "tle"}
        elif $n.TLE > 0 then {state: "note", why: "tle_and_wrong"}
        elif $wrongish > 0 then {state: "bad", why: "wrong_no_tle"}
        else {state: "bad", why: "no_tle"} end)
     else
       (if $n.WA > 0 then {state: "ok", why: "wa"}
        elif ($n.TLE + $n.MLE + $n.RE) > 0 then {state: "note", why: "failed_other"}
        else {state: "bad", why: "accepted"} end)
     end)
  + {counts: ($n | del(.X) | with_entries(select(.value > 0))), tmax: $tmax, tl: $tl};
# calx_val: o resultado do VALIDADOR DE ENTRADA de um host (entrada category=="validator" do sols).
#   verdict: none (pacote sem validador) | ok | invalid | error (não compilou / infra)
def calx_val:
  (.verdict // "" | tostring | ascii_downcase | split(",")[0]) as $v
  | [ (.tests // [])[] | (.code // "" | tostring) ] as $cs
  | { state: (if ($v | IN("none", "ok", "invalid", "error")) then $v else "error" end),
      total: ($cs | length),
      invalid: ([ $cs[] | select(. == "INVALID") ] | length),
      failed: ([ $cs[] | select(. == "FAIL") ] | length) };
# calx_sum($hs; $files): o sumário de um problema a partir dos hosts ATUAIS (já filtrados por versão).
#   $hs    = [ {host, sols:[… cada uma já com .expect]} ]
#   $files = ["good/a.cpp", "wrong/b.py", …] — as soluções que o PACOTE tem hoje (upcoming fica fora)
# Uma solução conta como `bad` se é bad/norun em ALGUM host; `note` se não é bad em nenhum e é note em
# algum. `missing` = solução do pacote sem resultado em host nenhum (calibração rápida só roda as good).
def calx_sum($hs; $files):
  [ $hs[] | (.sols // [])[] | select((.category // "") | IN("good", "pass", "slow", "wrong"))
    | {k: ((.category // "") + "/" + (.file // "")), s: (.expect.state // "")} ] as $r
  | ($r | group_by(.k) | map({k: .[0].k, st: map(.s)})) as $by
  | [ $by[] | select(.st | any(. == "bad" or . == "norun")) | .k ] as $bad
  | [ $by[] | select((.st | any(. == "bad" or . == "norun")) | not) | select(.st | any(. == "note")) | .k ] as $note
  | ($by | map(.k)) as $seen
  | [ ($files // [])[] | select(. as $f | ($seen | index($f)) | not) ] as $missing
  | [ $hs[] | (.sols // [])[] | select(.category == "validator") | calx_val ] as $vs
  | { hosts: ($hs | length), total: ($by | length), bad: ($bad | length), note: ($note | length),
      bad_files: $bad, note_files: $note, missing: $missing,
      validator: (if ($vs | length) == 0 then {state: "unknown", total: 0, invalid: 0, failed: 0}
                  else ($vs | sort_by(if .state == "error" then 0 elif .state == "invalid" then 1
                                      elif .state == "ok" then 2 else 3 end) | .[0])
                       + {invalid: ($vs | map(.invalid) | max)} end) };
'
# a projeção que vai ao mapa do Painel (run/calib-summary.json): só o que o /problems/status usa
_CALX_SUM_PROG='{at: (.at // null), stale: (.stale // false), hosts: (.hosts // 0), total: (.total // 0),
   bad: (.bad // 0), note: (.note // 0), missing: ((.missing // []) | length), validator: (.validator // null)}'

# calx_allowtle <pkgdir> -> true|false: o conf do pacote tem ALLOWTLEDURINGCALIBRATION=y? (grep: o conf
# é CÓDIGO do autor e o servidor nunca o source-a — mesma regra do tl_conf_overrides)
calx_allowtle(){
  local c=""; [[ -n "$1" && -f "$1/conf" ]] && c="$(<"$1/conf")" 2>/dev/null
  [[ "$c" == *ALLOWTLEDURINGCALIBRATION* ]] \
    && grep -qE '^[[:space:]]*ALLOWTLEDURINGCALIBRATION=["'"'"']?[yY]' "$1/conf" 2>/dev/null \
    && { echo true; return; }
  echo false
}
# calx_pkg_files <pkgdir> -> ["good/a.cpp", …] — as soluções que a calibração deve rodar. O calibreitor
# percorre sols/<cat>/* (o glob não pega arquivo oculto); a API roda com noglob, então é find.
calx_pkg_files(){
  local p="$1" c
  [[ -n "$p" && -d "$p/sols" ]] || { echo '[]'; return; }
  for c in good pass slow wrong; do
    [[ -d "$p/sols/$c" ]] || continue
    find "$p/sols/$c" -mindepth 1 -maxdepth 1 -type f ! -name '.*' -printf "$c/%f\n" 2>/dev/null
  done | LC_ALL=C sort | jq -Rsc 'split("\n") | map(select(length > 0))'
}

calx_summary_file(){ printf '%s/%s.json' "$CALX_SUM_DIR" "$1"; }   # id tem '#', não tem '/'
calx_summary_upsert(){ _summary_upsert "$1" "$(calx_summary_file "$1")" "$_CALX_SUM_PROG" "$CAL_SUMMARY"; }
calx_summary_ensure(){ mkdir -p "$CALX_SUM_DIR" 2>/dev/null; _summary_ensure "$CALX_SUM_DIR" "$_CALX_SUM_PROG" "$CAL_SUMMARY"; }

# calx_summary_write <id> — recalcula o sumário a partir de run/calib/<id>/<host>.json, só com os hosts
# que calibraram a VERSÃO ATUAL do pacote (a mesma regra de `stale` do /problems/calib). Chamado pelo
# /judge/calib-report (rota de juiz: pode abrir o pacote) e pelo bin/calib-summary-rebuild.sh.
calx_summary_write(){
  local id="$1" pkg ver eff allow files d out t
  pkg="$(pkg_path "$id")"; [[ -n "$pkg" && -d "$pkg" ]] || return 0
  d="$CALIB_DIR/$id"; [[ -d "$d" ]] || return 0
  ver="$(pkg_judge_version "$pkg" "$id" 2>/dev/null)"; ver="${ver//[^0-9a-f]/}"
  eff="$(tl_store_served "$id" 2>/dev/null)"; jq -e 'type == "object"' >/dev/null 2>&1 <<<"$eff" || eff='{}'
  allow="$(calx_allowtle "$pkg")"
  files="$(calx_pkg_files "$pkg")"; [[ -n "$files" ]] || files='[]'
  mkdir -p "$CALX_SUM_DIR" 2>/dev/null
  out="$(calx_summary_file "$id")"; t="$out.tmp.${BASHPID}"   # nome resolvido ANTES do redirect
  find "$d" -maxdepth 1 -name '*.json' -type f -exec cat {} + 2>/dev/null \
    | jq -sc --arg id "$id" --arg ver "$ver" --argjson eff "$eff" --argjson allow "$allow" \
        --argjson files "$files" --argjson now "$EPOCHSECONDS" "$CALX_JQ"'
        map(select(.host) | select(($ver == "") or ((.checksum // "") == "") or (.checksum == $ver))
            | {host, sols: ((.sols // []) | map(. + {expect: calx($eff; $allow)}))})
        | calx_sum(.; $files) + {id: $id, version: $ver, at: $now, stale: false}' > "$t" 2>/dev/null \
    && [[ -s "$t" ]] && mv -f "$t" "$out" || { rm -f "$t"; return 1; }
  calx_summary_upsert "$id"
}
# calx_mark_stale <id> — o pacote mudou naquilo que a calibração exercita (sols/, tests/, scripts/,
# conf): o resultado das soluções deixou de ser o de AGORA. Chamado pelo problem_commit. Barato: só
# mexe se já existe sumário e ele ainda não está marcado.
calx_mark_stale(){
  local f t; f="$(calx_summary_file "$1")"
  [[ -s "$f" ]] || return 0
  jq -e '.stale == true' "$f" >/dev/null 2>&1 && return 0
  t="$f.tmp.${BASHPID}"
  jq -c '.stale = true' "$f" > "$t" 2>/dev/null && [[ -s "$t" ]] && mv -f "$t" "$f" || { rm -f "$t"; return 0; }
  calx_summary_upsert "$1"
}
# calx_drop <id> — o problema deixou de existir com esse id (delete/move)
calx_drop(){
  local f; f="$(calx_summary_file "$1")"
  [[ -e "$f" ]] || return 0
  rm -f "$f"
  [[ -s "$CAL_SUMMARY" ]] || return 0
  ( flock 9; t="$CAL_SUMMARY.tmp.${BASHPID}"
    jq -c --arg id "$1" 'del(.[$id])' "$CAL_SUMMARY" > "$t" 2>/dev/null && [[ -s "$t" ]] && mv -f "$t" "$CAL_SUMMARY" || rm -f "$t"
  ) 9>>"$CAL_SUMMARY.lock"
}
