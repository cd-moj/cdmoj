# GET /contest/admin/audit-log?contest=<id>[&since=&action=&user=&limit=]  (admin DO contest)
# Feed cronológico UNIFICADO de tudo que aconteceu no contest, no INSTANTE EXATO de cada
# evento (trace completo), juntando 4 fontes:
#   - var/admin-audit.log             (ações de admin: epoch\twho\taction\tdetails)   -> kind=admin
#   - var/access.log                  (logins: epoch\tlogin\tip\tua_b64)              -> kind=login
#   - users/<login>/history           (1 SUBMISSÃO por linha, no sub_epoch)           -> kind=submit
#   - users/<login>/results/<id>.json (1 VEREDICTO por correção, no finalized_at)     -> kind=verdict
# Cada submissão gera DUAS entradas: a submissão (quando o aluno enviou) e o veredicto
# (quando o juiz respondeu, com a hora exata da correção). O results/<id>.json é gravado
# por TODO caminho de finalização (daemon/ingest/rejulgar/set-verdict) — cobre tudo sem
# depender do daemon registrar nada. Filtros: since (epoch), action/user (substr), limit.
#
# ARQUITETURA (não regredir): as 4 fontes emitem NDJSON (1 objeto por LINHA) para UM arquivo
# temporário, e o envelope sai de UMA passada de jq que lê esse arquivo por --slurpfile. Só
# ESCALARES (since/action/user/limit) vão por argv. Passar os arrays por --argjson estourava o
# MAX_ARG_STRLEN (128 KiB POR ARGUMENTO — não o ARG_MAX de 2 MB): o array do admin-audit
# sozinho dá 2,8 MB no treino => "jq: Argument list too long". E como o header já tinha saído,
# o cliente recebia 200 com corpo VAZIO (falha muda). Mesmo padrão de dashboard.sh/badges.sh.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"

since="$(param since)"; [[ "$since" =~ ^[0-9]+$ ]] || since=0
limit="$(param limit)"; [[ "$limit" =~ ^[0-9]+$ ]] || limit=500
(( limit > 5000 )) && limit=5000
action="$(param action)"; user="$(param user)"
SRC_MAX=20000   # teto de linhas lidas por fonte (limita memória; feed recente)
RES_MAX=8000    # teto de results/*.json lidos (os mais recentes por mtime)

cdir="$CONTESTSDIR/$contest"
EV="$(mktemp)" || fail 500 "Falha ao criar temporário" "tmp_failed"
trap 'rm -f "$EV"' EXIT

read_tail() { [[ -f "$1" ]] && tail -n "$SRC_MAX" "$1" 2>/dev/null || true; }
# Pré-filtro barato de `since` nos .log (o epoch é o campo 1 do TSV). É só economia: quem
# GARANTE o corte é o select(.time >= $since) da passada final.
since_tsv() { awk -F'\t' -v s="$since" 'NF && $1+0 >= s'; }

