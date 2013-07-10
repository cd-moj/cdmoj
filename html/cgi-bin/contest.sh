#!/bin/bash

source common.sh


AGORA=$(date +%s)

#limpar caminho, exemplo
#www.brunoribas.com.br/~ribas/moj/cgi-bin/contest.sh/contest-teste/oi
#vira 'contest-teste/oi'
CAMINHO="$PATH_INFO"
#TESTE="$0"
#CAMINHO="$(sed -e 's#.*/contest.sh/##' <<< "$CAMINHO")"

#contest é a base do caminho
CONTEST=$(cut -d'/' -f2 <<< "$CAMINHO")

if [[ "x$CONTEST" == "x" ]] || [[ ! -d "$CONTESTSDIR/$CONTEST" ]]; then
    tela-erro
    exit 0
fi

if [[ "$CONTEST" == "admin" ]]; then
    bash admin.sh
    exit 0
fi


#o contest é valido, tem que verificar o login
if verifica-login $CONTEST| grep -q Nao; then
    tela-login $CONTEST
fi

source $CONTESTSDIR/$CONTEST/conf
#estamos logados
cabecalho-html
printf "<h1>$(pega-nome $CONTEST) em \"<em>$CONTEST_NAME</em>\"</h1>\n"

if (( AGORA < CONTEST_START )); then
    ((FALTA = CONTEST_START - AGORA))
    MSG=
    if (( FALTA >= 60 )); then
        MSG="$((FALTA/60)) minutos"
    fi
    ((FALTA=FALTA%60))
    if ((FALTA > 0 )); then
        MSG="$MSG e $FALTA segundos"
    fi
    printf "<p>O Contest ainda <b>NÃO</b> está em execução</p>\n"
    printf "<center>Aguarde $MSG</center>"
    cat ../footer.html
    exit 0
fi

#mostrar exercicios
printf "<h2>Problems</h2>\n"
TOTPROBS=${#PROBS[@]}
#((TOTPROBS=TOTPROBS/5))
SELETOR=
echo "<ul>"
for ((i=0;i<TOTPROBS;i+=5)); do
    SELETOR="$SELETOR <option value=\"$i\">${PROBS[$((i+3))]}</option>"
    printf "<li>&emsp;&emsp;&emsp;&emsp;<b>${PROBS[$((i+3))]}</b> - ${PROBS[$((i+2))]}"
    LINK="${PROBS[$((i+4))]}"
    if [[ "${PROBS[$((i+4))]}" == "site" ]]; then
        LINK="$(link-prob-${PROBS[i]} ${PROBS[$((i+1))]})"
    fi

    if [[ "$LINK" =~ "http://" ]]; then
        printf " - [<a href=\"$LINK\" target=\"_blank\">problem description</a>]</li>\n"
    elif [[ "$LINK" != "none" ]]; then
        printf " - [<a href=\"$BASEURL/contests/$CONTEST_ID/$LINK\" target=\"_blank\">problem description</a>]</li>\n"
    else
        printf "</li>\n"
    fi
done
echo "</ul>"

echo "<br/><br/>"
printf "<h2>My Submissions</h2>\n"
cat << EOF
<table border="1" width="100%"> <tr><td>Problema</td><td>Resposta</td><td>Submissão em</td><td>Tempo de Prova</td></tr>
EOF

LOGIN=$(pega-login)

while read LINE; do
    PROB="$(cut -d ':' -f3 <<< "$LINE")"
    RESP="$(cut -d ':' -f4 <<< "$LINE")"
    TIME="$(cut -d ':' -f1 <<< "$LINE")"
    TIMEE="$(date --date=@$TIME)"
    PROBSHORTNAME=${PROBS[$((PROB+3))]}
    PROBFULLNAME="${PROBS[$((PROB+2))]}"
    ((TEMPODEPROVA= (TIME - CONTEST_START)/60 ))
    echo "<tr><td>$PROBSHORTNAME - $PROBFULLNAME</td><td>$RESP</td><td>$TIMEE</td><td>$TEMPODEPROVA</td></tr>"
done < $CONTESTSDIR/$CONTEST/data/$LOGIN

echo "</table>"

echo "<br/><br/>"
printf "<h2>Submit Problem</h2>\n"

if (( AGORA > CONTEST_END )); then
    echo "<p> O contest não está mais em andamento</p>"
else
cat << EOF
<form enctype="multipart/form-data" action="$BASEURL/cgi-bin/submete.sh/$CONTEST" method="post">
    <input type="hidden" name="MAX_FILE_SIZE" value="30000">
    Problem: <select name=problem>$SELETOR</select>
    File: <input name="myfile" type="file">
    <br/>
    <input type="submit" value="Submit">
    <br/>
</form>
EOF
fi

cat ../footer.html
