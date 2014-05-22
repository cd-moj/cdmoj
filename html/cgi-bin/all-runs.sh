#!/bin/bash

source common.sh
AGORA=$(date +%s)


#limpar caminho, exemplo
#www.brunoribas.com.br/~ribas/moj/cgi-bin/contest.sh/contest-teste/oi
#vira 'contest-teste/oi'
CAMINHO="$PATH_INFO"
#TESTE="$0"
#CAMINHO="$(sed -e 's#.*/contest.sh/##' <<< "$CAMINHO")"

#contest é a base do caminho
CONTEST=$(cut -d'/' -f2 <<< "$CAMINHO")

if [[ "x$CONTEST" == "x" ]] || [[ ! -d "$CONTESTSDIR/$CONTEST" ]] || 
  [[ "$CONTEST" == "admin" ]]; then
  tela-erro
  exit 0
fi

source $CONTESTSDIR/$CONTEST/conf
if verifica-login $CONTEST| grep -q Nao; then
  tela-login $CONTEST
elif is-admin | grep -q Nao; then
  tela-erro
  exit 0
else
  incontest-cabecalho-html $CONTEST
fi
printf "<h1>Todas Submissões em \"<em>$CONTEST_NAME</em>\"</h1>\n"

cd $CONTESTSDIR/$CONTEST/data/
for i in *; do
  if grep -q '\.admin' <<< "$i" ; then
    continue
  fi
  NOME="$(grep "^$i:" ../passwd |cut -d: -f3)"
  cat << EOF
  <h2>$NOME ($i)</h2>
  <table border=1>
  <tr><th>Problema</th><th>Resposta</th><th>Horário da
  Submissão</th><th>fonte</th></tr>
EOF
  LINHA=1
  while read LINE; do
    CODIGO=$(cut -d: -f1,2 <<< $LINE)
    HORA=$(cut -d: -f1 <<< $LINE)
    HORA="$(date --date=@$HORA)"
    RESP=$(cut -d: -f4 <<< $LINE)
    EXERCICIO=$(cut -d: -f3 <<< $LINE)
    BGCOLOR=
    if (( LINHA%2 == 0 )); then
      BGCOLOR="bgcolor='#00EEEE'"
    fi
    cat <<EOF
    <tr $BGCOLOR><td>${PROBS[$((EXERCICIO+3))]}</td><td>$RESP</td><td>$HORA</td>
    <td><a target=_blank href='$BASEURL/cgi-bin/getcode.sh/$CONTEST/$CODIGO-$i-${PROBS[$((EXERCICIO+3))]}'>codigo</a>
    </td></tr>
EOF
  ((LINHA++))
  done < $i
  echo "</table><br/>"
done

incontest-footer
