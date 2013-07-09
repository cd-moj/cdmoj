#!/bin/bash

source common.sh


#limpar caminho, exemplo
#www.brunoribas.com.br/~ribas/moj/cgi-bin/index.sh/contest-teste/oi
#vira 'contest-teste/oi'
CAMINHO="$0"
CAMINHO=($(sed -e 's#.*/index.sh/##' <<< "$CAMINHO"))

#contest é a base do caminho
CONTEST=$(cut -d'/' -f1 <<< "CAMINHO")
cabecalho-html
printf "<h1>Contests</h1>\n"

for contest in $CONTESTSDIR/*; do
    if [[ "$contest" == "$CONTESTSDIR/*" || "$contest" == "$CONTESTSDIR/admin" ]]; then
        continue
    fi
    NOW=$(date +%s)
    source $contest/conf
    printf "$CONTEST_START $CONTEST_END <span class=\"titcontest\"><b>$CONTEST_NAME</b> : "
    if (( $CONTEST_END > NOW )); then
        printf "<a href=\"contest.sh/$CONTEST_ID\">Join</a>"
    else
        printf "Finished"
    fi
    printf " | <a href=\"score.sh/$CONTEST_ID\">Score</a></span>"
    printf "<ul><li>&emsp;&emsp;&emsp;&emsp;Início: $(date --date=@$CONTEST_START)</li>"
    printf "<li>&emsp;&emsp;&emsp;&emsp;Término:  $(date --date=@$CONTEST_END)</li></ul><br/><br/>\n"
done|sort -t" " -k1 -n -r|sort -s -n -r -t" " -k2 |cut -d" " -f3-
cat ../footer.html
exit 0