# VEREDICTO: os results mais recentes por mtime, até RES_MAX. O `who` é o ALUNO (o .login
# segue DENTRO do JSON — só o nome do arquivo o perdeu no store por-usuário), p/ o filtro de
# usuário casar a submissão E o veredicto dela. `-n 200`: um JSON corrompido aborta o LOTE do
# jq, então o lote pequeno limita o estrago (a escrita do daemon é atômica; é cinto+suspensório).
results_ndjson() {
  local d="$cdir/users"; [[ -d "$d" ]] || return 0
  find "$d" -mindepth 3 -maxdepth 3 -path '*/results/*.json' -printf '%T@\t%p\n' 2>/dev/null \
    | sort -rn | head -n "$RES_MAX" | cut -f2- | tr '\n' '\0' \
    | xargs -0 -r -n 200 jq -c --argjson since "$since" '
        select(type=="object" and (.finalized_at // 0) > 0 and (.finalized_at) >= $since)
        | { time:(.finalized_at), who:(.login//"?"), kind:"verdict", action:(.verdict//""),
            details:("\(.problem_id//"") (\(.lang//"")) #\(.id//"")"
                     + (if .host then " · juiz:\(.host)" else "" end)
                     + (if (.duration_s//null)!=null then " · \(.duration_s)s" else "" end)) }'
}

# --- as 4 fontes -> NDJSON num arquivo só -----------------------------------------------
# `jq -R -c` é STREAMING (sem -s): uma linha ruim é pulada e o resto da fonte sobrevive. O
# `-R -cs` de antes era TUDO-OU-NADA — um ua_b64 inválido no access.log zerava a fonte
# INTEIRA e o `|| '[]'` engolia em silêncio. stderr p/ /dev/null no bloco todo: sob fcgiwrap
# um stderr entupido trava o worker (502).
{
  # ADMIN — epoch \t who \t action \t details
  read_tail "$cdir/var/admin-audit.log" | since_tsv | jq -R -c '
    select(length>0) | split("\t")
    | { time:(.[0]|tonumber? // 0), who:(.[1]//"?"), kind:"admin",
        action:(.[2]//""), details:(.[3]//"") }'

  # LOGIN — epoch \t login \t ip \t ua_b64  (ua corrompido não pode matar a fonte)
  read_tail "$cdir/var/access.log" | since_tsv | jq -R -c '
    select(length>0) | split("\t")
    | { time:(.[0]|tonumber? // 0), who:(.[1]//"?"), kind:"login", action:"login",
        details:( (.[2]//"") + " · " + ((.[3]//"") | try @base64d catch "") ) }'

  # SUBMISSÃO — store por-usuário. emit_history_sorted (lib/users.sh) faz o fan-out sobre
  # users/*/history e emite o FORMATO GLOBAL de 7 campos, ordenado por sub_epoch, só as
  # últimas SRC_MAX. O controle/history GLOBAL é do modelo legado e NÃO existe nos contests
  # v2 (mesma migração já feita no dashboard.sh) — lê-lo deixava kind=submit sempre vazio.
  # O veredicto pode conter ':', então sub_epoch/subid saem por índice NEGATIVO (.[-2]/.[-1])
  # e login/probid/lang por índice positivo (.[1]/.[2]/.[3]).
  emit_history_sorted "$contest" "$SRC_MAX" \
    | awk -F: -v s="$since" 'NF>=7 && $(NF-1)+0 >= s' \
    | jq -R -c '
        select(length>0) | split(":") | select(length>=7)
        | { time:(.[-2]|tonumber? // 0), who:(.[1]//"?"), kind:"submit",
            action:"submissão", details:("\(.[2]//"") (\(.[3]//"")) #\(.[-1]//"")") }'

  # VEREDICTO — users/<login>/results/<id>.json (o results/ GLOBAL também é do modelo legado)
  results_ndjson
  true
} > "$EV" 2>/dev/null

# --- UMA passada: filtros, ordem, corte, envelope ----------------------------------------
# --slurpfile entrega o NDJSON já como ARRAY de eventos (arquivo vazio => []). `time > 0`
# descarta linha corrompida (viraria um evento de 1970 no fim da lista).
# NÃO usamos ok_json aqui DE PROPÓSITO: ele emite o header ANTES de rodar o jq, e uma falha do
# jq viraria 200-com-corpo-vazio (era exatamente o sintoma deste bug). Montamos o corpo primeiro
# (limitado a `limit` <= 5000 eventos) e só então respondemos — jq quebrou => 500 honesto. O
# `printf` é BUILTIN (não faz execve), então a variável grande não reintroduz o ARG_MAX.
body="$(jq -cn --slurpfile ev "$EV" \
  --argjson since "$since" --arg act "$action" --arg usr "$user" --argjson lim "$limit" '
  $ev
  | map(select((.time // 0) > 0 and (.time) >= $since))
  | (if $act=="" then . else map(select(((.action//"")|ascii_downcase)|contains($act|ascii_downcase))) end)
  | (if $usr=="" then . else map(select(((.who//"")|ascii_downcase)|contains($usr|ascii_downcase))) end)
  | sort_by(-.time) | .[:$lim]
  | {success:true, count:length, events:.}' 2>/dev/null)"

[[ -n "$body" ]] || fail 500 "Falha ao montar o feed de auditoria" "audit_render_failed"
emit_json 200 OK
printf '%s\n' "$body"
