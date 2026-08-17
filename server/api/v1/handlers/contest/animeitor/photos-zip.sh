# GET /contest/animeitor/photos-zip?contest=<id>   (Bearer: .animeitor ou admin do contest)
# Pacote com as fotos dos times: `fotos/<login>.webp` + `teams.csv` (o índice que casa a foto
# com o time) + `placeholder.webp`. O nome do arquivo é o LOGIN — a mesma chave que aparece no
# `contest`/`runs` do webcast, então o Animeitor liga foto e placar sem heurística de nome.
# TODO time tem arquivo: quem não mandou foto leva a FOTO PADRÃO (decisão do produto — o
# Animeitor acha `<login>.webp` sempre e não precisa tratar ausência). Quem mandou de verdade
# está na coluna `padrao` do CSV (false = foto do time).
# Foto antiga em PNG entra como `fotos/<login>.png` (o pacote diz a verdade sobre o acervo;
# server/bin/photos-to-webp.sh converte tudo de uma vez).
require_method GET
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
{ is_animeitor || is_admin; } || fail 403 "Apenas a conta de placar (.animeitor) ou o admin" "animeitor_required"
source "$_LIBDIR/team-photo.sh"

stg="$(mktemp -d 2>/dev/null)" || fail 500 "tmp" "tmp"
trap 'rm -rf "$stg"' EXIT
mkdir -p "$stg/fotos"
csv="$stg/teams.csv"
printf 'login,nome,universidade,coorte,bandeira,foto,padrao\n' > "$csv"

# a padrão entra UMA vez na raiz (referência) e é copiada p/ cada time sem foto
PH="$(tp_placeholder "$contest")"
[[ -n "$PH" ]] && cp -f "$PH" "$stg/placeholder.webp" 2>/dev/null

n=0; nf=0; nph=0
while IFS= read -r d; do
  login="${d##*/}"
  case "$login" in *.admin|*.judge|*.cjudge|*.staff|*.cstaff|*.mon|*.animeitor|.removed-users) continue;; esac
  n=$((n+1))
  f="$(tp_file "$contest" "$login")"
  fname=""; isph=false
  if [[ -n "$f" ]]; then
    fname="$login.${f##*.}"
    cp -f "$f" "$stg/fotos/$fname" 2>/dev/null && nf=$((nf+1)) || fname=""
  elif [[ -n "$PH" ]]; then
    fname="$login.${PH##*.}"; isph=true
    cp -f "$PH" "$stg/fotos/$fname" 2>/dev/null && nph=$((nph+1)) || { fname=""; isph=false; }
  fi
  # campos do CSV com vírgula/aspas viram campo citado (RFC4180) — nome de time tem de tudo
  if [[ -f "$d/account.json" ]]; then
    jq -r --arg l "$login" --arg fn "$fname" --argjson ph "$isph" '
      (.team // {}) as $t
      | [$l, ($t.name // .fullname // $l), ($t.univ_short // ""), ($t.cohort // ""),
         ($t.flag // ""), $fn, $ph] | @csv' "$d/account.json" 2>/dev/null
  else
    jq -rn --arg l "$login" --arg fn "$fname" --argjson ph "$isph" '[$l,$l,"","","",$fn,$ph] | @csv'
  fi >> "$csv"
done < <(find "$CONTESTSDIR/$contest/users" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)

audit_log_to "$contest" animeitor-photos-zip "teams=$n photos=$nf padrao=$nph by=$SESSION_LOGIN"

fn="fotos-$(printf '%s' "$contest" | tr -cd 'A-Za-z0-9._-')-$(date +%Y%m%d-%H%M).zip"
printf 'Status: 200 OK\r\n'
printf 'Content-Type: application/zip\r\n'
printf 'Content-Disposition: attachment; filename="%s"\r\n' "$fn"
printf '\r\n'
( cd "$stg" && zip -q -r - . )
