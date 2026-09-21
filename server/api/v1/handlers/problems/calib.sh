# GET /problems/calib?id=<id>   (Bearer)
# Resumo de calibração p/ o editor: por juiz (host) que calibrou — o TL calibrado (do store),
# quando, e o LOG de calibração (run/calib/<id>/<host>.json), p/ o autor ver como cada solução
# se comportou em cada juiz.
require_method GET
require_auth
source "$_DIR/lib/tl-store.sh"; source "$_DIR/lib/orgs.sh"; source "$_DIR/lib/problems.sh"
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

# CORPO ANTES DO CABEÇALHO (pode ser grande: log + sols por host — sai p/ arquivo).
# npy normaliza chaves de TL py3/py2 legadas (calibração pré-unificação) p/ 'py'.
BODYF="$(mktemp)"; trap 'rm -f "$LOGF" "$BODYF"' EXIT
jq -cn --argjson store "$store" --slurpfile lg "$LOGF" --argjson gl "$goodlangs" \
   --arg pkgver "$pkgver" --argjson clive "$calibrating" --argjson ov "$(tl_conf_overrides "$pkg")" '
  def npy: if .=="py3" or .=="py2" then "py" else . end;
  ($lg[0] // {}) as $logs
  | ($store.hosts // {}) as $h
  | (($h|keys) + ($logs|keys) | unique) as $hosts
  | ([ $h[]?.tl // {} | keys[] | npy | select(.!="default") ] | unique) as $served   # calibrado em >=1 host
  # TL EFETIVO ao lado do medido: o cartão precisa dizer "os tempos abaixo são a MEDIÇÃO da
  # calibração, mas o julgamento usa X" — a calibração ignora o override de propósito
  # (MOJ_CALIBRATING=1 no calibreitor), então hosts[].tl NUNCA vai refletir o override.
  | ([ $h[]?.tl // {} | to_entries[] ] | group_by(.key | npy)
     | map({ (.[0].key | npy): (map(.value | tonumber? // 0) | max | tostring) }) | add // {}) as $cal
  | (if ($ov|length) == 0 then $cal
     else ((($cal|keys) + ($ov|keys)) | unique) as $ks
          | reduce $ks[] as $k ({}; .[$k] = ($ov[$k] // $ov["default"] // $cal[$k]))
          | with_entries(select(.value != null) | .value |= tostring)
     end) as $eff
  | { success:true, id:($store.id // ""), checksum:($store.checksum // ""), version:$pkgver,
      being_calibrated:(($clive|length) > 0), calibrating:$clive,
      good_langs:$gl, tl_override:$ov,
      time_limits:$eff, time_limits_calibrated:$cal,
      missing_langs:[ $gl[] | select(. as $g | ($served|index($g)|not)) ],     # sem TL em NENHUM host
      hosts: [ $hosts[] as $n
               | ($h[$n].tl // {}) as $htl
               | ($htl | keys | map(npy)) as $htlk
               | ($logs[$n].version // "") as $hv
               # desatualizado = calibrou OUTRA versão do pacote (só dá p/ afirmar quando as duas
               # versões são conhecidas: juiz antigo/report sem versão não é acusado de nada)
               | (($pkgver != "") and ($hv != "") and ($hv != $pkgver)) as $stale
               | { host:$n, tl:$htl,
                   missing:[ $gl[] | select(. as $g | ($htlk|index($g)|not)) ],  # sem TL NESTE host
                   # o MAIOR entre o carimbo do store de TL e o do log: calibração que termina
                   # SEM TL novo (good que falhou/TLE — justo o caso de quem está consertando
                   # solução) só bumpa o log, e com o store vencendo ela ficava INVISÍVEL p/ quem
                   # esperava "chegou algo mais novo"
                   at:([($h[$n].at // 0), ($logs[$n].at // 0)] | max),
                   version:$hv, stale:$stale,
                   log:($logs[$n].log // null),
                   reports:(if $stale then [] else ($logs[$n].reports // []) end),
                   sols:(if $stale then [] else ($logs[$n].sols // []) end) } ] }' > "$BODYF" 2>/dev/null
[[ -s "$BODYF" ]] || fail 500 "Falha ao montar a resposta" "calib_fail"
emit_json 200 OK
cat "$BODYF"
