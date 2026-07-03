# GET /problems/status  (Bearer) -> painel de status dos problemas do setter (dono + colaborador).
# Agrega, por id VISÍVEL: validação (run/validation), calibração + time_limits + "precisa recalibrar"
# (run/tl x tl_checksum do índice) e "sendo calibrado AGORA" (filas de calibração). A FRONTEIRA de
# acesso é owners_visible — problema PRIVADO de terceiro NUNCA aparece (a API garante, não a UI).
# Custo: sem hash de pacote por request — stale sai da comparação de dois checksums já materializados
# (o do pacote atual vem carimbado no índice por gen-problem-owners.sh; o calibrado, de run/tl).
require_method GET
require_auth
source "$_DIR/lib/problems.sh"
source "$_DIR/lib/tl-store.sh"
source "$_DIR/../../judge-gw/sched-lib.sh"

# 1) FRONTEIRA DE SEGURANÇA (owners_visible) + estreitamento a dono/colaborador (tira público-só:
#    só REMOVE do conjunto já filtrado, nunca alarga).
vis="$(owners_visible | jq -c --arg me "$SESSION_LOGIN" \
   '.problems |= map(select(.owner==$me or ((.collaborators // [])|index($me)|type=="number")))' 2>/dev/null)"
[[ -n "$vis" ]] || vis='{"problems":[]}'

ids="$(mktemp)"; jq -r '.problems[].id' <<<"$vis" 2>/dev/null > "$ids"

# 2) SENDO CALIBRADO AGORA (uma varredura das filas -> conjunto pequeno).
calib="$(calibrating_set)"

# 3) MAPA DE TL (só dos ids VISÍVEIS; nunca lê run/tl de terceiros). checksum calibrado + TL servível
#    (máx entre hosts por linguagem, direto do store) + updated_at. Um jq só (bulk-slurp).
tlmap="$(mktemp)"
while IFS= read -r id; do f="$(tl_store_file "$id")"; [[ -f "$f" ]] && cat "$f"; done < "$ids" \
  | jq -sc 'map({key:.id, value:{
       calibrated:(((.hosts // {})|length)>0),
       at:(.updated_at // null), checksum:(.checksum // ""),
       tl:([.hosts[].tl // {}]
           | reduce (.[]|to_entries[]) as $e ({}; .[$e.key]=([(.[$e.key]//0),($e.value|tonumber? // 0)]|max))
           | with_entries(.value|=tostring)) }}) | from_entries' > "$tlmap" 2>/dev/null
[[ -s "$tlmap" ]] || echo '{}' > "$tlmap"

# 4) MAPA DE VALIDAÇÃO (idem; o arquivo já traz .id).
valmap="$(mktemp)"
while IFS= read -r id; do f="$RUNDIR/validation/$id.json"; [[ -f "$f" ]] && cat "$f"; done < "$ids" \
  | jq -sc 'map({key:.id, value:{ok:.ok, checks:(.checks // []), at:(.at // null),
       render_warnings:(.render_warnings // "")}}) | from_entries' > "$valmap" 2>/dev/null
[[ -s "$valmap" ]] || echo '{}' > "$valmap"

# 5) JOIN + AGREGADOS. JSON grande (vis) via stdin; mapas via --slurpfile; conjunto calib via
#    --argjson (é pequeno) — nada de JSON grande no argv (ARG_MAX).
emit_json 200 OK
jq -c --slurpfile TL "$tlmap" --slurpfile VAL "$valmap" --argjson CAL "$calib" '
  ($TL[0] // {}) as $tl | ($VAL[0] // {}) as $val
  | ($CAL | map({(.):true}) | add // {}) as $calset
  | [ .problems[]
      | .id as $id
      | ($val[$id]) as $v | ($tl[$id]) as $t
      | (($v.checks // []) | any(.name=="good_sol_accepts" and (.ok|not))) as $gsbad
      | (if $v==null then "none" elif ($v.ok==true) then "ok" else "error" end) as $vstate
      | ($t.calibrated // false) as $cal
      | (($t.checksum // "") != "" and (.tl_checksum // "") != "" and ($t.checksum != .tl_checksum)) as $stale
      | { id:$id, title:(.title // .prob // $id), owner:.owner, author:.author, public:.public,
          collaborators:(.collaborators // []),
          validated:$vstate,
          calibrated:$cal,
          being_calibrated:(($calset[$id]) // false),
          stale:$stale,
          needs_recalibration:($cal and $stale),
          error:(($vstate=="error") or $gsbad),
          error_reasons:([ (if $vstate=="error" then "validation_failed" else empty end),
                           (if $gsbad then "good_sol_rejected" else empty end) ]),
          time_limits:($t.tl // {}), updated_at:($t.at // null),
          validated_at:($v.at // null),
          render_warnings:($v.render_warnings // "") } ] as $rows
  | { success:true, total:($rows|length),
      counts:{
        validated:          ([$rows[]|select(.validated=="ok")]|length),
        validation_error:   ([$rows[]|select(.validated=="error")]|length),
        unvalidated:        ([$rows[]|select(.validated=="none")]|length),
        calibrated:         ([$rows[]|select(.calibrated)]|length),
        uncalibrated:       ([$rows[]|select(.calibrated|not)]|length),
        being_calibrated:   ([$rows[]|select(.being_calibrated)]|length),
        needs_recalibration:([$rows[]|select(.needs_recalibration)]|length),
        errors:             ([$rows[]|select(.error)]|length) },
      calibrating_ids:[$rows[]|select(.being_calibrated)|.id],
      attention_ids:  [$rows[]|select(.error or .needs_recalibration)|.id],
      problems:$rows }' <<<"$vis" 2>/dev/null \
  || jq -cn '{success:true, total:0, counts:{}, calibrating_ids:[], attention_ids:[], problems:[]}'

rm -f "$ids" "$tlmap" "$valmap"
