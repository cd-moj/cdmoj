#!/bin/bash

PREFIX="$1"
HTMLDIR="$2"

if (( $# != 2 )); then
    echo "$0 PREFIX HTMLDIR"
fi

bash configure.sh $PREFIX
rsync -aHx --delete-during html/ "$HTMLDIR"
rsync -aHx --delete-during etc judge scripts "$PREFIX"

echo "============================================="
echo "Please edit $PREFIX/etc/common.conf and"
echo " $PREFIX/etc/judge.conf"
echo "============================================="
