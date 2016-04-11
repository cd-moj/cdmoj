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
  CODIGO=$(cut -d: -f3 <<< "$ARQFONTE")
  ssh mojjudge@mojjudge.naquadah.com.br "bash autojudge-sh.sh $LINGUAGEM $PROBID $CODIGO" < "$ARQFONTE"
}

#Retorna string do resultado
function pega-resultado-cdmoj()
{
  JOBID="$1"
  echo "$JOBID"
}
