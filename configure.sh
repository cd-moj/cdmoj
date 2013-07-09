#!/bin/bash

PREFIX="$1"
if [[ "x$PREFIX" == "x" ]]; then
    echo "$0 PREFIX"
fi

sed -i -e "s/#CONFDIR#/$HOME\/etc/g,s/#SCRIPTSDIR#/$HOME\/scripts/g" \
    judge/* \
    html/cgi-bin/*sh
