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

CAMINHO="$PATH_INFO"
CONTEST="$(cut -d'/' -f2 <<<"$CAMINHO")"
CONTEST_HTML=$CONTESTSDIR/treino/enunciados/$CONTEST.html

TABLE=$(awk -v CONTEST="$CONTEST" -F ':' '{
    PROB=$3

    if(PROB == CONTEST) {
      TIME=$1
      CODE=$1":"$2
      RESP=$4

      HUMANTIME=strftime("%c", TIME)

      print "<tr><td>" RESP "</td><td>" HUMANTIME "</td><td>" CODE "</td></tr>"
    }
}' "$CONTESTSDIR/treino/data/mockLoginTeste")

if [ -z "$TABLE" ]; then
  TABLE="Voce ainda não tentou resolver essa quetão, basta enviar sua solução."
else
  TABLE="
      <div id="table-wrapper">
        <div id="table-scroll">
          <table>
            <thead>
              <tr>
                <th><span class="text">Resposta</span></th>
                <th><span class="text">Submissão em</span></th>
                <th><span class="text">Código</span></th>
              </tr>
            </thead>
            <tbody>
              $TABLE
            </tbody>
          </table>
        </div>
      </div>
    "
fi

cabecalho-html
cat <<EOF
<script type="text/javascript" src="/js/simpletabs_1.3.packed.js"></script>
<style type="text/css" media="screen">
  @import "/css/scrollableTable.css";
  @import "/css/questao.css";
</style>

<div style="border:1px solid #ccc; padding:10px; font-size:14px; color: #666;">

  $TABLE

  <div style="display: flex; justify-content: space-between; border-bottom:1px solid #ccc; padding:15px 0 10px 0;">
    <form enctype="multipart/form-data" action="$BASEURL/cgi-bin/submete.sh/treino/$CONTEST" method="post">
      <p><strong>Enviar uma solução:</strong></p>
      <input type="hidden" name="MAX_FILE_SIZE" value="30000">
      <div>
        <input name="myfile" type="file" style="margin:10px 0 0 0">
        <input type="submit" value="Submit" style="height: 22px">
      </div>
    </form>

    <div>
      <p><strong>Observações:</strong></p>
      <p style="margin-top: 15px;">Tempo Limite de execução: 250ms</p>
    </div>
  </div>

  <div class="questao">
    $(< $CONTEST_HTML)
  </div>
</div>
EOF
cat ../footer.html

exit 0
