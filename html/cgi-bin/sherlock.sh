#!/bin/bash
#This file is part of CD-MOJ.
#
#CD-MOJ is free software: you can redistribute it and/or modify
#it under the terms of the GNU General Public License as published by
#the Free Software Foundation, either version 3 of the License, or
#(at your option) any later version.
#
#CD-MOJ is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with CD-MOJ.  If not, see <http://www.gnu.org/licenses/>.

source common.sh
AGORA=$(date +%s)


#limpar caminho, exemplo
#www.brunoribas.com.br/~ribas/moj/cgi-bin/contest.sh/contest-teste/oi
#vira 'contest-teste/oi'
CAMINHO="$PATH_INFO"
#TESTE="$0"
#CAMINHO="$(sed -e 's#.*/contest.sh/##' <<< "$CAMINHO")"

#contest é a base do caminho
CONTEST="$(cut -d'/' -f2 <<< "$CAMINHO")"
CONTEST="${CONTEST// }"

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
printf "<h1>SHERLOCK de \"<em>$CONTEST_NAME</em>\"</h1>\n"

cat << EOF
<p><em>Sherlock</em> é uma ferramenta para detecção de plágio. Informações
sobre esta ferramente acesse
<a href="http://sydney.edu.au/engineering/it/~scilect/sherlock/">http://sydney.edu.au/engineering/it/~scilect/sherlock/</a></p>
<br>
<p>Não considere esta ferramenta como única fonte de deteção de plágio, pode
acontecer falsos positivos, por isso uma análise mais criteriosa nos
arquivos apontados como identicos deve ser utilizada</p>
<br>
<p>Aqui serão mostrados apenas similaridades acima de 20%.</p>
<br>
<p>Esta página ainda é EXPERIMENTAL, alguma coisa ainda pode dar
errado</p><br/>
EOF

#Gerar Tabela com pontuacao
TOTPROBS=${#PROBS[@]}
#((TOTPROBS=TOTPROBS/5))
SELETOR=
for ((i=0;i<TOTPROBS;i+=5)); do
  printf "<h2>${PROBS[$((i+3))]} - ${PROBS[$((i+2))]}</h2>"
  printf "<pre>"
  cd $CONTESTSDIR/$CONTEST
  ARQUIVOS=$(grep ":$i:Accepted" data/*|cut -d: -f2,3| while read LINE; do echo submissions/${LINE}*-${PROBS[$((i+3))]}.*; done)
  $CONTESTSDIR/../bin/sherlock -t 20 $ARQUIVOS
  printf "</pre>"
  printf "<br/><br/>"
done

incontest-footer
