# lib/tl-sim.sh — SIMULAÇÃO E SUGESTÃO DO TEMPO-LIMITE a partir da calibração (26/10/2026). Pedido do Ribas:
# "simular como seria o TL com o Kattis com vários tempos de resolução, com os dados que a calibração já tem" e
# "sugerir a melhor configuração do TL, tanto na execução padrão como com o Kattis". Fonte única: o /problems/calib
# serve `tl_sim` e `tl_suggest`, e a web e o `moj calib` só MOSTRAM (traduzem os códigos). Nada roda de novo: tudo
# sai dos tempos que a calibração mediu, teste a teste, em cada juiz da versão atual do pacote.
#
#   W[L]   = o pior tempo de teste AC das good de L (piso 0,01 s), num juiz em que alguma good de L foi aceita — a
#            conta do calibreitor; o servido é o MÁX entre os juízes (a classe de hardware julga com ele, sched-lib).
#            default = o máx, entre os juízes, do menor W do juiz (o TL[default] de cada um é o menor).
#   MOJ    : TL = off + cf × W + 0,02 (cf = TLMOD[calibrafactor]; "A+B" no conf vira A + B × W, a conta do bc do
#            calibreitor); Kattis: TL = o menor múltiplo de r ≥ a × W, no mínimo r (tl_kattis do mojtools).
#   Depois, a MESMA regra do servidor (tl_eff, lib/tl-store.sh): TLMOD sum/mult e o TLOVERRIDE, que é final.
#
# Cada solução, em cada juiz, contra o TL de uma configuração (tolerância d = TLMOD[<lang>|default.drift]):
#   good/pass │ todo teste ≤ TL + d
#   slow MOJ  │ algum teste > TL + d          slow Kattis │ algum teste ≥ b × TL (a margem da spec)
#   O teste morto no teto `etl` só prova "≥ etl": se ele não decide, a solução fica "não medida" (unmeasured) e não
#   reprova a configuração. Falha que não depende do TL (WA/RE/MLE/UE) e as wrong ficam de fora.
#
# Sugestão: MOJ — o cf atual se vale, senão 1,35, senão o meio do intervalo válido [cf_min, cf_max), senão conflito
# (a solução que dá o piso e a que dá o teto). Kattis — o MAIOR r que vale (com o a e o b do conf), senão o a (mais
# perto do conf) que vale com o r do conf, senão o maior b ≤ o do conf que vale, senão conflito.
#
# ⚠ TLSIM_JQ usa calx_cls (CALX_JQ, lib/calib-expect.sh) e tl_eff (_TL_EFF_DEF, lib/tl-store.sh): componha DEPOIS
# deles. O jq mora em variável (o jq-portability.sh não o compila): rode o smoke-tl-sim.sh com o jq 1.7.

