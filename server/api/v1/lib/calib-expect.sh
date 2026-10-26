# lib/calib-expect.sh — O QUE CADA CATEGORIA DE SOLUÇÃO TEM DE FAZER NA CALIBRAÇÃO (fonte única).
#
# Relato do Arthur Botelho (22/09/2026): "se uma solução TLE receber WA ou o contrário, marca ok", e o
# problema seguia "validado" com solução de veredicto errado. O juízo morava só no navegador (`solOk` do
# editor), lia a STRING do veredicto e errava em três casos:
#   - com TLE e WA na mesma solução, o TLE vence a string e o WA some;
#   - em problema pontuado a string era `Wrong,Np` (até 24/09/2026 — hoje traz o pior teste) e um slow
#     que deu TLE aparecia "revisar";
#   - wrong com CE/UE/"linguagem indisponível" contava como ok (não prova nada sobre os testes).
# E nada disso chegava ao Painel. Aqui o juízo olha o CÓDIGO DE CADA TESTE (`tests[].code`) e o TL
# EFETIVO (o servido, com TLOVERRIDE): a calibração mede sem o override (MOJ_CALIBRATING=1), então uma
# good acima de um override baixo passava na calibração e tomava TLE no julgamento.
#
#   categoria │ ok (✓)                        │ note (≈ certo, outro motivo)  │ bad (✗)
#   good      │ todos AC, tempo ≤ TL efetivo  │ TLE com ALLOWTLE…=y           │ algum não-AC · tempo > TL efetivo
#   pass      │ todos AC, tempo ≤ TL efetivo  │ —                             │ algum não-AC · tempo > TL efetivo
#   (TL efetivo = TLOVERRIDE › calibrado, MAIS a tolerância TLMOD[<lang>|default.drift] — a conta do juiz)
#   slow      │ ≥1 TLE, o resto AC            │ ≥1 TLE + WA/RE/MLE em outros  │ nenhum TLE
#   wrong     │ ≥1 WA                         │ falhou só por TLE/MLE/RE      │ todos AC
#   qualquer  │ norun: CE, UE, linguagem indisponível, sem veredicto (a solução não exercitou os testes)
#
# OS DOIS MÉTODOS DE TL (26/10/2026; mojtools tl-methods.sh, cdmoj/docs/PACOTE.md "Métodos de TL"): o juiz
# julga pass/slow/wrong pelo método do conf (`code`, `tl`) E pelo outro (`code_alt`, `tl_alt`), e a linha
# diz qual é qual (`method`). `calx(…; $m; $kp)` avalia pelo método `$m`: os códigos do próprio método, senão
# os alternativos — trocar o TLMETHOD do conf não perde o juízo. Linha sem o juízo por `$m` (calibrada antes,
# ou juiz anterior) = `unmeasured` (fica fora do sumário: conta como solução sem resultado). No Kattis entram
# as MARGENS da spec ($kp = {a, b}):
#   good  │ ≈ tl_no_margin: aceita, mas a × tmax > TL (só com TLOVERRIDE abaixo: o servido é ≥ a × W de cada juiz)
#   slow  │ ✓ só se algum teste com TLE passou de b × TL (`ratio` = o maior tempo/TL); ≈ tle_no_margin (é o
#         │ "no such multiple" da spec, sem bloquear); ≈ tle_unmeasured (o teste morreu no teto `etl` < b × TL)
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
# calx_tests($m): os testes da solução pelo método $m — [{c, t, tl}] —, ou null se a linha não tem esse juízo.
# As good rodam com o TL fictício da calibração: o juízo delas é por TEMPO (contra o servido), qualquer método.
def calx_tests($m):
  if (.category // "") == "good" or ((.method // "moj") == $m) then
    [ (.tests // [])[] | {c: ((.code // "") | calx_cls), t: (.time | calx_num), tl: (.tl | calx_num)} ]
  elif ((.tests // []) | length) > 0 and ((.tests // []) | all(has("code_alt"))) then
    [ (.tests // [])[] | {c: ((.code_alt // "") | calx_cls), t: (.time | calx_num), tl: (.tl_alt | calx_num)} ]
  else null end;
# calx($eff; $allowtle; $drift; $m; $kp): a expectativa de UMA solução pelo método $m. $eff = TL efetivo
# {lang:"seg"} DESSE método; $allowtle = bool; $drift = a TOLERÂNCIA do conf {lang|default: seg} (calx_drift)
# — o juiz só dá TLE acima de TL + tolerância (mojtools/build-and-test.sh), então "good mais lenta que o TL"
# também só é divergente acima dela; $kp = {a, b} do Kattis (tl_conf_kattis).
def calx($eff; $allowtle; $drift; $m; $kp):
  (.category // "") as $cat
  | calx_tests($m) as $tsm
  | ($tsm // []) as $ts
  | ($ts | reduce .[] as $x ({AC: 0, WA: 0, TLE: 0, MLE: 0, RE: 0, UE: 0, X: 0}; .[$x.c] += 1)) as $n
  | ($ts | length) as $tot
  | (.verdict // "" | tostring) as $v
  | ([ $ts[] | select(.c == "AC") | (.t // 0) ] | max) as $tmax
  | ((($eff // {})[(.lang // "")] // ($eff // {})["default"]) | calx_num) as $tl
  | (((($drift // {})[(.lang // "")] // ($drift // {})["default"] // 0) | calx_num) // 0) as $d
  # a folga de 1e-9 é a da aritmética: o juiz decide em decimal exato (bc), o jq em ponto flutuante
  | (($tl != null) and ($tmax != null) and ($tmax > ($tl + $d + 0.000000001))) as $over
  | ($n.WA + $n.RE + $n.MLE) as $wrongish
  # MARGENS do Kattis: a = ac_to_time_limit (good), b = time_limit_to_tle (slow); a maior razão tempo/TL entre
  # os testes que deram TLE; o teto de tempo de cada teste (`etl`) diz se a margem chegou a ser medida
  | ($m == "kattis") as $isk
  | ((($kp // {}).a | calx_num) // 2) as $ka | ((($kp // {}).b | calx_num) // 1.5) as $kb
  | ([ $ts[] | select(.c == "TLE" and .t != null and .tl != null and .tl > 0) | (.t / .tl) ] | max) as $rmax
  | ((.etl // null) | calx_num) as $etl
  | ([ $ts[] | select(.c == "TLE" and .tl != null) | .tl ] | max) as $tltle
  | (if ($cat | IN("good", "pass", "slow", "wrong") | not) then {state: "skip", why: "category"}
     elif ($v | test("^Compilation Error")) then {state: "norun", why: "ce"}
     elif ($v | test("not availa"; "i")) then {state: "norun", why: "lang"}
     elif $tsm == null then {state: "unmeasured", why: "other_method"}
     elif ($n.UE > 0) or ($n.X > 0) then {state: "norun", why: "ue"}
     elif $tot == 0 then {state: "norun", why: "noverdict"}
     elif ($cat == "good") or ($cat == "pass") then
       (if $n.AC == $tot then
          (if $over then {state: "bad", why: "over_tl"}
           elif $isk and ($cat == "good") and ($tl != null) and ($tmax != null) and (($ka * $tmax) > ($tl + 0.000000001))
             then {state: "note", why: "tl_no_margin"}
           else {state: "ok", why: "all_ac"} end)
        elif ($cat == "good") and $allowtle and ($n.TLE > 0) and ($wrongish == 0) then {state: "note", why: "tle_allowed"}
        else {state: "bad", why: "failed"} end)
     elif $cat == "slow" then
       (if ($n.TLE > 0) and ($wrongish == 0) then
          (if ($isk | not) then {state: "ok", why: "tle"}
           elif ($rmax != null) and ($rmax >= ($kb - 0.000000001)) then {state: "ok", why: "tle"}
           elif ($etl != null) and ($tltle != null) and ($etl < ($kb * $tltle - 0.000000001))
             then {state: "note", why: "tle_unmeasured"}
           else {state: "note", why: "tle_no_margin"} end)
        elif $n.TLE > 0 then {state: "note", why: "tle_and_wrong"}
        elif $wrongish > 0 then {state: "bad", why: "wrong_no_tle"}
        else {state: "bad", why: "no_tle"} end)
     else
       (if $n.WA > 0 then {state: "ok", why: "wa"}
        elif ($n.TLE + $n.MLE + $n.RE) > 0 then {state: "note", why: "failed_other"}
        else {state: "bad", why: "accepted"} end)
     end)
  + {counts: ($n | del(.X) | with_entries(select(.value > 0))), tmax: $tmax, tl: $tl, drift: $d, method: $m}
  + (if $isk and ($cat == "good") then {need: $ka} elif $isk and ($cat == "slow") then {need: $kb, ratio: $rmax, etl: $etl} else {} end);
# calx($eff; $allowtle; $drift): a expectativa de UMA solução pelo método MOJ (a forma de antes dos dois métodos).
def calx($eff; $allowtle; $drift): calx($eff; $allowtle; $drift; "moj"; {});
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
# `unmeasured` (sem o juízo pelo método avaliado) fica de fora: a solução conta como sem resultado (`missing`).
def calx_sum($hs; $files):
  [ $hs[] | (.sols // [])[] | select((.category // "") | IN("good", "pass", "slow", "wrong"))
    | select((.expect.state // "") != "unmeasured")
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
# calx_drift <pkgdir> -> {lang: seg, default: seg}: a TOLERÂNCIA acima do TL antes de TLE, das linhas
# TLMOD[<lang>.drift] / TLMOD[default.drift] do conf (a específica vence no calx; a última linha vence entre
# repetidas, como no `source` do juiz). Por grep, como o tl_conf_overrides — o conf é código do autor.
calx_drift(){
  local conf="$1/conf" c=""
  [[ -n "$1" && -f "$conf" ]] && c="$(<"$conf")" 2>/dev/null
  [[ "$c" == *drift* ]] || { echo '{}'; return; }
  sed -nE 's/^[[:space:]]*TLMOD\[([A-Za-z0-9]{1,16})\.drift\]=["'"'"']?([0-9]+\.?[0-9]*|\.[0-9]+)["'"'"']?[[:space:]]*(#.*)?$/\1\t\2/p' "$conf" 2>/dev/null \
    | jq -Rnc '[inputs | split("\t") | select(length == 2)
                | {((.[0] | if . == "py3" or . == "py2" then "py" elif . == "cc" or . == "cxx" or . == "c++" or . == "hpp" then "cpp" elif . == "h" then "c" else . end)): (.[1] | tonumber)}]
               | add // {}'
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
# _calx_locked <id> <comando…> — o flock POR PROBLEMA do sumário de calibração (run/calib-sum/<id>.lock): dois
# calib-report juntos calculavam o sumário cada um com os arquivos de host que via, e o último `mv` podia deixar
# um juiz de fora. Ordem dos locks: o diretório run/calib/<id> (calib-report) → este → o do sumário agregado.
_calx_locked(){
  local id="$1"; shift
  mkdir -p "$CALX_SUM_DIR" 2>/dev/null
  ( flock -w 10 9 || exit 75; "$@" ) 9>>"$CALX_SUM_DIR/$id.lock"
}
calx_summary_write(){ _calx_locked "$1" _calx_summary_write_locked "$1"; }
_calx_summary_write_locked(){
  local id="$1" pkg ver eff allow drift files d out t meth=moj kp
  pkg="$(pkg_path "$id")"; [[ -n "$pkg" && -d "$pkg" ]] || return 0
  d="$CALIB_DIR/$id"; [[ -d "$d" ]] || return 0
  ver="$(pkg_judge_version "$pkg" "$id" 2>/dev/null)"; ver="${ver//[^0-9a-f]/}"
  # o MÉTODO do TL do conf AGORA (o sumário do Painel segue o método que vale) + os parâmetros do Kattis
  tl_conf_method_to meth "$pkg"; kp="$(tl_conf_kattis "$pkg")"; [[ -n "$kp" ]] || kp='{}'
  eff="$(tl_store_served "$id" "" "" "$meth" 2>/dev/null)"; jq -e 'type == "object"' >/dev/null 2>&1 <<<"$eff" || eff='{}'
  allow="$(calx_allowtle "$pkg")"
  drift="$(calx_drift "$pkg")"; [[ -n "$drift" ]] || drift='{}'
  files="$(calx_pkg_files "$pkg")"; [[ -n "$files" ]] || files='[]'
  mkdir -p "$CALX_SUM_DIR" 2>/dev/null
  out="$(calx_summary_file "$id")"; t="$out.tmp.${BASHPID}"   # nome resolvido ANTES do redirect
  find "$d" -maxdepth 1 -name '*.json' -type f -exec cat {} + 2>/dev/null \
    | jq -sc --arg id "$id" --arg ver "$ver" --argjson eff "$eff" --argjson allow "$allow" --argjson drift "$drift" \
        --arg m "$meth" --argjson kp "$kp" \
        --argjson files "$files" --argjson now "$EPOCHSECONDS" "$CALX_JQ"'
        map(select(.host) | select(($ver == "") or ((.checksum // "") == "") or (.checksum == $ver))
            | {host, sols: ((.sols // []) | map(. + {expect: calx($eff; $allow; $drift; $m; $kp)}))})
        | calx_sum(.; $files) + {id: $id, version: $ver, at: $now, stale: false, method: $m}' > "$t" 2>/dev/null \
    && [[ -s "$t" ]] && mv -f "$t" "$out" || { rm -f "$t"; return 1; }
  calx_summary_upsert "$id"
}
# calx_mark_stale <id> — o pacote mudou naquilo que a calibração exercita (sols/, tests/, scripts/,
# conf): o resultado das soluções deixou de ser o de AGORA. Chamado pelo problem_commit. Barato: só
# mexe se já existe sumário e ele ainda não está marcado.
calx_mark_stale(){ [[ -s "$(calx_summary_file "$1")" ]] || return 0; _calx_locked "$1" _calx_mark_stale_locked "$1"; }
_calx_mark_stale_locked(){
  local f t; f="$(calx_summary_file "$1")"
  [[ -s "$f" ]] || return 0
  jq -e '.stale == true' "$f" >/dev/null 2>&1 && return 0
  t="$f.tmp.${BASHPID}"
  jq -c '.stale = true' "$f" > "$t" 2>/dev/null && [[ -s "$t" ]] && mv -f "$t" "$f" || { rm -f "$t"; return 0; }
  calx_summary_upsert "$1"
}
# calib_state_drop <id> — o diretório da calibração por host (run/calib/<id>: logs, sols, reports HTML) e o
# sumário das soluções. Sob o lock do diretório (o mesmo que o /judge/calib-report segura): um report em curso
# termina antes, e o que esperava o lock re-confere o pacote e responde 404.
calib_state_drop(){
  local id="$1" d="$CALIB_DIR/$1"
  [[ -n "$id" ]] || return 0
  if [[ -d "$d" ]]; then ( exec 8>>"$d/.lock"; flock -w 20 8; rm -rf "$d" ); fi
  calx_drop "$id"
}
# calib_state_move <old> <new> — move entre orgs: o diretório vai junto e o sumário é REFEITO no id novo (antes
# saía do antigo e nunca nascia no novo: o Painel dizia "sem calibração" com o TL servido)
calib_state_move(){
  local old="$1" new="$2" d="$CALIB_DIR/$1"
  [[ -n "$old" && -n "$new" && "$old" != "$new" ]] || return 0
  if [[ -d "$d" && ! -e "$CALIB_DIR/$new" ]]; then ( exec 8>>"$d/.lock"; flock -w 20 8; mv "$d" "$CALIB_DIR/$new" ); fi
  calx_drop "$old"
  [[ -d "$CALIB_DIR/$new" ]] && calx_summary_write "$new"
  return 0
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
