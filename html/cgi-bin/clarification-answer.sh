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

INFOS="$(grep -A2 'name="clarification_info"' <<< "$POST" |tail -n1|tr -d '\n'|tr -d '\r')"
USER="$(grep -A2 'name="user"' <<< "$POST" |tail -n1|tr -d '\n'|tr -d '\r')"
CONTEST="$(grep -A2 'name="contest"' <<< "$POST" |tail -n1|tr -d '\n'|tr -d '\r')"
PROBLEM="$(grep -A2 'name="problem"' <<< "$POST" |tail -n1|tr -d '\n'|tr -d '\r')"
TIME="$(grep -A2 'name="time"' <<< "$POST" |tail -n1|tr -d '\n'|tr -d '\r')"
PROBSHORTNAME="${PROBS[$((PROBLEM+3))]}"

for ARQ in $CACHEDIR/messages/clarifications/*; do
	N="$(basename $ARQ)"
	USR_AUX="$(cut -d: -f1 <<< "$N")"
	TIME_AUX="$(cut -d: -f3 <<< "$ARQ")"
	if [[ "$USER" == "$USR_AUX" && "$TIME_AUX" == "$TIME"  ]]; then
		CLARIFICATION="$(cut -d: -f2 "$ARQ")"
	fi
done

cat << EOF
	<form enctype="multipart/form-data" action="$BASEURL/cgi-bin/clarification-2.sh/$CONTEST" method="post">
        <div>
            <label>Clarification: </label>
	    <textarea name="clarification" value="" rows="4" cols="50" disabled>$CLARIFICATION</textarea>
        </div>
	<div>
            <label>Answer: </label>
EOF
	   if [[ -f "$CACHEDIR/messages/answers/$LOGIN:$USER:$CONTEST:$TIME:ANSWER:$PROBSHORTNAME" ]];then
		   ANSWER="$(cut -d: -f2 "$CACHEDIR/messages/answers/$LOGIN:$USER:$CONTEST:$TIME:ANSWER:$PROBSHORTNAME")"
         echo "<textarea name="answer" value="$ANSWER" rows="4" cols="50" disabled>$ANSWER</textarea>
		<div>
           	   <input type="submit" value="Enviar" disabled>
	        </div>"
 	   else
		cat << EOF
		   <textarea name="answer" value="$ANSWER" rows="4" cols="50"></textarea>
	 	   </div>
			<input type="checkbox" name="global" value="GLOBAL">
			<label for="global">Dispon&iacute;vel para todos no contest</label>
		   <input type="hidden" name="timeCLR" value="$TIME">
		   <input type="hidden" name="timeANS" value="$AGORA">
		   <input type="hidden" name="problem" value="$PROBLEM">
		   <input type="hidden" name="user" value="$USER">

        	   <div>
           	   <input type="submit" value="Enviar">
	           </div>
EOF
	   fi
	   
          echo "</form>"

cat ../footer.html
exit 0
