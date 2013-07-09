#!/bin/bash

PREFIX="$1"
if [[ "x$PREFIX" == "x" ]]; then
    echo "$0 PREFIX"
    exit 0
fi

sed -ibkp -e "s/#CONFDIR#/$PREFIX\/etc/g" -e "s/#SCRIPTSDIR#/$PREFIX\/scripts/g" \
    judge/*sh html/cgi-bin/*sh
