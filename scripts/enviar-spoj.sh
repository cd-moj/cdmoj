SPOJLANGS=(C Cpp Java Pascal Bash)

function login-spoj()
{
  local SITE="$1"
  #source enviar-conf
   curl -c $HOME/.cache/cookie-spoj-$SITE -s -A "Mozilla/4.0" \
     -F "login_user=$LOGINSPOJ" -F "password=$PASSWDSPOJ" \
       http://$SITE.spoj.com > /dev/null
}

#retorna o ID da submissao
function enviar-spoj()
{
  ARQFONTE="$1"
  PROBID="$2"
  LINGUAGEM="$3"
  local SITE="$4"
  if (( $(wc -l "$ARQFONTE" |awk '{print $1}') == 0 )); then
    echo "ArquivoCorrompido"
    return
  fi

  #C é 11, mas vamos deixar 41
  if [[ "$LINGUAGEM" == "C" ]];then
    LINGUAGEM=11;
  elif [[ "$LINGUAGEM" == "Cpp" ]];then
    LINGUAGEM=41;
  elif [[ "$LINGUAGEM" == "CPP" ]];then
    LINGUAGEM=41;
  elif [[ "$LINGUAGEM" == "C++" ]];then
    LINGUAGEM=41;
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
  else
    LINGUAGEM=41;
  fi

  #enviar
  curl -A "Mozilla/4.0" -b ~/.cache/cookie-spoj-$SITE \
    -F "subm_file=@$ARQFONTE" \
    -F "lang=$LINGUAGEM" \
    -F "problemcode=$PROBID" \
      http://$SITE.spoj.com/submit/complete/ |
    grep newSubmissionId |awk -F'"' '{print $(NF-1)}'
}

#Retorna string do resultado
function pega-resultado-spoj()
{
  #source enviar-conf
  JOBID="$1"
  local SITE="$2"
  RESP=
  if [[ "$JOBID" == "ArquivoCorrompido" ]]; then
    RESP="Arquivo Corrompido, reenvie"
  else
    RESP="$(curl -s -A "Mozilla/4.0" http://$SITE.spoj.com/status/$LOGINSPOJ/signedlist/|grep $JOBID|awk -F'|' '{print $5}')"
    RESP=${RESP// }
    while [[ "$RESP" == "??" ]]; do
      sleep 5
      RESP="$(curl -s -A "Mozilla/4.0" http://$SITE.spoj.com/status/$LOGINSPOJ/signedlist/|grep $JOBID|awk -F'|' '{print $5}')"
      RESP=${RESP// }
  done
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

#wrappers
function login-spoj-br()
{
  login-spoj br
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
  login-spoj www
}

function enviar-spoj-www()
{
  enviar-spoj "$1" "$2" "$3" www
}

function pega-resultado-spoj-www()
{
  pega-resultado-spoj "$1" www
}
