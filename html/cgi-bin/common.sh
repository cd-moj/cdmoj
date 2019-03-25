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
  local URL="$BASEURL/cgi-bin"
  ADMINMENU=
  if is-admin | grep -q Sim ; then
    ADMINMENU="<li><a href=\"$URL/statistic.sh/$CONTEST\"><span class=\"title\">Estatísticas</span><span class=\"text\">Relatório do Contest</span></a></li>"
    ADMINMENU+="<li><a href=\"$URL/sherlock.sh/$CONTEST\"><span class=\"title\">Sherlock</span><span class=\"text\">Identificação de Plágio</span></a></li>"
    ADMINMENU+="<li><a href=\"$URL/all-runs.sh/$CONTEST\"><span class=\"title\">Todas Submissões</span><span class=\"text\">Separadas por usuários</span></a></li>"
  fi
  if is-mon | grep -q Sim ; then
    ADMINMENU+="<li><a href=\"$URL/all-runs.sh/$CONTEST\"><span class=\"title\">Todas Submissões</span><span class=\"text\">Separadas por usuários</span></a></li>"
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
        <link type="text/css" rel="stylesheet" href="/css/menu1.css" media="screen" />
        <link type="text/css" rel="stylesheet" href="/css/badideas.css" media="screen" />
    </head>
    <body class="bg">
      <div id="geral">
        <div id="header">
          <h1><font color="white">CD-MOJ</font></h1>
          <img src="$BASEURL/images/h1_line_2.png">
          <p style="float:right;">$MSG</font></p>
          <p><font color=lightyellow>$(pega-nome $CONTEST)</font><font color=white> em <em>$CONTEST_NAME</em></font></p>
        </div>
        <div id="content">
          <div id="menu1">
          <ul>
            <li><a href="$URL/contest.sh/$CONTEST"><span class="title">Contest</span><span class="text">Problemas e Submissões</span></a></li>
            <li><a href="$URL/score.sh/$CONTEST"><span class="title">Score</span><span class="text">Placar atualizado</span></a></li>
            <li><a href="$URL/passwd.sh/$CONTEST"><span class="title">Trocar Senha</span><span class="text">CD-MOJ mais pessoal</span></a></li>
            $ADMINMENU
            <li><a href="$URL/logout.sh/$CONTEST"><span class="title">Logout</span><span class="text">Sair</span></a></li>
          </ul>
          </div>
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
function is-mon()
{
  local LOGIN=$(pega-login)
  if grep -q '\.mon$' <<< "$LOGIN"; then
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
  source $CONTESTSDIR/$1/conf
  cabecalho-html
  printf "<h1>Login em $CONTEST_NAME</h1>\n"
  cat << EOF
<form enctype="multipart/form-data" action="$BASEURL/cgi-bin/login.sh/$1" method="post">
<label class="login">Login:</label><input name="login" type="text"><br/>
<label class="login">Senha:</label><input name="senha" type="password"><br/>
  <br/>
  <input type="submit" value="Login">
  <br/>
</form>
EOF
  cat ../footer.html
  exit 0;
}
