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

TAG="$PATH_INFO"

RUNNING=$(awk '{print $0}' $CONTESTSDIR/treino/var/tags/#${TAG:1})

SHOW_TAGS=$(awk 'NR <= 10 {printf "<a class=\"tagCell\" href=\"%s\">%s</a>", substr($0, 2), $0}' $CONTESTSDIR/treino/var/all-tags)

MENSAGEM="
<div style=\"border:1px solid #E0E0E0; padding:5px 15px 5px;margin:0 10px 10px 10px;\">
  <p style=\"color:#666;font-size:14px;\">Desenvolva suas habilidades com os desafios da nossa plataforma!</p>
  <p>Entre com o <a href='https://t.me/mojinho_bot' target=_blank>@mojinho_bot</a> enviando: <i>participar treino</i></p>
</div>
"
if verifica-login treino | grep -q Sim; then
  MENSAGEM="
  <div style=\"border:1px solid #E0E0E0; padding:5px 15px 5px;margin:0 10px 10px 10px; display:flex;justify-content: end;\">
    <a href=\"/cgi-bin/logout.sh\"><span>Logout</span></a>
  </div>
  "
fi

cabecalho-html
cat <<EOF
<script type="text/javascript" src="/js/treino.js"></script>

<style type="text/css" media="screen">
  @import "/css/treino.css";
</style>

<h1> TAG: ${TAG:1} </h1>
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
    <a href="/cgi-bin/all-tags.sh">Visualizar Todas</a>
  </div>

</div>
EOF
cat ../footer.html

exit 0
