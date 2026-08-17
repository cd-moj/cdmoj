# lib/team-photo.sh — FOTO e BRASÃO do time: um caminho só para gravar e para achar.
#
# A foto do time chega por três portas (o capitão na inscrição, o admin no painel de Times e o
# .animeitor na página do telão) e antes cada uma repetia o mesmo `convert`. Agora todas passam
# por aqui, e o formato de armazenamento é **WEBP** (decisão do Ribas): a foto de time é grande
# (170-620 KB em PNG no esquenta) e o pacote que vai para o Animeitor fica muito menor.
#
# LEGADO: os `photo.png` que já estão no disco continuam válidos e servidos — `tp_file` procura
# o webp primeiro e cai no png. `server/bin/photos-to-webp.sh --apply` converte o acervo antigo.
# Por isso NADA no código pode presumir a extensão: use tp_file/tp_has.
#
# ⚠ O `convert` precisa do delegate WEBP (libwebp). Sem ele, o ImageMagick grava PNG com nome
# .webp SEM avisar — por isso `tp_store` confere o formato do arquivo gravado antes de publicar
# (e o Containerfile tem asserção de build).

# tp_file <c> <login> -> caminho da foto existente ("" se não há)
tp_file(){
  local d; d="$(user_dir "$1" "$2")"
  [[ -s "$d/photo.webp" ]] && { printf '%s' "$d/photo.webp"; return 0; }
  [[ -s "$d/photo.png"  ]] && { printf '%s' "$d/photo.png";  return 0; }
  printf ''
}
tp_has(){ [[ -n "$(tp_file "$1" "$2")" ]]; }

# tp_ctype <arquivo> -> Content-Type pela EXTENSÃO (só gravamos webp/png)
tp_ctype(){ case "$1" in *.webp) printf 'image/webp';; *) printf 'image/png';; esac; }

# tp_store <c> <login> <base64> [maxpx] — grava a foto (webp). Ecoa o caminho final.
# Aceita qualquer formato de entrada (png/jpg/webp/…): quem valida é o convert.
# rc!=0: 1 = base64 inválido, 2 = imagem inválida/sem delegate webp.
tp_store(){
  local c="$1" u="$2" b64="$3" px="${4:-1000}" d out tmp
  d="$(user_dir "$c" "$u")"; mkdir -p "$d" 2>/dev/null
  out="$d/photo.webp"
  b64="${b64#data:*;base64,}"                       # tolera data-url
  tmp="$(mktemp)" || return 2
  printf '%s' "$b64" | base64 -d > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
  # '>' = só ENCOLHE (não infla foto pequena); -strip tira metadados (EXIF/GPS da câmera)
  if ! convert "$tmp" -auto-orient -strip -resize "${px}x${px}>" -quality 82 "webp:$out.tmp" 2>/dev/null; then
    rm -f "$tmp" "$out.tmp"; return 2
  fi
  rm -f "$tmp"
  # o convert sem delegate WEBP escreve PNG calado: conferir o que saiu, não o que pedimos.
  # (--mime-type, não a descrição por extenso: essa muda entre versões do `file`.)
  if [[ "$(file --mime-type -b "$out.tmp" 2>/dev/null)" != image/webp ]]; then
    rm -f "$out.tmp"; return 2
  fi
  mv -f "$out.tmp" "$out"
  rm -f "$d/photo.png"                              # o webp substitui o legado deste time
  _tp_mkthumb "$out" "$d/$TP_THUMB"                 # miniatura já sai pronta (50 ms)
  printf '%s' "$out"
}

# --- MINIATURA (galeria) ---------------------------------------------------------------
# A galeria do .animeitor mostra o time num cartão de ~170px: servir a foto de 1000px ali é
# 37 KB por cartão (numa prova de 1000 times, dezenas de MB ao rolar). A miniatura de 320px
# custa 7 KB. Ela nasce no upload; para o acervo antigo é gerada na 1ª leitura, no molde
# build-once do pr_build_pdf (lib/print.sh): confere mtime, flock, reconfere dentro do lock.
TP_THUMB=photo.thumb.webp

_tp_mkthumb(){  # <origem> <destino> — silencioso; rc!=0 se não deu
  convert "$1" -strip -resize '320x320>' -quality 78 "webp:$2.tmp" 2>/dev/null || { rm -f "$2.tmp"; return 1; }
  [[ "$(file --mime-type -b "$2.tmp" 2>/dev/null)" == image/webp ]] || { rm -f "$2.tmp"; return 1; }
  mv -f "$2.tmp" "$2"
}