# tl_conf_cf <pkgdir> -> {"cf":1.35,"off":0} do TLMOD[calibrafactor] do conf (a última linha vence; sem source).
# "A+B" = {off:A, cf:B}; valor que o bc do calibreitor não entenderia como número = o padrão, com `raw`.
tl_conf_cf(){
  local conf="$1/conf" _c="" _l v=""
  [[ -n "$1" && -f "$conf" ]] && _c="$(<"$conf")" 2>/dev/null
  if [[ "$_c" == *calibrafactor* ]]; then
    while IFS= read -r _l; do
      [[ "$_l" =~ ^[[:space:]]*TLMOD\[calibrafactor\]=[\"\']?([^\"\'[:space:]#]*) ]] && v="${BASH_REMATCH[1]}"
    done <<<"$_c"
  fi
  jq -cn --arg v "$v" '
    def n: if test("^([0-9]+\\.?[0-9]*|\\.[0-9]+)$") then (if startswith(".") then "0" + . else . end | tonumber) else null end;
    if $v == "" then {cf: 1.35, off: 0}
    elif ($v | n) != null then {cf: ($v | n), off: 0}
    elif ($v | test("^[0-9.]+\\+[0-9.]+$")) and (($v | split("+")[0] | n) != null) and (($v | split("+")[1] | n) != null)
      then {cf: ($v | split("+")[1] | n), off: ($v | split("+")[0] | n)}
    else {cf: 1.35, off: 0, raw: $v} end'
}

TLSIM_JQ='
# número canônico (`. + 0`): o jq 1.7+ imprime o literal `2.0` do conf como veio, e a resposta tem de ser igual em todo jq
def tls_num: if type == "number" then . + 0 elif . == null then null else (tostring | tonumber? // null) end;
def tls_r6: ((. * 1000000) | round) / 1000000;
def tls_r2: ((. * 100) | round) / 100;
def tls_abs: if . < 0 then -. else . end;
# os casos: UMA solução num juiz da versão atual — {cat, file, lang, host, n, tmax (o maior tempo), wac (o maior AC),
# killed (algum teste morto no teto), etl, tdep (falha que não depende do TL), acc (aceita: good que conta p/ o W)}
def tls_cases($hx; $allowtle):
  [ $hx[] | select(.stale | not) | .host as $h | (.sols // [])[]
    | select((.category // "") | IN("good", "pass", "slow"))
    | ((.etl // null) | tls_num) as $etl
    | [ (.tests // [])[] | {c: ((.code // "") | calx_cls), t: (.time | tls_num)} ] as $ts
    | (.verdict // "" | tostring) as $v
    | {cat: .category, file: (.category + "/" + (.file // "")), lang: (.lang // ""), host: $h, n: ($ts | length),
       tmax: ([ $ts[] | .t // empty ] | max), wac: ([ $ts[] | select(.c == "AC") | .t // empty ] | max),
       killed: ([ $ts[] | select(.c == "TLE" and .t != null and $etl != null and .t >= ($etl - 0.000001)) ] | length > 0),
       etl: $etl, tdep: ([ $ts[] | select(.c | IN("WA", "RE", "MLE", "UE", "X")) ] | length > 0),
       acc: (($v | startswith("Accepted")) or ($allowtle and ($v | startswith("Time Limit")))),
       ce: (($v | test("^Compilation Error")) or ($v | test("not availa"; "i")))} ];
# W por juiz ({host: {lang: W}}, só linguagens com good aceita no juiz) e o servido ({lang: W, default})
def tls_wh($cases):
  [ $cases[] | select(.cat == "good") ] as $g
  | reduce ($g | map(.host) | unique)[] as $h ({};
      [ $g[] | select(.host == $h) ] as $gh
      | .[$h] = (reduce ([ $gh[] | select(.acc) | .lang ] | unique)[] as $L ({};
                   .[$L] = ([ $gh[] | select(.lang == $L) | .wac // 0 ] + [0.01] | max))));
def tls_w($wh):
  ([ $wh[] | keys[] ] | unique) as $ls
  | (reduce $ls[] as $L ({}; .[$L] = ([ $wh[] | .[$L] // empty ] | max)))
  + (([ $wh[] | select(length > 0) | [ .[] ] | min ] | max) as $d | if $d == null then {} else {default: $d} end);
# o TL CRU de uma configuração, por linguagem (números)
def tls_moj($w; $cf; $off): $w | map_values((($off + $cf * .) + 0.02) | tls_r6);
def tls_kat($w; $a; $r): $w | map_values((((($a * . / $r) - 0.000000001) | ceil) as $n | ([$n, 1] | max) * $r) | tls_r6);
# o efetivo (a regra do servidor) em números
def tls_eff($raw; $ov; $m): tl_eff($raw | map_values(tostring); $ov; $m) | map_values(tls_num);
# UMA solução num juiz contra o TL efetivo: ok | fail | unmeasured | skip
def tls_eval($c; $eff; $drift; $isk; $b):
  (($eff[$c.lang] // $eff.default) | tls_num) as $tl
  | (((($drift // {})[$c.lang] // ($drift // {}).default // 0) | tls_num) // 0) as $d
  | if $tl == null or $c.tdep or $c.ce or $c.n == 0 or $c.tmax == null then "skip"
    elif $c.cat == "slow" then
      (if $isk then ($b * $tl) else ($tl + $d) end) as $thr
      | if ($isk and ($c.tmax >= ($thr - 0.000000001))) or (($isk | not) and ($c.tmax > ($thr + 0.000000001))) then "ok"
        elif $c.killed then "unmeasured" else "fail" end
    elif $c.killed then (if ($tl + $d) < ($c.etl - 0.000000001) then "fail" else "unmeasured" end)
    elif $c.tmax > ($tl + $d + 0.000000001) then "fail" else "ok" end;
def tls_row($cases; $eff; $drift; $isk; $b):
  [ $cases[] | {f: .file, r: tls_eval(.; $eff; $drift; $isk; $b)} ] as $ev
  | {ok: ([ $ev[] | select(.r == "fail") ] | length == 0),
     fail: ([ $ev[] | select(.r == "fail") | .f ] | unique),
     unmeasured: ([ $ev[] | select(.r == "unmeasured") | .f ] | unique)};
# o intervalo de cf em que todas as soluções que dependem dele saem certas: [min, max) — piso das good/pass, teto
# das slow (a de teste morto no teto entra pelo etl: abaixo dele a configuração vale com certeza)
def tls_cfint($cases; $w; $ov; $m; $drift; $off):
  [ $cases[] | select((.tdep or .ce or .n == 0 or .tmax == null) | not)
    | . as $c
    | select((($ov // {})[$c.lang] // ($ov // {}).default) == null)
    | (($w[$c.lang] // $w.default) | tls_num) as $wl
    | (((($m // {}).sum // {})[$c.lang] // 0) | tls_num) as $s
    | (((($m // {}).mult // {})[$c.lang] // 1) | tls_num) as $x
    | (((($drift // {})[$c.lang] // ($drift // {}).default // 0) | tls_num) // 0) as $d
    | select($wl != null and $wl > 0 and $x != null and $x > 0)
    | (if $c.killed then $c.etl else $c.tmax end) as $t
    | ((((($t - $d) / $x) - $s - 0.02 - $off) / $wl)) as $cf
    | {f: $c.file, cf: $cf, k: (if $c.cat == "slow" then "max" else "min" end)} ] as $b
  | ([ $b[] | select(.k == "min") ] | max_by(.cf)) as $lo
  | ([ $b[] | select(.k == "max") ] | min_by(.cf)) as $hi
  | {min: (if $lo == null then null else ($lo.cf | tls_r6) end), min_by: ($lo.f // null),
     max: (if $hi == null then null else ($hi.cf | tls_r6) end), max_by: ($hi.f // null),
     n: ($b | length)};
# os limites do TL EFETIVO do Kattis que cada solução impõe, sem o arredondamento: good/pass pedem TL ≥ tmax − d; a
# lenta pede b × TL ≤ tmax. No conflito, nomeia a de piso mais alto e a lenta de teto mais baixo (o par que se cruza)
def tls_kbounds($cases; $ov; $drift; $b):
  [ $cases[] | select((.tdep or .ce or .n == 0 or .tmax == null or .killed) | not) | . as $c
    | select((($ov // {})[$c.lang] // ($ov // {}).default) == null)
    | (((($drift // {})[$c.lang] // ($drift // {}).default // 0) | tls_num) // 0) as $d
    | if $c.cat == "slow" then {f: $c.file, k: "max", v: ($c.tmax / $b)} else {f: $c.file, k: "min", v: ($c.tmax - $d)} end ] as $x
  | {pass: (([ $x[] | select(.k == "min") ] | max_by(.v)) // {} | .f // null),
     slow: (([ $x[] | select(.k == "max") ] | min_by(.v)) // {} | .f // null)};
def tls_in($i; $cf): ($i.min == null or $cf >= ($i.min - 0.000000001)) and ($i.max == null or $cf < ($i.max - 0.000000001));
# tl_sim + tl_suggest: $kp = {a, b, r} do conf; $cfc = {cf, off} (tl_conf_cf)
def tlsim($hx; $ov; $m; $drift; $kp; $cfc; $allowtle):
  tls_cases($hx; $allowtle) as $cases
  | tls_w(tls_wh($cases)) as $w
  | if ($w | length) == 0 then {tl_sim: null, tl_suggest: null}
    else
      (($cfc.cf // 1.35) | tls_num) as $cf0 | (($cfc.off // 0) | tls_num) as $off
      | (($kp.a // 2) | tls_num) as $ka | (($kp.b // 1.5) | tls_num) as $kb | (($kp.r // 1) | tls_num) as $kr
      | (($ov // {}) | keys) as $ovl
      | ([1, 1.2, 1.35, 1.5, 2, 2.5, 3, $cf0] | unique) as $cfs
      | ([0.01, 0.05, 0.1, 0.2, 0.5, 1, $kr] | unique) as $rs
      | [ $cfs[] as $cf | tls_eff(tls_moj($w; $cf; $off); $ov; $m) as $e
          | {cf: $cf, current: ($cf == $cf0), tl: $e} + tls_row($cases; $e; $drift; false; $kb) ] as $mrows
      | [ $rs[] as $r | tls_eff(tls_kat($w; $ka; $r); $ov; $m) as $e
          | {r: $r, current: ($r == $kr), tl: $e} + tls_row($cases; $e; $drift; true; $kb) ] as $krows
      | tls_cfint($cases; $w; $ov; $m; $drift; $off) as $int
      # ---- sugestão MOJ ----
      | (if ($ov | has("default")) or $int.n == 0 then {state: "none", cf: $cf0, why: (if ($ov | has("default")) then "override" else "no_constraints" end)}
         elif tls_in($int; $cf0) then {state: "keep", cf: $cf0, why: "current_valid"}
         elif tls_in($int; 1.35) then {state: "change", cf: 1.35, why: "default_valid"}
         elif $int.min != null and ($int.max == null or $int.min < $int.max) then
           (if $int.max == null then ((($int.min * 20) | ceil) / 20) else ((($int.min + $int.max) / 2) | tls_r2) end) as $mid
           | (if tls_in($int; $mid) then $mid else ($int.min | tls_r6) end) as $c
           | {state: "change", cf: $c, why: "interval"}
         else {state: "conflict", cf: $cf0, why: "conflict", pass: $int.min_by, slow: $int.max_by} end) as $smoj
      # ---- sugestão Kattis ----
      | ([ $krows[] | select(.ok) | .r ] | max) as $rbest
      | (if ($ov | has("default")) then {state: "none", a: $ka, b: $kb, r: $kr, why: "override"}
         elif $rbest != null then {state: (if $rbest == $kr then "keep" else "change" end), a: $ka, b: $kb, r: $rbest,
                                   why: (if $rbest == $kr then "current_valid" else "largest_r" end)}
         else
           ([1, 1.25, 1.5, 1.75, 2, 2.5, 3, 4, 5, 10, $ka] | unique
            | map(. as $a | {a: $a, ok: tls_row($cases; tls_eff(tls_kat($w; $a; $kr); $ov; $m); $drift; true; $kb).ok})
            | map(select(.ok)) | sort_by((.a - $ka) | tls_abs) | .[0].a) as $abest
           | if $abest != null then {state: "change", a: $abest, b: $kb, r: $kr, why: "adjust_a"}
             else
               ([$kb, 1.4, 1.3, 1.25, 1.2, 1.1, 1] | unique | map(select(. <= $kb))
                | map(. as $b | {b: $b, ok: tls_row($cases; tls_eff(tls_kat($w; $ka; $kr); $ov; $m); $drift; true; $b).ok})
                | map(select(.ok)) | max_by(.b) | .b) as $bbest
               | if $bbest != null then {state: "change", a: $ka, b: $bbest, r: $kr, why: "adjust_b"}
                 else tls_kbounds($cases; $ov; $drift; $kb) as $kbn
                      | {state: "conflict", a: $ka, b: $kb, r: $kr, why: "conflict", pass: $kbn.pass, slow: $kbn.slow} end
             end
         end) as $skat
      | {tl_sim: {hosts: ([ $cases[] | .host ] | unique), w: ($w | map_values(tls_r6)), overrides: $ovl,
                  moj: {cf: $cf0, off: $off, raw: ($cfc.raw // null), interval: $int, rows: $mrows},
                  kattis: {a: $ka, b: $kb, r: $kr, rows: $krows}},
         tl_suggest: {moj: $smoj, kattis: $skat}}
    end;
'
