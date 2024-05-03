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

# Array para armazenar as linhas do arquivo
ALL_TAGS=()

# Ler cada linha do arquivo e adicionar ao array
while IFS= read -r line; do
    ALL_TAGS+=("$line")
done < $CONTESTSDIR/treino/var/all-tags

ALL_TAGS=($(printf "%s\n" "${ALL_TAGS[@]}" | sort))


SECTIONS=""
# Function to add a new section
add_section() {
    SECTIONS+="<div class=\"tagSection\">
      <p>${1^}</p>
      <div class=\"tagsContent\">
        $2
      </div>
    </div>"
}

# Iterate over the words
current_section=""
current_content=""
for word in "${ALL_TAGS[@]}"; do
    # Extract the first letter
    first_letter="${word:1:1}"

    # If the first letter changes, add the current section and start a new one
    if [[ "$first_letter" != "$current_section" ]]; then
        # Add the current section if it's not empty
        if [[ -n "$current_section" ]]; then
            add_section "$current_section" "$current_content"
        fi
        # Start a new section
        current_section="$first_letter"
        current_content=""
    fi
    # Add the current word to the content of the section
    current_content+="<a class=\"tagCell\" href=\"tag.sh/${word:1}\">$word</a>"
done
# Add the last section
add_section "$current_section" "$current_content"


cabecalho-html
cat <<EOF
<script type="text/javascript" src="/js/treino.js"></script>

<style type="text/css" media="screen">
  @import "/css/treino.css";
</style>

<div>
  <h1>Tags</h1>
  <div class="treino" style="flex-wrap: wrap;">
    $SECTIONS
  </div>
</div>
EOF
cat ../footer.html

exit 0
