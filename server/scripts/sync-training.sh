#!/bin/bash

source $SERVERDIR/etc/common.conf

HOST="localhost"
PORT=10000

# --------- CONTESTSDIR
mkdir -p "$CONTESTSDIR/treino/enunciados"
mkdir -p "$CONTESTSDIR/treino/var"
mkdir -p "$CONTESTSDIR/treino/var/conquistas/"
mkdir -p "$CONTESTSDIR/treino/data"
mkdir -p "$CONTESTSDIR/treino/submissions"
mkdir -p "$CONTESTSDIR/treino/controle"

if [ ! -f "$CONTESTSDIR/treino/conf" ]; then
    echo 'CONTEST_ID=treino
CONTEST_NAME="Treino Livre"' > "$CONTESTSDIR/treino/conf"
fi



# --------- GET PROBLEMS
echo "[i]    Updating listproblems: $HOST $PORT"
problems_json=$(echo '{"cmd": "listproblems"}' | nc "$HOST" "$PORT")

if [[ -z "$problems_json" ]]; then
    echo "[-]    Erro while updating listproblems"
    exit 0
fi

problems=$(jq -r '.problems[] | @json' <<< "$problems_json")

# Removendo problemas locais que nao foram encontratos no host
enunciados_locais=$(find "$CONTESTSDIR/treino/enunciados" -name "*.html" -exec basename {} .html \;)

for enunciado_local in $enunciados_locais; do
    nome_problema="${enunciado_local//#//}"
    if ! grep -q "$nome_problema" <<< "$problems"; then
    	echo "[+]    O enunciado '$enunciado_local' nao foi encontrado no host. Removendo..."
        rm "$CONTESTSDIR/treino/enunciados/$enunciado_local".html
    fi
done

# Iterar sobre cada problema
while IFS=" " read -r problem; do
    name=$(jq -r '.[0]' <<< "$problem")
    modified=$(jq -r '.[1]' <<< "$problem")

    echo ""
    echo "[i]    Trabalhando em $name"

    local_name=$(echo "${name//\//#}")
    local_modified=""
    if [[ -f "$CONTESTSDIR/treino/enunciados/$local_name".html ]]; then
        local_modified=$(stat -c %Y "$CONTESTSDIR/treino/enunciados/$local_name".html)
    fi

    # Se o arquivo nao existir ou sua data de modificacao for diferente do repositorio...
    if [[ -z "$local_modified" ]] || [[ "$local_modified" != "$modified" ]]; then

        # Obter o problema e executar comandos adicionais
        echo "[+]    Atualizando HTML de $name"
        questao_json=$(echo '{"cmd": "getproblemhtml", "param": "'$name'"}' | nc "$HOST" "$PORT")
        
        # HTML ---
        # Verifica se o html nao esta vazio e o coloca no diretorio de enunciados
        questao_html=$(jq -r .html <<< "$questao_json" | base64 -d)
        questao_title=$(jq -r .title <<< "$questao_json")
        if [[ "x$questao_html" != "x" ]]; then
            echo "$questao_html" > "$CONTESTSDIR/treino/enunciados/$local_name".html
            # trocando data de criacao do arquivo local
            touch -m -d @"$modified" "$CONTESTSDIR/treino/enunciados/$local_name".html

            mkdir -p "$CONTESTSDIR/treino/var/questoes/$local_name"
            if [[ "x$questao_title" != "x" ]]; then
                echo "$questao_title" > "$CONTESTSDIR/treino/var/questoes/$local_name/title"
                echo "[+]    Atualizando o titulo de $name"
            else
                echo "${local_name#*#}" > "$CONTESTSDIR/treino/var/questoes/$local_name/title"
                echo "[-]    $name nao possui titilo. O ID sera usado como titulo..."
            fi
        else
            echo "[-]    $name nao possui HTML. Abortando..."
            continue
        fi

        # TAGS ---
        # Verifica as tags e as coloca no diretorio
        echo "[+]    Atualizando as TAGS de $name"
        questao_tags=$(jq -r .tags <<< "$questao_json" | base64 -d | tr ' ' '_' | tr '/' '_')
        if [[ ! -z "$questao_tags" ]]; then
            echo "$questao_tags" > "$CONTESTSDIR/treino/var/questoes/$local_name/tags"
        fi

        # TL ---
        # Verifica o tl e o coloca no diretorio
        echo "[+]    Atualizando o TL de $name"
        questao_json=$(echo '{"cmd": "problemtl", "param": "'$name'"}' | nc "$HOST" "$PORT" | jq -r)
        if [[ ! -z "$questao_json" ]]; then
            mkdir -p "$CONTESTSDIR/treino/var/questoes/$local_name"
            echo "$questao_json" | jq -r '.tl[] | "\(.language): \(.tl)"' > "$CONTESTSDIR/treino/var/questoes/$local_name/tl"
        fi
        continue
    fi
    echo "[i]    Nao ha nada para fazer em $name"
