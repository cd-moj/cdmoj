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

#TEMPOI=$(awk '{print $1}' /proc/uptime)

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
NOW=$(date +%s)
for contest in $CONTESTSDIR/*; do
  if [[ "$contest" == "$CONTESTSDIR/*" || "$contest" == "$CONTESTSDIR/admin" ]]; then
    continue
  fi
  if [[ -e "/dev/shm/cache.ended-${contest##*/}" ]] && [[ "/dev/shm/cache.ended-${contest##*/}" -nt $contest/conf ]]; then
    continue
  fi
  rm -f "/dev/shm/cache.ended-${contest##*/}"
  source $contest/conf
  THIS="$CONTEST_START $CONTEST_END <span class=\"titcontest\"><b>$CONTEST_NAME</b> : "
  if (( $CONTEST_END > NOW )); then
    THIS+="<a href=\"contest.sh/$CONTEST_ID\">Join</a>"
  else
    THIS+="<a href=\"contest.sh/$CONTEST_ID\">Finished</a>"
  fi
  THIS+=" | <a href=\"score.sh/$CONTEST_ID\">Score</a>"
  THIS+=" | <a href=\"statistic.sh/$CONTEST_ID\">Statistic</a></span>"
  THIS+="<ul><li>&emsp;&emsp;&emsp;&emsp;Início: $(date --date=@$CONTEST_START)</li>"
  THIS+="<li>&emsp;&emsp;&emsp;&emsp;Término:  $(date --date=@$CONTEST_END)</li></ul><br/><br/>"

  if (( NOW +1800 < $CONTEST_START )); then
    UPCOMING+="$THIS\n"
  elif (( NOW > $CONTEST_END )); then
    echo "$THIS" > "/dev/shm/cache.ended-${contest##*/}"
  else
    RUNNING+="$THIS\n"
  fi
done
RUNNING="$(printf "$RUNNING"|sort -t" " -k1 -n -r|cut -d" " -f3-)"
ENDED="$(cat /dev/shm/cache.ended-*|sort -t" " -k1 -n -r|cut -d" " -f3-)"
UPCOMING="$(printf "$UPCOMING"|sort -t" " -k1 -n|cut -d" " -f3-)"
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
