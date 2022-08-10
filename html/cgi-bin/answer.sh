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

#echo "$(ls $CACHEDIR/messages/clarifications/)" > $CACHEDIR/$CONTEST/files_before

echo "<h1>Respostas</h1>"

TOTPROBS=${#PROBS[@]}
for ((i=0;i<TOTPROBS;i+=5)); do
   SELETOR="$SELETOR <option value=\"$i\">${PROBS[$((i+3))]}</option>"
	PROBLEM="${PROBS[$((i+3))]} - ${PROBS[$((i+2))]}"
	
   	echo "<h2>$PROBLEM</h2>"
	cat << EOF

   	 <table border="1" width="10%"> <tr><th>Problema</th><th>Tempo</th><th>Clarification</th><th>Resposta</th></tr>
EOF
	
	for ARQ in $CACHEDIR/messages/clarifications/*; do
		N="$(basename $ARQ)"
		TIME="$(cut -d: -f3 <<< "$ARQ")"
		PROBLEM_="$(cut -d: -f1 "$ARQ")"
		PROBSHORTNAME="${PROBS[$((PROBLEM_+3))]}"
  		PROBFULLNAME="${PROBS[$((PROBLEM_+2))]}"
		PROBLEM="$PROBSHORTNAME - $PROBFULLNAME"
		MSG="$(cut -d: -f2 "$ARQ")"
		USER="$(cut -d: -f1 <<<  "$N")"
		ANSWER="Not Answered Yet"
		if [[ ! -e "$ARQ" ]]; then
			continue
		fi

		#echo "<h2>$PROBLEM</h2>"
   		if [[ "${PROBS[$((i+3))]}" == "$PROBSHORTNAME" ]];then
			for ARQ in $CACHEDIR/messages/answers/*; do
				USR_AUX="$(cut -d: -f2 <<< "$ARQ")"
				TIME_AUX="$(cut -d: -f4 <<< "$ARQ")"
				if [[ "$USER" == "$USR_AUX" && "$TIME_AUX" == "$TIME"  ]]; then
					ANSWER="$(cut -d: -f2 "$ARQ")"
				fi
			done
			echo "<tr><td>$PROBLEM</td><td>$TIME</td><td>$MSG</td><td>$ANSWER</td></tr>"
		fi
	done
	echo "</table><br><br>"
done

cat ../footer.html
exit 0
