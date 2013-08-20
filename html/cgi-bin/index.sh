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
cat << EOF
<script type="text/javascript" src="/js/simpletabs_1.3.packed.js"></script>
<style type="text/css" media="screen">
  @import "/css/simpletabs.css";
</style>
<h1>Contests</h1>
EOF

RUNNING=
ENDED=
UPCOMING=
for contest in $CONTESTSDIR/*; do
  if [[ "$contest" == "$CONTESTSDIR/*" || "$contest" == "$CONTESTSDIR/admin" ]]; then
    continue
  fi
  NOW=$(date +%s)
  source $contest/conf
  THIS="$CONTEST_START $CONTEST_END <span class=\"titcontest\"><b>$CONTEST_NAME</b> : "
  if (( $CONTEST_END > NOW )); then
    THIS="$THIS<a href=\"contest.sh/$CONTEST_ID\">Join</a>"
  else
    THIS="${THIS}Finished"
  fi
  THIS="$THIS | <a href=\"score.sh/$CONTEST_ID\">Score</a>"
  THIS="$THIS | <a href=\"statistic.sh/$CONTEST_ID\">Statistic</a></span>"
  THIS="$THIS<ul><li>&emsp;&emsp;&emsp;&emsp;Início: $(date --date=@$CONTEST_START)</li>"
  THIS="$THIS<li>&emsp;&emsp;&emsp;&emsp;Término:  $(date --date=@$CONTEST_END)</li></ul><br/><br/>\n"

  if (( NOW < $CONTEST_START )); then
    UPCOMING="$UPCOMING$THIS"
  elif (( NOW > $CONTEST_END )); then
    ENDED="$ENDED$THIS"
  else
    RUNNING="$RUNNING$THIS"
  fi
done
RUNNING="$(printf "$RUNNING"|sort -t" " -k1 -n -r|sort -s -n -r -t" " -k2 |cut -d" " -f3-)"
ENDED="$(printf "$ENDED"|sort -t" " -k1 -n -r|sort -s -n -r -t" " -k2 |cut -d" " -f3-)"
UPCOMING="$(printf "$UPCOMING"|sort -t" " -k1 -n -r|sort -s -n -r -t" " -k2 |cut -d" " -f3-)"
cat << EOF
<div class="simpleTabs">
            <ul class="simpleTabsNavigation">
                <li><a href="#">Running</a></li>
                <li><a href="#">Upcoming</a></li>
                <li><a href="#">Past</a></li>
            </ul>
            <div class="simpleTabsContent">$RUNNING</div>
            <div class="simpleTabsContent">$UPCOMING</div>
            <div class="simpleTabsContent">$ENDED</div>
        </div>
EOF
cat ../footer.html
exit 0
