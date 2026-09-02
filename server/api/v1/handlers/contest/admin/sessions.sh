# GET /contest/admin/sessions?contest=<id>  (admin DO contest)
# Sessões ativas do contest + alerta de UA/IP diferentes (mesmo login de máquinas distintas).
#
# ⚠ UMA VARREDURA, ZERO forks por sessão (véspera da prova 29/08: a versão com subshell +
# jq POR ARQUIVO custava 21-24 s por chamada — o SESSIONDIR é GLOBAL e sessão não expira,
# então são milhares de arquivos; o painel do admin pola e cada poll prendia um worker por
# meio minuto). O laço sourceia cada arquivo NO SHELL DO HANDLER (mesma confiança do
# load_session: sessão é escrita com printf %q), acumula linhas \x01 e UM jq no final monta
# tudo — o UA sai em base64 e o decode é @base64d dentro do jq.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"

# Esta varredura completa é também quem SEMEIA o índice por login (lib/session-index.sh)
# quando ele ainda não foi semeado neste contest — só apêndice, sob flock -n; se outro
# processo está semeando, não repete. Depois disso o login usa o índice (sessão única).
_seed=0; _sfd=""
if ! sess_index_seeded "$contest"; then
  _sd="$(_sidx_dir "$contest")"; mkdir -p "$_sd" 2>/dev/null; chmod 700 "$_sd" 2>/dev/null
  if exec {_sfd}>"$_sd/.seed.lock" 2>/dev/null && flock -n "$_sfd" 2>/dev/null; then _seed=1; fi
fi
set +o noglob; shopt -s nullglob
tmpf="$(mktemp)"
for f in "$SESSIONDIR"/*; do
  [[ -f "$f" ]] || continue
  CONTEST=""; LOGIN=""; USERFULLNAME=""; LOGINAT=""; IP=""; UA_B64=""; MKEY=""
  source "$f" 2>/dev/null
  [[ "$CONTEST" == "$contest" && -n "$LOGIN" ]] || continue
  [[ "$LOGINAT" =~ ^[0-9]+$ ]] || LOGINAT=0
  (( _seed )) && valid_id "$LOGIN" && printf '%s\n' "${f##*/}" >> "$_sd/$LOGIN" 2>/dev/null
  printf '%s\x01%s\x01%s\x01%s\x01%s\x01%s\n' "$LOGIN" "$USERFULLNAME" "$IP" "$UA_B64" "$LOGINAT" "$MKEY" >> "$tmpf"
done
shopt -u nullglob
if (( _seed )); then : > "$_sd/.seeded"; fi
[[ -n "$_sfd" ]] && eval "exec ${_sfd}>&-"

# corpo ANTES do cabeçalho (regra da casa): jq falhou ⇒ 500 com rastro, nunca 200 vazio.
body="$(jq -Rcs '
  [ split("\n")[] | select(length>0) | split("\u0001")
    | {login:.[0], name:.[1], ip:.[2],
       user_agent:(.[3] | if length>0 then (try @base64d catch "?") else "" end),
       login_at:(.[4]|tonumber? // 0), mkey:(.[5] // "")} ] as $all
  | ($all | group_by(.login)
        | map({login:.[0].login, nip:(map(.ip)|unique|length), nua:(map(.user_agent)|unique|length)})
        | INDEX(.login)) as $g
  | ($all | map(. + {multi_ip:(($g[.login].nip)>1), multi_ua:(($g[.login].nua)>1)})
        | sort_by(-.login_at)) as $s
  | {success:true, count:($s|length), sessions:$s,
     alerts:([ $s[] | select(.multi_ip or .multi_ua) | {login, multi_ip, multi_ua} ] | unique_by(.login)) }
' < "$tmpf")" || { rm -f "$tmpf"; fail 500 "Falha ao montar sessões" "build_fail"; }
rm -f "$tmpf"
emit_json 200 OK
printf '%s\n' "$body"
