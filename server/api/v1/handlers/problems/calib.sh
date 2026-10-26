# GET /problems/calib?id=<id>   (Bearer)
# Resumo de calibração p/ o editor: por juiz (host) que calibrou — o TL calibrado (do store),
# quando, e o LOG de calibração (run/calib/<id>/<host>.json), p/ o autor ver como cada solução
# se comportou em cada juiz.
require_method GET
require_auth
source "$_DIR/lib/tl-store.sh"; source "$_DIR/lib/orgs.sh"; source "$_DIR/lib/problems.sh"
source "$_DIR/lib/tl-sim.sh"   # tl_sim/tl_suggest: o TL de outras configurações, com os tempos desta calibração
source "$_DIR/lib/calib-expect.sh"   # CALX_JQ: o que cada categoria tem de fazer (fonte única)
: "${RUNDIR:=/home/ribas/moj/run}"; : "${CALIB_DIR:=$RUNDIR/calib}"

id="$(param id)"
[[ -n "$id" ]] || fail 400 "Missing id" "id_missing"
valid_id "$id" || fail 400 "Invalid id" "id_invalid"
require_problem_edit "$id"   # log de calibração revela comportamento das soluções -> só dono/colaborador

store="$(tl_store_get "$id")"; [[ -n "$store" ]] || store='{}'
# agregado por host vai em ARQUIVO (--slurpfile): log (≤60 KB/host) + sols estruturado
# passam fácil do teto de 128 KiB POR ARGUMENTO do jq com 2-3 juízes.
LOGF="$(mktemp)"; trap 'rm -f "$LOGF"' EXIT
d="$CALIB_DIR/$id"
if [[ -d "$d" ]]; then
  find "$d" -maxdepth 1 -name '*.json' -type f -exec cat {} + 2>/dev/null \
    | jq -s -c 'map(select(.host)
        | {(.host): {at:.at, version:.checksum, log:.log,
                     reports:(.reports // []), sols:(.sols // [])}}) | add // {}' \
    > "$LOGF" 2>/dev/null
fi
[[ -s "$LOGF" ]] || echo '{}' > "$LOGF"

# linguagens das soluções good (extensão) — p/ apontar as que NÃO calibraram (falharam). O -o noglob
# da API vale aqui -> uso find, não glob.
pkg="$(pkg_path "$id")"; goodlangs='[]'
# VERSÃO ATUAL do pacote (pkg_judge_version): quem calibrou outra versão entra como `stale` e SEM as
# soluções — mostrar o `sols` de uma versão anterior é o que fazia o autor ver solução já removida
# (e não ver a nova) como se fosse o estado de agora.
pkgver="$(pkg_judge_version "$pkg" "$id" 2>/dev/null)"; pkgver="${pkgver//[^0-9a-f]/}"
# EM VOO agora (fila + em execução, inclusive a dirigida pelo marcador): é o que faz a tela do autor
# esperar de verdade em vez de desistir no relógio. Uma calibração leva MINUTOS (medido em produção,
# 21/09/2026: 3 a 7 min conforme o nº de soluções × testes) e o editor desistia em 80 s, some com o
# aviso e parava de buscar — relatos do José Leite e do Arthur Botelho. Array pequeno: pode ir por
# --argjson sem risco de ARG_MAX.
calibrating="$(calibrating_for "$id" 2>/dev/null)"; [[ -n "$calibrating" ]] || calibrating='[]'
if [[ -n "$pkg" && -d "$pkg/sols/good" ]]; then
  # extensão -> linguagem canônica (lang_canon_ext: py2/py3 = py, cc/cxx/c++ = cpp), a chave do TL
  declare -F lang_canon_ext >/dev/null || source "$_LIBDIR/langs.sh"
  goodlangs="$(find "$pkg/sols/good" -maxdepth 1 -type f 2>/dev/null \
    | while IFS= read -r gf; do e="${gf##*.}"; [[ "$e" != "$gf" ]] && { lang_canon_ext "$e"; echo; }; done \
    | LC_ALL=C sort -u | jq -Rsc 'split("\n")|map(select(length>0))')"
  [[ -n "$goodlangs" ]] || goodlangs='[]'
fi

# as soluções que o pacote tem HOJE (o `missing` do sumário) + o ALLOWTLEDURINGCALIBRATION do conf
pfiles="$(calx_pkg_files "$pkg")"; [[ -n "$pfiles" ]] || pfiles='[]'
allowtle="$(calx_allowtle "$pkg")"
drift="$(calx_drift "$pkg")"; [[ -n "$drift" ]] || drift='{}'   # TLMOD[<lang>|default.drift] do conf
# OS DOIS MÉTODOS DE TL (26/10/2026, mojtools tl-methods.sh): o do conf (TLMETHOD) é o que vale — `time_limits`,
# `expect`, `summary` —; o outro sai ao lado (`time_limits_by_method`, `expect_alt`, `summary_alt`) p/ o autor
# comparar antes de trocar (a troca não recalibra: os juízes medem os dois).
meth=moj; tl_conf_method_to meth "$pkg"
kp="$(tl_conf_kattis "$pkg")"; [[ -n "$kp" ]] || kp='{}'

# CORPO ANTES DO CABEÇALHO (pode ser grande: log + sols por host — sai p/ arquivo).
# npy normaliza chaves de TL py3/py2 legadas (calibração pré-unificação) p/ 'py'.
# Cada solução ganha `expect` (lib/calib-expect.sh, contra o TL EFETIVO) e a resposta ganha `summary`
# (o mesmo sumário que o /judge/calib-report grava p/ o Painel). A entrada category=="validator" (o
# validador de entrada) sai de `sols` e vai p/ `hosts[].validator`.
BODYF="$(mktemp)"; trap 'rm -f "$LOGF" "$BODYF"' EXIT
jq -cn --argjson store "$store" --slurpfile lg "$LOGF" --argjson gl "$goodlangs" \
   --arg pkgver "$pkgver" --argjson clive "$calibrating" --argjson ov "$(tl_conf_overrides "$pkg")" \
   --argjson mods "$(tl_conf_mods "$pkg")" --argjson cfc "$(tl_conf_cf "$pkg")" \
   --argjson pfiles "$pfiles" --argjson allowtle "$allowtle" --argjson drift "$drift" \
   --arg meth "$meth" --argjson kp "$kp" "$CALX_JQ$_TL_EFF_DEF$TLSIM_JQ"'
  def npy: if .=="py3" or .=="py2" then "py" else . end;
  # o MÁXIMO entre os juízes de uma metade da tabela (tl = MOJ, tl_kattis = Kattis)
  def calmax($h; $f): [ $h[]?[$f] // {} | to_entries[] ] | group_by(.key | npy)
     | map({ (.[0].key | npy): (map(.value | tonumber? // 0) | max | tostring) }) | add // {};
  # TL EFETIVO ao lado do medido: o cartão precisa dizer "os tempos abaixo são a MEDIÇÃO da
  # calibração, mas o julgamento usa X" — a calibração ignora o override de propósito
  # (MOJ_CALIBRATING=1 no calibreitor), então hosts[].tl NUNCA vai refletir o override. Nem o TLMOD
  # sum/mult, que o juiz soma por cima da tabela (tl_eff, lib/tl-store.sh: a MESMA regra do resto).
  def effof($cal): tl_eff($cal; $ov; $mods);
  ($lg[0] // {}) as $logs
  | ($store.hosts // {}) as $h
  | (if $meth == "kattis" then "moj" else "kattis" end) as $alt
  | (if $meth == "kattis" then "tl_kattis" else "tl" end) as $fld
  | (($h|keys) + ($logs|keys) | unique) as $hosts
  | ([ $h[]?[$fld] // {} | keys[] | npy | select(.!="default") ] | unique) as $served   # calibrado em >=1 host
  | calmax($h; "tl") as $calm | calmax($h; "tl_kattis") as $calk
  | (if $meth == "kattis" then $calk else $calm end) as $cal
  | (effof($calm)) as $effm | (effof($calk)) as $effk
  | (if $meth == "kattis" then $effk else $effm end) as $eff
  | (if $meth == "kattis" then $effm else $effk end) as $effalt
  | [ $hosts[] as $n
      | ($logs[$n].version // "") as $hv
      | { host:$n,
          stale:(($pkgver != "") and ($hv != "") and ($hv != $pkgver)),
          sols:(($logs[$n].sols // []) | map(. + {expect: calx($eff; $allowtle; $drift; $meth; $kp),
                                                  expect_alt: calx($effalt; $allowtle; $drift; $alt; $kp)})) } ] as $hx
  | ($hx | map({(.host): .}) | add // {}) as $hxm
  | { success:true, id:($store.id // ""), checksum:($store.checksum // ""), version:$pkgver,
      being_calibrated:(($clive|length) > 0), calibrating:$clive,
      good_langs:$gl, tl_override:$ov, tl_mods:$mods,
      tl_method:$meth, kattis:$kp,
      time_limits:$eff, time_limits_calibrated:$cal,
      time_limits_by_method:{moj:{calibrated:$calm, effective:$effm}, kattis:{calibrated:$calk, effective:$effk}},
      missing_langs:[ $gl[] | select(. as $g | ($served|index($g)|not)) ],     # sem TL em NENHUM host
      allow_tle:$allowtle, drift:$drift,
      summary:calx_sum([ $hx[] | select(.stale | not) ]; $pfiles),
      summary_alt:calx_sum([ $hx[] | select(.stale | not) | .sols |= map(.expect = .expect_alt) ]; $pfiles),
      # CLASSES DE HARDWARE (26/10/2026): juízes idênticos (o tl-report carimba hosts[h].class) julgam com o TL da
      # classe = o máx entre eles (o claim o põe no job; judge-gw/sched-lib.sh `_TLCLASS_DEF`). `tl`/`tl_kattis` crus
      # (calibrados); `effective`/`effective_kattis` com o TLMOD e o TLOVERRIDE do conf (tl_eff), o que o juiz cobra.
      classes: [ $h | to_entries | map(select((.value.class // "") != "")) | group_by(.value.class)[]
                 | (map({(.key): .value}) | add) as $ch
                 | calmax($ch; "tl") as $ct | calmax($ch; "tl_kattis") as $ck
                 | {class: .[0].value.class, hosts: map(.key), tl: $ct, tl_kattis: $ck,
                    effective: tl_eff($ct; $ov; $mods), effective_kattis: tl_eff($ck; $ov; $mods)} ],
      hosts: [ $hosts[] as $n
               | ($h[$n][$fld] // {}) as $htl
               | ($htl | keys | map(npy)) as $htlk
               | ($logs[$n].version // "") as $hv
               # desatualizado = calibrou OUTRA versão do pacote (só dá p/ afirmar quando as duas
               # versões são conhecidas: juiz antigo/report sem versão não é acusado de nada)
               | (($pkgver != "") and ($hv != "") and ($hv != $pkgver)) as $stale
               | { host:$n, tl:($h[$n].tl // {}), tl_kattis:($h[$n].tl_kattis // {}), class:($h[$n].class // null),
                   missing:[ $gl[] | select(. as $g | ($htlk|index($g)|not)) ],  # sem TL NESTE host
                   # o MAIOR entre o carimbo do store de TL e o do log: calibração que termina
                   # SEM TL novo (good que falhou/TLE — justo o caso de quem está consertando
                   # solução) só bumpa o log, e com o store vencendo ela ficava INVISÍVEL p/ quem
                   # esperava "chegou algo mais novo"
                   at:([($h[$n].at // 0), ($logs[$n].at // 0)] | max),
                   version:$hv, stale:$stale,
                   log:($logs[$n].log // null),
                   reports:(if $stale then [] else ($logs[$n].reports // []) end),
                   sols:(if $stale then [] else [ $hxm[$n].sols[] | select(.category != "validator") ] end),
                   validator:(if $stale then null
                              else ([ $hxm[$n].sols[] | select(.category == "validator") ] | .[0]
                                    | if . == null then null
                                      else (calx_val + {file: (.file // ""), tests: (.tests // [])}) end) end) } ] }
    # SIMULAÇÃO E SUGESTÃO DO TL (lib/tl-sim.sh): o TL de outras configurações (cf do MOJ; resolução, a e b do
    # Kattis) contra os tempos desta calibração, dos juízes da versão atual; a web e a CLI só mostram. Com calibração
    # em voo, não calcula (tl_sim_state "calibrating"): os dados estão pela metade e o editor consulta esta rota a cada
    # 4 s justamente nessa hora — no fixture de 10 juízes × 30 soluções × 100 testes a simulação custa ~160 ms
    # Erro em tempo de execução na simulação (só exibição) NÃO derruba a rota inteira: vira tl_sim_state "error" e o
    # resto do painel de calibração sai normal.
    + (if ($clive | length) > 0 then {tl_sim: null, tl_suggest: null, tl_sim_state: "calibrating"}
       else (try (tlsim([ $hx[] | {host, stale, sols} ]; $ov; $mods; $drift; $kp; $cfc; $allowtle)
                  | . + {tl_sim_state: (if .tl_sim == null then "no_data" else "ok" end)})
             catch {tl_sim: null, tl_suggest: null, tl_sim_state: "error"}) end)' > "$BODYF" 2>/dev/null
[[ -s "$BODYF" ]] || fail 500 "Falha ao montar a resposta" "calib_fail"
emit_json 200 OK
cat "$BODYF"
