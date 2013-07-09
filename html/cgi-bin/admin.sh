#!/bin/bash

source common.sh

#o contest é valido, tem que verificar o login
if verifica-login admin| grep -q Nao; then
    tela-login admin
fi

#ok logados
TMP=$(mktemp)
POST=$TMP
cat > $TMP
if [[ "x$(< $TMP)" != "x" ]]; then
    LOGIN=$(pega-login)
    FILENAME="$(grep -a 'filename'  "$POST" |sed -e 's/.*filename="\(.*\)".*/\1/g')"
    fd='Content-Type: '
    boundary="$(head -n1 "$POST")"
    INICIO=$(cat -n $TMP| grep -a Content-Type|awk '{print $1}')
    ((INICIO++))
    sed -i  -e "1,${INICIO}d" $TMP
    cp $TMP $SUBMISSIONDIR/admin:$LOGIN:$FILENAME
    rm $TMP

fi
cabecalho-html
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
