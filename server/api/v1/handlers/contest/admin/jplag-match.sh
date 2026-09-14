# GET /contest/admin/jplag-match?contest=<id>&run=<rid>&i=<n>  (juiz/chefe/admin)
# Serve o match<i>.html do jplag (lado-a-lado das soluções). O html traz só o nome sanitizado
# do arquivo (= login), sem nome de time — pode ir p/ o juiz comum.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_judge || fail 403 "Apenas juiz, juiz-chefe ou admin" "judge_required"
run="$(param run)"; i="$(param i)"
[[ "$run" =~ ^run-[a-f0-9]{6,16}$ ]] || fail 400 "run inválido" "run_invalid"
[[ "$i" =~ ^[0-9]{1,5}$ ]] || fail 400 "índice inválido" "i_invalid"
f="$CONTESTSDIR/$contest/jplag/$run/out/match$i.html"
[[ -f "$f" ]] || fail 404 "Comparação não encontrada" "match_notfound"
respond 200 OK "text/html; charset=utf-8"
cat "$f"
