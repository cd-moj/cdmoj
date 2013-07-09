#!/bin/bash

PREFIX="$1"
HTMLDIR="$2"

if (( $# != 2 )); then
    echo "$0 PREFIX HTMLDIR"
    exit 0
fi

bash configure.sh "$PREFIX" "$HTMLDIR"
rsync -aHx --delete-during html/ "$HTMLDIR"
rsync -aHx --delete-during bin judge scripts "$PREFIX"

mkdir -p "$HTMLDIR/contests"
cp -r contests/sample .
tar cfj "$HTMLDIR/contests/sample.tar.bz2" sample
rm -rf sample

if [[ ! -d "$PREFIX/etc/" ]]; then
    mkdir -p "$PREFIX/etc"
    echo "[ Ok ] Creating $PREFIX/etc"
fi

if [[ ! -e "$PREFIX/etc/common.conf" ]]; then
    cp etc/common.conf "$PREFIX/etc/common.conf"
    echo "[ Ok ] Copying common.conf to $PREFIX/etc"
fi

if [[ ! -e "$PREFIX/etc/judge.conf" ]]; then
    cp etc/judge.conf "$PREFIX/etc/judge.conf"
    echo "[ Ok ] Copying judge.conf to $PREFIX/etc"
    chmod 600 "$PREFIX/etc/judge.conf"
    echo "[ Ok ] chmod 600 $PREFIX/etc/judge.conf"
fi

echo "============================================="
echo "Please edit $PREFIX/etc/common.conf and"
echo " $PREFIX/etc/judge.conf"
echo "============================================="
