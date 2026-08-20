# GET /contest/balloons?contest=<id>
# Mapa letra/shortname -> cor (hex sem '#') dos balões. Default = paleta ICPC;
# pode ser sobrescrito (parcial ou total) por contests/<id>/balloons.json.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_not_secret_or_auth "$contest"   # contest secreto: visual do placar exige sessão do contest

# CACHE: o mapa de cores é o MESMO p/ todo mundo (não há variante) e a rota entra em todo
# carregamento de página. Entrada única: o balloons.json do contest.
# Sem teto de idade: o corpo é 100% função de duas coisas — o balloons.json do contest e a
# paleta padrão, que é CÓDIGO. As duas são entradas (o próprio handler entra pelo BASH_SOURCE,
# então um deploy que mude a paleta invalida). Assim a rota não paga o `find` do TTL.
BCF="$CONTESTSDIR/$contest/var/balloons-cache.json"
if resp_cache_fresh "$BCF" "${BALLOONS_CACHE_TTL:-0}" \
     "$CONTESTSDIR/$contest/balloons.json" "${BASH_SOURCE[0]}"; then
  emit_json 200 OK; printf '%s' "$(<"$BCF")"; exit 0
fi

# objeto default construído com jq (aceita chaves sem aspas)
DEFAULT="$(jq -cn '{A:"FFFFFF",B:"000000",C:"FF0000",D:"800000",E:"FFFF00",
                    F:"008000",G:"0000FF",H:"000080",I:"FF00FF",J:"800080",
                    K:"00FF00",L:"00FFFF",M:"C0C0C0",N:"FF8000",O:"A3794D"}')"

f="$CONTESTSDIR/$contest/balloons.json"
if [[ -f "$f" ]] && jq -e . "$f" >/dev/null 2>&1; then
  # override merge: defaults + arquivo (chaves do arquivo prevalecem)
  BBODY="$(jq -cn --argjson d "$DEFAULT" --slurpfile o "$f" \
    '{success:true, balloons:($d + ($o[0]))}')"
else
  BBODY="$(jq -cn --argjson d "$DEFAULT" '{success:true, balloons:$d}')"
fi
[[ -n "$BBODY" ]] || fail 500 "Falha ao montar a resposta" "build_fail"
resp_cache_store "$BCF" "$BBODY"
emit_json 200 OK; printf '%s' "$BBODY"
