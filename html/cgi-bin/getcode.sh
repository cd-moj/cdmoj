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
CONTEST="$(cut -d'/' -f2 <<< "$CAMINHO")"
CONTEST="${CONTEST// }"
ARQUIVO="$(cut -d'/' -f3 <<< "$CAMINHO")"
ARQUIVO="${ARQUIVO// }"

if [[ "x$CONTEST" == "x" ]] || [[ ! -d "$CONTESTSDIR/$CONTEST" ]] || 
  [[ "$CONTEST" == "admin" ]]; then
  tela-erro
  exit 0
fi

source $CONTESTSDIR/$CONTEST/conf
if verifica-login $CONTEST| grep -q Nao; then
  tela-login $CONTEST
elif is-admin | grep -q Nao; then
  tela-erro
  exit 0
fi

TEMPO=$(cut -d: -f1 <<< "$ARQUIVO")
USUARIO=$(cut -d- -f2 <<< "$ARQUIVO")
((TEMPO= (TEMPO - CONTEST_START) ))
TYPE=$(grep "^$TEMPO:$USUARIO:" $CONTESTSDIR/$CONTEST/controle/history|cut -d: -f4)
if [[ ! -e "$CONTESTSDIR/$CONTEST/submissions/$ARQUIVO.$TYPE" ]]; then
  tela-erro
  exit 0
fi
printf "Content-type: text/txt\n\n"
cat "$CONTESTSDIR/$CONTEST/submissions/$ARQUIVO.$TYPE"
