function updatescore()
{
    contest=$1
    > $CONTESTSDIR/$contest/controle/SCORE.tmp
  [[ "$SONIC" == 1 ]] && cat $CONTESTSDIR/$contest/running/* > $CONTESTSDIR/$contest/controle/SCORE.tmp 2>/dev/null && echo "<br><br><br>" >> $CONTESTSDIR/$contest/controle/SCORE.tmp

    CLASSIFICACAO=1
    cat $CONTESTSDIR/$contest/controle/*.score|sort -n -t ':' -k3|
      sort -s -n -r -t ':' -k2|
      cut -d: -f1|
      while read LINE; do
        BGCOLOR=""
        if (( CLASSIFICACAO%2 == 0 ));then
          BGCOLOR="bgcolor='#00EEEE'"
        fi
        echo "<tr $BGCOLOR><td>$CLASSIFICACAO<br/></td>$LINE";
        ((CLASSIFICACAO++))
      done  >> $CONTESTSDIR/$CONTEST/controle/SCORE.tmp
      mv $CONTESTSDIR/$CONTEST/controle/SCORE{.tmp,}
}
