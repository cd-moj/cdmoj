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
source "$CONTESTSDIR"/"$CONTEST"/conf
AGORA=$(date +%s)
LOGIN=$(pega-login)
POST="$(cat )"
CAMINHO="$PATH_INFO"

#contest é a base do caminho
CONTEST="$(cut -d'/' -f2 <<< "$CAMINHO")"
CONTEST="${CONTEST// }"

if [[ "x$CONTEST" == "x" ]] || [[ ! -d "$CONTESTSDIR/$CONTEST" ]] || [[ -z $CLARIFICATION ]] || [ $CLARIFICATION -eq 0]; then
  tela-erro
  exit 0
fi

if verifica-login "$CONTEST"| grep -q Nao; then
  tela-login "$CONTEST"
else
  incontest-cabecalho-html "$CONTEST"
fi

echo "<h1>Clarification</h1>"

TOTPROBS=${#PROBS[@]}
for ((i=0;i<TOTPROBS;i+=5)); do
   SELETOR="$SELETOR <option value=\"$i\">${PROBS[$((i+3))]}</option>"
done

MSG_CLARIFICATION="$(grep -A2 'name="msg_clarification"' <<< "$POST" |tail -n1|tr -d '\n'|tr -d '\r')"
PROBLEM="$(grep -A2 'name="problems"' <<< "$POST" |tail -n1|tr -d '\n'|tr -d '\r')"
GLOBAL="$(grep -A2 'name="global"' <<< "$POST" |tail -n1|tr -d '\n'|tr -d '\r')"
SHORTPROBLEM="${PROBS[$(($PROBLEM + 3))]}"
((FALTA= (CONTEST_START - AGORA)))

if (is-admin | grep -q Sim && is-mon | grep -q Nao) || (is-admin | grep -q Nao && is-mon | grep -q Sim); then
	if [[ ! -z  "${MSG_CLARIFICATION// }" ]]; then
		if [[ "$REQUEST_METHOD" == "POST" ]]; then
			#avisa que ha clarification
			if [[ "$GLOBAL" == "GLOBAL" ]]; then
				echo "$MSG_CLARIFICATION" > "$SUBMISSIONDIR"/"$CONTEST":"$AGORA":"$RANDOM":"$LOGIN":answer:"$GLOBAL"
			else
				echo "$MSG_CLARIFICATION" > "$SUBMISSIONDIR"/"$CONTEST":"$AGORA":"$RANDOM":"$LOGIN":answer
			fi
			echo "$(ls "$CONTESTSDIR"/"$CONTEST"/messages/answers/)" > "$CONTESTSDIR"/"$CONTEST"/controle/"$LOGIN".d/files_before_ans
			TIME_TMP="$AGORA"
			echo "$PROBLEM:$MSG_CLARIFICATION:$AGORA:$FALTA"  >> "$CONTESTSDIR"/"$CONTEST"/messages/clarifications/"$LOGIN":"$CONTEST":"$TIME_TMP":CLARIFICATION:"$SHORTPROBLEM"
			echo "$(ls "$CONTESTSDIR"/"$CONTEST"/messages/clarifications/)" > "$CONTESTSDIR"/"$CONTEST"/messages/files_after
			REQUEST_METHOD=""
		fi
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
			<input type="checkbox" name="global" value="GLOBAL">
			<label id="checkbox-label" for="global">Dispon&iacute;vel para todos no contest</label>
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
	if [[ ! -z  "${MSG_CLARIFICATION// }" ]]; then
		#ORDEMDOPROBLEMA:MENSAGEM:TEMPODEENVIODAMSG:TEMPORESTANTEPROVA
		if [[ "$REQUEST_METHOD" == "POST" ]]; then
			#avisa que ha clarification
			touch  "$SUBMISSIONDIR"/"$CONTEST":"$AGORA":"$RANDOM":"$LOGIN":clarification
			echo "$(ls "$CONTESTSDIR"/"$CONTEST"/messages/answers/)" > "$CONTESTSDIR"/"$CONTEST"/controle/"$LOGIN".d/files_before_ans
			echo "$PROBLEM:$MSG_CLARIFICATION:$AGORA:$FALTA" >> "$CONTESTSDIR"/"$CONTEST"/messages/clarifications/"$LOGIN":"$CONTEST":"$AGORA":CLARIFICATION:"$SHORTPROBLEM"
			echo "$(ls "$CONTESTSDIR"/"$CONTEST"/messages/clarifications/)" > "$CONTESTSDIR"/"$CONTEST"/messages/files_after
			REQUEST_METHOD=""
		fi
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
fi

cat ../footer.html
exit 0