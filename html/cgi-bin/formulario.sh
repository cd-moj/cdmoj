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

source common.sh
#o contest é valido, tem que verificar o login
#if verifica-login admin| grep -q Nao; then
#  tela-login admin
#fi

#ok logados
AGORA="$(date +%s)"
LOGIN=$(pega-login)
NOME="$(pega-nome admin)"
TMP=$(mktemp)
TMP_DIR=$(mktemp -d)
mkdir $TMP_DIR/enunciados
DIR_ENUNCIADOS="$TMP_DIR/enunciados"
POST=$TMP
cat > $TMP
if [[ "x$(< $TMP)" != "x" ]]; then
  BOUNDARY="$(head -n1 "$POST")"
  CONTEST_ID="$(grep -a -A3 'contest_id' "$POST"|tr '\n' '&'|cut '-d&' -f3|tr -d ' '|sed -e 's/\r//')"
  NOME_COMPLETO="$(grep -a -A3 'nome_completo' "$POST"|tr '\n' '&'|cut '-d&' -f3|sed -e 's/\r//')"
  DATA_INICIO="$(grep -a -A3 'data_inicio' "$POST"|tr '\n' '&'|cut '-d&' -f3|sed -e 's/\r//')"
  HORA_INICIO="$(grep -a -A3 'hora_inicio' "$POST"|tr '\n' '&'|cut '-d&' -f3|sed -e 's/\r//')"
  INICIO=$(date --date="$HORA_INICIO $DATA_INICIO" +%s)
  DATA_FIM="$(grep -a -A3 'data_fim' "$POST"|tr '\n' '&'|cut '-d&' -f3|sed -e 's/\r//')"
  HORA_FIM="$(grep -a -A3 'hora_fim' "$POST"|tr '\n' '&'|cut '-d&' -f3|sed -e 's/\r//')"
  TERMINO=$(date --date="$HORA_FIM $DATA_FIM" +%s)
  USERS="$(sed -n "/users/,/${BOUNDARY}/p" "$POST"|sed '1,2d;$d'|tr -d '\r')"
  N_USERS="$(sed -n "/users/,/${BOUNDARY}/p" "$POST"|sed '1,2d;$d'|wc -l)"
  SITE_ID="$(grep -a -E 'cdmoj|spoj\-br|spoj\-www' "$POST"|tr '\n' '&'|tr -d '\r')"
  ID_SITE="$(grep -a -A2 'id_site' "$POST"|sed -e 's/\--/@/g'|tr '\n' '&'|tr -d '\r')"
  TITULO="$(grep -a -A2 'titulo' "$POST"|sed -e 's/\--/@/g'|tr '\n' '&'|tr -d '\r')"
  NOME_PEQUENO="$(grep -a -A2 'nome_pequeno' "$POST"|sed -e 's/\--/@/g'|tr '\n' '&'|tr -d '\r')"
  ENUNCIADOS="$(grep -a 'filename' "$POST"|tr '\n' '&'|tr -d '\r')"
  N_CONTESTS="$(grep -a 'site_id' "$POST"|wc -l)"
  prob=""
  LINHA=""
  cont=1
  while (("$cont" <= "$N_CONTESTS")); do
    prob+="$(echo $SITE_ID|cut '-d&' -f"$cont") "
    prob+="$(echo $ID_SITE|sed -e 's/@&/@/g'|cut '-d@' -f"$cont"|cut '-d&' -f3) "
    prob+="\"$(echo $TITULO|sed -e 's/@&/@/g'|cut '-d@' -f"$cont"|cut '-d&' -f3)\" "
    prob+="$(echo $NOME_PEQUENO|sed -e 's/@&/@/g'|cut '-d@' -f"$cont"|cut '-d&' -f3) "
    prob+="$(echo $ENUNCIADOS|cut '-d&' -f"$cont"|cut '-d=' -f3|sed -e 's/\"//g')"
    LINHA+=$prob'\n'
    prob=""
    ((cont++))
  done
  CONTEST="$(echo -e $LINHA)"
  N_ENUNCIADOS="$(grep -a 'enunciado_problema' "$POST"|wc -l)"
  cont=1;
  while (( "$cont" <= "$N_ENUNCIADOS" )); do
    FILE_NAME="$(echo $ENUNCIADOS|tr '\n' '&'|cut '-d&' -f$cont|cut '-d=' -f3|sed -e 's/\"//g')"
    sed -n "/${FILE_NAME}/,/${BOUNDARY}/p" "$POST"|sed '1,3d;$d' > "$TMP_DIR/enunciados/$FILE_NAME"
    ((cont++))
  done
  cat << EOF > $TMP_DIR/contest-description.txt
$CONTEST_ID
"$NOME_COMPLETO"
$INICIO
$TERMINO
$N_CONTESTS
$CONTEST
$N_USERS
$USERS
EOF
tar cf $SUBMISSIONDIR/admin:$AGORA:$RANDOM:$LOGIN:newcontest $TMP_DIR/enunciados $TMP_DIR/contest-description.txt
fi
cabecalho-html
#echo "<pre>"
#cat $TMP
#echo "</pre>"
rm -rf $TMP $TMP_DIR
#sleep 3
echo "<br/><br/>"
printf "<h2>Últimas mensagens do LOG do admin $LOGIN</h2>"
echo "<pre>"
cat $CONTESTSDIR/admin/$LOGIN.msgs
echo "</pre>"
cat ../footer.html

exit 0