done <<< "$problems"



# --------- LISTA DE QUESTOES
for questao in $CONTESTSDIR/treino/var/questoes/*/; do

    nome_questao=$(basename $questao)
    titulo=$( < "$questao/title")

    if [ ! -f "$CONTESTSDIR/treino/enunciados/$nome_questao".html ]; then
        THIS="<li><span class=\"titcontest\"><b style=\"color: #aaa; font-size: 18px;\">$titulo</b></span>"
        THIS+="<p>Não disponível</p>"
        THIS+="<div class=\"inTags\"><b>Tags: </b><div class=\"contestTags\">"
        THIS+=$(awk '{printf "<a class=\"tagCell\" href=\"tag.sh/%s\">%s</a>", substr($0, 2), $0}' $questao/tags)
        THIS+="</div></div></li>"
        
        echo "$THIS" > $questao/li
        continue
    fi

    if [ -f "$CONTESTSDIR/treino/var/questoes/$nome_questao/tags" ]; then
        # espacar o "#" do no me da questao -> ${nome_questao//#/%23}
        THIS="<li><span class=\"titcontest\"><a href=\"questao.sh/${nome_questao//#/%23}\">"
        THIS+="<b>$titulo</b></a></span>"
        THIS+="<div class=\"inTags\"><b>Tags: </b><div class=\"contestTags\">"
        THIS+=$(awk '{printf "<a class=\"tagCell\" href=\"tag.sh/%s\">%s</a>", substr($0, 2), $0}' $questao/tags)
        THIS+="</div></div></li>"
        
        echo "$THIS" > $questao/li
    fi
done



# --------- CONTESTS BY TAG
if [ -d "$CONTESTSDIR/treino/var/tags" ]; then
    rm -rf $CONTESTSDIR/treino/var/tags
fi
mkdir -p $CONTESTSDIR/treino/var/tags

for questao in $CONTESTSDIR/treino/var/questoes/*/; do

    nome_questao=$(basename $questao)
    titulo=$( < "$questao/title")

    if [ -f "$CONTESTSDIR/treino/enunciados/$nome_questao".html ]; then
        if [ -f "$questao/tags" ]; then
            while IFS= read -r line; do
                if ! echo "$line" | grep -q '[/ ]'; then
                    THIS="<li><span class=\"titcontest\"><a href=\"/cgi-bin/questao.sh/${nome_questao//#/%23}\">"
                    THIS+="<b>$titulo</b></a></span>"
                    THIS+="<div class=\"inTags\"><b>Tags: </b><div class=\"contestTags\">"
                    THIS+=$(awk '{printf "<a class=\"tagCell\" href=\"%s\">%s</a>", substr($0, 2), $0}' $questao/tags)
                    THIS+="</div></div></li>"

                    echo "$THIS" >> $CONTESTSDIR/treino/var/tags/$line
                fi
            done < "$questao/tags"
        fi
    fi
done



# --------- ALL_TAGS
ALL_TAGS=()

new_tag() {
    local elemento="$1"
    local -n conjunto="$2"

    if [[ ! " ${conjunto[*]} " =~ $elemento ]]; then
        conjunto+=("$elemento")
    fi
}

for questao in $CONTESTSDIR/treino/var/questoes/*/; do
    if [ -f "$questao/tags" ]; then
        if ! echo "$line" | grep -q '[/ ]'; then
            while IFS= read -r line; do
                new_tag $line ALL_TAGS
            done <"$questao/tags"
        fi
    fi
done
printf '%s\n' "${ALL_TAGS[@]}" > $CONTESTSDIR/treino/var/all-tags
