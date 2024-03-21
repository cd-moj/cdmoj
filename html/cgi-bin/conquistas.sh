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

#TEMPOI=$(awk '{print $1}' /proc/uptime)

source common.sh

#limpar caminho, exemplo
#www.brunoribas.com.br/~ribas/moj/cgi-bin/index.sh/contest-teste/oi
#vira 'contest-teste/oi'
CAMINHO="$0"
CAMINHO=($(sed -e 's#.*/index.sh/##' <<<"$CAMINHO"))
CONTEST=$(cut -d'/' -f1 <<<"CAMINHO")

if verifica-login treino |grep -q Nao; then
  tela-login treino/conquistas.usuario
fi
LOGIN=$(pega-login)

ACERTOU=0
SUBMISSOES=0

RUNNING=""

if [ -d "$CONTESTSDIR/treino/controle/$LOGIN.d" ]; then
  for registro in "$CONTESTSDIR/treino/controle/$LOGIN.d"/*; do
    QUESTAO="$(basename "$registro")"
    if [ -f "$CONTESTSDIR/treino/enunciados/$QUESTAO".html ]; then
      RUNNING+="$(cat "$CONTESTSDIR/treino/var/tags-by-contest/"$QUESTAO)"
      
      source $registro
      ACERTOU=$(expr $ACERTOU + $JAACERTOU)
      SUBMISSOES=$(expr $SUBMISSOES + $TENTATIVAS)
      
      RUNNING+="
        <div class="titcontest" style='border-bottom: 1px dotted #c1c1c1; display: flex; justify-content: space-between; padding-bottom: 5px'>
          <span><b>Acertos: </b> $JAACERTOU </span> |
          <span><b>Tentativas: </b>$TENTATIVAS </span> |
          <span><b>K/D: </b>$(printf "%.2f\n" $(echo "scale=3; ($JAACERTOU / $TENTATIVAS) + 0.005" | bc))</span>
        </div>
      "
    fi
  done
fi

KD="
  <div style='border: 1px solid #e0e0e0; margin: 10px;  padding: 15px; font-size: 18px;'>
    <span><b>Usuario: </b> $LOGIN </span>
    <div style='display: flex; justify-content: space-between;  padding-top: 15px'>
    <span><b>Acertos: </b>$ACERTOU </span> |
    <span><b>Tentativas: </b>$SUBMISSOES </span> |
    <span><b>K/D: </b>$(printf "%.2f\n" $(echo "scale=3; ($ACERTOU / $SUBMISSOES) + 0.005" | bc))</span>
    </div>
  </div>
"

if [ -z "$RUNNING" ]; then
  RUNNING="Oops, parece que voce ainda nao possui conquistas"
fi

cabecalho-html
cat <<EOF
<script type="text/javascript" src="/js/treino.js"></script>

<style type="text/css" media="screen">
 <!-- @import "/css/simpletabs.css"; -->
  @import "/css/treino.css";

</style>
<h1>Conquistas do Usuario</h1>
  $KD
<div class="treino">
  <div class="treinoTabs" style="width: 100%;">
    <!--- Pagination script --->
    <div class="conquistas">
      <ul class="treinoList">
        $RUNNING
      </ul>
    </div>
  </div>
</div>
EOF
cat ../footer.html

exit 0
