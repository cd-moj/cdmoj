#!/bin/bash

source #CONFDIR#/common.conf

NEWCONTEST="$1"
CONTESTDESC="$1/contest-description.txt"

if (( $# != 1 )); then
    echo "$0 path/to/contest-description.txt"
    echo "    check file format"
    exit 0
fi

if [[ ! -e "$CONTESTDESC" ]]; then
    echo "\"$CONTESTDESC\": file not found"
    exit 0
fi

#if [[ ! -d "$CONTESTSDIR" ]]; then
#    echo "\"$CONTESTSDIR\": Directory not fount"
#    exit 0
#fi

CONTEST_ID=
CONTEST_NAME=
ALLPROBS=
USUARIOS=
{
    read CONTEST_ID
    read CONTEST_NAME
    read CONTEST_START
    read CONTEST_END
    read PROBCOUNT
    for((i=0;i<PROBCOUNT;i++)); do
        read PROBDESC
        ALLPROBS=( "${ALLPROBS[@]}" "$PROBDESC" )
    done

    read USUARIOSCOUNT
    for((i=0;i<USUARIOSCOUNT;i++)); do
        read LINHA
        USUARIOS="$USUARIOS$LINHA\n"
    done
} < "$CONTESTDESC"

mkdir "$CONTESTSDIR/$CONTEST_ID"

for i in controle data enunciados submissions; do
    mkdir "$CONTESTSDIR/$CONTEST_ID/$i"
done

#data of users must be writabble by www-data
chmod go+rwx "$CONTESTSDIR/$CONTEST_ID/data"

{
    echo "CONTEST_ID=$CONTEST_ID"
    echo "CONTEST_NAME=$CONTEST_NAME"
    echo "CONTEST_START=$CONTEST_START"
    echo "CONTEST_END=$CONTEST_END"
    echo "PROBS=(${ALLPROBS[@]})"
} > $CONTESTSDIR/$CONTEST_ID/conf

printf "$USUARIOS" > $CONTESTSDIR/$CONTEST_ID/passwd

if [[ -d "$NEWCONTEST/enunciados" ]]; then
    #copia enunciados para html
    mkdir -p $HTMLDIR/contests/$CONTEST_ID/
    cp -r $NEWCONTEST/enunciados/* $HTMLDIR/contests/$CONTEST_ID/
    chmod a+rX -R $NEWCONTEST/enunciados/* $HTMLDIR/contests/$CONTEST_ID/
fi

exit 0
