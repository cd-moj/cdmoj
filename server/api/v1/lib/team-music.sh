# lib/team-music.sh — MÚSICA do time: a faixa que o telão toca quando o time resolve.
#
# É a irmã de lib/team-photo.sh, e de propósito com a mesma cara (tm_* ↔ tp_*): a música chega
# pela mesa do telão (`.animeitor`), é servida por rota própria, entra no pacote .zip e tem uma
# PADRÃO para quem não mandou a sua.
#
# ⚠ Duas diferenças que valem a pena saber antes de mexer:
#  1. **Nada de conversão.** A imagem de produção NÃO tem ffmpeg (a foto tem o `convert` do
#     ImageMagick; áudio não tem equivalente). Então o mp3 é gravado COMO CHEGOU, e o que
#     protege é a VALIDAÇÃO: `file --mime-type` tem de dizer `audio/mpeg` (mesmo cuidado do
#     upload da capa do caderno). Extensão não é prova de nada.
#  2. **Sem miniatura** — não existe "thumb" de áudio; o cliente toca ou não toca.

TM_FILE=music.mp3
TM_PH=placeholder.mp3
# daqui (api/v1/lib) até server/etc são TRÊS níveis — mesma conta do TP_ETC.
: "${TM_ETC:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../etc" 2>/dev/null && pwd)}"

# tm_file <c> <login> -> caminho da música ("" se não há)
tm_file(){
  local d; d="$(user_dir "$1" "$2")"
  [[ -s "$d/$TM_FILE" ]] && { printf '%s' "$d/$TM_FILE"; return 0; }
  printf ''
}
tm_has(){ [[ -n "$(tm_file "$1" "$2")" ]]; }

# tm_is_mp3 <arquivo> — 0 se o conteúdo é mesmo MP3
tm_is_mp3(){ [[ "$(file --mime-type -b "$1" 2>/dev/null)" == audio/mpeg ]]; }

# _tm_decode <b64-ou-arquivo-com-b64> <destino> — decodifica e confere que é mp3.
# rc: 1 = base64 inválido, 2 = não é audio/mpeg.
_tm_decode(){
  local src="$1" out="$2"
  if [[ -f "$src" ]]; then base64 -d < "$src" > "$out.tmp" 2>/dev/null
  else b64_strip_data_prefix src; printf '%s' "$src" | base64 -d > "$out.tmp" 2>/dev/null; fi || { rm -f "$out.tmp"; return 1; }
  [[ -s "$out.tmp" ]] || { rm -f "$out.tmp"; return 1; }
  tm_is_mp3 "$out.tmp" || { rm -f "$out.tmp"; return 2; }
  mv -f "$out.tmp" "$out"
}

# tm_store <c> <login> <base64|arquivo-com-base64> — grava a música do time. Ecoa o caminho.
# O 3º argumento pode ser o base64 OU o caminho de um arquivo que o contém (o handler usa a
# segunda forma: 15 MB de mp3 = ~20 MB de base64, que não pode virar variável de shell).
# rc!=0: 1 = base64 inválido, 2 = não é mp3.
tm_store(){
  local c="$1" u="$2" src="$3" d out rc
  d="$(user_dir "$c" "$u")"; mkdir -p "$d" 2>/dev/null
  out="$d/$TM_FILE"
  _tm_decode "$src" "$out" || { rc=$?; return "$rc"; }
  printf '%s' "$out"
}

# tm_remove <c> <login>
tm_remove(){ local d; d="$(user_dir "$1" "$2")"; rm -f "$d/$TM_FILE"; }

# --- MÚSICA PADRÃO (quem não mandou a sua) ----------------------------------------------
# Mesma doutrina da foto padrão: a rota nunca dá 404 por ausência — devolve a padrão, e quem
# precisa saber quem MANDOU olha o `has_music` das listagens.
# tm_placeholder <c> -> a do contest, senão a de fábrica do repo
tm_placeholder(){
  local d="$CONTESTSDIR/$1" f
  [[ -s "$d/$TM_PH" ]] && { printf '%s' "$d/$TM_PH"; return 0; }
  f="$TM_ETC/team-placeholder.mp3"; [[ -s "$f" ]] && printf '%s' "$f"
}
tm_placeholder_custom(){ [[ -s "$CONTESTSDIR/$1/$TM_PH" ]]; }

# tm_placeholder_store <c> <base64|arquivo-com-base64> — troca a padrão do contest
tm_placeholder_store(){
  local out="$CONTESTSDIR/$1/$TM_PH" rc
  _tm_decode "$2" "$out" || { rc=$?; return "$rc"; }
  printf '%s' "$out"
}
tm_placeholder_reset(){ rm -f "$CONTESTSDIR/$1/$TM_PH"; }
