#!/bin/bash
source #CONFDIR#/common.conf
source #SCRIPTSDIR#/oj-links.sh

function incontest-footer()
{
  cat << EOF
</div>
</div>
<div id="footer">
--- <BR/>
Gerado em: $(date)
</div>
<script type="text/javascript">cufon();</script>
</body>
</html>
EOF
}
function incontest-cabecalho-html()
{
  local CONTEST=$1
  local MSG="$2"
  ADMINMENU=
  if is-admin | grep -q Sim ; then
    ADMINMENU="<li><a href=\"/cgi-bin/statistic.sh/$CONTEST\">Estatísticas</a></li>"
    ADMINMENU+="<li><a href=\"/cgi-bin/sherlock.sh/$CONTEST\">Sherlock (experimental)</a></li>"
  fi
  printf "Content-type: text/html\n\n"
  cat << EOF
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
    <head>
        <title>CD-MOJ - Contest Driven Meta Online Judge</title>
        <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />

        <script src="/js/application.js" type="text/javascript"></script>
        <script src="/js/cufon.js" type="text/javascript"></script>
        <script src="/js/AvantGarde_Bk_BT_400.font.js" type="text/javascript"></script>

        <!-- CSS -->
        <link type="text/css" rel="stylesheet" href="/css/incontest.css" media="screen" />
        <link type="text/css" rel="stylesheet" href="/css/badideas.css" media="screen" />
    </head>
    <body class="bg">
      <div id="geral">
        <div id="header">
          <h1><font color="white">CD-MOJ</font></h1>
          <p style="float:right;">$MSG</font></p>
          <p><font color=lightyellow>$(pega-nome $CONTEST)</font><font color=white> em <em>$CONTEST_NAME</em></font></p>
        </div>
        <div id="content">
          <ul id="menu">
            <li><a href="/cgi-bin/contest.sh/$CONTEST">Problemas e Submissões</a></li>
            <li><a href="/cgi-bin/score.sh/$CONTEST">Score</a></li>
            <li><a href="/cgi-bin/passwd.sh/$CONTEST">Trocar Senha</a></li>
            <li><a href="/cgi-bin/logout.sh/$CONTEST">Logout</a></li>
            $ADMINMENU
          </ul>
          <br/><br/>
          <div id="text">
EOF
}

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

function is-admin()
{
  local LOGIN=$(pega-login)
  if grep -q '\.admin$' <<< "$LOGIN"; then
    echo Sim
  else
    echo Nao
  fi
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
