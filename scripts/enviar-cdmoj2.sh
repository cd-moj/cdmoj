#ARQFONTE=arquivo-com-a-fonte
#PROBID=id-do-problema

function login-cdmoj2()
{
  true
}

#retorna o ID da submissao
function enviar-cdmoj2()
{
  local ARQFONTE=$1
  local PROBID=$2
  local LINGUAGEM=$3
  local ARQ="$(basename "$ARQFONTE")"

  if [[ ! -e /tmp/cdmoj2-delegation-lastserver ]]; then
    echo 0 > /tmp/cdmoj2-delegation-lastserver
  fi

  LASTSERVER=$(< /tmp/cdmoj2-delegation-lastserver)
  TOTALSERVERS=$(ls -d $SUBMISSIONDIR/../cdmoj2-delegation-server*|wc -l)
  ((NEXT= (LASTSERVER+1)%TOTALSERVERS))
  echo "$NEXT" > /tmp/cdmoj2-delegation-lastserver
  ID="$NEXT.$(awk -F: '{print $2"."$3}' <<< "$ARQ")"

  cp "$ARQFONTE" "$SUBMISSIONDIR/../cdmoj2-delegation-server$NEXT/submit:$PROBID:$ID:$LINGUAGEM"
  echo "$ID"
}

#Retorna string do resultado
function pega-resultado-cdmoj2()
{
  JOBID="$1"
  SERVER="$(cut -d'.' -f1 <<< "$JOBID")"
  JOBFILE="$SUBMISSIONDIR/../cdmoj2-delegation-server$SERVER/$JOBID"
  while [[ ! -e "$JOBFILE" ]]; do
    sleep 3
  done
  RESP="$(< "$JOBFILE")"
  rm "$JOBFILE"
  echo "$RESP"
}
