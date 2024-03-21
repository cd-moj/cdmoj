#!/bin/bash

source $SERVERDIR/etc/common.conf

# --------- CONTESTSDIR
mkdir -p "$CONTESTSDIR/treino/enunciados"
mkdir -p "$CONTESTSDIR/treino/var"
mkdir -p "$CONTESTSDIR/treino/data"
mkdir -p "$CONTESTSDIR/treino/submissions"
mkdir -p "$CONTESTSDIR/treino/controle"

if [ ! -f "$CONTESTSDIR/treino/conf" ]; then
    echo 'CONTEST_ID=Treino
    CONTEST_NAME="Treino Livre"' > "$CONTESTSDIR/treino/conf"
fi



# --------- GIT
REPO_URL=""

if [ -d "$SERVERDIR/repository/.git" ]; then
    # If the directory exists and is a git repository, pull changes
    cd "$SERVERDIR/repository" || exit
    git pull
else
    # If the directory doesn't exist or is not a git repository, clone it
    mkdir -p $SERVERDIR/repository
    git clone --recurse-submodules $REPO_URL $SERVERDIR/repository
fi



# --------- HTML
# interacting to prevent make from stopping after file naming error
for questao in $SERVERDIR/repository/*/; do
    questao=$(basename $questao)
    make $questao.html
done

# removing htmls from deleted content,
for questao in $SERVERDIR/repository/*.html; do
    pasta=$(basename "${questao%.*}")

    if [ ! -d "$SERVERDIR/repository/$pasta" ]; then
        rm "$questao"
    fi
done

rm "$CONTESTSDIR/treino/enunciados/"*.html
# use "cp" because "mv" will not allow "make" to detect when is up to date
cp "$SERVERDIR/repository/"*.html "$CONTESTSDIR/treino/enunciados"



# --------- ALL_TAGS
ALL_TAGS=()

new_tag() {
    local elemento="$1"
    local -n conjunto="$2"

    if [[ ! " ${conjunto[*]} " =~ $elemento ]]; then
        conjunto+=("$elemento")
    fi
}

for questao in $SERVERDIR/repository/*/; do
    if [ -f "$questao/tags" ]; then
        while IFS= read -r line; do
            new_tag $line ALL_TAGS
        done <"$questao/tags"
    fi
done

printf '%s\n' "${ALL_TAGS[@]}" >$CONTESTSDIR/treino/var/ALL_TAGS



# --------- CONTEST LIST
if [ -d "$CONTESTSDIR/treino/var/tags-by-contest" ]; then
    rm -rf $CONTESTSDIR/treino/var/tags-by-contest
fi
mkdir -p $CONTESTSDIR/treino/var/tags-by-contest

for questao in $SERVERDIR/repository/*/; do

    CONTEST_ID=$(basename $questao)

    if [ ! -f "$SERVERDIR/repository/$CONTEST_ID.html" ]; then
        continue
    fi

    if [ -f "$questao/tags" ]; then
        THIS="<li><span class=\"titcontest\"><a href=\"questao.sh/$CONTEST_ID\">"
        THIS+="<b>$CONTEST_ID</b></a></span>"
        THIS+="<div class=\"inTags\"><b>Tags: </b><div class=\"contestTags\">"
        THIS+=$(awk '{printf "<a class=\"tagCell\" href=\"tag.sh/%s\">%s</a>", substr($0, 2), $0}' $questao/tags)
        THIS+="</div></div></li>"

        echo "$THIS" >>$CONTESTSDIR/treino/var/tags-by-contest/$CONTEST_ID
    fi
done



# --------- CONTESTS BY TAG
if [ -d "$CONTESTSDIR/treino/var/contests-by-tags" ]; then
    rm -rf $CONTESTSDIR/treino/var/contests-by-tags
fi
mkdir -p $CONTESTSDIR/treino/var/contests-by-tags

for questao in $SERVERDIR/repository/*/; do

    CONTEST_ID=$(basename $questao)

    if [ ! -f "$SERVERDIR/repository/$CONTEST_ID.html" ]; then
        continue
    fi

    if [ -f "$questao/tags" ]; then
        while IFS= read -r line; do
            THIS="<li><span class=\"titcontest\"><a href=\"/cgi-bin/questao.sh/$CONTEST_ID\">"
            THIS+="<b>$(basename $CONTEST_ID)</b></a></span>"
            THIS+="<div class=\"inTags\"><b>Tags: </b><div class=\"contestTags\">"
            THIS+=$(awk '{printf "<a class=\"tagCell\" href=\"%s\">%s</a>", substr($0, 2), $0}' $questao/tags)
            THIS+="</div></div></li>"

            echo "$THIS" >>$CONTESTSDIR/treino/var/contests-by-tags/$line
        done <"$questao/tags"
    fi
    cp $questao/tags $CONTESTSDIR/treino/var/contests-by-tags/$CONTEST_ID
done
