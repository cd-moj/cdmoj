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
echo "$POST" > $CACHEDIR/POSTT
CAMINHO="$PATH_INFO"

#contest é a base do caminho
CONTEST="$(cut -d'/' -f2 <<< "$CAMINHO")"
CONTEST="${CONTEST// }"

source $CONTESTSDIR/$CONTEST/conf
incontest-cabecalho-html $CONTEST

echo "$REQUEST_METHOD"
if is-admin | grep -q Nao; then
    TOTPROBS=${#PROBS[@]}
    for ((i=0;i<TOTPROBS;i+=5)); do
        SELETOR="$SELETOR <option value=\"$i\">${PROBS[$((i+3))]}</option>"
    done

    if [ "$(ls -A $CACHEDIR/MSGS)" ]; then
    cat << EOF
    <table border="1" width="10%"> <tr><th>Problema</th><th>Resposta</th></tr>
EOF
    #for para completar toda a tabela de duvidas ja feitas
    for ARQ in $CACHEDIR/MSGS/*; do
	if [[ ! -e "$ARQ" ]]; then
		continue
	fi
	N="$(basename $ARQ)"
	PROBLEM="$(cut -d: -f1 "$ARQ")"
	PROBSHORTNAME=${PROBS[$((PROBLEM+3))]}
  	PROBFULLNAME="${PROBS[$((PROBLEM+2))]}"
	PROBLEM="$PROBSHORTNAME - $PROBFULLNAME"
	MSG="$(cut -d: -f2 "$ARQ")"
	echo "<tr><td>$PROBLEM</td><td>$MSG</td></tr>"	
	#echo "$MSG"
    done
	
    echo "</table>"

    fi

    if [ "$REQUEST_METHOD" == "GET" ]; then 
    cat << EOF
    <body>
    <form accept-charset="utf-8" enctype="multipart/form-data" action="$BASEURL/cgi-bin/clarification-2.sh/$CONTEST" method="post">
        <div>
            <label>Problema: <select name="problems">$SELETOR</select></label><br>
        </div>
        <div>
            <label>Clarification: </label>
            <textarea name="msg_clarification" rows="4" cols="50"></textarea>
        </div>
        <div>
            <label>Answer: </label>
            <textarea name="msg_answer" rows="4" cols="50" disabled></textarea>
        </div>
        <div>
            <input type="submit" value="Enviar">
            <button type="submit" http-equiv="\"refresh\" content=\"0; url=$BASEURL\" formmethod="post">refresh</button>
        </div>
    </form>
    </body>
EOF
    elif [ "$REQUEST_METHOD" == "POST" ]; then
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
    echo "$PROBLEM:$MSG_CLARIFICATION:$TIME:$FALTA" > $CACHEDIR/MSGS/$CONTEST:$SHORTPROBLEM
    cat << EOF
    <form enctype="multipart/form-data" action="$BASEURL/cgi-bin/clarification.sh/$CONTEST" method="post">
        <div>
            <label>Problema: <select name="problems">$SELETOR</select></label><br>
        </div>
        <div>
            <label>Clarification: </label>
            <textarea name="msg_clarification" rows="4" cols="50" value="$MSG_CLARIFICATION" disabled></textarea>
        </div>
        <div>
            <label>Answer: </label>
            <textarea name="msg_answer" rows="4" cols="50" disabled></textarea>
        </div>
        <div>
            <input type="submit" value="Enviar">
            <button type="submit" http-equiv="\"refresh\" content=\"0; url=$BASEURL\" formmethod="post">refresh</button>
        </div>
    </form>
EOF
    fi
else
    echo "ADMIIIIIIIIIIN"
fi
