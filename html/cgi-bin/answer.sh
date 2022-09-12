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

function declare-variables()
{			
	local arq=$1
	N="$(basename "$arq")"
	TIME="$(cut -d: -f3 <<< "$N")"
	PROBLEM_ID="$(awk -F '>>' '{ print $1 }' "$arq")"
	PROBSHORTNAME="${PROBS[$((PROBLEM_ID+3))]}"
	PROBFULLNAME="${PROBS[$((PROBLEM_ID+2))]}"
	PROBLEM="$PROBSHORTNAME - $PROBFULLNAME"
	MSG="$(awk -F '>>' '{ print $2 }' "$arq" | sed -e 's/&/<br>/g')"
	USER="$(cut -d: -f1 <<<  "$N")"
	ANSWER="Not Answered Yet"
}

source common.sh
AGORA=$(date +%s)
LOGIN=$(pega-login)
POST="$(cat )"
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
else
  incontest-cabecalho-html "$CONTEST"
fi

echo "<h1>Respostas</h1>"

TOTPROBS=${#PROBS[@]}
for ((i=0;i<TOTPROBS;i+=5)); do
   	SELETOR="$SELETOR <option value=\"$i\">${PROBS[$((i+3))]}</option>"
	PROBLEM="${PROBS[$((i+3))]} - ${PROBS[$((i+2))]}"
	
   	echo "<h2>$PROBLEM</h2>"
	ADMINTABLE="<table border="1" width="10%"> <tr><th>Contest</th><th>Usu&aacute;rio</th><th>Problema</th><th>Tempo</th><th>Clarification</th><th>Answer</th><th>Respondido por</th></tr>"  
 	USERTABLE="<table border="1" width="10%"> <tr><th>Problema</th><th>Tempo</th><th>Clarification</th><th>Resposta</th></tr>"
	if is-admin | grep -q Sim; then
		echo "$ADMINTABLE"
	elif is-mon | grep -q Sim; then
		echo "$ADMINTABLE"
	else
 		echo "$USERTABLE"
	fi

	for ARQ in "$CONTESTSDIR/$CONTEST/messages/clarifications"/*; do	

		if [[ ! -e "$ARQ" ]]; then
			continue
		fi

		declare-variables "$ARQ"
   		
		if [[ "${PROBS[$((i+3))]}" == "$PROBSHORTNAME" ]];then
			for ARQA in "$CONTESTSDIR/$CONTEST/messages/answers"/*; do

				if [[ ! -e "$ARQA" ]]; then
					continue
				fi

				N="$(basename "$ARQA")"
				USR_AUX="$(cut -d: -f1 <<< "$N")"
				TIME_AUX="$(cut -d: -f3 <<< "$N")"
	
				if [[ "$USER" == "$USR_AUX" && "$TIME_AUX" == "$TIME"  ]]; then
					FILE="$ARQA"
					TYPE="ANSWER"
				fi

			done

			if grep -q '\.admin$' <<< "$USER"; then
				ANSWER="Clarified by admin"
				MANAGER_="Answered by himself"
				COLOR="background-color: darkseagreen;"
				LINK="$MSG"
			elif grep -q '\.mon$' <<< "$USER"; then
				ANSWER="Clarified by monitor"
				MANAGER_="Answered by himself"
				COLOR="background-color: darkseagreen;"
				LINK="$MSG"
			else
				ANSWER="Not Answered Yet"
				MANAGER_="Nobody"
				LINK="<button style='background: none; border: none; color: #666; text-align: justify;text-decoration: none; cursor: pointer; font-size: 12px; font-family: serif;' type='submit'>$MSG</button>"
				COLOR=""
			fi

			if [[ ! -e $FILE ]];then
				FILE="$ARQ"
				TYPE="CLARIFICATION"
			fi
			while read -r LINE; do
				if [[ "$TYPE" == "ANSWER" ]]; then
					ANSWER="$( awk -F '>>' '{ print $5 }' <<< "$LINE" | sed -e 's/&/<br>/g')"
					MANAGER="$( awk -F '>>' '{ print $1 }' <<< "$LINE")"
					# Supervisor sem .admin ou .mon
					MANAGER_="$( awk -F '>>' '{ print $1 }' <<< "$LINE" | cut -d. -f1)"
					FILE=""
				fi

			ADMINTABLECONTENT="<tr style='$COLOR'>
 			<form enctype="multipart/form-data" action="$BASEURL/cgi-bin/clarification-answer.sh/$CONTEST" style='diplay: inline;' method="post">
				<td>
					<input type="hidden" name="contest" value="$CONTEST">
					$CONTEST
				</td>
				<td>
					<input type="hidden" name="user" value="$USER">
					$USER
				</td>
				<td>
					<input type="hidden" name="problem" value="$PROBLEM_ID">
					$PROBSHORTNAME
				</td>
				<td>		
					<input type="hidden" name="time" value="$TIME">
					$(date --date=@"$TIME")
				</td>
				<td>
					$LINK	
				</td>
				<td>
					<input type="hidden" name="answer" value='$ANSWER'>
					$ANSWER
				</td>
				<td>
					<input type="hidden" name="manager" value='$MANAGER'>
					$MANAGER_
				</td>
				</form>
			</tr>"
			USERTABLECONTENT="<tr style='$COLOR'><td>$PROBLEM</td><td>$(date --date=@"$TIME")</td><td>$MSG</td><td>$ANSWER</td></tr>"

			if is-admin | grep -q Sim; then
				echo "$ADMINTABLECONTENT"
				unset MANAGER
			elif is-mon | grep -q Sim; then
				echo "$ADMINTABLECONTENT"
				unset MANAGER
			else
				if [[ "$USER" == "$(pega-login)" ]];then
					echo "$USERTABLECONTENT"
					unset MANAGER
				elif grep -q '\.admin$' <<< "$USER" || grep -q '\.mon$' <<< "$USER"; then
					echo "$USERTABLECONTENT"
					unset MANAGER
				fi
			fi
		done < "$FILE"
		fi
	done

	echo "</table><br><br>"
done

if [[ "$REQUEST_METHOD" == "POST" ]]; then
	boundary="$( grep -a -B2 'answer' <<< "$POST" | head -n1)"
	RESP="$(grep -a -A15 'answer' <<< "$POST")"
    RESP="$(echo $RESP | awk -F "$boundary" '{ print $1 }' | sed -e 's/Content-Disposition: form-data; name="answer"//' | sed -e "s/\r//g" | sed -r -e 's/(.{0}).{2}//')"
	USR="$(grep -A2 'name="user"' <<< "$POST" |tail -n1|tr -d '\n'|tr -d '\r')"
	TIME_CLR="$(grep -A2 'name="timeCLR"' <<< "$POST" |tail -n1|tr -d '\n'|tr -d '\r')"
	PROBL="$(grep -A2 'name="problem"' <<< "$POST" |tail -n1|tr -d '\n'|tr -d '\r')"
	GLOBAL="$(grep -A2 'name="global"' <<< "$POST" |tail -n1|tr -d '\n'|tr -d '\r')"
	PROBSHORTNAME="${PROBS[$((PROBL+3))]}"

	for ARQ in "$CONTESTSDIR/$CONTEST/messages/clarifications"/*; do
		if [[ ! -e "$ARQ" ]]; then
			continue
		fi

		declare-variables "$ARQ"

		if [[ "$TIME" == "$TIME_CLR" && "$PROBL" == "$PROBLEM_ID" && "$USER" == "$USR"  ]] && [[ -n "${RESP// }" ]]; then
			#avisa que tem uma nova resposta para uma clarification
			if [[ "$GLOBAL" == "GLOBAL" ]]; then
				echo "$RESP" > "$SUBMISSIONDIR"/"$CONTEST":"$AGORA":"$RANDOM":"$LOGIN":answer:"$GLOBAL" 
			else
				echo "$RESP" > "$SUBMISSIONDIR"/"$CONTEST":"$AGORA":"$RANDOM":"$LOGIN":answer
			fi
			#Cria um historico para os supervisores do contest para verificar as clarifications dos usuarios
			echo "$(ls "$CONTESTSDIR"/"$CONTEST"/messages/clarifications/)" > "$CONTESTSDIR"/"$CONTEST"/messages/files_before
			echo ""$LOGIN">>"$USER">>"$CONTEST">>"$PROBL">>"$RESP">>"$TIME"" >> "$CONTESTSDIR"/"$CONTEST"/messages/answers/"$USER":"$CONTEST":"$TIME":ANSWER:"$PROBSHORTNAME"
			#Cria um historico para os participantes do contest para verificar as respostas dos supervisores
			echo "$(ls "$CONTESTSDIR"/"$CONTEST"/messages/answers/)" > "$CONTESTSDIR"/"$CONTEST"/controle/"$USER".d/files_after_ans
			REQUEST_METHOD=""
		fi
	done
fi

cat ../footer.html
exit 0