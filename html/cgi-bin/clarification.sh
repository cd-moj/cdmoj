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

echo "<h1>Clarification</h1>"

TOTPROBS=${#PROBS[@]}
for ((i=0;i<TOTPROBS;i+=5)); do
   SELETOR="$SELETOR <option value=\"$i\">${PROBS[$((i+3))]}</option>"
done

if is-admin | grep -q Nao; then

    if [[ "$(ls -A $CONTESTSDIR/$CONTEST/messages/clarifications/ | wc -l)" > 0 ]]; then
    #Talvez seja necessario ver ma solucao pra atualizar a tabela
    #for para completar toda a tabela de duvidas ja feitas
    for ARQ in $CONTESTSDIR/$CONTEST/messages/clarifications/*; do
	if [[ ! -e "$ARQ" ]]; then
		continue
	fi

	N="$(basename $ARQ)"
	USER="$(cut -d: -f1 <<<  "$N")"
	TIME="$(cut -d: -f3 <<< "$ARQ")"
	PROBLEM="$(cut -d: -f1 "$ARQ")"
	PROBSHORTNAME=${PROBS[$((PROBLEM+3))]}
  	PROBFULLNAME="${PROBS[$((PROBLEM+2))]}"
	PROBLEM="$PROBSHORTNAME - $PROBFULLNAME"
	MSG="$(cut -d: -f2 "$ARQ")"
	ANSWER="Not Answered Yet"

	for ARQ in $CONTESTSDIR/$CONTEST/messages/answers/*; do
		USR_AUX="$(cut -d: -f2 <<< "$ARQ")"
		TIME_AUX="$(cut -d: -f4 <<< "$ARQ")"
		if [[ "$USER" == "$USR_AUX" && "$TIME_AUX" == "$TIME"  ]]; then
			ANSWER="$(cut -d: -f2 "$ARQ")"
		fi
	done

    done

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
    #Guardando dúvidas para recuperar posteriormente; Tentar identificar usuário pelo login
    #ORDEMDOPROBLEMA:MENSAGEM:TEMPODEENVIODAMSG:TEMPORESTANTEPROVA

    if [[ "$REQUEST_METHOD" == "POST" ]]; then
		#avisa que ha clarification
		touch  $SUBMISSIONDIR/$CONTEST:$AGORA:$RANDOM:$LOGIN:clarification
		#sleep 1
	    echo "$(ls $CONTESTSDIR/$CONTEST/messages/answers/)" > $CONTESTSDIR/$CONTEST/messages/files_before_ans
		echo "$PROBLEM:$MSG_CLARIFICATION:$AGORA:$FALTA" >> $CONTESTSDIR/$CONTEST/messages/clarifications/$LOGIN:$CONTEST:$AGORA:CLARIFICATION:$SHORTPROBLEM
		echo "$(ls $CONTESTSDIR/$CONTEST/messages/clarifications/)" > $CONTESTSDIR/$CONTEST/messages/files_after
		REQUEST_METHOD=""
    fi
    cat << EOF
    <form enctype="multipart/form-data" action="$BASEURL/cgi-bin/clarification.sh/$CONTEST" method="post">
	<div class="row">
        	<div class="row__cell--1">
            		<label>Problema: </label><br>
        	</div>
		<div class="row__cell">
			<select name="problems" id="select-clarification">$SELETOR</select>
		</div>
	</div>
	<div class="row">
        	<div class="row__cell--1">
            		<label>Clarification: </label>
		</div>
		<div class="row__cell">
           		<textarea id="textarea-form" name="msg_clarification" value="$MSG_CLARIFICATION"></textarea>
        	</div>
	</div>
        <div class="row">
	    <div class="row__cell--1"></div>	
	    <div class="row__cell--fill--btn">
            	<input id="btn-form" type="submit" value="Enviar">
	    	<input id="btn-form" type="reset" value="Limpar">
	    </div>
	</div>
	</div>
    </form>
EOF
else
	if [ "$(ls -A $CONTESTSDIR/$CONTEST/messages/clarifications)" ]; then
    cat << EOF
      
    <table border="1" width="10%"> <tr><th>Contest</th><th>Usu&aacute;rio</th><th>Problema</th><th>Tempo</th><th>Clarification</th><th>Answer</th></tr>
EOF
    #Talvez seja necessario ver ma solucao pra atualizar a tabela
    #for para completar toda a tabela de duvidas ja feitas
    for ARQ in $CONTESTSDIR/$CONTEST/messages/clarifications/*; do
	if [[ ! -e "$ARQ" ]]; then
		continue
	fi

	N="$(basename $ARQ)"
	TIME="$(cut -d: -f3 <<< "$ARQ")"
	PROBLEM_="$(cut -d: -f1 "$ARQ")"
	PROBSHORTNAME="${PROBS[$((PROBLEM_+3))]}"
  	PROBFULLNAME="${PROBS[$((PROBLEM_+2))]}"
	PROBLEM="$PROBSHORTNAME - $PROBFULLNAME"
	MSG="$(cut -d: -f2 "$ARQ")"
	USER="$(cut -d: -f1 <<<  "$N")"
	ANSWER="Not Answered Yet"	

	for ARQ in $CONTESTSDIR/$CONTEST/messages/answers/*; do
		USR_AUX="$(cut -d: -f2 <<< "$ARQ")"
		TIME_AUX="$(cut -d: -f4 <<< "$ARQ")"
		if [[ "$USER" == "$USR_AUX" && "$TIME_AUX" == "$TIME"  ]]; then
			ANSWER="$(cut -d: -f2 "$ARQ")"
		fi

	done

echo "<tr>
	
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
		<input type="hidden" name="problem" value="$PROBLEM_">
		$PROBSHORTNAME
	</td>
	<td>		
		<input type="hidden" name="time" value="$TIME">
		$TIME
	</td>
	<td>
	
	<button style='background: none; border: none; color: #666; text-decoration: none; cursor: pointer; font-size: 12px; font-family: serif;' type='submit'>
				$MSG
		</button>
	</td>
	<td>
		$ANSWER
	</td>
	</form>
     <tr>"		
     
     	if [[ "$REQUEST_METHOD" == "POST" ]]; then
   		RESP="$(grep -A2 'name="answer"' <<< "$POST" |tail -n1|tr -d '\n'|tr -d '\r')"
   		USR="$(grep -A2 'name="user"' <<< "$POST" |tail -n1|tr -d '\n'|tr -d '\r')"
		TIME_ANS="$(grep -A2 'name="timeANS"' <<< "$POST" |tail -n1|tr -d '\n'|tr -d '\r')"
		TIME_CLR="$(grep -A2 'name="timeCLR"' <<< "$POST" |tail -n1|tr -d '\n'|tr -d '\r')"

   		PROBL="$(grep -A2 'name="problem"' <<< "$POST" |tail -n1|tr -d '\n'|tr -d '\r')"
		GLOBAL="$(grep -A2 'name="global"' <<< "$POST" |tail -n1|tr -d '\n'|tr -d '\r')"
    		PROBSHORTNAME="${PROBS[$((PROBL+3))]}"
    		
		if [[ "$TIME" == "$TIME_CLR" && "$PROBL" == "$PROBLEM_" && "$USER" == "$USR"  ]]; then
			#avisa que tem uma resposta para um clarification
			if [[ "$GLOBAL" == "GLOBAL" ]]; then
				echo "$RESP" > $SUBMISSIONDIR/$CONTEST:$AGORA:$RANDOM:$LOGIN:answer:$GLOBAL 
			else
				echo "$RESP" > $SUBMISSIONDIR/$CONTEST:$AGORA:$RANDOM:$LOGIN:answer
			fi
			#sleep 1
			echo "$(ls $CONTESTSDIR/$CONTEST/messages/clarifications/)" > $CONTESTSDIR/$CONTEST/messages/files_before
    		echo "$PROBL:$RESP:$TIM" > $CONTESTSDIR/$CONTEST/messages/answers/$LOGIN:$USER:$CONTEST:$TIME:ANSWER:$PROBSHORTNAME
			echo "$(ls $CONTESTSDIR/$CONTEST/messages/answers/)" > $CONTESTSDIR/$CONTEST/messages/files_after_ans
			REQUEST_METHOD=""
		fi
    fi


done
echo "</table>"


    else
	 echo "<h3>Nenhuma d&uacute;vida</h3>"
    fi
fi

cat ../footer.html
exit 0