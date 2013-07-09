#!/bin/bash

source common.sh

#o contest é valido, tem que verificar o login
if verifica-login $CONTEST| grep -q Nao; then
    tela-login $CONTEST
fi

#ok logados

printf "<h1>Administrador</h1>\n"

printf "<p>For now we only support a non-html way of administration</p>\n"

exit 0
