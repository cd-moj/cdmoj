# GET /treino/admin/sessions  (.admin) -> sessões ativas do treino (login, ip, user-agent, hora)
# UMA passada, sem processo por sessão: um grep acha os arquivos do treino (`CONTEST=treino`), o
# bash os lê por `source` no MESMO processo (o conteúdo é `%q` — o source é o parser certo), e UM jq
# monta a lista e decodifica o user-agent (@base64d). Antes eram 3 processos por sessão (subshell +
# jq + base64): com 21.254 sessões (a sessão não expira) a aba — a PRIMEIRA do painel — levava 69 s
# (19/09/2026). O corpo é montado ANTES do cabeçalho (falha = 500, nunca "200 com lista vazia").
require_auth_contest treino
is_admin || fail 403 "Apenas administradores do treino" "admin_required"
_US=$'\x1f'   # separador de campos; \n separa sessões — nenhum dos dois pode sobrar dentro de um valor
_sess_rows(){
  local f CONTEST LOGIN USERFULLNAME LOGINAT IP UA_B64 MKEY ACTOR
  while IFS= read -r -d '' f; do
    CONTEST=""; LOGIN=""; USERFULLNAME=""; LOGINAT=""; IP=""; UA_B64=""
    source "$f" 2>/dev/null
    [[ "$CONTEST" == treino ]] || continue
    printf '%s\n' "${LOGIN//[$_US$'\n']/ }$_US${USERFULLNAME//[$_US$'\n']/ }$_US${IP//[$_US$'\n']/ }$_US${UA_B64//[$_US$'\n']/}$_US${LOGINAT//[^0-9]/}"
  done < <(find "$SESSIONDIR" -maxdepth 1 -type f -print0 2>/dev/null | xargs -0 -r grep -lxZF 'CONTEST=treino' 2>/dev/null)
}
body="$(_sess_rows | jq -R -s -c '
  split("\n") | map(select(length > 0) | split("")
    | {login:(.[0] // ""), name:(.[1] // ""), ip:(.[2] // ""),
       user_agent:((.[3] // "") | (try @base64d catch "")),
       login_at:((.[4] // "0") | (tonumber? // 0))})
  | {success:true, count:length, sessions:(sort_by(-.login_at))}' 2>/dev/null)"
[[ -n "$body" ]] || fail 500 "Falha ao listar as sessões" "build_fail"
emit_json 200 OK
printf '%s\n' "$body"
