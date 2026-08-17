# GET /contest/animeitor/photos-zip?contest=<id>   (Bearer: .animeitor ou admin do contest)
# Pacote com TODAS as fotos dos times: `fotos/<login>.webp` + `teams.csv` (o índice que casa a
# foto com o time). O nome do arquivo é o LOGIN — a mesma chave que aparece no `contest`/`runs`
# do webcast, então o Animeitor liga foto e placar sem heurística de nome.
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
printf 'login,nome,universidade,coorte,bandeira,foto\n' > "$csv"

n=0; nf=0
while IFS= read -r d; do
  login="${d##*/}"
  case "$login" in *.admin|*.judge|*.cjudge|*.staff|*.cstaff|*.mon|*.animeitor|.removed-users) continue;; esac
  n=$((n+1))
  f="$(tp_file "$contest" "$login")"
  fname=""
  if [[ -n "$f" ]]; then
    fname="$login.${f##*.}"
    cp -f "$f" "$stg/fotos/$fname" 2>/dev/null && nf=$((nf+1)) || fname=""
  fi
  # campos do CSV com vírgula/aspas viram campo citado (RFC4180) — nome de time tem de tudo
  if [[ -f "$d/account.json" ]]; then
    jq -r --arg l "$login" --arg fn "$fname" '
      (.team // {}) as $t
      | [$l, ($t.name // .fullname // $l), ($t.univ_short // ""), ($t.cohort // ""),
         ($t.flag // ""), $fn] | @csv' "$d/account.json" 2>/dev/null
  else
    jq -rn --arg l "$login" --arg fn "$fname" '[$l,$l,"","","",$fn] | @csv'
  fi >> "$csv"
done < <(find "$CONTESTSDIR/$contest/users" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)

audit_log_to "$contest" animeitor-photos-zip "teams=$n photos=$nf by=$SESSION_LOGIN"

fn="fotos-$(printf '%s' "$contest" | tr -cd 'A-Za-z0-9._-')-$(date +%Y%m%d-%H%M).zip"
printf 'Status: 200 OK\r\n'
printf 'Content-Type: application/zip\r\n'
printf 'Content-Disposition: attachment; filename="%s"\r\n' "$fn"
printf '\r\n'
( cd "$stg" && zip -q -r - . )
