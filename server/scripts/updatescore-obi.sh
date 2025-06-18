function updatescore()
{
  contest=$1
  local RANKDIR="$CONTESTSDIR/$contest/rank"
  mkdir -p $RANKDIR
  [[ "$SONIC" == 1 ]] && cat $RANKDIR/../running/* > $RANKDIR/SCORETABLE.work 2>/dev/null && echo "<br><br><br>" >> $RANKDIR/SCORETABLE.work
  local P
  ( echo "<table border=1><tr>"
    echo -n "<td><b>#</b></td><td><b>Equipe</b></td>"
    for((P=0;P<${#PROBS[@]};P+=5));do
      echo -n "<td><b>${PROBS[$((P+3))]}</b></td>"
    done
   echo "<td><b>SCORE</b></td></tr>" ) >> $RANKDIR/SCORETABLE.work

  local CONT=0
  local LASTSCORE=0
  for ALUNO in $RANKDIR/../data/*; do
    [[ ! -e "$ALUNO" ]] && continue
    [[ "$ALUNO" =~ "admin" ]] && continue
    ALUNOFILE=$(basename $ALUNO)
    [[ -e "$RANKDIR/cache-$ALUNOFILE" ]] && [[ "$RANKDIR/cache-$ALUNOFILE" -nt "$ALUNO" ]] && cat $RANKDIR/cache-$ALUNOFILE && continue
    local SCORE=0
    local STRING="<td>$(grep "^$ALUNOFILE:" $RANKDIR/../passwd|cut -d: -f3)</td>"
    #echo "$NOTA:<tr><td>$(grep $ALUNOFILE: $RANKDIR/../passwd|cut -d: -f3)</td><td>$LEXICO</td><td>$SINTATICO</td><td>$MEPA1</td><td>$MEPA2</td><td>$TOTAL</td><td>$MULTIPLICADOR</td><td>$NOTA</td></tr>"|tee $RANKDIR/cache-$ALUNOFILE
    local RESULTADO=""
    for((P=0;P<${#PROBS[@]};P+=5)); do
      RESULTADO="$(grep -q ":$P:" $ALUNO && echo MANDOU)"
      [[ -z "$RESULTADO" ]] && STRING+="<td>-</td>" && continue
      RESULTADO=$(grep -q ":$P:Accepted" $ALUNO && echo 100 || echo 0)
      if (( RESULTADO == 0 )); then
        unset PONTOSPARCIAIS
        unset PONTOSPARICIAISLEITURA
        declare -a PONTOSPARCIAIS
        declare -a PONTOSPARICIAISLEITURA
        while read LINE; do
          [[ -z "$LINE" ]] && continue
          readarray -d ' ' PONTOSPARICIAISLEITURA <<< "$LINE"
          for i in ${!PONTOSPARICIAISLEITURA[@]}; do
            [[ -z "${PONTOSPARICIAISLEITURA[$i]}" ]] && continue
            [[ "${PONTOSPARICIAISLEITURA[$i]}" == ' ' ]] && continue
            [[ -z "${PONTOSPARCIAIS[$i]}" ]] && PONTOSPARCIAIS[$i]=0
            (( ${PONTOSPARICIAISLEITURA[$i]} > 0 )) && (( ${PONTOSPARICIAISLEITURA[$i]} > ${PONTOSPARCIAIS[$i]} )) && PONTOSPARCIAIS[$i]=${PONTOSPARICIAISLEITURA[$i]}
          done
        done <<< "$(grep ":$P:Wrong" $ALUNO|grep -o '|.*|'|tr -d '|'|tr -s ' ')"
        RESULTADO=0
        for i in ${!PONTOSPARCIAIS[@]}; do
          ((RESULTADO+=${PONTOSPARCIAIS[$i]}))
        done
      fi
      ((SCORE+=RESULTADO))
      STRING+="<td>$RESULTADO</td>"
    done
    echo "$SCORE:$STRING<td><b>$SCORE</b></td>"|tee $RANKDIR/cache-$ALUNOFILE

  done|sort -r -n -t: -k1|
    while read LINE; do
      SCOREATUAL=$(cut -d: -f1 <<< "$LINE");
      if ((SCOREATUAL != LASTSCORE)); then
        LASTSCORE=$SCOREATUAL
        ((CONT++))
      fi
      echo "<tr><td><b>$CONT</b></td>$(cut -d: -f2 <<< "$LINE")</tr>"
      done >> $RANKDIR/SCORETABLE.work

  echo "</table><br/>Tabela regerada às $(date -R)<br/>" >> $RANKDIR/SCORETABLE.work
  mv $RANKDIR/SCORETABLE.work $RANKDIR/SCORETABLE
}
