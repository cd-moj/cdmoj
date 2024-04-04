#!/bin/bash
#This file is part of CD-MOJ.
#
#CD-MOJ is free software: you can redistribute it and/or modify
#it under the terms of the GNU General Public License as published by
#the Free Software Foundation, either version 3 of the License, or
#(at your option) any later version.
#
#CD-MOJ is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with CD-MOJ.  If not, see <http://www.gnu.org/licenses/>.

source common.sh

CAMINHO="$PATH_INFO"
CONQ_OPT="$(cut -d'/' -f2 <<<"$CAMINHO")"

if verifica-login treino |grep -q Nao; then
  tela-login treino/conquistas.usuario
fi
LOGIN=$(pega-login)

USER_CONQS="$CONTESTSDIR/treino/var/conquistas/$LOGIN"

# Verifica se o arquivo de buffer ja existe. life span = 5min
if [[ -f "$USER_CONQS""$CONQ_OPT" ]]; then
  CONQT=$(stat -c %Y "$USER_CONQS""$CONQ_OPT")
  if (( EPOCHSECONDS - CONQT < 300 )); then
    (
      flock -x 42
      cat "$USER_CONQS""$CONQ_OPT"
      exit 0
    ) 42<"$USER_CONQS""$CONQ_OPT"

      exit 0
  fi
fi

