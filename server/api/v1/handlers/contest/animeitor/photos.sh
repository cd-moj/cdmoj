# GET /contest/animeitor/photos?contest=<id>   (Bearer: .animeitor ou admin do contest)
# Galeria das fotos: um item por conta que compete (papel fora), com nome, sigla, coorte, sede,
# se tem foto, formato, bytes e **mtime** (o cliente usa como cache-buster estável do <img>).
# Traz também a MÚSICA do time (has_music/music_bytes/music_mtime) — de graça: ela sai da MESMA
# varredura da foto, e é por isso que a página de 1000 times não ficou mais lenta.
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
{ is_animeitor || is_admin || is_cstaff; } || fail 403 "Apenas a conta de placar (.animeitor), o chefe de sede (.cstaff) ou o admin" "animeitor_required"

cdir="$CONTESTSDIR/$contest"
W="$(mktemp -d)" || fail 500 "tmp" "tmp"
trap 'rm -rf "$W"' EXIT

# CHEFE DE SEDE: vê só os times do escopo dele (staff-filters.json — o MESMO recorte da fila de
# impressão, das etiquetas e da cerimônia). Escopo vazio/ausente = vê tudo (convenção da casa;
# o preflight avisa). rc=1 de staff_visible_logins significa "não filtre".
# ⚠ quem manda é o rc, NÃO o tamanho da saída: rc=0 com lista VAZIA é "escopo que não casa
# ninguém" (vê nada), e tratar isso como "sem filtro" abriria o contest inteiro.
scoped=false
if is_cstaff; then
  source "$_LIBDIR/print.sh"
  staff_visible_logins "$contest" "$SESSION_LOGIN" > "$W/vis.txt" && scoped=true
fi
jq -R -s '[ split("\n")[] | select(length > 0) ]' "$W/vis.txt" > "$W/vis.json" 2>/dev/null \
  || printf '[]' > "$W/vis.json"

# (1) assets: UMA varredura com tamanho e mtime de foto E música (nada de `stat` por arquivo)
find "$cdir/users" -mindepth 2 -maxdepth 2 \
  \( -name 'photo.webp' -o -name 'photo.png' -o -name 'music.mp3' \) \
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
jq -cn --slurpfile acc "$W/acc.json" --slurpfile ph "$W/ph.json" \
       --slurpfile vis "$W/vis.json" --argjson scoped "$scoped" '
  # recorte do chefe de sede: só depois da junção, para o item continuar idêntico ao do animeitor
  (if $scoped then (($vis[0] // []) | map({(.): true}) | add // {}) else null end) as $only
  | ($ph[0] // []) as $P
  | ($P | map(select(.file | startswith("photo."))) | map({(.login): .}) | add // {}) as $byl
  | ($P | map(select(.file == "music.mp3"))         | map({(.login): .}) | add // {}) as $bym
  | ($acc | map({(.login): true}) | add // {}) as $known
  | ( $acc + ( $P | map(.login) | unique
               | map(select($known[.] == null))
               | map(select(test("\\.(admin|judge|cjudge|staff|cstaff|mon|animeitor)$") | not))
               | map({login:., name:., univ:"", cohort:"", region:"", flag:""}) ) )
  | map( ($byl[.login] // {}) as $p | ($bym[.login] // {}) as $m
         | . + { has_photo: ($p.file != null),
                 format: (if $p.file == null then ""
                          elif ($p.file | endswith(".webp")) then "webp" else "png" end),
                 bytes: ($p.bytes // 0), mtime: ($p.mtime // 0),
                 has_music: ($m.file != null),
                 music_bytes: ($m.bytes // 0), music_mtime: ($m.mtime // 0) } )
  | (if $only then map(select($only[.login])) else . end)
  | sort_by(.name | ascii_downcase)' > "$W/out.json" 2>/dev/null || printf '[]' > "$W/out.json"
[[ -s "$W/out.json" ]] || printf '[]' > "$W/out.json"

# a página mostra a foto e a música PADRÃO (as que vão para quem não mandou as suas) e precisa do
# mtime delas p/ furar o cache da própria pré-visualização
source "$_LIBDIR/team-photo.sh"
source "$_LIBDIR/team-music.sh"
_phf="$(tp_placeholder "$contest")"; _muf="$(tm_placeholder "$contest")"
ok_json '{teams:$t[0], total:($t[0] | length), with_photo:($t[0] | map(select(.has_photo)) | length),
          with_music:($t[0] | map(select(.has_music)) | length), scoped:$sc,
          placeholder:{custom:$pc, mtime:$pm, music_custom:$mc, music_mtime:$mm}}' \
  --slurpfile t "$W/out.json" --argjson sc "$scoped" \
  --argjson pc "$(tp_placeholder_custom "$contest" && echo true || echo false)" \
  --argjson pm "$(stat -c %Y "$_phf" 2>/dev/null || echo 0)" \
  --argjson mc "$(tm_placeholder_custom "$contest" && echo true || echo false)" \
  --argjson mm "$(stat -c %Y "$_muf" 2>/dev/null || echo 0)"
