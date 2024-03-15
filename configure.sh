#!/bin/bash

PREFIX="$1"
HTMLDIR="$2"
if [[ "x$PREFIX" == "x" ]]; then
  echo "$0 PREFIX"
  exit 0
fi

sed -ibkp -e "s;#CONFDIR#;$PREFIX/etc;g" -e "s;#SCRIPTSDIR#;$PREFIX/scripts;g" \
  -e "s;#HTMLDIR#;$HTMLDIR;g" -e "s;#BASEDIR#;$PREFIX;g"\
  judge/*sh html/cgi-bin/*sh bin/*sh etc/* scripts/* daemons/*sh
