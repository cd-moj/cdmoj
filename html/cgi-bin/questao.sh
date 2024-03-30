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

CAMINHO="$PATH_INFO"
QUESTAO="$(cut -d'/' -f2 <<<"$CAMINHO")"
CONTEST_HTML=$CONTESTSDIR/treino/enunciados/$QUESTAO.html

if verifica-login treino |grep -q Nao; then
  # espacar o "#" do no me da questao -> ${nome_questao//#/%23}
  tela-login treino/${QUESTAO//#/%23}
fi
LOGIN=$(pega-login)

TABLE=$(awk -v QUESTAO="$QUESTAO" -F ':' '{
    PROB=$3

    if(PROB == QUESTAO) {
      TIME=$1
      CODE=$1":"$2
      RESP=$4

      HUMANTIME=strftime("%c", TIME)

      print "<tr><td>" RESP "</td><td>" HUMANTIME "</td><td>" CODE "</td></tr>"
    }
}' "$CONTESTSDIR/treino/data/$LOGIN")

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

TLE=$(awk 'NR==1 {printf "<option disabled selected style=\"display:none;\">%s</option>", $0; next} {printf "<option disabled>%s</option>", $0}' $CONTESTSDIR/treino/var/questoes/$QUESTAO/tl)

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
    <form enctype="multipart/form-data" action="$BASEURL/cgi-bin/submete.sh/treino/${QUESTAO//#/%23}" method="post">
      <p><strong>Enviar uma solução:</strong></p>
      <input type="hidden" name="MAX_FILE_SIZE" value="30000">
      <div>
        <input name="myfile" type="file" style="margin:10px 0 0 0">
        <input type="submit" value="Submit" style="height: 22px">
      </div>
    </form>

    <div class="tle_info">
      <p style="margin-bottom: 10px;"><strong>Observações:</strong></p>
      <label for="cars">Time Limit</label>
      <select>
        $TLE
      </select>
    </div>
  </div>

  <div class="questao">
    $(< $CONTEST_HTML)
  </div>
</div>
EOF
cat ../footer.html

exit 0
