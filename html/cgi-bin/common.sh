#!/bin/bash
source #CONFDIR#/common.conf
source #SCRIPTSDIR#/oj-links.sh

function cabecalho-html()
{
  printf "Content-type: text/html\n\n"
  cat ../header.html
  cat ../menu.html
  cat << EOF
          <div id="text">
EOF

  return
  cat << EOF
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.0 Transitional//EN">
<HTML>
<HEAD>
<META NAME="generator" CONTENT="http://txt2tags.org">
<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=iso-8859-1">
<LINK REL="stylesheet" TYPE="text/css" HREF="/css/novo.css">
</HEAD><BODY BGCOLOR="white" TEXT="black">
EOF
}

function pega-login()
{
  local  LOGIN="$(echo "$HTTP_COOKIE"|sed -e 's/COOKIE=/ /' | tr ';' '\n'|grep login=|cut -d'=' -f2)"
  local  LOGIN=${LOGIN// }
  echo "$LOGIN"
}

function pega-nome()
{
  local CONTEST=$1
  local LOGIN="$(pega-login)"
  grep "^$LOGIN:" $CONTESTSDIR/$CONTEST/passwd |cut -d':' -f3
}

function verifica-login()
{
  local SITE="$1"

  #verificar COOKIES

  local LOGIN="$(pega-login)"
  local HASH="$(echo "$HTTP_COOKIE" |sed -e 's/COOKIE=/ /'| tr ';' '\n'|grep hash=|cut -d'=' -f2)"
  HASH=${HASH// }


  if [[ "x$LOGIN" == "x" ]] ;then
    echo Nao
  elif [[ ! -e "$CACHEDIR/$LOGIN-$SITE" ]]; then
    echo Nao
  else
    HASHARMAZENADA="$(< $CACHEDIR/$LOGIN-$SITE)"
    if [[ "$HASH" != "$HASHARMAZENADA" ]]; then
      echo Nao
    else
      echo Sim
    fi
  fi

}

function tela-erro()
{
  cabecalho-html
  echo "<h1>Ocorreu algum Erro</h1>"
  cat ../footer.html
}

function tela-login()
{
  cabecalho-html
  printf "<h1>Login em $1</h1>\n"
  cat << EOF
<form enctype="multipart/form-data" action="$BASEURL/cgi-bin/login.sh/$1" method="post">
  Login: <input name="login" type="text"><br/>
  Senha: <input name="senha" type="password"><br/>
  <br/>
  <input type="submit" value="Login">
  <br/>
</form>
EOF
  cat ../footer.html
  exit 0;
}
