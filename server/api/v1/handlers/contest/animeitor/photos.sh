# GET /contest/animeitor/photos?contest=<id>   (Bearer: .animeitor ou admin do contest)
# Galeria das fotos: um item por conta que compete (papel fora), com nome, sigla, coorte, sede,
# se tem foto, formato, bytes e **mtime** (o cliente usa como cache-buster estável do <img>).
#
# ESCALA: prova de verdade tem 1000+ times. A versão ingênua (um `jq` + dois `stat` + um
# subshell POR TIME) levava 5,3 s com 1000 — aqui são DUAS varreduras, no molde do
# score/score-common.sh (`sc_cells`): um `find -printf` traz tamanho+mtime de todas as fotos e um
# `find | xargs jq` lê todas as contas de uma vez (o login sai do `input_filename`). A junção é
# por --slurpfile: agregado de N arquivos NUNCA entra por --argjson (teto de 128 KiB por arg).
require_method GET
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
{ is_animeitor || is_admin; } || fail 403 "Apenas a conta de placar (.animeitor) ou o admin" "animeitor_required"

cdir="$CONTESTSDIR/$contest"
W="$(mktemp -d)" || fail 500 "tmp" "tmp"
trap 'rm -rf "$W"' EXIT

# (1) fotos: uma varredura com tamanho e mtime (nada de `stat` por arquivo)
find "$cdir/users" -mindepth 2 -maxdepth 2 \( -name 'photo.webp' -o -name 'photo.png' \) \
  -printf '%h\t%f\t%s\t%T@\n' 2>/dev/null > "$W/ph.tsv" || :
jq -R -s '[ split("\n")[] | select(length > 0) | split("\t")
            | select(length >= 4)
            | {login:(.[0] | split("/") | .[-1]), file:.[1],
               bytes:(.[2] | tonumber), mtime:(.[3] | tonumber | floor)} ]' \
  "$W/ph.tsv" > "$W/ph.json" 2>/dev/null || printf '[]' > "$W/ph.json"

# (2) contas: um jq só (login pelo input_filename — account.json de participante compartilhado
# pode nem ter o campo). Conta de PAPEL sai aqui dentro (lista canônica de lib/auth.sh).
find "$cdir/users" -mindepth 2 -maxdepth 2 -name account.json -print0 2>/dev/null \
  | xargs -0 -r jq -c '
      (input_filename | split("/") | .[-2]) as $l
      | select($l | test("\\.(admin|judge|cjudge|staff|cstaff|mon|animeitor)$") | not)
      | (.team // {}) as $t
      | {login:$l, name:(($t.name // .fullname // $l)), univ:($t.univ_short // ""),
         cohort:($t.cohort // ""), region:($t.region // ""), flag:($t.flag // "")}' \
  > "$W/acc.json" 2>/dev/null || :

# (3) junta: conta ∪ (dir que só tem foto — participante de USERS_FROM sem account local)
jq -cn --slurpfile acc "$W/acc.json" --slurpfile ph "$W/ph.json" '
  ($ph[0] // []) as $P
  | ($P | map({(.login): .}) | add // {}) as $byl
  | ($acc | map({(.login): true}) | add // {}) as $known
  | ( $acc + ( $P | map(.login) | unique
               | map(select($known[.] == null))
               | map(select(test("\\.(admin|judge|cjudge|staff|cstaff|mon|animeitor)$") | not))
               | map({login:., name:., univ:"", cohort:"", region:"", flag:""}) ) )
  | map( ($byl[.login] // {}) as $p
         | . + { has_photo: ($p.file != null),
                 format: (if $p.file == null then ""
                          elif ($p.file | endswith(".webp")) then "webp" else "png" end),
                 bytes: ($p.bytes // 0), mtime: ($p.mtime // 0) } )
  | sort_by(.name | ascii_downcase)' > "$W/out.json" 2>/dev/null || printf '[]' > "$W/out.json"
[[ -s "$W/out.json" ]] || printf '[]' > "$W/out.json"

# a página mostra a foto PADRÃO (a que vai para quem não mandou) e precisa do mtime dela p/
# furar o cache da própria pré-visualização
source "$_LIBDIR/team-photo.sh"
_phf="$(tp_placeholder "$contest")"
ok_json '{teams:$t[0], total:($t[0] | length), with_photo:($t[0] | map(select(.has_photo)) | length),
          placeholder:{custom:$pc, mtime:$pm}}' \
  --slurpfile t "$W/out.json" \
  --argjson pc "$(tp_placeholder_custom "$contest" && echo true || echo false)" \
  --argjson pm "$(stat -c %Y "$_phf" 2>/dev/null || echo 0)"
