# GET /problems/source?id=<id>[&tests=meta|full]   (Bearer)
# Devolve o SOURCE do problema (enunciado/autor/tags/conf/exemplos/testes OCULTOS/SOLUÇÕES/editorial).
# ACESSO (garantido AQUI na API, nunca só na interface): conteúdo sensível => SÓ dono ou colaborador.
#
# tests=meta (DEFAULT): os testes ocultos saem como {name,size_in,size_out,omitted:true} — SEM
#   conteúdo — e a resposta traz `tests_omitted:true`. O conteúdo de UM teste vem por
#   /problems/test. Motivo: um problema com testes grandes (OBI: inputs de 12MB) gerava um
#   corpo de CENTENAS DE MB — 52s de rede num caso real — e o editor web ficava todo esse
#   tempo mostrando o formulário vazio (indistinguível de "problema novo").
# tests=full: corpo completo, para ROUND-TRIP (o `moj clone` manda full; sem isso o clone
#   materializaria um pacote sem testes).
require_method GET
require_auth
source "$_DIR/lib/orgs.sh"; source "$_DIR/lib/problems.sh"

id="$(param id)"; [[ -n "$id" ]] || fail 400 "Missing id" "id_missing"
valid_id "$id" || fail 400 "Invalid id" "id_invalid"
repo="${id%%#*}"; prob="${id##*#}"
[[ "$prob" != "$id" ]] || fail 400 "Id sem '#'" "id_invalid"
owner="$(problem_owner "$id")"
[[ -n "$owner" ]] || fail 404 "Problema não encontrado" "not_found"
# CORTE NA API: o source traz testes ocultos + soluções -> só dono/colaborador. Não-autorizado: 404
# (nem revela que existe). SEM atalho de .admin. Burlar pela interface não adianta: a trava está aqui.
require_problem_edit "$id"

# O canônico é a árvore LOCAL do problema (repo git por problema); leitura de arquivo pura.
pkg="$MOJ_PROBLEMS_DIR/$repo/$prob"
[[ -d "$pkg" ]] || fail 404 "Problema não encontrado" "not_found"

_t="$(param tests)"; case "$_t" in full) SRC_TESTS=full;; *) SRC_TESTS=meta;; esac
export SRC_TESTS

# O source pode ser GRANDE (tests=full): vai p/ ARQUIVO e entra no jq por --slurpfile (ARG_MAX).
# CORPO ANTES DO CABEÇALHO (regra do projeto): com emit_json antes, uma falha do jq (OOM num
# pacote enorme, disco cheio) devolvia 200 com corpo VAZIO — e o editor caía no estado
# "problema novo" sem nenhum erro visível. Agora falha vira 500 de verdade.
srcf="$(mktemp)"; outf="$(mktemp)"
trap 'rm -f "$srcf" "$outf"' EXIT
read_problem_source "$pkg" > "$srcf"
[[ -s "$srcf" ]] || fail 500 "Falha ao ler o pacote do problema" "read_fail"
jq -cn --arg id "$id" --arg o "$owner" --slurpfile s "$srcf" \
  '{success:true, id:$id, owner:$o, editable:true} + $s[0]' > "$outf" || fail 500 "Falha ao serializar o pacote" "read_fail"
[[ -s "$outf" ]] || fail 500 "Falha ao serializar o pacote" "read_fail"

emit_json 200 OK
cat "$outf"
