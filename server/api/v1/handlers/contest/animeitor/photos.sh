# GET /contest/animeitor/photos?contest=<id>   (Bearer: .animeitor ou admin do contest)
# Galeria das fotos dos times: um item por conta que compete (papel fora), com nome, sigla,
# coorte, se tem foto, bytes e mtime. É o que a página do telão lista para conferir quem ainda
# não mandou foto. A imagem em si vem por /contest/team-photo (rota pública, com cache).
require_method GET
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
{ is_animeitor || is_admin; } || fail 403 "Apenas a conta de placar (.animeitor) ou o admin" "animeitor_required"
source "$_LIBDIR/team-photo.sh"

cdir="$CONTESTSDIR/$contest"
# mesma exclusão de papel do /contest/teams (a lista canônica vive em lib/auth.sh)
items="$( { find "$cdir/users" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | while IFS= read -r d; do
    login="${d##*/}"
    case "$login" in *.admin|*.judge|*.cjudge|*.staff|*.cstaff|*.mon|*.animeitor|.removed-users) continue;; esac
    f="$(tp_file "$contest" "$login")"
    sz=0; mt=0
    if [[ -n "$f" ]]; then sz="$(stat -c %s "$f" 2>/dev/null || echo 0)"; mt="$(stat -c %Y "$f" 2>/dev/null || echo 0)"; fi
    fmt=""; [[ "$f" == *.webp ]] && fmt=webp; [[ "$f" == *.png ]] && fmt=png
    if [[ -f "$d/account.json" ]]; then
      jq -c --arg l "$login" --argjson sz "$sz" --argjson mt "$mt" --arg fmt "$fmt" \
        '(.team // {}) as $t
         | {login:$l, name:(($t.name // .fullname // $l)), univ:($t.univ_short // ""),
            cohort:($t.cohort // ""), flag:($t.flag // ""),
            has_photo:($fmt != ""), format:$fmt, bytes:$sz, mtime:$mt}' "$d/account.json" 2>/dev/null
    else
      # participante compartilhado (USERS_FROM) sem account local: só o que dá para saber
      jq -cn --arg l "$login" --argjson sz "$sz" --argjson mt "$mt" --arg fmt "$fmt" \
        '{login:$l, name:$l, univ:"", cohort:"", flag:"", has_photo:($fmt != ""), format:$fmt, bytes:$sz, mtime:$mt}'
    fi
  done; } | jq -cs 'sort_by(.name|ascii_downcase)')"
[[ -n "$items" ]] || items='[]'

ok_json_slurp '{teams:$t[0], total:($t[0]|length), with_photo:($t[0]|map(select(.has_photo))|length)}' t "$items"
