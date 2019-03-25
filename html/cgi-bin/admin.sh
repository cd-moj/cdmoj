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
source new-contest.sh

#o contest é valido, tem que verificar o login
if verifica-login admin| grep -q Nao; then
  tela-login admin
fi

#ok logados
LOGIN=$(pega-login)
NOME="$(pega-nome admin)"

cabecalho-html
printf "<h1>Administrador $NOME</h1>\n"
printf "<h2>Trocar Senha</h2>\n"
printf "<p> - <a href='$BASEURL/cgi-bin/passwd.sh/admin'>passwd</a></p><br/>"

cat << EOF
  <script type="text/javascript" src="/js/simpletabs_1.3.packed.js"></script>
  <style type="text/css" media="screen">
    @import "/css/simpletabs.css";
  </style>
EOF

cat << EOF
<div class="simpleTabs">
            <ul class="simpleTabsNavigation">
                <li><a href="#">Old School</a></li>
                <li><a href="#">Form</a></li>
            </ul>
            <div class="simpleTabsContent">$(new-contest-old)</div>
            <div class="simpleTabsContent">$(new-contest-form)</div>
        </div>
EOF
echo "<br/><br/>"
printf "<h2>Últimas mensagens do LOG do admin $LOGIN</h2>"
echo "<pre>"
cat $CONTESTSDIR/admin/$LOGIN.msgs
echo "</pre>"
cat ../footer.html
exit 0
