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

#contest é a base do caminho
CONTEST=$(cut -d'/' -f1 <<<"CAMINHO")

SHOW_TAGS=$(awk 'NR <= 10 {printf "<a class=\"tagCell\" href=\"tag.sh/%s\">%s</a>", substr($0, 2), $0}' $CONTESTSDIR/treino/var/ALL_TAGS)

MENSAGEM="
<div style=\"border:1px solid #E0E0E0; padding:5px 15px 5px;margin:0 10px 10px 10px;\">
  <p style=\"color:#666;font-size:14px;\">Desenvolva suas habilidades com os desafios da nossa plataforma!</p>
  <p>Entre com o <a href='https://t.me/mojinho_bot' target=_blank>@mojinho_bot</a> enviando: <i>participar treino</i></p>
</div>
"

RUNNING=""
if [ -d "$CONTESTSDIR/treino/var/tags-by-contest" ]; then
    for file in "$CONTESTSDIR/treino/var/tags-by-contest"/*; do
        if [ -f "$file" ]; then
            RUNNING+="$(cat "$file")"
        fi
    done
fi

if [ -z "$RUNNING" ]; then
  RUNNING="Oops, parece que houve algum problema no treinamento"
fi

cabecalho-html
cat <<EOF
<script type="text/javascript" src="/js/treino.js"></script>

<style type="text/css" media="screen">
  @import "/css/treino.css";

</style>
<h1>Treino Livre</h1>
  $MENSAGEM
<div class="treino">
  <div class="treinoTabs">
    <!--- Pagination script --->
    <ul class="treinoList">
      $RUNNING
    </ul>
  </div>

  <div class="tagSection">
    <p>Tags:</p>
    <div class="tagsContent">  
      $SHOW_TAGS
    </div>
    <a href="all-tags.sh">Visualizar Todas</a>
  </div>

</div>
EOF
cat ../footer.html

exit 0
