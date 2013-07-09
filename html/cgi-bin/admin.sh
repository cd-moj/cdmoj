#!/bin/bash

source common.sh

#o contest é valido, tem que verificar o login
if verifica-login $CONTEST| grep -q Nao; then
    tela-login $CONTEST
fi

#ok logados
POST="$(cat |tr -d '\r' )"
if [[ "x$POST" != "x" ]]; then
    LOGIN=$(pega-login)
    FILENAME="$(grep 'filename' <<< "$POST" |sed -e 's/.*filename="\(.*\)".*/\1/g')"
    fd='Content-Type: '
    boundary="$(head -n1 <<< "$POST")"
    sed -e "1,/$fd/d;/^$/d;/$boundary/,\$d" <<< "$POST" > $SUBMISSIONDIR/admin:$LOGIN:$FILENAME

fi

printf "<h1>Administrador</h1>\n"

printf "<h2>Baixe o contest template</h2>\n"
printf "<p> <a href=\"$BASEURL/contests/sample.tar.bz2\">AQUI</a></h1>\n"

echo "<br/><br/>"
printf "<h2>Envie o novo contest</h2>"

cat << EOF
<p> Reenviar um contest já existente irá recriá-lo sem perder as submissões
</p>
<form enctype="multipart/form-data" action="$BASEURL/cgi-bin/admin.sh" method="post">
    <input type="hidden" name="MAX_FILE_SIZE" value="30000">
    File: <input name="myfile" type="file">
    <br/>
    <input type="submit" value="Submit">
    <br/>
</form>
EOF

exit 0
