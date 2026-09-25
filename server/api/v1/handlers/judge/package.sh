# GET /judge/package?id=<id>   (Bearer mojw_<token>)
# Devolve o PACOTE do problema (.tar.gz) p/ o juiz CACHEAR localmente — substitui o
# clone do repositório inteiro. Inclui as soluções (o juiz calibra). O header
# X-Moj-Checksum traz a VERSÃO DO PACOTE (pkg_judge_version — o mesmo valor do package-meta,
# `sols/` inteiro incluído): o juiz guarda-a junto do tl que calibrou e re-baixa/recalibra quando
# ela muda. X-Moj-Tl-Checksum leva a chave ESTREITA (diagnóstico). Fonte: MOJ_PROBLEMS_DIR (store do
# servidor). NÃO embute tl/tl.<host> (cada juiz calibra o seu).
require_method GET
require_worker
source "$_DIR/lib/tl-store.sh"

id="$(param id)"; [[ -n "$id" ]] || fail 400 "Missing id" "id_missing"
valid_id "$id" || fail 400 "Invalid id" "id_invalid"
prob="${id##*#}"; [[ "$prob" != "$id" ]] || fail 400 "Id sem '#'" "id_invalid"
pkg="$(pkg_path "$id")"; [[ -n "$pkg" ]] || fail 404 "Pacote não encontrado" "not_found"

cks="$(pkg_judge_version "$pkg" "$id")"; tlc="$(pkg_tl_checksum "$pkg" "$id")"
fn="$(printf '%s' "$prob" | tr -cd 'A-Za-z0-9._-')"; [[ -n "$fn" ]] || fn=problema
parent="$(dirname "$pkg")"; base="$(basename "$pkg")"

# CACHE do .tar.gz (XIV Maratona UnB, 25/09/2026): montar o `tar -czf` a CADA download custou 5,7 s de CPU
# p/ um pacote de 27 MB (mdp-unb-xiv#super-dash), por juiz e por cache frio — e a 1ª submissão do problema
# naquele juiz esperava isso. A CHAVE cobre TUDO que vai no tar (caminho, tamanho, mtime e modo de cada
# arquivo, fora .git/tl/tl.* — as mesmas exclusões do tar): a pkg_version não serve, porque não cobre
# enunciado/docs, que também vão no pacote. Nome do arquivo pelo md5 do id (sanear `#` colidiria ids).
# Um flock por problema (dois juízes com cache frio não montam o mesmo tar juntos); fica só a versão
# atual de cada problema, e o que ficou 7 dias sem uso sai na próxima montagem (disco).
PKC="$RUNDIR/pkgcache"; mkdir -p "$PKC" 2>/dev/null
key="$(cd "$parent" && find "$base" \( -name .git -o -name tl -o -name 'tl.*' \) -prune -o -printf '%p\t%s\t%T@\t%m\n' 2>/dev/null \
       | LC_ALL=C sort | md5sum | cut -c1-16)"
idh="$(printf '%s' "$id" | md5sum | cut -c1-16)"
f="$PKC/$idh.$key.tar.gz"
if [[ -n "$key" && ! -s "$f" ]] && exec {lk}>"$PKC/$idh.lock" && flock -w 300 "$lk"; then
  if [[ ! -s "$f" ]]; then
    t="$f.tmp.$BASHPID"
    if tar -czf "$t" -C "$parent" --exclude='.git' --exclude='tl' --exclude='tl.*' "$base" 2>/dev/null; then
      mv -f "$t" "$f"
      find "$PKC" -maxdepth 1 -name "$idh.*.tar.gz" ! -name "${f##*/}" -delete 2>/dev/null
      find "$PKC" -maxdepth 1 -name '*.tar.gz' -mtime +7 -delete 2>/dev/null
    else rm -f "$t"; fi
  fi
  flock -u "$lk"
fi

printf 'Status: 200 OK\r\n'
printf 'Content-Type: application/gzip\r\n'
printf 'X-Moj-Checksum: %s\r\n' "$cks"
printf 'X-Moj-Tl-Checksum: %s\r\n' "$tlc"
printf 'Content-Disposition: attachment; filename="%s.tar.gz"\r\n' "$fn"
if [[ -s "$f" ]]; then
  touch -c "$f" 2>/dev/null                     # uso recente (a limpeza de 7 dias olha o mtime)
  printf 'Content-Length: %s\r\n\r\n' "$(stat -c%s "$f")"
  cat "$f"
else
  # sem cache (disco cheio, falha no tar): o caminho antigo, em fluxo — o juiz nunca fica sem pacote
  printf '\r\n'
  tar -czf - -C "$parent" --exclude='.git' --exclude='tl' --exclude='tl.*' "$base" 2>/dev/null
fi
