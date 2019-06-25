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

source #CONFDIR#/judge.conf
source #CONFDIR#/common.conf
source #SCRIPTSDIR#/enviar-spoj.sh
source #SCRIPTSDIR#/enviar-uri.sh

function updatescore()
{
    contest=$1

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
      done  > $CONTESTSDIR/$CONTEST/controle/SCORE.tmp
      mv $CONTESTSDIR/$CONTEST/controle/SCORE{.tmp,}
}

function updatedotscore()
{
  local NOME="$2"
  local LOGIN="$1"
  local CONTEST="$3"

  local PENALTYCOST=20
  source $CONTESTSDIR/$CONTEST/conf

  #gerar arquivo para montar o score
  local ACUMPENALIDADES=0
  local ACUMACERTOS=0
  local TAMARRAY=${#PROBS[@]}
  #Ordem tabela de score
  #nome | A | B | C | D | ... | Acertos | Penalidade |
  {
    printf "<td>$NOME</td>"
    for((prob=0;prob<TAMARRAY;prob+=5)); do
      JAACERTOU=0
      TENTATIVAS=0
      PENDING=0
      source $CONTESTSDIR/$CONTEST/controle/$LOGIN.d/$prob 2>/dev/null
      if (( TENTATIVAS == 0 )) && (( PENDING==0 )) ; then
        printf "<td></td>"
      elif (( JAACERTOU > 0 )); then
        ((ACUMACERTOS++))
        ((JAACERTOU = JAACERTOU/60))
        ((ACUMPENALIDADES+= (TENTATIVAS-1)*PENALTYCOST + JAACERTOU))
        printf "<td><img src='/images/yes.png'/><br/><small>$TENTATIVAS/$JAACERTOU</small></td>"
      else
        PENDINGBLINK=
        TENTATIVASSTAT=""
        if (( PENDING > 0 )); then
          PENDINGBLINK="<blink><img src='/images/yes.png'/></blink>"
        fi
        if (( TENTATIVAS > 0 )); then
          TENTATIVASSTAT="$TENTATIVAS/-"
        fi
        printf "<td>$PENDINGBLINK<br/><small>$TENTATIVASSTAT</small></td>"
      fi
    done
    printf "<td>$ACUMACERTOS ($ACUMPENALIDADES)</td></tr>:$ACUMACERTOS:$ACUMPENALIDADES\n"
  } > $CONTESTSDIR/$CONTEST/controle/$LOGIN.score
}


mkdir -p $SUBMISSIONDIR-log
mkdir -p $SUBMISSIONDIR-enviaroj

#make $SUBMISSIONDIR world writtable
chmod 777 $SUBMISSIONDIR

#ordem de ARQ: $CONTEST:$AGORA:$RAND:$LOGIN:comando:$PROBLEMA:$FILETYPE:$RESP
#Variaveis: CONTEST; ID; LOGIN; COMANDO; PROBID; LING; RESP;
for ARQ in $SUBMISSIONDIR/*; do
  if [[ ! -e "$ARQ" ]]; then
    continue
  fi
  N="$(basename "$ARQ")"
  printf "\n$N\n"
  CONTEST="$(cut -d: -f1 <<< "$N")"
  ID="$(cut -d: -f2,3 <<< "$N")"
  LOGIN="$(cut -d: -f4 <<< "$N")"
  COMANDO="$(cut -d: -f5 <<< "$N")"
  PROBID="$(cut -d: -f6 <<< "$N")"
  LING="$(cut -d: -f7 <<< "$N")"
  RESP="$(cut -d: -f8 <<< "$N")"
  #LING="$(file $ARQ|awk '{print $3}')"

  #carregar contest
  unset ALLOWLATEUSER
  source $CONTESTSDIR/$CONTEST/conf

  if [[ "$CONTEST" == "admin" && "$COMANDO" == "newcontest" ]]; then
    TMPDIR=$(mktemp -d)
    tar xf "$ARQ" -C $TMPDIR/
    CAMINHO="$(dirname $(find $TMPDIR -name 'contest-description.txt'))"
    MSG="$(bash #SCRIPTSDIR#/../bin/cria-contest.sh "$CAMINHO" "$LOGIN")"
    SAIDA=$?
    echo "$(date) $MSG" >> $CONTESTSDIR/admin/$LOGIN.msgs
    tail -n 20 $CONTESTSDIR/admin/$LOGIN.msgs > $TMPDIR.msgs
    mv $TMPDIR.msgs $CONTESTSDIR/admin/$LOGIN.msgs

    if (( SAIDA == 0 )); then
      CONTEST="$(head -n1 "$CAMINHO/contest-description.txt")"

      #Se já tem alguém logado no contest atualiza todos os .score
      UPSCORE=false
      for D in $CONTESTSDIR/$CONTEST/controle/*.d; do
        if [[ ! -e "$D" ]] || egrep -q '\.(admin|mon)' <<< "$D"; then
          continue
        fi
        LOGIN="$(basename "$D" .d)"
        NOME="$(grep "^$LOGIN:" $CONTESTSDIR/$CONTEST/passwd|cut -d: -f3)"
        updatedotscore "$LOGIN" "$NOME" "$CONTEST"
        UPSCORE=true
      done

      if [[ "$UPSCORE" == true ]]; then
        updatescore $CONTEST
      fi
    fi

    rm -rf $TMPDIR

  elif [[ "$COMANDO" == "login" ]]; then

    if [[ ! -d $CONTESTSDIR/$CONTEST/controle/$LOGIN.d ]]; then
      mkdir -p $CONTESTSDIR/$CONTEST/controle/$LOGIN.d
      #admin e mon(itor) não devem aparecer no score
      if egrep -q "\.(admin|mon)$" <<< "$LOGIN"; then
        continue
      fi

      {
        NOME="$(grep "^$LOGIN:" $CONTESTSDIR/$CONTEST/passwd|cut -d: -f3)"
        printf "<td>$NOME</td>"
        TAMARRAY=${#PROBS[@]}
        for ((prob=0;prob<TAMARRAY;prob+=5)); do
            printf "<td></td>"
        done
        printf "<td>0 (0)</td></tr>:0:0\n"
      } > $CONTESTSDIR/$CONTEST/controle/$LOGIN.score
      echo "<tr><td>--</td>$(<$CONTESTSDIR/$CONTEST/controle/$LOGIN.score)"|
        cut -d: -f1 >> $CONTESTSDIR/$CONTEST/controle/SCORE
    fi
  elif [[ "$COMANDO" == "adduser" && "$ID" == "mojinho:abc"  && "$ALLOWLATEUSER" == "y" ]]; then
    #Variaveis: CONTEST; ID; LOGIN; COMANDO; PROBID; LING; RESP;
    NEWUSERNAME="$LOGIN"
    NEWPASSWORD="$PROBID"
    NEWFULLNAME="$LING"
    NEWEMAIL="$RESP"
    if ! grep -q "^$LOGIN:" $CONTESTSDIR/$CONTEST/passwd; then
      echo "$NEWUSERNAME:$NEWPASSWORD:$NEWFULLNAME:$NEWEMAIL" >> $CONTESTSDIR/$CONTEST/passwd
    fi
    unset NEWUSERNAME NEWPASSWORD NEWFULLNAME NEWEMAIL

  elif [[ "$COMANDO" == "passwd" ]]; then
    OLDPASSWD=$PROBID
    NEWPASSWD=$LING
    if grep -q "^$LOGIN:$OLDPASSWD:" $CONTESTSDIR/$CONTEST/passwd; then
      sed -i -e "s/^$LOGIN:$OLDPASSWD:/$LOGIN:$NEWPASSWD:/" $CONTESTSDIR/$CONTEST/passwd
    fi

  elif [[ "$COMANDO" == "rejulgado" ]]; then
    PROBIDFILE=$CONTESTSDIR/$CONTEST/controle/$LOGIN.d/$PROBID

    JAACERTOU=0
    TENTATIVAS=0
    PENDING=0
    if [[ -e $PROBIDFILE ]]; then
      source $PROBIDFILE
    fi

    TEMPO="$(cut -d: -f1 <<< "$ID")"
    ((TEMPO= (TEMPO - CONTEST_START) ))

    #gravar nova resposta no arquivo de solucoes
    #TODO colocar um lock no arquivo do usuario
    USRFILE="$CONTESTSDIR/$CONTEST/data/$LOGIN"
    sed -i -e "s/^$ID:.*/$ID:$PROBID:$RESP/" "$USRFILE"
    chmod 777 "$USRFILE"

    #Recontar tentativas
    JAACERTOU=0
    TENTATIVAS=0
    PENDING=0
    while read LINE; do
      RESPOLD="$(cut -d: -f2 <<< "$LINE")"
      if grep -q "Accepted" <<< "$RESPOLD"; then
        JAACERTOU=$(cut -d: -f3 <<< "$LINE")
        ((JAACERTOU= JAACERTOU - CONTEST_START))
        ((TENTATIVAS++))
        break
      else
        ((TENTATIVAS++))
      fi
    done <<< "$(awk -F: '{print $3":"$4":"$1":"$2}' $CONTESTSDIR/$CONTEST/data/$LOGIN | grep "^$PROBID:")"
    {
      echo "JAACERTOU=$JAACERTOU"
      echo "TENTATIVAS=$TENTATIVAS"
      echo "PENDING=$PENDING"
    } > $PROBIDFILE
    if egrep -q "\.(admin|mon)$" <<< "$LOGIN"; then
      rm $PROBIDFILE
    fi
      sed -i "s/^$TEMPO:$LOGIN:$PROBID:.*:.*:$ID$/$TEMPO:$LOGIN:$PROBID:$LING:$RESP:$ID/" $CONTESTSDIR/$CONTEST/controle/history

    NOME="$(grep "^$LOGIN:" $CONTESTSDIR/$CONTEST/passwd|cut -d: -f3)"
    if ! egrep -q "\.(admin|mon)$" <<< "$LOGIN"; then
      updatedotscore "$LOGIN" "$NOME" "$CONTEST"
      updatescore $CONTEST
    fi

  elif [[ "$COMANDO" == "corrigido" ]]; then

    PROBIDFILE=$CONTESTSDIR/$CONTEST/controle/$LOGIN.d/$PROBID

    JAACERTOU=0
    TENTATIVAS=0
    PENDING=0
    if [[ -e $PROBIDFILE ]]; then
      source $PROBIDFILE
    fi

    ((PENDING--))

    TEMPO="$(cut -d: -f1 <<< "$ID")"
    ((TEMPO= (TEMPO - CONTEST_START) ))

    if [[ "$RESP" == "Accepted"  && "$JAACERTOU" == "0" ]] ; then
      JAACERTOU=$TEMPO
    elif [[ "$JAACERTOU" != "0" ]] ; then
      RESP="$RESP (Ignored)"
    fi

    if ! [[ "$RESP" =~ "Ignored" ]]; then
      ((TENTATIVAS++))
      {
        echo "JAACERTOU=$JAACERTOU"
        echo "TENTATIVAS=$TENTATIVAS"
        echo "PENDING=$PENDING"
      } > $PROBIDFILE
      if egrep -q "\.(admin|mon)$" <<< "$LOGIN"; then
        rm $PROBIDFILE
      fi
    fi
    echo "$TEMPO:$LOGIN:$PROBID:$LING:$RESP:$ID" >> $CONTESTSDIR/$CONTEST/controle/history


    #gravar no arquivo de solucoes
    #TODO colocar um lock no arquivo do usuario
    USRFILE="$CONTESTSDIR/$CONTEST/data/$LOGIN"
    sed -i -e "s/^$ID:.*/$ID:$PROBID:$RESP/" "$USRFILE"
    chmod 777 "$USRFILE"

    NOME="$(grep "^$LOGIN:" $CONTESTSDIR/$CONTEST/passwd|cut -d: -f3)"
    if ! egrep -q "\.(admin|mon)$" <<< "$LOGIN"; then
      updatedotscore "$LOGIN" "$NOME" "$CONTEST"
      updatescore $CONTEST
    fi

  elif [[ "$COMANDO" == "rejulgar" ]]; then
    cp "$ARQ" $SUBMISSIONDIR-enviaroj/
    USRFILE="$CONTESTSDIR/$CONTEST/data/$LOGIN"
    sed -i -e "s/^$ID:\(.*\)$/$ID:\1 (Rejulgando)/" "$USRFILE"
    chmod 777 "$USRFILE"

    TEMPO="$(cut -d: -f1 <<< "$ID")"
    ((TEMPO= (TEMPO - CONTEST_START) ))

    if egrep -q "\.(admin|mon)$" <<< "$LOGIN"; then
      true
    else
      sed -i "s/^$TEMPO:\(.*\):$ID$/$TEMPO:\1 (Rejulgando):$ID/" $CONTESTSDIR/$CONTEST/controle/history
    fi

  elif [[ "$COMANDO" == "submit" ]]; then
    #SITE do problema:
    SITE=${PROBS[PROBID]}

    PROBIDFILE=$CONTESTSDIR/$CONTEST/controle/$LOGIN.d/$PROBID

    JAACERTOU=0
    TENTATIVAS=0
    PENDING=0
    if [[ -e $PROBIDFILE ]]; then
      source $PROBIDFILE
    fi

    cp "$ARQ" $SUBMISSIONDIR-enviaroj/
    if (( $JAACERTOU > 0 )) ; then
      true
      #RESP=Ignored
      #gravar no arquivo de solucoes
      #USRFILE="$CONTESTSDIR/$CONTEST/data/$LOGIN"
      #sed -i -e "s/^$ID:.*/$ID:$PROBID:$RESP/" "$USRFILE"
      #chmod 777 "$USRFILE"
    elif [[ "$JAACERTOU" == "0" ]] ; then

      ((PENDING++))
      {
        echo "JAACERTOU=0"
        echo "TENTATIVAS=$TENTATIVAS"
        echo "PENDING=$PENDING"
      } > $PROBIDFILE
    fi

    #admin e mon(itor) não devem aparecer no score
    if egrep -q "\.(admin|mon)$" <<< "$LOGIN"; then
      rm $PROBIDFILE
    else
      NOME="$(grep "^$LOGIN:" $CONTESTSDIR/$CONTEST/passwd|cut -d: -f3)"
      updatedotscore "$LOGIN" "$NOME" "$CONTEST"
      updatescore $CONTEST
    fi


    #copiar $ARQ para o diretorio com historico de submissoes
    cp "$ARQ" "$CONTESTSDIR/$CONTEST/submissions/$ID-$LOGIN-${PROBS[PROBID+3]}.$LING"

  fi
    cp "$ARQ" $SUBMISSIONDIR-log/
    rm -f "$ARQ"
done
