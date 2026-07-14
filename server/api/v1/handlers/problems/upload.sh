# POST /problems/upload   (Bearer)   body: {id? | repo(=org),prob, tar_b64}
# Sobe um .tar(.gz)/.zip do pacote e ATUALIZA TUDO (substitui o conteúdo do problema). Commit LOCAL
# autorado pelo login (sem Gitea). Novo problema exige permissão de criação. Acesso = membro da org.
require_method POST
require_auth
source "$_DIR/lib/orgs.sh"; source "$_DIR/lib/problems.sh"

body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
id="$(jq -r '.id // empty' <<<"$body")"
if [[ -n "$id" ]]; then valid_id "$id" || fail 400 "Invalid id" "id_invalid"; org="${id%%#*}"; prob="${id##*#}"
else org="$(jq -r '.repo // .org // empty' <<<"$body")"; prob="$(jq -r '.prob // empty' <<<"$body")"; id="$org#$prob"; fi
[[ "$org" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{1,63}$ ]] || fail 400 "Org inválida" "org_invalid"
[[ "$prob" =~ ^[a-z0-9][a-z0-9._-]{1,80}$ ]] || fail 400 "Nome de problema inválido" "prob_invalid"
[[ "$org" == "$SESSION_LOGIN" ]] && ensure_implicit_org "$SESSION_LOGIN"
org_exists "$org" || fail 404 "Org não existe (crie com /orgs/create)" "org_missing"
org_is_member "$org" "$SESSION_LOGIN" || fail 403 "Você não é membro dessa org" "forbidden"
pdir="$MOJ_PROBLEMS_DIR/$org/$prob"

tarf="$(mktemp)"; ex=""
trap 'rm -rf "$tarf" "$ex"' EXIT
jq -r '.tar_b64 // .archive_b64 // ""' <<<"$body" | base64 -d > "$tarf" 2>/dev/null
[[ -s "$tarf" ]] || fail 400 "Arquivo vazio/ inválido" "tar_empty"
ex="$(mktemp -d)"
if [[ "$(head -c2 "$tarf")" == "PK" ]]; then
  command -v unzip >/dev/null || fail 501 "Sem unzip no servidor (envie .tar.gz)" "no_unzip"
  unzip -Z1 "$tarf" 2>/dev/null | grep -qE '(^/|(^|/)\.\.(/|$))' && fail 400 "Zip com caminho inseguro" "zip_unsafe"
  unzip -qq -o "$tarf" -d "$ex" 2>/dev/null || fail 400 "Zip inválido" "zip_bad"
else
  tar -tf "$tarf" 2>/dev/null | grep -qE '(^/|(^|/)\.\.(/|$))' && fail 400 "Arquivo com caminho inseguro" "tar_unsafe"
  # cada compressão precisa do descompressor externo (o `tar` só delega). Sem ele, um tar VÁLIDO
  # dava "Arquivo inválido" — erro mentiroso. A imagem embarca gzip/bzip2/zstd/xz; se algum sumir,
  # o erro passa a dizer QUAL falta (como o caminho do zip já fazia).
  case "$(od -An -tx1 -N4 "$tarf" 2>/dev/null | tr -d ' \n')" in
    1f8b*)    need=gzip;;  425a68*)   need=bzip2;;
    28b52ffd) need=zstd;;  fd377a58*) need=xz;;
    *)        need="";;
  esac
  [[ -z "$need" ]] || command -v "$need" >/dev/null 2>&1 \
    || fail 501 "Sem $need no servidor (envie .tar.gz)" "no_$need"
  tar -xf "$tarf" -C "$ex" --no-same-owner 2>/dev/null \
    || fail 400 "Arquivo inválido (tar/tar.gz/tar.bz2/tar.xz/tar.zst/zip)" "tar_bad"
fi
# raiz do pacote: 1 diretório de topo -> usa ele; senão a raiz extraída
src="$ex"; top="$(find "$ex" -maxdepth 1 -mindepth 1)"
[[ "$(printf '%s\n' "$top" | grep -c .)" -eq 1 && -d "$top" ]] && src="$top"

if [[ ! -d "$pdir" ]]; then   # problema NOVO via tar -> exige permissão de criação
  source "$_DIR/lib/contest-create.sh"
  cc_can_create "$SESSION_LOGIN" || fail 403 "Sem permissão para criar novos problemas (mesma regra de criar contest)" "create_forbidden"
