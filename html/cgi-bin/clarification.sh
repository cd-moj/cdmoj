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
echo "$POST" > $CACHEDIR/POSTT
CAMINHO="$PATH_INFO"

#contest é a base do caminho
CONTEST="$(cut -d'/' -f2 <<< "$CAMINHO")"
CONTEST="${CONTEST// }"

source $CONTESTSDIR/$CONTEST/conf
incontest-cabecalho-html $CONTEST

TOTPROBS=${#PROBS[@]}
for ((i=0;i<TOTPROBS;i+=5)); do
   SELETOR="$SELETOR <option value=\"$i\">${PROBS[$((i+3))]}</option>"
done

if is-admin | grep -q Nao; then
    
    if [ "$(ls -A $CACHEDIR/messages/clarifications/)" ]; then
    cat << EOF
    <table border="1" width="10%"> <tr><th>Problema</th><th>Resposta</th></tr>
EOF
    #Talvez seja necessario ver ma solucao pra atualizar a tabela
    #for para completar toda a tabela de duvidas ja feitas
    for ARQ in $CACHEDIR/messages/clarifications/*; do
	if [[ ! -e "$ARQ" ]]; then
		continue
	fi
	N="$(basename $ARQ)"
	PROBLEM="$(cut -d: -f1 "$ARQ")"
	PROBSHORTNAME=${PROBS[$((PROBLEM+3))]}
  	PROBFULLNAME="${PROBS[$((PROBLEM+2))]}"
	PROBLEM="$PROBSHORTNAME - $PROBFULLNAME"
	MSG="$(cut -d: -f2 "$ARQ")"
	#echo "$(cut -d: -f3 <<< "$ARQ")"
	if [[ "$(cut -d: -f3 <<< "$ARQ")" == "CLARIFICATION" ]]; then
		MSG="$(echo "Not Answered Yet")"
	fi
	echo "<tr><td>$PROBLEM</td><td>$MSG</td></tr>"	
	#echo "$MSG"
    done
	
    echo "</table>"

    fi

    MSG_CLARIFICATION="$(grep -A2 'name="msg_clarification"' <<< "$POST" |tail -n1|tr -d '\n'|tr -d '\r')"
    PROBLEM="$(grep -A2 'name="problems"' <<< "$POST" |tail -n1|tr -d '\n'|tr -d '\r')"
    SHORTPROBLEM="${PROBS[$(($PROBLEM + 3))]}"
    ((FALTA= (CONTEST_START - AGORA)))
    ((TIME= (CONTEST_START - FALTA)))
    TIMEE="$(date --date=@$TIME)"
    ((TEMPODEPROVA= (TIME - CONTEST_START)/60 ))
    #Corrigir questao dos acentos
    MSG="$(echo $MSG_CLARIFICATION | iconv -f UTF8 -t 'ASCII//TRANSLIT')"
    #echo "$MSG"
    #mkdir MSGS
    #Guardando dúvidas para recuperar posteriormente; Tentar identificar usuário pelo login
    #ORDEMDOPROBLEMA:MENSAGEM:TEMPODEENVIODAMSG:TEMPORESTANTEPROVA
    echo "$PROBLEM:$MSG_CLARIFICATION:$TIME:$FALTA" > $CACHEDIR/messages/clarifications/$LOGIN:$CONTEST:CLARIFICATION:$SHORTPROBLEM
    cat << EOF
    <form enctype="multipart/form-data" action="$BASEURL/cgi-bin/clarification-2.sh/$CONTEST" method="post">
        <div>
            <label>Problema: <select name="problems">$SELETOR</select></label><br>
        </div>
        <div>
            <label>Clarification: </label>
            <textarea name="msg_clarification" rows="4" cols="50" value="$MSG_CLARIFICATION"></textarea>
        </div>
        <div>
            <input type="submit" value="Enviar">
	</div>
    </form>
EOF
else

    printf "<div style='text-align: left;'><h1>Quadro de D&uacute;vidas</h1></div>"

	if [ "$(ls -A $CACHEDIR/messages/clarifications/)" ]; then
    cat << EOF
    <table border="1" width="10%"> <tr><th>Contest</th><th>Usu&aacute;rio</th><th>Problema</th><th>Status</th><th>Clarification</th><th>Answer</th></tr>
EOF
    #Talvez seja necessario ver ma solucao pra atualizar a tabela
    #for para completar toda a tabela de duvidas ja feitas
    for ARQ in $CACHEDIR/messages/clarifications/*; do
	if [[ ! -e "$ARQ" ]]; then
		continue
	fi
	N="$(basename $ARQ)"
	PROBLEM_="$(cut -d: -f1 "$ARQ")"
	PROBSHORTNAME="${PROBS[$((PROBLEM_+3))]}"
  	PROBFULLNAME="${PROBS[$((PROBLEM_+2))]}"
	PROBLEM="$PROBSHORTNAME - $PROBFULLNAME"
	MSG="$(cut -d: -f2 "$ARQ")"
	STATUS=""

	if [[ "$REQUEST_METHOD" == "POST" ]]; then
	    echo "$PROBSHORTNAME"
	    ANSWER="$(grep -A2 'name="answer"' <<< "$POST" |tail -n1|tr -d '\n'|tr -d '\r')"
	    echo "$PROBLEM:$ANSWER" > $CACHEDIR/messages/answers/$LOGIN:$CONTEST:ANSWER:$PROBSHORTNAME
        fi

	for ARQ in $CACHEDIR/messages/answers/*; do
		if [[ "$PROBSHORTNAME" == "$(cut -d: -f4 <<< "$ARQ")" ]]; then
			N2="$(basename $ARQ)"
			echo "$(cut -d: -f3 <<< "$ARQ")"
			if [[ "$(cut -d: -f3 <<< "$ARQ")" == "ANSWER" ]]; then
				STATUS="$(echo "Answered")"
			fi
			else
				STATUS="$(echo "Not Answered Yet")"
			fi
	done
	CONTEST="$(cut -d: -f2 <<< "$N")"
	USER="$(cut -d: -f1 <<< "$N")"
	echo "<tr><td>$CONTEST</td><td>$USER</td><td>$PROBSHORTNAME</td><td>$STATUS</td><td>
	<form method='post' enctype="multipart/form-data" action="$BASEURL/cgi-bin/clarification-answer.sh/$CONTEST" style='diplay: inline;'>
       		<input type='hidden' name='clarification_info' value='$USER:$CONTEST:$PROBLEM_:$MSG'>	
		<button style='background: none; border: none; color: #666; text-decoration: none; cursor: pointer; font-size: 12px; font-family: serif;' type='submit'>$MSG</button>
	</form>
	</td><td>$ANSWER</td>"
    done
	
    echo "</table>"

    fi
fi


