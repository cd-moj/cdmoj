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

SPOJLANGS=(C Cpp Java Pascal Bash)

function enviar-spoj()
{
  ARQFONTE="$1"
  PROBID="$2"
  LINGUAGEM="$3"
  local SITE="$4"
  if [[ "x$SITE" == "x" ]]; then
    SITE=www
  fi

  if (( $(wc -l "$ARQFONTE" |awk '{print $1}') == 0 )); then
    echo "ArquivoCorrompido"
    return
  fi

  if [[ "$LINGUAGEM" == "C" ]];then
    LINGUAGEM=11;
  elif [[ "$LINGUAGEM" == "CXX" ]];then
    LINGUAGEM=1;
  elif [[ "$LINGUAGEM" == "CPP" ]];then
    LINGUAGEM=44;
  elif [[ "$LINGUAGEM" == "C++" ]];then
    LINGUAGEM=44;
  elif [[ "$LINGUAGEM" == "Java" ]];then
    LINGUAGEM=10;
  elif [[ "$LINGUAGEM" == "JAVA" ]];then
    LINGUAGEM=10;
  elif [[ "$LINGUAGEM" == "Pascal" ]];then
    LINGUAGEM=22;
  elif [[ "$LINGUAGEM" == "PAS" ]];then
    LINGUAGEM=22;
  elif [[ "$LINGUAGEM" == "Bash" ]];then
    LINGUAGEM=28;
  elif [[ "$LINGUAGEM" == "SH" ]];then
    LINGUAGEM=28;
  elif [[ "$LINGUAGEM" == "PY" ]];then
    LINGUAGEM=4;
  elif [[ "$LINGUAGEM" == "PERL" ]];then
    LINGUAGEM=3;
  elif [[ "$LINGUAGEM" == "CS" ]];then
    LINGUAGEM=27;
  elif [[ "$LINGUAGEM" == "HS" ]];then
    LINGUAGEM=21;
  elif [[ "$LINGUAGEM" == "LUA" ]];then
    LINGUAGEM=26;
  elif [[ "$LINGUAGEM" == "RB" ]];then
    LINGUAGEM=17;
  elif [[ "$LINGUAGEM" == "PHP" ]];then
    LINGUAGEM=29;
  elif [[ "$LINGUAGEM" == "F95" ]]; then
    LINGUAGEM=5;
  else
    LINGUAGEM=1;
    echo "LangNotFound"
    return
  fi

  curl -m 30 -A "Mozilla/4.0" -b $HOME/.cache/cookie-spoj-$SITE \
    -d "lang=$LINGUAGEM&problemcode=$PROBID" \
    --data-urlencode "file@$ARQFONTE" https://$SITE.spoj.com/submit/complete/ |
    grep newSubmissionId | awk -F'"' '{print $(NF-1)}'
  if echo "${PIPESTATUS[@]}"|grep -q 1; then
    mv ${ARQFONTE} ${ARQFONTE%PP}XX
  fi
}

function pega-resultado-spoj()
{
  JOBID="$1"
  local SITE="$2"
  if [[ "x$SITE" == "x" ]]; then
    SITE=www
  fi

  local CONT=0
  RESP=
  if [[ "$JOBID" == "ArquivoCorrompido" ]]; then
    RESP="Arquivo Corrompido, reenvie"
  elif [[ "$JOBID" == "LangNotFound" ]]; then
    RESP="Linguagem nao identificada, utilize a extensão correta."
  else
    RESP="$(curl -m 30 -s -A "Mozilla/4.0" -b $HOME/.cache/cookie-spoj-$SITE https://$SITE.spoj.com/status/$LOGINSPOJ/signedlist/|grep $JOBID|awk -F'|' '{print $5}')"
    RESP=${RESP// }
    while [[ "$RESP" == "??" ]] && ((CONT < 25)); do
      ((CONT++))
      sleep 5
      RESP="$(curl -m 30 -s -A "Mozilla/4.0" -b $HOME/.cache/cookie-spoj-$SITE https://$SITE.spoj.com/status/$LOGINSPOJ/signedlist/|grep $JOBID|awk -F'|' '{print $5}')"
      RESP=${RESP// }
  done
  fi

  if (( CONT >= 25 )); then
    RESP="??"
  fi

  case "$RESP" in
    AC)
      RESP="Accepted"
      ;;
    WA)
      RESP="Wrong Answer"
      ;;
    RE)
      RESP="RunTime Error"
      ;;
    TLE)
      RESP="Time Limit Exceeded"
      ;;
    CE)
      RESP="Compilation Error"
      ;;
  esac
  echo "$RESP"
}

function login-spoj-br()
{
  curl -m 30 -c $HOME/.cache/cookie-spoj-br -s -A "Mozilla/4.0" \
    -d "login_user=$LOGINSPOJ&password=$PASSWDSPOJ" \
    https://www.spoj.com/login/aHR0cDovL2JyLnNwb2ouY29tLw== > /dev/null
}

function enviar-spoj-br()
{
  enviar-spoj "$1" "$2" "$3" br
}

function pega-resultado-spoj-br()
{
  pega-resultado-spoj "$1" br
}

function login-spoj-www()
{
  curl -m 30 -c $HOME/.cache/cookie-spoj-www -s -A "Mozilla/4.0" \
    -d "login_user=$LOGINSPOJ&password=$PASSWDSPOJ" \
    https://www.spoj.com > /dev/null
}

function enviar-spoj-www()
{
  enviar-spoj "$1" "$2" "$3" www
}

function pega-resultado-spoj-www()
{
  pega-resultado-spoj "$1" www
}