fi
mkdir -p "$pdir"
# O `.moj-meta.json` é ARQUIVO DO SERVIDOR — o cliente não manda nem apaga:
#  - o `public` só o /problems/set-public escreve (é o único que checa a trava da org). Se viesse do
#    tar, bastava baixar um problema público, adaptá-lo p/ uma prova numa org privada e dar `moj
#    upload`: a próxima indexação (um tl-report de calibração basta) publicaria a prova.
#  - `collections`, `display_title` e `public_at` idem — cada um tem sua rota.
# O tar do `moj upload` NEM TEM o meta (o cliente guarda `.moj-id`), então sem o --exclude o
# `--delete` do rsync APAGARIA o meta do servidor a cada upload (título/coleções/public_at perdidos;
# o `public` sobrevive pelo pub_srv abaixo). Excluir dos DOIS lados resolve: o do tar é ignorado, o
# do servidor fica.
pub_srv=false
[[ -f "$pdir/.moj-meta.json" ]] && jq -e '.public == true' "$pdir/.moj-meta.json" >/dev/null 2>&1 && pub_srv=true
# O pacote do servidor vira EXATAMENTE o que o autor enviou: o que ele apagou tem de sumir daqui
# (--delete), e o .git (repo local do problema, onde o problem_commit escreve) tem de sobreviver.
# O fallback antigo era `|| cp -a`, que faz nem uma coisa nem outra — e como o rsync não estava na
# imagem, TODO upload em produção caía nele, calado: teste/solução apagada continuava valendo, e um
# tar com .git dentro sobrescrevia o histórico do servidor. Agora o caminho sem rsync FAZ a mesma
# coisa (com tar, que sempre existe), e erro de rsync não é mais engolido.
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete --exclude='.git' --exclude='.moj-meta.json' "$src"/ "$pdir"/ \
    || fail 500 "Falha ao gravar o pacote (rsync)" "pkg_write_failed"
else
  find "$pdir" -mindepth 1 -maxdepth 1 ! -name .git ! -name .moj-meta.json -exec rm -rf {} + 2>/dev/null
  ( cd "$src" && tar -cf - --exclude=.git --exclude=.moj-meta.json . ) | ( cd "$pdir" && tar -xf - ) \
    || fail 500 "Falha ao gravar o pacote (tar)" "pkg_write_failed"
fi
owner="$(problem_owner "$id")"; [[ -n "$owner" ]] || owner="$SESSION_LOGIN"

# TÍTULO e COLEÇÕES vêm do PACOTE (o `.moj-meta.json` do tar): são campos de CONTEÚDO. Só
# `public`/`public_at`/`owner` são de ACESSO e continuam IGNORADOS do tar (é o furo que o --exclude
# fecha). Sem isto, todo problema NOVO subido por upload entrava com o título = NOME DA PASTA e sem
# coleção: o write_meta só PRESERVA o que o servidor já tem, e problema novo não tem nada — e o
# .moj-meta.json do tar, que traz o título certo, tinha acabado de ser descartado pelo --exclude.
tar_title=""; tar_colls=""
if [[ -f "$src/.moj-meta.json" ]] && jq -e . "$src/.moj-meta.json" >/dev/null 2>&1; then
  tar_title="$(jq -r '.display_title // empty' "$src/.moj-meta.json" 2>/dev/null)"
  tar_colls="$(jq -c '[.collections[]? | select(type=="string")]' "$src/.moj-meta.json" 2>/dev/null)"
  [[ "$tar_colls" == "[]" ]] && tar_colls=""      # sem coleção no tar => não mexe nas do servidor
fi
coll_register "$org" "$SESSION_LOGIN"             # a coleção homônima da org é sempre válida (= create)
# CURADA: coleção marcada tem de EXISTIR no registro (mesma trava do /problems/edit)
if [[ -n "$tar_colls" ]]; then
  while IFS= read -r cn; do [[ -n "$cn" ]] || continue
    coll_exists "$cn" || fail 400 "Coleção '$cn' não existe — crie antes (moj collection create)" "coll_unknown"
  done < <(jq -r '.[]?' <<<"$tar_colls")
fi
write_meta "$pdir" "$owner" "$org" "$pub_srv" "$tar_colls" "$tar_title"   # public: o do SERVIDOR
_pkg_canon_modes "$pdir"   # 644/755 — o mesmo modo do caminho do push (o tl-checksum inclui o modo)
[[ -f "$pdir/problem.yaml" ]] || bash "$MOJTOOLS_DIR/kattis/sidecar.sh" "$pdir" "$id" "$org" >/dev/null 2>&1 || true

sha="$(problem_commit "$pdir" "$SESSION_LOGIN" "upload do pacote: $prob")"
pub="$(jq -r 'if .public==true then "true" else "false" end' "$pdir/.moj-meta.json" 2>/dev/null)"
colls="$(jq -c '.collections // []' "$pdir/.moj-meta.json" 2>/dev/null)"
title="$(jq -r '.display_title // ""' "$pdir/.moj-meta.json" 2>/dev/null)"
author="$(head -1 "$pdir/author" 2>/dev/null)"
authored_upsert "$id" "$owner" "$org" "$prob" "$title" "${pub:-false}" "${colls:-[]}" "$author" '[]'
audit_log "upload" "id=$id by=$SESSION_LOGIN"
ok_json '{action:"upload", id:$id, sha:$s}' --arg id "$id" --arg s "${sha:0:12}"
