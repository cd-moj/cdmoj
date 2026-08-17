#!/bin/bash
# photos-to-webp.sh [<contest> …] [--apply]
#
# Converte o ACERVO de fotos de time (users/<login>/photo.png) para WEBP, que é o formato
# de hoje (ver server/api/v1/lib/team-photo.sh). Sem --apply é dry-run: só lista o que faria
# e quanto economiza. Com --apply grava o .webp e REMOVE o .png só depois de o arquivo novo
# existir e ser mesmo um webp.
#
# Sem argumento de contest, varre TODOS os contests. A foto de PERFIL do treino
# (contests/treino/users/<login>/photo.png, 100x100) NÃO entra: é outro conceito, servido por
# outra rota — por isso o contest `treino` é pulado.
set -u
: "${CONTESTSDIR:=/home/ribas/moj/contests}"
APPLY=0; THUMBS=0; ARGS=()
for a in "$@"; do case "$a" in
  --apply)  APPLY=1;;
  --thumbs) THUMBS=1; APPLY=1;;   # só preenche as miniaturas que faltam (não reconverte foto)
  -*) echo "uso: $0 [<contest> …] [--apply] [--thumbs]" >&2; exit 1;;
  *) ARGS+=("$a");;
esac; done

command -v convert >/dev/null || { echo "sem ImageMagick (convert)" >&2; exit 1; }
convert -list format 2>/dev/null | grep -qE '^ *WEBP' || { echo "convert SEM delegate WEBP" >&2; exit 1; }

set +o noglob; shopt -s nullglob
if (( ${#ARGS[@]} )); then CONTESTS=("${ARGS[@]}"); else
  CONTESTS=(); for d in "$CONTESTSDIR"/*/; do c="${d%/}"; c="${c##*/}"; [[ "$c" == treino ]] && continue; CONTESTS+=("$c"); done
fi

# mkthumb <origem> <destino> — a MESMA receita da lib (320px/q78); `webp:` explícito porque o
# ImageMagick escolhe o formato pela extensão e o temporário é .tmp
mkthumb(){
  convert "$1" -strip -resize '320x320>' -quality 78 "webp:$2.tmp" 2>/dev/null \
    && [[ "$(file --mime-type -b "$2.tmp" 2>/dev/null)" == image/webp ]] \
    && mv -f "$2.tmp" "$2" && return 0
  rm -f "$2.tmp"; return 1
}

tot=0; ok=0; fail=0; before=0; after=0; nth=0
for c in "${CONTESTS[@]}"; do
  [[ -d "$CONTESTSDIR/$c/users" ]] || continue
  # miniaturas que faltam (para QUALQUER foto, inclusive as já convertidas)
  for f in "$CONTESTSDIR/$c/users"/*/photo.webp "$CONTESTSDIR/$c/users"/*/photo.png; do
    d="${f%/photo.*}"; th="$d/photo.thumb.webp"
    [[ -s "$th" && "$th" -nt "$f" ]] && continue
    if (( APPLY )); then mkthumb "$f" "$th" && nth=$((nth+1)); else nth=$((nth+1)); fi
  done
  (( THUMBS )) && continue
  for f in "$CONTESTSDIR/$c/users"/*/photo.png; do
    d="${f%/photo.png}"; login="${d##*/}"
    [[ -s "$d/photo.webp" ]] && continue      # já convertido (o png é resíduo)
    tot=$((tot+1)); sz=$(stat -c %s "$f" 2>/dev/null || echo 0); before=$((before+sz))
    if (( APPLY == 0 )); then printf 'DRY %s/%s (%s KB)\n' "$c" "$login" "$((sz/1024))"; continue; fi
    # `webp:` explícito: sem ele o ImageMagick escolhe o formato pela EXTENSÃO — e a do
    # temporário é `.tmp`, que não é formato nenhum (era o motivo de falhar em tudo)
    if convert "$f" -auto-orient -strip -resize '1000x1000>' -quality 82 "webp:$d/photo.webp.tmp" 2>/dev/null \
       && [[ "$(file --mime-type -b "$d/photo.webp.tmp" 2>/dev/null)" == image/webp ]]; then
      mv -f "$d/photo.webp.tmp" "$d/photo.webp"; rm -f "$f"
      nsz=$(stat -c %s "$d/photo.webp" 2>/dev/null || echo 0); after=$((after+nsz)); ok=$((ok+1))
      printf 'OK  %s/%s %s KB -> %s KB\n' "$c" "$login" "$((sz/1024))" "$((nsz/1024))"
    else
      rm -f "$d/photo.webp.tmp"; fail=$((fail+1)); printf 'ERRO %s/%s\n' "$c" "$login"
    fi
  done
done
printf -- '---\n%s foto(s); convertidas=%s falhas=%s; %s KB -> %s KB; miniaturas=%s\n' \
  "$tot" "$ok" "$fail" "$((before/1024))" "$((after/1024))" "$nth"
(( APPLY == 0 )) && printf 'dry-run: rode com --apply para gravar\n'
exit 0
