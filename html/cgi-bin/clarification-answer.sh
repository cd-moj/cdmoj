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
LOGIN=$(pega-login)
POST="$(cat )"


CAMINHO="$PATH_INFO"


#contest é a base do caminho
CONTEST="$(cut -d'/' -f2 <<< "$CAMINHO")"
CONTEST="${CONTEST// }"

source $CONTESTSDIR/$CONTEST/conf
incontest-cabecalho-html $CONTEST


echo "<h1>Respondendo...</h1>"
#echo "$POST"
INFOS="$(grep -A2 'name="clarification_info"' <<< "$POST" |tail -n1|tr -d '\n'|tr -d '\r')"
#echo "$INFOS"
USER="$(cut -d: -f1 <<< "$INFOS")"
CONTEST="$(cut -d: -f2 <<< "$INFOS")"
PROBLEM="$(cut -d: -f3 <<< "$INFOS")"
CLARIFICATION="$(cut -d: -f4 <<< "$INFOS")"
TIME="$(cut -d: -f5 <<< "$INFOS")"

cat << EOF
	<form enctype="multipart/form-data" action="$BASEURL/cgi-bin/clarification-2.sh/$CONTEST" method="post">
        <div>
            <label>Clarification: </label>
	    <textarea name="clarification" value="$PROBLEM:$TIME:$CLARIFICATION" rows="4" cols="50" disabled>$CLARIFICATION</textarea>
        </div>
	<div>
            <label>Answer: </label>
            <textarea name="answer" value="answer" rows="4" cols="50"></textarea>
        </div>

        <div>
            <input type="submit" value="Enviar">
	</div>
    </form>
EOF
