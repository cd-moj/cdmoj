# GET /contest/history?contest=<id>   (Bearer) -> TXT
# Submissões DO PRÓPRIO usuário no contest, do controle/history.
# 7 campos por linha: tempo:username:problemid:lang:verdict:epoch:subid
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"

emit_text
hist="$CONTESTSDIR/$contest/controle/history"
[[ -f "$hist" ]] || exit 0

# Modo do placar (mesmo seletor do score/build.sh: CONTEST_TYPE/SCORE_MODE). Em placares com
# pontos PARCIAIS (obi/heurístico/outro) o competidor PODE ver o score; em binários (icpc/treino/
# ausente) escondemos o sufixo ,Np do veredicto (anti-leak: não revela quão perto ficou). A trava
# é no servidor — o competidor nem recebe o score. O history em disco NÃO muda.
rawtype="$(sed -n 's/^[[:space:]]*CONTEST_TYPE=//p; s/^[[:space:]]*SCORE_MODE=//p' "$CONTESTSDIR/$contest/conf" 2>/dev/null | tail -1)"
rawtype="${rawtype%\"}"; rawtype="${rawtype#\"}"; rawtype="${rawtype%\'}"; rawtype="${rawtype#\'}"
rawtype="$(printf '%s' "$rawtype" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
case "$rawtype" in obi|heuristic|flia|outro|custom) strip=0 ;; *) strip=1 ;; esac

awk -F: -v u="$SESSION_LOGIN" -v strip="$strip" 'BEGIN{OFS=":"} $2==u {
  if (strip+0==1) { v=$5; sub(/,.*/, "", v); $5=v }   # corta o sufixo de score do veredicto
  print
}' "$hist"
