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
POST="$(cat )"
LOGIN="$(pega-login)"

CAMINHO="$PATH_INFO"

#contest é a base do caminho
CONTEST="$(cut -d'/' -f2 <<< "$CAMINHO")"
CONTEST="${CONTEST// }"

source "$CONTESTSDIR"/"$CONTEST"/conf
if [[ "x$CONTEST" == "x" ]] || [[ ! -d "$CONTESTSDIR/$CONTEST" ]] || [[ $CLARIFICATION -eq 0 ]] || [[ -z ${CLARIFICATION// }  ]] ; then
  tela-erro
  exit 0
fi

if verifica-login "$CONTEST"| grep -q Nao; then
  tela-login "$CONTEST"
elif (is-admin | grep -q Nao) && (is-mon | grep -q Nao); then
  tela-erro
  exit 0
else
  incontest-cabecalho-html "$CONTEST"
fi

echo "<h1>Respondendo...</h1>"

ANSWER="$(grep -A2 'name="answer"' <<< "$POST" |tail -n1|tr -d '\n' | tr -d '\r' | sed -e 's/<br>/\n/g')"
USER="$(grep -A2 'name="user"' <<< "$POST" |tail -n1|tr -d '\n'|tr -d '\r' | cut -d . -f1)"
CONTEST="$(grep -A2 'name="contest"' <<< "$POST" |tail -n1|tr -d '\n'|tr -d '\r')"
PROBLEM="$(grep -A2 'name="problem"' <<< "$POST" |tail -n1|tr -d '\n'|tr -d '\r')"
TIME="$(grep -A2 'name="time"' <<< "$POST" |tail -n1|tr -d '\n'|tr -d '\r')"
PROBSHORTNAME="${PROBS[$((PROBLEM+3))]}"

for ARQ in "$CONTESTSDIR"/"$CONTEST"/messages/clarifications/*; do
	N="$(basename "$ARQ")"
	USR_AUX="$(cut -d: -f1 <<< "$N")"
	TIME_AUX="$(cut -d: -f3 <<< "$N")"
	if [[ "$USER" == "$USR_AUX" && "$TIME_AUX" == "$TIME"  ]]; then
		CLARIFICATION="$(awk -F '>>' '{ print $2 }' "$ARQ" | sed -e 's/&/\n/g')"
	fi
done

cat << EOF
	<form enctype="multipart/form-data" action="$BASEURL/cgi-bin/answer.sh/$CONTEST" method="post">
        <div class="row">
	    <div class="row__cell--1">
            	<label>Clarification: </label>
	    </div>
	    <div class="row__cell">
	    	<textarea id="textarea-form" name="clarification" value="" rows="4" cols="50" disabled>$CLARIFICATION</textarea>
	    </div>
        </div>
		<div class="row">
	    <div class="row__cell--1">
            	<label>Answer: </label>
	    </div>
EOF
	   	if [[ ! -f "$CONTESTSDIR/$CONTEST/messages/answers/$USER:$CONTEST:$TIME:ANSWER:$PROBSHORTNAME" ]];then
	   		FILE="$ARQ"
	   	else
			FILE="$CONTESTSDIR/$CONTEST/messages/answers/$USER:$CONTEST:$TIME:ANSWER:$PROBSHORTNAME"
	   	fi
		while read LINE; do
			USER_AUX="$(awk -F '>>' '{ print $1 }' <<< "$LINE")"
			if [[ "$USER_AUX" == "$LOGIN" ]]; then	
				echo "<div class="row__cell"><textarea id="textarea-form" name="answer" value="$ANSWER" rows="4" cols="50" disabled>$ANSWER</textarea></div>
					</div>
				<div class="row">
					<div class="row__cell--1"></div>
					<div class="row__cell--fill--btn">
							<input id="btn-form" type="submit" value="Enviar" disabled>
						<input id="btn-form" type="reset" value="Limpar" disabled>
					</div>
					</div>"
				break
 	   else
		cat << EOF
		  <div class="row__cell">
		   	<textarea id="textarea-form" name="answer" value="$ANSWER" rows="4" cols="50"></textarea>
		   </div>
	 	   </div>
			<div class="row">
				<input type="checkbox" name="global" value="GLOBAL">
				<label id="checkbox-label" for="global">Dispon&iacute;vel para todos no contest</label>
			</div>
		   <input type="hidden" name="timeCLR" value="$TIME">
		   <input type="hidden" name="timeANS" value="$AGORA">
		   <input type="hidden" name="problem" value="$PROBLEM">
		   <input type="hidden" name="user" value="$USER">

        	   <div class="row">
			<div class="row__cell--1"></div>
			<div class="row__cell--fill--btn">
           	   		<input id="btn-form" type="submit" value="Enviar">
				<input id="btn-form" type="reset" value="Limpar">
			</div>
	           </div>
EOF
	   fi
	   done < "$FILE"

    echo "</form>"

cat ../footer.html
exit 0