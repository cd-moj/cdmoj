# GET /contest/virtual?contest=<id>   (pública, como o placar)
# -> {success:true, available:true|false[, url]}
# PARTICIPAÇÃO VIRTUAL dá p/ fazer AGORA? É o portão INTEIRO de lib/virtual.sh (vr_load: módulo, não secreto, ICPC,
# placar não anônimo, encerrada para todas as sedes, descongelada, todos os problemas públicos no treino). Quem usa: o
# aviso "Refaça esta prova" do placar, que fica no subdomínio do contest e não tem o token do treino p/ perguntar ao
# /treino/virtual/info. Antes o placar decidia só por "módulo ligado + prova encerrada" e mostrava o link num contest
# cujo problema era privado (`blablabla`, 07/10/2026). A resposta não diz o MOTIVO: o público não precisa saber o que
# falta (o painel do dono, Evento › Virtual, diz).
require_method GET
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_not_secret_or_auth "$contest"
source "$_LIBDIR/virtual.sh"
if vr_load "$contest"; then
  ok_json '{available:true, url:("/treino/virtual/?c=" + $c)}' --arg c "$contest"
else
  ok_json '{available:false}'
fi
