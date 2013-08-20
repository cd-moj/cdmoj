#ARQFONTE=arquivo-com-a-fonte
#PROBID=id-do-problema

function login-cdmoj()
{
  true
}

#retorna o ID da submissao
function enviar-cdmoj()
{
  ARQFONTE=$1
  PROBID=$2
  LINGUAGEM=$3
  ssh mojjudge@naquadria.brunoribas.com.br "bash autojudge-sh.sh $LINGUAGEM $PROBID" < "$ARQFONTE"
}

#Retorna string do resultado
function pega-resultado-cdmoj()
{
  JOBID="$1"
  echo "$JOBID"
}