# tp_thumb <c> <login> -> caminho da miniatura ("" se não há foto nem deu para gerar)
tp_thumb(){
  local c="$1" u="$2" d src th
  src="$(tp_file "$c" "$u")"; [[ -n "$src" ]] || { printf ''; return 0; }
  d="$(user_dir "$c" "$u")"; th="$d/$TP_THUMB"
  [[ -s "$th" && "$th" -nt "$src" ]] && { printf '%s' "$th"; return 0; }
  ( flock -w 10 9 || exit 1
    [[ -s "$th" && "$th" -nt "$src" ]] && exit 0            # outro processo já gerou
    _tp_mkthumb "$src" "$th" || exit 1
  ) 9>"$d/.thumb.lock" 2>/dev/null
  [[ -s "$th" ]] && { printf '%s' "$th"; return 0; }
  printf '%s' "$src"                                        # sem miniatura, serve a foto
}

# tp_remove <c> <login> — apaga a foto (as duas extensões) e a miniatura
tp_remove(){ local d; d="$(user_dir "$1" "$2")"; rm -f "$d/photo.webp" "$d/photo.png" "$d/$TP_THUMB"; }

# --- FOTO PADRÃO (quem não mandou foto) -------------------------------------------------
# A API nunca mais devolve 404 de foto: time sem foto recebe a PADRÃO, para o Animeitor (que
# busca a foto de cada time do placar) não ficar com buraco no telão. Quem escolhe a imagem é o
# `.animeitor` do contest; sem escolha, vale a de fábrica que vem no repo — mesmo padrão do
# info-sheet (`server/etc/info-sheet.pt.md`, sobrescrito por `contests/<c>/docs/`).
# ⚠ Em produção `server/etc/` é read-only (vem da imagem): a miniatura de fábrica é COMMITADA,
# nada é gerado ao lado dela. Só a customizada (em contests/<c>/) nasce em runtime.
TP_PH=placeholder.webp
TP_PH_THUMB=placeholder.thumb.webp
# daqui (api/v1/lib) até server/etc são TRÊS níveis — o `$_DIR/../../etc` do contest-docs.sh
# parte de api/v1, não da lib.
: "${TP_ETC:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../etc" 2>/dev/null && pwd)}"

# tp_placeholder <c> [thumb] -> caminho da foto padrão (custom do contest, senão a de fábrica)
tp_placeholder(){
  local c="$1" want="${2:-}" d f
  d="$CONTESTSDIR/$c"
  if [[ -n "$want" ]]; then
    [[ -s "$d/$TP_PH_THUMB" ]] && { printf '%s' "$d/$TP_PH_THUMB"; return 0; }
    [[ -s "$d/$TP_PH" ]]       && { printf '%s' "$d/$TP_PH"; return 0; }   # custom sem thumb
    f="$TP_ETC/team-placeholder.thumb.webp"; [[ -s "$f" ]] && { printf '%s' "$f"; return 0; }
  else
    [[ -s "$d/$TP_PH" ]] && { printf '%s' "$d/$TP_PH"; return 0; }
  fi
  f="$TP_ETC/team-placeholder.webp"; [[ -s "$f" ]] && printf '%s' "$f"
}

# tp_placeholder_custom <c> — 0 se o contest tem padrão PRÓPRIA (≠ a de fábrica)
tp_placeholder_custom(){ [[ -s "$CONTESTSDIR/$1/$TP_PH" ]]; }

# tp_placeholder_store <c> <base64> — grava a padrão do contest (mesma receita da foto de time).
# rc!=0: 1 = base64 inválido, 2 = imagem inválida/sem delegate webp.
tp_placeholder_store(){
  local c="$1" b64="$2" d out tmp
  d="$CONTESTSDIR/$c"; out="$d/$TP_PH"
  b64="${b64#data:*;base64,}"
  tmp="$(mktemp)" || return 2
  printf '%s' "$b64" | base64 -d > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
  if ! convert "$tmp" -auto-orient -strip -resize '1000x1000>' -quality 82 "webp:$out.tmp" 2>/dev/null; then
    rm -f "$tmp" "$out.tmp"; return 2
  fi
  rm -f "$tmp"
  [[ "$(file --mime-type -b "$out.tmp" 2>/dev/null)" == image/webp ]] || { rm -f "$out.tmp"; return 2; }
  mv -f "$out.tmp" "$out"
  _tp_mkthumb "$out" "$d/$TP_PH_THUMB"
  printf '%s' "$out"
}

# tp_placeholder_reset <c> — volta à de fábrica (apaga a do contest, como o "remove" da capa)
tp_placeholder_reset(){ rm -f "$CONTESTSDIR/$1/$TP_PH" "$CONTESTSDIR/$1/$TP_PH_THUMB"; }
