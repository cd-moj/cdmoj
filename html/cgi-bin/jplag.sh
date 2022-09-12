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

function print-problems(){
    local TOTPROBS=$1
    for ((i=0;i<TOTPROBS;i+=5)); do
        echo "<h2>${PROBS[$((i+3))]} - ${PROBS[$((i+2))]}</h2>"
        for dir in "${LINGUAGENS[@]}"; do
			if [ -d "$HTMLDIR"/jplag/"$CONTEST"/"$dir" ]; then
				print-cabecalho-tabela "$dir"

				for file in "$HTMLDIR"/jplag/"$CONTEST"/"$dir"/*; do
					N="$(basename "$file")"	    
					if [[ "matches_avg.csv" == "$N" ]]; then
						INDEX=0
						while read -r LINE; do
							PROBLEM="$(cut -d '-' -f3 <<< "$LINE" | cut -d. -f1 | cut -d ';' -f1)"
							SUBMISSION1="$(cut -d '-' -f2 <<< "$LINE" | cut -d. -f1 | cut -d ';' -f1)"
							SUBMISSION2="$(cut -d '-' -f4 <<< "$LINE" | cut -d. -f1 | cut -d ';' -f1)"
							TAXA="$(cut -d ';' -f4 <<< "$LINE" | cut -d ';' -f1)"
		
							if [[ "${PROBS[$((i+3))]}" == "$PROBLEM" ]]; then
								aux=$(echo "$TAXA" | cut -d. -f1)
								taxa_int="$(( "$aux" + 0 ))"
								if [[ $taxa_int -gt 70  ]]; then
									link="$BASEURL/jplag/$CONTEST/$dir/match$INDEX.html"
									INDEX=$((INDEX+1))
									cat << EOF
										<tr>
											<td>$SUBMISSION1</td>
											<td>$SUBMISSION2</td>
											<td><a href="$link">$TAXA</a></td>
										</tr>
EOF
								fi		    
							fi
						done < "$file"
					fi
				done
				echo "</table><br>"
			fi
        done
    done
}

function print-cabecalho-tabela()
{
	local dir=$1
	if [ "$dir" == "cpp" ]; then
		ling="C/C++"
	elif [ "$dir" == "python3" ]; then
		ling="Python"
	elif [ "$dir" == "java" ]; then
		ling="Java"
	elif [ "$dir" == "csharp" ]; then
		ling="C#"
	elif [ "$dir" == "scheme" ]; then
		ling="Scheme"
	elif [ "$dir" == "text" ]; then
		ling="Text"
	fi

	printf "<h3>Linguagem - %s - <a href=""$BASEURL"/jplag/"$CONTEST"/$dir/index.html">Geral</a></h3>" "$ling"
	cat << EOF
		<table border="1"><tr><th>Submiss&atilde;o 1</th><th>Submiss&atilde;o 2</th><th>Taxa de Pl&aacute;gio</th></tr>
EOF
}

source common.sh
POST="$(cat )"
AGORA=$(date +%s)

#limpar caminho, exemplo
#www.brunoribas.com.br/~ribas/moj/cgi-bin/contest.sh/contest-teste/oi
#vira 'contest-teste/oi'
CAMINHO="$PATH_INFO"
#TESTE="$0"
#CAMINHO="$(sed -e 's#.*/contest.sh/##' <<< "$CAMINHO")"

#contest é a base do caminho
CONTEST="$(cut -d'/' -f2 <<< "$CAMINHO")"
CONTEST="${CONTEST// }"

if [[ "x$CONTEST" == "x" ]] || [[ ! -d "$CONTESTSDIR/$CONTEST" ]] ||
[[ "$CONTEST" == "admin" ]]; then
    tela-erro
    exit 0
fi

source "$CONTESTSDIR"/"$CONTEST"/conf
if verifica-login "$CONTEST"| grep -q Nao; then
    tela-login "$CONTEST"
elif (is-admin | grep -q Nao); then
  tela-erro
  exit 0
else
    incontest-cabecalho-html "$CONTEST"
fi


printf "<h1>JPLAG</h1>\n"

cat << EOF
<p>JPlag é um sistema que encontra semelhanças entre vários conjuntos de arquivos de código-fonte Desta forma, pode detectar plágio de software e conluio no desenvolvimento de software. <br>O JPlag atualmente suporta várias linguagens de programação, metamodelos EMF e texto em linguagem natural.</p><br>
<p><b>Caso a página não atualize com novos dados aós clicar no botão de anále atualize a página.</b></p>
<p>Esta página ainda é EXPERIMENTAL, alguma coisa ainda pode dar
errado</p><br/>
EOF

#Gerar Tabela com pontuacao
TOTPROBS=${#PROBS[@]}
#((TOTPROBS=TOTPROBS/5))

LINGUAGENS=(java python3 cpp csharp char text scheme all)
TOTLINGS=${#LINGUAGENS[@]}
for ((i=0;i<TOTLINGS;i+=1)); do
    SELETOR="$SELETOR <option value=\"$i\">${LINGUAGENS[$i]}</option>"
done

echo "
	<form enctype="multipart/form-data" action="$BASEURL/cgi-bin/jplag.sh/$CONTEST" method="post">
		Linguagem: <select name="linguagem" id="select-clarification">$SELETOR</select>
		<input id="btn-form" type="submit" value="Analisar">
	</form>
"

if [[ "$REQUEST_METHOD" == "POST" ]];then

	while read -r line; do
        readarray -d: -t LIN <<< "$line"
        CODIGO=${LIN[5]}:${LIN[6]}
        RESP="${LIN[4]}"
        EXERCICIO="${LIN[2]}"
        TYPE=${LIN[3],,}
		
	if [[ "$RESP" == "Accepted" ]] || [[ "$RESP" == "Accepted (Ignored)" ]]; then
            ARQ="$CODIGO-${LIN[1]}-${PROBS[$((EXERCICIO+3))]}.$TYPE"
            TYPE="$(awk -F'.' '{print $NF}' <<< "$ARQ")"
            ARQUIVO="$(basename "$ARQ" ".$TYPE" | tr -d '\n')"	
            if [ ! -f "$CONTESTSDIR"/"$CONTEST"/submissions/accepted/"$ARQUIVO" ]; then
                cp -s "$CONTESTSDIR"/"$CONTEST"/submissions/"$ARQUIVO" "$CONTESTSDIR"/"$CONTEST"/submissions/accepted/ 
            fi	
        fi	
    done < "$CONTESTSDIR/$CONTEST/controle/history"

    LINGUAGEM="$(grep -A2 'name="linguagem"' <<< "$POST" |tail -n1|tr -d '\n'|tr -d '\r')"
    LING=${LINGUAGENS[$LINGUAGEM]}
    touch  "$SUBMISSIONDIR"/"$CONTEST":"$AGORA":"$RAND":"$LOGIN":jplag:analisar:"$LING"

    print-problems "$TOTPROBS"
else
    print-problems "$TOTPROBS"
fi

incontest-footer