# flock para evitar concorrencia. File descriptor = 42;
(
flock -x 42
exec > >(tee "$USER_CONQS""$CONQ_OPT")


# TOTAL KD -----------------------------------------------
KD=""
if [ -d "$CONTESTSDIR/treino/controle/$LOGIN.d" ]; then
  ACERTOU=0
  SUBMISSOES=0

  for registro in "$CONTESTSDIR/treino/controle/$LOGIN.d"/*; do
    questao="$(basename "$registro")"
    if [ -d "$CONTESTSDIR/treino/var/questoes/$questao" ]; then
      source $registro
      ACERTOU=$(expr $ACERTOU + $JAACERTOU)
      SUBMISSOES=$(expr $SUBMISSOES + $TENTATIVAS)
    fi
  done

  KD="
    <div class='simpleTabsContent currentTab' style='border: 1px solid #e0e0e0; padding: 15px; font-size: 18px;'>
      <span><b>Usuario: </b> $LOGIN </span>
      <div style='display: flex; justify-content: space-between;  padding-top: 15px'>
      <span><b>Acertos: </b>$ACERTOU </span> |
      <span><b>Tentativas: </b>$SUBMISSOES </span> |
      <span><b>K/D: </b>$(printf "%.2f\n" $(echo "scale=3; ($ACERTOU / $SUBMISSOES) + 0.005" | bc))</span>
      </div>
    </div>
  "
fi

TO_SHOW=""
if [ -d "$CONTESTSDIR/treino/controle/$LOGIN.d" ]; then

# QUESTOES -----------------------------------------------
  if [ -z "$CONQ_OPT" ]; then
    for login_data in "$CONTESTSDIR/treino/controle/$LOGIN.d"/*; do
      questao="$(basename "$login_data")"

      if [ -d "$CONTESTSDIR/treino/var/questoes/$questao" ]; then
        source $login_data

        TO_SHOW+=$( < $CONTESTSDIR/treino/var/questoes/$questao/li)

        # Removendo </li> para adicionar div abaixo
        TOSHOW="${TOSHOW::-5}"
        TOSHOW+="    
            <div class="titcontest" style='border-bottom: 1px dotted #c1c1c1; display: flex; justify-content: space-between; padding-bottom: 5px'>
              <span><b>Acertos: </b> $JAACERTOU </span> |
              <span><b>Tentativas: </b>$TENTATIVAS </span> |
              <span><b>K/D: </b>$(printf "%.2f\n" $(echo "scale=3; ($JAACERTOU / $TENTATIVAS) + 0.005" | bc))</span>
            </div>
          </li>
        "
      fi
    done

# TAGS -----------------------------------------------
  elif [ "$CONQ_OPT" == "tags" ]; then
    declare -A tag_jaacertou_totals
    declare -A tag_tentativas_totals
    declare -A tag_questions

    for login_data in "$CONTESTSDIR/treino/controle/$LOGIN.d/"*; do
        questao=$(basename "$login_data")

        if [ -d "$CONTESTSDIR/treino/var/questoes/$questao" ]; then
          source $login_data
          total_jaacertou="$JAACERTOU"
          total_tentativas="$TENTATIVAS"
          
          tags_file="$CONTESTSDIR/treino/var/questoes/$questao/tags"
          
          if [ -f "$tags_file" ]; then
              while IFS= read -r tag; do
                  tag_jaacertou_totals["$tag"]=$((tag_jaacertou_totals["$tag"] + total_jaacertou))
                  tag_tentativas_totals["$tag"]=$((tag_tentativas_totals["$tag"] + total_tentativas))
                  tag_questions["$tag"]+="$questao "
                  
              done < "$tags_file"
          fi
        fi
    done

    for tag in "${!tag_jaacertou_totals[@]}"; do
        total_jaacertou="${tag_jaacertou_totals["$tag"]}"
        total_tentativas="${tag_tentativas_totals["$tag"]}"
        questions="${tag_questions["$tag"]}"
          
        TO_SHOW+="
        <li>
          <span class="titcontest"><a href="/cgi-bin/tag.sh/${tag:1}"><b>$tag</b></a></span>

          <div class="inTags"><b>Questoes: </b>
            <div class="contestTags">
        "
        for question in ${questions}; do
          if [ -f "$CONTESTSDIR/treino/enunciados/$question".html ]; then
            TO_SHOW+=$(printf "<a class=\"tagCell\" href=\"/cgi-bin/questao.sh/%s\">%s</a>" ${question//#/%23} ${question#*#})
          else
            TO_SHOW+=$(printf "<a class=\"tagCell\" style=\"color: #888 !important;\">%s</a>"  ${question#*#})
          fi
        done <<< "$questions"

        TO_SHOW+="
            </div>
          </div>

          <div class="titcontest" style='border-bottom: 1px dotted #c1c1c1; display: flex; justify-content: space-between; padding-bottom: 5px'>
            <span><b>Acertos: </b> $total_jaacertou </span> |
            <span><b>Tentativas: </b>$total_tentativas </span> |
            <span><b>K/D: </b>$(printf "%.2f\n" $(echo "scale=3; ($total_jaacertou / $total_tentativas) + 0.005" | bc))</span>
          </div>
        </li>
        "
    done
  fi
fi

if [ -z "$TO_SHOW" ]; then
  TO_SHOW="Oops, parece que voce ainda nao possui conquistas"
fi

cabecalho-html
cat <<EOF
<script type="text/javascript" src="/js/treino.js"></script>

<style type="text/css" media="screen">
  @import "/css/simpletabs.css";
  @import "/css/treino.css";
</style>

<h1>Conquistas do Usuario</h1>

<div class="simpleTabs">
  <ul class="simpleTabsNavigation">
      <li><a href="/cgi-bin/conquistas.sh">Questoes</a></li>
      <li><a href="/cgi-bin/conquistas.sh/tags">Tags</a></li>
  </ul>
  $KD
</div>

<div class="treino">
  <div class="treinoTabs" style="width: 100%;">
    <!--- Pagination script --->
    <div class="conquistas">
      <ul class="treinoList">
        $TO_SHOW
      </ul>
    </div>
  </div>
</div>

<div class="treinoTabs" style="width: 100%;">
  <ul class="treinoList" style="padding: 5px;">
    Ultima atualização: $(date +"%d/%m/%Y %H:%M:%S")
  </ul>
</div>
EOF
cat ../footer.html

) 42>"$USER_CONQS""$CONQ_OPT"
exit 0
