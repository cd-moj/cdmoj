# lib/problems.sh — apoio aos handlers de gestão de problemas (Meus/Compartilhados/Públicos/
# Coleções). Serve o índice de donos (contests/treino/var/problem-owners.json) e o regenera
# em BACKGROUND quando velho (nunca bloqueia o request, exceto na 1ª geração a frio).
: "${MOJTOOLS_DIR:=/home/ribas/moj/mojtools}"
: "${PROBLEM_OWNERS_TTL_MIN:=30}"
OWNERS_INDEX="$CONTESTSDIR/treino/var/problem-owners.json"

# ensure_owners_index — garante que o índice exista e seja VÁLIDO; se velho, regen em background.
# Devolve 0 só se o índice está USÁVEL. Quem chama NÃO pode transformar "índice quebrado" em
# "lista vazia" (foi assim que board/Painel/ls/coleções ficaram vazios, com 200, calados).
ensure_owners_index(){
  local f="$OWNERS_INDEX" lock="$OWNERS_INDEX.lock"
  # 0 BYTE ou JSON quebrado contam como AUSENTE. Antes o teste era `[[ ! -f ]]`: um arquivo de 0
  # byte era "presente" e NUNCA regenerava a frio — e o owners_merged o virava em lista vazia.
  if [[ ! -s "$f" ]] || ! jq -e . "$f" >/dev/null 2>&1; then
    MOJ_PROBLEMS_DIR="$MOJ_PROBLEMS_DIR" CONTESTSDIR="$CONTESTSDIR" RUNDIR="${RUNDIR:-/home/ribas/moj/run}" \
      bash "$MOJTOOLS_DIR/gen-problem-owners.sh" >/dev/null 2>&1
    # confere DE VERDADE: o exit code do gerador era descartado, então uma falha dele (MOJTOOLS_DIR
    # errado, var/ não gravável, morto pelo timeout) ficava invisível p/ sempre.
    if [[ -s "$f" ]] && jq -e . "$f" >/dev/null 2>&1; then authored_prune; return 0; fi
    return 1
  fi
  if [[ -n "$(find "$f" -mmin "+$PROBLEM_OWNERS_TTL_MIN" 2>/dev/null)" ]]; then
    # lock COM EXPIRAÇÃO: o `mkdir` vazava se o processo morresse no meio (container reiniciado,
    # kill do worker) e aí o índice não regenerava NUNCA mais.
    [[ -n "$(find "$lock" -maxdepth 0 -mmin +20 2>/dev/null)" ]] && rmdir "$lock" 2>/dev/null
    if mkdir "$lock" 2>/dev/null; then
      ( MOJ_PROBLEMS_DIR="$MOJ_PROBLEMS_DIR" CONTESTSDIR="$CONTESTSDIR" RUNDIR="${RUNDIR:-/home/ribas/moj/run}" \
        setsid bash -c 'bash "$1" >/dev/null 2>&1; rmdir "$2" 2>/dev/null' \
          _ "$MOJTOOLS_DIR/gen-problem-owners.sh" "$lock" & ) 2>/dev/null
    fi
  fi
  # poda oportunista do overlay (barata: mtime curto-circuita quando não há regen nova)
  authored_prune
  return 0
}

AUTHORED_INDEX="$CONTESTSDIR/treino/var/authored.json"   # overlay de problemas recém-criados

# owners_merged — emite {problems:[...]} mesclando o índice gerado + o overlay authored
# (recém-autorado vence por id). Dá visibilidade IMEDIATA ao que foi criado/editado.
owners_merged(){
  ensure_owners_index || return 1     # índice inutilizável: ERRA — não finge lista vazia
  # o overlay authored dá visibilidade IMEDIATA ao recém-criado/editado, mas NÃO pode APAGAR os campos
  # que só o índice calcula (tl_checksum, public_at — protegidos por o overlay não os escrever — e
  # `html`, DELETADO do overlay na mescla: o upsert antigo gravava html:false fixo e, antes da poda
  # do authored_prune, 343 problemas públicos ficaram com "sem HTML" eterno no painel) — por isso é
  # MESCLADO sobre a entrada do índice (base + overlay, overlay vence campo-a-campo) em vez de
  # substituí-la. Sem isso, todo problema no overlay perdia tl_checksum/public_at (staleness e
  # heatmap de entrada sub-reportados).
  #
  # ATENÇÃO ao `( … + … )`: valor de campo de objeto NÃO aceita operador binário solto no **jq 1.7**
  # (o da imagem de produção). O jq 1.8 (dev) aceita — então isto compilava aqui e explodia lá:
  # `{problems: A + B}` virava erro de sintaxe, o `2>/dev/null` engolia, e TODA listagem (problemas,
  # orgs, coleções) devolvia 200 com CORPO VAZIO ("Resposta inválida do servidor"). Ver CLAUDE.md.
  #
  # E ATENÇÃO ao DESLOCAMENTO DE ENTRADA (foi o que esvaziou board/Painel/ls/coleções, calado):
  # com `jq -s A B`, se A NÃO EXISTE (ou tem 0 byte) o jq só reclama no stderr (engolido pelo
  # 2>/dev/null), NÃO aborta, e as entradas ANDAM UMA CASA — `.[0]` vira o OVERLAY. O programa então
  # imprime um `{"problems":[]}` PERFEITAMENTE VÁLIDO, a guarda `[[ -n "$out" ]]` não dispara, e o
  # cliente recebe 200 com lista vazia (e o overlay é engolido junto). Por isso: (1) o índice é
  # VALIDADO antes (ensure_owners_index), (2) os dois arquivos entram por --slurpfile — que ERRA se o
  # arquivo não abre, em vez de deslocar — e (3) vazio aqui é ERRO (return 1), nunca lista vazia.
  local ovf="$AUTHORED_INDEX" out
  # overlay corrompido não pode derrubar a listagem INTEIRA (ele é só "visibilidade imediata")
  jq -e . "$ovf" >/dev/null 2>&1 || ovf=/dev/null
  out="$(jq -n --slurpfile idx "$OWNERS_INDEX" --slurpfile ov "$ovf" '
    ($idx[0] // {problems:[]}) as $base
    | ((($ov[0]) // {}) | [to_entries[].value]) as $ovl
    | (($base.problems // []) | map({key:.id, value:.}) | from_entries) as $bmap
    | ($ovl | map(.id)) as $ids
    | { problems: ( (($base.problems // []) | map(select((.id as $i | $ids|index($i)) | not)))
                    + ($ovl | map(($bmap[.id] // {}) + (. | del(.html)))) ) }
  ' 2>/dev/null)" || return 1
  [[ -n "$out" ]] || return 1
  printf '%s' "$out"
}

# orgs_json_for <login> — array JSON das orgs do login (membro OU admin; inclui a implícita).
# '[]' se nada/falha. É o termo de ORG dos filtros de visibilidade (pequeno: --argjson ok).
# my_orgs_json = atalho p/ o login da sessão.
orgs_json_for(){
  _need_orgs
  local o; o="$(org_list_for "$1" 2>/dev/null)"
  jq -e 'type=="array"' >/dev/null 2>&1 <<<"$o" || o='[]'
  printf '%s' "$o"
}
my_orgs_json(){ orgs_json_for "$SESSION_LOGIN"; }

# owners_visible — {problems:[...]} PRÉ-FILTRADO ao que $SESSION_LOGIN PODE VER (público OU dono OU
# colaborador OU **MEMBRO DA ORG** — membro vê TODOS os problemas da org, inclusive privados;
# decisão do Ribas 2026-07-16, casando a visibilidade com o gate de edição, que sempre foi
# org_is_member). É A FRONTEIRA DE SEGURANÇA da gestão (a API garante o acesso, NÃO a interface):
# problema privado some das listagens p/ NÃO-membros — inclusive p/ .admin. Reusada por
# owners_emit E /problems/status; ter UMA definição só evita divergência do filtro (ponto crítico).
# Propaga a FALHA do índice (rc!=0 e stdout vazio) em vez de virar lista vazia — quem chama tem de
# responder 503, nunca "você não tem problema nenhum".
owners_visible(){
  local m; m="$(owners_merged)" || return 1
  local _orgs; _orgs="$(my_orgs_json)"
  jq -c --arg _me "$SESSION_LOGIN" --argjson _orgs "$_orgs" \
    '.problems |= map(select(.public or .owner==$_me
       or ((.collaborators // [])|index($_me)|type=="number")
       or (((.repo // (.id|split("#")[0])) as $r | $_orgs|index($r))|type=="number")))' \
    <<<"$m" 2>/dev/null
}
# owners_emit <jq-program> [jq-args...] — emite {success,...} aplicando o programa sobre o objeto JÁ
# FILTRADO (com .problems só visíveis). Use $login/$name já passados via --arg pelos handlers.
owners_emit(){
  local prog="$1"; shift
  # o conjunto visível é calculado ANTES do cabeçalho: com o `emit_json 200` já enviado não dá mais
  # p/ dizer 503, e a listagem quebrada virava "200 + lista vazia" (o cliente entende "não tenho
  # problema nenhum" — indistinguível de estar tudo bem).
  local vis; vis="$(owners_visible)" \
    || fail 503 "Índice de problemas indisponível (a regeração falhou) — tente de novo em instantes" "index_unavailable"
  emit_json 200 OK
  jq -c "$@" "$prog" <<<"$vis" 2>/dev/null || jq -cn '{success:true, problems:[]}'
}

# calibrating_set -> ["<id>",...] em calibração AGORA. Uma varredura só das TRÊS filas de calibração:
# run/updates/{pending,inprogress} (kind=="calibrate"; pending mistura kind=="index", por isso o
# filtro) + run/commands/<host> (action=="calibrate", recalibração direcionada). Conjunto pequeno ->
# o chamador junta com INDEX(.) p/ testar pertinência em O(1). Sem evento de conclusão: "done" é
# inferido pelo run/tl/<id>.json mais novo (best-effort; pode piscar no meio do voo).
# O `-n` do último jq NÃO é firula — é o conserto do BOARD VAZIO. Sem ele (`jq -R` lendo stdin), com
# as filas VAZIAS — o estado NORMAL: ninguém calibrando — o jq não recebe entrada nenhuma, o programa
# não roda, ele **não imprime nada e SAI 0**. O `|| echo '[]'` não dispara (não houve erro!), a função
# devolve "" e o /problems/status faz `--argjson CAL ""` => "invalid JSON text passed to --argjson" =>
# o jq grande morre => cai no fallback `{total:0, problems:[]}` => `moj board` e a aba Painel MUDOS,
# com HTTP 200. Com `-n`, o programa roda uma vez, `inputs` lê o que houver (nada) e sai `[]`.
# É a mesma família do `grep -c` (imprime 0 e sai 1) — ver CLAUDE.md.
calibrating_set(){
  local _ud="${UPDATESDIR:-${RUNDIR:-/home/ribas/moj/run}/updates}"
  local _cd="${CMDDIR:-${RUNDIR:-/home/ribas/moj/run}/commands}"
  { find "$_ud/pending" "$_ud/inprogress" -name '*.json' -exec cat {} + 2>/dev/null \
      | jq -r 'select(.kind=="calibrate") | .target // empty'
    find "$_cd" -mindepth 2 -name '*.json' -exec cat {} + 2>/dev/null \
      | jq -r 'select(.action=="calibrate") | .id // empty'
  } 2>/dev/null | LC_ALL=C sort -u | jq -Rc -n '[inputs|select(length>0)]' 2>/dev/null || echo '[]'
}

# _idx_lock <arquivo> — abre o fd 9 travado (flock) p/ o read-modify-write de um índice JSON.
# SEM ISTO, dois pushes/saves simultâneos liam o MESMO estado, reconstruíam e gravavam: o último
# vencia e a entrada do outro SUMIA da listagem. Pior: quando o `cat` devolvia vazio (janela do
# `mv`, disco cheio), o `cur` virava '{}' e o upsert seguinte APAGAVA O OVERLAY INTEIRO. Mesmo
# padrão do problem_commit (que já trava a árvore git — a trava estava no objeto errado).
_idx_lock(){ local f="$1"; mkdir -p "$(dirname "$f")" 2>/dev/null; printf '%s' "$f.lock"; }

# authored_upsert <id> <owner> <repo> <prob> <title> <public:true|false> <collections-json> <author> [collabs-json]
authored_upsert(){
  local f="$AUTHORED_INDEX" lk; lk="$(_idx_lock "$f")"
  ( flock 9 2>/dev/null
    local cur tmp; cur="$(cat "$f" 2>/dev/null)"; [[ -n "$cur" ]] || cur='{}'
    jq -e . >/dev/null 2>&1 <<<"$cur" || cur='{}'          # overlay ilegível: recomeça (não propaga lixo)
    tmp="$f.tmp.$$"
    # o overlay entra por STDIN, nunca por --argjson: o teto do kernel é 128 KiB POR ARGUMENTO
    # e o overlay CRESCE (1 entrada por problema criado/subido). Quando passou de 128 KiB
    # (migrações em massa de 2026-07), o execve do jq falhava "Argument list too long", o
    # 2>/dev/null engolia e o upsert virava NO-OP silencioso — todo problema novo (upload E
    # editor) nascia INVISÍVEL p/ o próprio autor (404 em validation/get) até o índice de
    # donos alcançar. Ver ../CLAUDE.md (ARG_MAX) e a lição jq-argmax-128k.
    # normalizações ESPELHANDO o gerador do índice (divergência aqui = entrada que nunca poda e
    # que VENCE a mescla com o valor pior): título sem \r/\t/\n (metas CRLF da migração serviam
    # "Título\r" nas listagens) e collections vazio = [org] (a convenção "o repo é a coleção-curso"
    # do gen-problem-owners — o [] literal atropelava a coleção-default do índice).
    ( umask 077; printf '%s' "$cur" | jq --arg id "$1" --arg o "$2" --arg r "$3" --arg p "$4" \
        --arg t "$5" --arg pub "$6" --argjson colls "${7:-[]}" --arg au "$8" --argjson cb "${9:-[]}" '
        . as $cur
        | ($cur[$id] // {}) as $old
        | ($t | gsub("[\r\n\t]"; "")) as $tc
        | $cur + { ($id): ($old + {
            id:$id, owner:$o, repo:$r, prob:$p,
            title:(if $tc=="" then ($old.title // $p) else $tc end),
            author:($au | gsub("[\r\n\t]"; "")), author_norm:(($au | gsub("[\r\n\t]"; ""))|ascii_downcase),
            collaborators:$cb,
            collections:(if ($colls|length)==0 then [$r] else $colls end),
            public:($pub=="true") }) }
      ' ) > "$tmp" 2>/dev/null && [[ -s "$tmp" ]] && mv -f "$tmp" "$f" || rm -f "$tmp"
  ) 9>"$lk"
}
# authored_patch <id> <jq-expr-sobre-a-entrada> [jq-args...] — patch parcial de 1 entrada
authored_patch(){
  local id="$1" expr="$2"; shift 2
  local f="$AUTHORED_INDEX" lk; lk="$(_idx_lock "$f")"
  ( flock 9 2>/dev/null
    local cur tmp; cur="$(cat "$f" 2>/dev/null)"; [[ -n "$cur" ]] || exit 0
    tmp="$f.tmp.$$"
    ( umask 077; jq "$@" --arg _id "$id" "if has(\$_id) then .[\$_id] |= ($expr) else . end" <<<"$cur" ) \
      > "$tmp" 2>/dev/null && mv -f "$tmp" "$f" || rm -f "$tmp"
  ) 9>"$lk"
}
# authored_prune — PODA do overlay: remove as entradas JÁ refletidas no índice de donos SEM
# divergência nos campos de setter (owner/title/public/collections/collaborators). O overlay é
# só a ponte de visibilidade imediata até o índice alcançar; sem poda ele crescia p/ sempre
# (chegou a 344 entradas/131KiB — estourou o --argjson do upsert e eternizou um html:false
# envenenado). Auto-throttle por MTIME: só roda quando o índice é MAIS NOVO que o overlay (a
# própria poda/um upsert rejuvenesce o overlay ⇒ no máx. 1 poda por regeneração do índice).
# Entrada DIVERGENTE (edit mais novo que o índice) e NÃO-indexada FICAM — podam num passo futuro.
authored_prune(){
  local f="$AUTHORED_INDEX" lk
  [[ -s "$f" && -s "$OWNERS_INDEX" ]] || return 0
  [[ "$OWNERS_INDEX" -nt "$f" ]] || return 0
  lk="$(_idx_lock "$f")"
  ( flock 9 2>/dev/null
    [[ "$OWNERS_INDEX" -nt "$f" ]] || exit 0          # rechecagem sob o lock
    local tmp="$f.tmp.$$"
    # overlay por STDIN (ARG_MAX) + índice por --slurpfile; {} de saída é válido (tudo podado)
    jq -c --slurpfile idx "$OWNERS_INDEX" '
      ((($idx[0].problems) // []) | map({key:.id, value:.}) | from_entries) as $by
      | with_entries( .value as $v | ($by[$v.id] // null) as $p
          | select( ($p == null)
              or (($v.owner // "") != ($p.owner // ""))
              or (($v.title // "") != ($p.title // ""))
              or (($v.public // false) != ($p.public // false))
              or ((($v.collections // [])|sort) != (($p.collections // [])|sort))
              or ((($v.collaborators // [])|sort) != (($p.collaborators // [])|sort)) ) )
      ' < "$f" > "$tmp" 2>/dev/null && [[ -s "$tmp" ]] && mv -f "$tmp" "$f" || rm -f "$tmp"
  ) 9>"$lk"
  return 0
}

# authored_remove <id> — tira a entrada do overlay (problema removido -> some na hora das listas)
authored_remove(){
  local f="$AUTHORED_INDEX" lk; lk="$(_idx_lock "$f")"
  ( flock 9 2>/dev/null
    local cur tmp; cur="$(cat "$f" 2>/dev/null)"; [[ -n "$cur" ]] || exit 0
    tmp="$f.tmp.$$"
    ( umask 077; jq --arg id "$1" 'del(.[$id])' <<<"$cur" ) > "$tmp" 2>/dev/null && mv -f "$tmp" "$f" || rm -f "$tmp"
  ) 9>"$lk"
}

# norm <txt> -> minúsculas, sem acento, só [a-z0-9 ] (espelha gen-problem-owners.sh)
prob_norm(){ printf '%s' "$1" | iconv -f utf-8 -t ascii//TRANSLIT 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9 ' ' ' | tr -s ' '; }

# ---- storage MOJ-nativo: repo git LOCAL por problema (sem Gitea) --------------------------
# O canônico É a árvore de trabalho em $MOJ_PROBLEMS_DIR/<org>/<prob> (pkg_path lê dela direto). O
# servidor commita local p/ auditoria; NÃO há mirror, push, remote nem token. ensure_repo_materialized
# vira no-op (o pacote já está no lugar) — mantida só p/ não quebrar chamadas remanescentes.
ensure_repo_materialized(){ return 0; }

# _need_orgs — garante lib/orgs.sh carregada (acesso por org). Idempotente.
_need_orgs(){ declare -F org_is_member >/dev/null || source "$(dirname "${BASH_SOURCE[0]}")/orgs.sh" 2>/dev/null; }

# problem_commit <pkgdir> <login> <msg> -> HEAD sha. git init idempotente + add -A + commit autorado
# pelo login. flock POR-PROBLEMA (dois saves no mesmo problema não corrompem a árvore/índice git).
problem_commit(){
  local pkg="$1" login="${2:-moj}" msg="${3:-update}" em="${2:-moj}@moj.local" lk
  [[ -d "$pkg" ]] || return 1
  # Modo canônico AQUI, no último passo de TODA escrita: o apply_problem_fields já normaliza, mas
  # quem grava DEPOIS dele (write_meta, o sidecar do Kattis: problem.yaml/.kattis.json) pegava o
  # `umask 007` do fcgiwrap e saía 660. Aqui nada escapa — o que vai p/ o commit está em 644/755.
  _pkg_canon_modes "$pkg"
  mkdir -p "${RUNDIR:-/home/ribas/moj/run}/locks" 2>/dev/null
  lk="${RUNDIR:-/home/ribas/moj/run}/locks/$(printf '%s' "$pkg" | md5sum 2>/dev/null | cut -c1-24).lock"
  (
    flock 9 2>/dev/null
    cd "$pkg" || exit 1
    if [[ ! -d .git ]]; then
      git -c init.defaultBranch=master init -q 2>/dev/null
    fi
    # Artefatos GERADOS não entram no git: o TL da calibração e os caches de compilação do
    # checker testlib (.checker-cache) e do árbitro interativo (.arbitro-cache) — são ELFs de
    # vários MB que um `git add -A` commitaria dentro do pacote. Idempotente de propósito: repo
    # criado antes destas linhas também as ganha (antes, o exclude só era escrito no `git init`).
    for _ex in 'tl' 'tl.*' '.checker-cache/' '.arbitro-cache/'; do
      grep -qxF "$_ex" .git/info/exclude 2>/dev/null || printf '%s\n' "$_ex" >> .git/info/exclude 2>/dev/null
    done
    git add -A 2>/dev/null
    GIT_AUTHOR_NAME="$login" GIT_AUTHOR_EMAIL="$em" GIT_COMMITTER_NAME="$login" GIT_COMMITTER_EMAIL="$em" \
      git commit -q -m "$msg" >/dev/null 2>&1 || true   # "nada a commitar" não é erro (e o
      # "On branch …" que o -q ainda imprime no STDOUT poluía o sha capturado pelo chamador)
    git rev-parse HEAD 2>/dev/null
  ) 9>"$lk"
}
# ---- COLEÇÕES = TAG de agrupamento (m:n) com REGISTRO CURADO -------------------------------
# Coleção é ORTOGONAL à ORG: um problema está em 1 org (acesso, prefixo do id) mas em VÁRIAS coleções
# (rótulos em .moj-meta.json collections[]). O nome é TEXTO LIVRE (pode ter espaços/acentos — é só
# rótulo, NUNCA vira id/caminho/arquivo). SEM members/admins (acesso é da ORG); só o DONO da coleção
# (ou .admin) renomeia/exclui. "Curada": marcar um problema numa coleção exige que ela EXISTA aqui.
COLL_REGISTRY="$CONTESTSDIR/treino/var/collections.json"
_coll_read(){ local c; c="$(cat "$COLL_REGISTRY" 2>/dev/null)"; [[ -n "$c" ]] || c='{}'; printf '%s' "$c"; }
coll_exists(){ [[ -f "$COLL_REGISTRY" ]] && jq -e --arg n "$1" 'has($n)' >/dev/null 2>&1 < "$COLL_REGISTRY"; }
coll_owner(){ [[ -f "$COLL_REGISTRY" ]] && jq -r --arg n "$1" '.[$n].owner // empty' "$COLL_REGISTRY" 2>/dev/null; }
coll_all(){ _coll_read | jq -c 'keys'; }
# coll_valid_name <name> -> 0 se nome válido (texto livre: 1..80 chars, sem caractere de controle)
coll_valid_name(){ local n="$1"; [[ -n "$n" ]] || return 1; [[ "$n" =~ [[:cntrl:]] ]] && return 1; (( ${#n} <= 80 )); }
# coll_can_manage <name> <login> — dono da coleção OU admin global
coll_can_manage(){ { declare -F is_admin >/dev/null && is_admin; } && return 0; [[ "$(coll_owner "$1")" == "$2" ]]; }
# coll_register <name> <owner> — cria (idempotente; preserva dono/at de quem já existe).
# Os três abaixo são read-modify-write do MESMO arquivo -> flock (senão duas criações simultâneas
# perdem uma; ver _idx_lock).
coll_register(){
  local n="$1" o="$2" lk; lk="$(_idx_lock "$COLL_REGISTRY")"
  ( flock 9 2>/dev/null
    local cur tmp; cur="$(_coll_read)"; tmp="$COLL_REGISTRY.tmp.$$"
    ( umask 077; jq --arg n "$n" --arg o "$o" --argjson now "$EPOCHSECONDS" '
        .[$n] = ((.[$n] // {}) + {owner:((.[$n].owner) // $o), created_by:((.[$n].created_by) // $o), at:((.[$n].at) // $now)})' <<<"$cur" ) \
      > "$tmp" 2>/dev/null && mv -f "$tmp" "$COLL_REGISTRY" || rm -f "$tmp"
  ) 9>"$lk"
}
coll_delete(){ local n="$1" lk; lk="$(_idx_lock "$COLL_REGISTRY")"
  ( flock 9 2>/dev/null
    local cur tmp; cur="$(_coll_read)"; tmp="$COLL_REGISTRY.tmp.$$"
    ( umask 077; jq --arg n "$n" 'del(.[$n])' <<<"$cur" ) > "$tmp" 2>/dev/null && mv -f "$tmp" "$COLL_REGISTRY" || rm -f "$tmp"
  ) 9>"$lk"; }
# coll_rename <old> <new> — renomeia no registro (o bulk nos metas dos problemas fica no handler).
coll_rename(){ local o="$1" n="$2" lk; lk="$(_idx_lock "$COLL_REGISTRY")"
  ( flock 9 2>/dev/null
    local cur tmp; cur="$(_coll_read)"; tmp="$COLL_REGISTRY.tmp.$$"
    ( umask 077; jq --arg o "$o" --arg n "$n" 'if has($o) and ($o!=$n) then .[$n]=(.[$o]) | del(.[$o]) else . end' <<<"$cur" ) \
      > "$tmp" 2>/dev/null && mv -f "$tmp" "$COLL_REGISTRY" || rm -f "$tmp"
  ) 9>"$lk"; }
# ---- registro de JOBS do retag (visibilidade do background) --------------------------------
# O retag roda destacado (setsid) e antes era MUDO: não dava p/ saber quando terminou nem se
# falhou parcialmente (a corrida do rename em rajada foi silenciosa). Cada bulk agora tem um
# job em var/retag-jobs.json {jobid:{from,to,by,started_at,total,done,failed,finished_at}},
# atualizado pelo worker e servido por GET /problems/collection-retag-status. Mantém ~50.
RETAG_JOBS="$CONTESTSDIR/treino/var/retag-jobs.json"
# _retag_job_patch <jobid> <jq-expr sobre o job> [jq args...] — RMW com flock; cria se ausente.
_retag_job_patch(){
  local jid="$1" expr="$2"; shift 2
  local f="$RETAG_JOBS" lk; lk="$(_idx_lock "$f")"
  ( flock 9 2>/dev/null
    local cur tmp; cur="$(cat "$f" 2>/dev/null)"; [[ -n "$cur" ]] || cur='{}'
    tmp="$f.tmp.$$"
    ( umask 077; jq "$@" --arg _j "$jid" '
        .[$_j] = ((.[$_j] // {}) | '"$expr"')
        | (if (keys|length) > 60
           then (to_entries | sort_by(.value.started_at // 0) | .[-50:] | from_entries)
           else . end)' <<<"$cur" ) \
      > "$tmp" 2>/dev/null && [[ -s "$tmp" ]] && mv -f "$tmp" "$f" || rm -f "$tmp"
  ) 9>"$lk"
}

# coll_bulk_retag <old> <new|""> <login> [jobid] -> nº de problemas afetados. Renomeia (new!="") ou REMOVE
# (new=="") a tag <old> no .moj-meta.json de TODOS os problemas que a têm (+ commit local + overlay +
# re-index dos que estão públicos, p/ o json servido refletir a tag nova). Usado por rename/delete.
# RETOMÁVEL por construção (processa só metas que AINDA têm a tag velha) e feito p/ rodar em
# BACKGROUND: N problemas = N commits + N reindexações — síncrono num request estourava o
# timeout do nginx e o loop morria no meio (rename da obi, 2026-07-17: 30 metas órfãos).
# A reindexação dos públicos é SEQUENCIAL (index_problem_now) — N setsids paralelos de
# gen-problem-json eram uma tempestade de pandoc.
coll_bulk_retag(){
  local old="$1" new="$2" login="${3:-moj}" jid="${4:-}" n=0 failed=0 pdir meta org prob id owner lk rc
  local newc_now title_now author_txt pub_now total
  declare -F index_problem_now >/dev/null || source "$(dirname "${BASH_SOURCE[0]}")/tl-store.sh" 2>/dev/null
  if [[ -n "$jid" ]]; then
    # total p/ a barra de progresso: um jq só sobre todos os metas (xargs pode fatiar em
    # lotes -> soma). Meta corrompido derruba um lote inteiro do jq -s: o total vira
    # ESTIMATIVA por baixo — aceitável, é só progresso.
    total="$(find "$MOJ_PROBLEMS_DIR" -mindepth 3 -maxdepth 3 -name .moj-meta.json -print0 2>/dev/null \
      | xargs -0 -r jq -s --arg o "$old" '[ .[] | select(((.collections // [])|index($o)) != null) ] | length' 2>/dev/null \
      | awk '{s+=$1} END{print s+0}')"
    _retag_job_patch "$jid" '. + {total: $t}' --argjson t "${total:-0}"
  fi
  while IFS= read -r pdir; do
    meta="$pdir/.moj-meta.json"; [[ -f "$meta" ]] || continue
    jq -e --arg o "$old" '((.collections // [])|index($o)) != null' >/dev/null 2>&1 < "$meta" || continue
    prob="${pdir##*/}"; org="${pdir%/*}"; org="${org##*/}"; id="$org#$prob"
    owner="$(problem_owner "$id")"; [[ -n "$owner" ]] || owner="$login"
    # A mutação ler-meta -> write_meta fica sob o MESMO lock por-problema do problem_commit:
    # N renames em rajada = N workers setsid varrendo os MESMOS metas, e o read-modify-write
    # sem lock corria — last-writer-wins engolia o rename do outro worker (problema em 4
    # coleções renomeadas ficou com resto de nome velho, 2026-07-22). O newc é recomputado
    # DENTRO do lock (recomputar fora e só escrever dentro perde update do mesmo jeito).
    # NÃO aninhar o problem_commit aqui (mesmo arquivo de lock, open próprio = se bloqueia).
    mkdir -p "${RUNDIR:-/home/ribas/moj/run}/locks" 2>/dev/null
    lk="${RUNDIR:-/home/ribas/moj/run}/locks/$(printf '%s' "$pdir" | md5sum 2>/dev/null | cut -c1-24).lock"
    rc=0
    (
      flock 9 2>/dev/null
      jq -e --arg o "$old" '((.collections // [])|index($o)) != null' >/dev/null 2>&1 < "$meta" || exit 3
      if [[ -n "$new" ]]; then nc="$(jq -c --arg o "$old" --arg nn "$new" '(.collections//[])|map(if .==$o then $nn else . end)|unique' "$meta")"
      else nc="$(jq -c --arg o "$old" '(.collections//[])|map(select(.!=$o))' "$meta")"; fi
      write_meta "$pdir" "$owner" "$org" "" "$nc" ""
    ) 9>"$lk" || rc=$?
    [[ $rc -eq 3 ]] && continue        # outro worker já retagueou este meta (retomada/rajada)
    if [[ $rc -ne 0 ]]; then
      failed=$((failed+1))
      [[ -n "$jid" ]] && _retag_job_patch "$jid" '. + {failed: $f}' --argjson f "$failed"
      continue
    fi
    problem_commit "$pdir" "$login" "coleção: $old -> ${new:-(removida)}" >/dev/null
    # Overlay via UPSERT, não patch: o authored_patch era NO-OP p/ id já PODADO do overlay —
    # problema PRIVADO renomeado ficava com o índice servido velho (moj info/collection show)
    # até a regen de ~30 min; o público se salvava pelo index_problem_now abaixo. Mesmo
    # padrão do edit.sh: relê os campos do meta recém-escrito.
    newc_now="$(jq -c '.collections // []' "$meta" 2>/dev/null)"; [[ -n "$newc_now" ]] || newc_now='[]'
    title_now="$(jq -r '.display_title // ""' "$meta" 2>/dev/null)"
    pub_now="$(jq -r 'if .public==true then "true" else "false" end' "$meta" 2>/dev/null)"
    author_txt="$(head -1 "$pdir/author" 2>/dev/null)"
    authored_upsert "$id" "$owner" "$org" "$prob" "$title_now" "${pub_now:-false}" "$newc_now" "$author_txt" '[]'
    [[ "$pub_now" == true ]] && declare -F index_problem_now >/dev/null && index_problem_now "$id" 1
    n=$((n+1))
    [[ -n "$jid" ]] && _retag_job_patch "$jid" '. + {done: $n}' --argjson n "$n"
  done < <(find "$MOJ_PROBLEMS_DIR" -mindepth 2 -maxdepth 2 -type d ! -name '.git' 2>/dev/null)
  printf '%s' "$n"
}
# coll_bulk_retag_bg <old> <new|""> <login> [delete] — o bulk acima DESTACADO em background
# (o request responde na hora; o retag é retomável). 4º arg "delete" = remove a coleção do
# REGISTRO só NO FIM do bulk (delete que morre no meio continua existindo ⇒ repetir retoma).
coll_bulk_retag_bg(){
  local old="$1" new="$2" login="${3:-moj}" after="${4:-}" lib jid
  lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  jid="rt$EPOCHSECONDS.$$.$RANDOM"
  _retag_job_patch "$jid" '. + {from:$from, to:$to, by:$by, started_at:$now, done:0, failed:0}' \
    --arg from "$old" --arg to "$new" --arg by "$login" --argjson now "$EPOCHSECONDS"
  ( setsid env RUNDIR="$RUNDIR" CONTESTSDIR="$CONTESTSDIR" MOJ_PROBLEMS_DIR="$MOJ_PROBLEMS_DIR" \
      MOJTOOLS_DIR="$MOJTOOLS_DIR" \
      bash -c 'source "$1/common.sh" 2>/dev/null; source "$1/problems.sh" && source "$1/tl-store.sh"
               n="$(coll_bulk_retag "$2" "$3" "$4" "$6")"
               [[ "$5" == delete ]] && coll_delete "$2"
               _retag_job_patch "$6" ". + {finished_at: \$now, done: \$n}" \
                 --argjson now "$EPOCHSECONDS" --argjson n "${n:-0}"
               declare -F audit_log >/dev/null 2>&1 \
                 && audit_log "collection-retag-done" "from=$2 to=${3:-(removida)} n=$n by=$4 job=$6"' \
      _ "$lib" "$old" "$new" "$login" "$after" "$jid" >/dev/null 2>&1 & ) 2>/dev/null
  printf '%s' "$jid"   # o handler devolve o job id p/ o cliente acompanhar
}
# grant_problem_collections — NO-OP (acesso é por ORG; coleção é só tag, não propaga colaborador).
grant_problem_collections(){ return 0; }

# problem_access <id> <login> -> mine|shared|public|denied|unknown
# (denied = existe, é privado e o login não é dono/colaborador; unknown = fora do índice)
problem_access(){
  local id="$1" me="$2" org="${1%%#*}" p owner pub
  ensure_owners_index
  p="$(owners_merged | jq -c --arg id "$id" 'first(.problems[]|select(.id==$id)) // empty' 2>/dev/null)"
  if [[ -z "$p" ]]; then
    # FALLBACK DE DISCO: índice/overlay atrasado ou quebrado NUNCA nega acesso a MEMBRO da org
    # (verdade de acesso = pacote em disco + orgs.json, não um cache lazy). Sem isto, o overlay
    # >128KiB (upsert no-op silencioso) fez todo problema recém-subido dar 404 p/ o PRÓPRIO
    # autor. Anti-leak intacto: não-membro segue 'unknown' (404) e público continua exigindo o
    # índice — este fallback só devolve 'shared', nunca 'public'.
    declare -F pkg_path >/dev/null || source "$(dirname "${BASH_SOURCE[0]}")/tl-store.sh" 2>/dev/null
    local pk; pk="$(pkg_path "$id" 2>/dev/null)"
    if [[ -n "$pk" && -d "$pk" ]]; then
      _need_orgs
      org_is_member "$org" "$me" && { printf 'shared'; return; }
    fi
    printf 'unknown'; return
  fi
  owner="$(jq -r '.owner // empty' <<<"$p")"; pub="$(jq -r 'if .public then 1 else 0 end' <<<"$p")"
  [[ "$owner" == "$me" ]] && { printf 'mine'; return; }
  _need_orgs
  org_is_member "$org" "$me" && { printf 'shared'; return; }
  [[ "$pub" == 1 ]] && { printf 'public'; return; }
  printf 'denied'
}
# require_problem_edit <id> — CORTA NA API (404) se o login não for MEMBRO da ORG do problema. Use nos
# endpoints que devolvem source/pacote/soluções/calibração (conteúdo sensível). Acesso = membro da org
# (org_is_member; membros+admins). SEM atalho de .admin. 404 (não 403) p/ não revelar a EXISTÊNCIA de um
# problema privado. A trava está AQUI na API, nunca só na interface.
require_problem_edit(){
  local id="$1" org="${1%%#*}"
  _need_orgs
  org_is_member "$org" "$SESSION_LOGIN" || fail 404 "Problema não encontrado" "not_found"
}
# require_problem_view <id> — CORTA (404) se o problema é PRIVADO e o login não é dono/colaborador.
# Público => qualquer um vê o detalhe/metadados (mas não o source/pacote -> require_problem_edit).
require_problem_view(){
  local acc; acc="$(problem_access "$1" "$SESSION_LOGIN")"
  [[ "$acc" == mine || "$acc" == shared || "$acc" == public ]] || fail 404 "Problema não encontrado" "not_found"
}

# problem_owner <id> -> login dono (overlay authored -> índice -> registro de repos). Vazio se desconhecido.
problem_owner(){
  local id="$1" o pk
  o="$(jq -r --arg id "$id" '.[$id].owner // empty' "$AUTHORED_INDEX" 2>/dev/null)"
  [[ -n "$o" ]] && { printf '%s' "$o"; return; }
  ensure_owners_index
  o="$(jq -r --arg id "$id" 'first(.problems[]|select(.id==$id)).owner // empty' "$OWNERS_INDEX" 2>/dev/null)"
  [[ -n "$o" ]] && { printf '%s' "$o"; return; }
  declare -F pkg_path >/dev/null || source "$(dirname "${BASH_SOURCE[0]}")/tl-store.sh" 2>/dev/null
  pk="$(pkg_path "$id" 2>/dev/null)"; [[ -n "$pk" && -f "$pk/.moj-meta.json" ]] && jq -r '.owner // empty' "$pk/.moj-meta.json" 2>/dev/null
}

# ---- autoria: materialização do pacote (escreve só os campos presentes no body) -----------
# grava o conteúdo de stdin num arquivo com EXATAMENTE 1 \n final (vazio continua vazio).
# Idempotente e auto-corretivo: sem isto, cada "Salvar" acumulava uma linha em branco nos
# arquivos (jq -r encerra a saída com \n; o valor lido já trazia o \n do arquivo).
# O caminho quente (apply_problem_fields) NÃO o usa mais — normaliza no próprio jq (`nl1`), com o
# mesmo resultado byte-a-byte e sem um fork por arquivo. Fica p/ quem grava 1 arquivo avulso.
_putfile(){ local f="$1" c; c="$(cat)"; if [[ -n "$c" ]]; then printf '%s\n' "$c" > "$f"; else : > "$f"; fi; }

# _pkg_canon_modes <pkgdir> — MODO CANÔNICO do pacote: 644 (arquivo), 755 (dir e arquivo com +x).
# INDEPENDENTE do umask do processo. O fcgiwrap roda com `umask 007` (p/ o socket unix nascer 0770,
# senão o nginx do sistema toma EACCES), e sem isto TODO arquivo gravado pela API saía 660 enquanto
# o MESMO pacote vindo de tar/rsync saía 644. Como o tl-checksum inclui o MODO de scripts/*, o mesmo
# conteúdo gerava checksum diferente conforme o caminho (push × upload) => recalibração espúria e
# conferência "checksum local == servidor" falhando à toa. Preserva o +x de quem já o tem (é
# load-bearing: o juiz executa scripts/compare.sh e <lang>/{compile,run}.sh direto).
_pkg_canon_modes(){
  local pkg="$1"
  [[ -d "$pkg" ]] || return 0
  find "$pkg" -name .git -prune -o -type d -exec chmod 755 {} + 2>/dev/null
  find "$pkg" -name .git -prune -o -type f ! -perm -u+x -exec chmod 644 {} + 2>/dev/null
  find "$pkg" -name .git -prune -o -type f   -perm -u+x -exec chmod 755 {} + 2>/dev/null
  return 0
}

# apply_problem_fields <pkgdir> <body-json-FILE> — materializa no pacote os campos presentes no body.
#
# O corpo vem em ARQUIVO, não em variável (read_body_file): um pacote de 84 MB vira ~100 MB de JSON, e
# a versão antiga fazia 36 `<<<"$body"` (cada um REGRAVA os 100 MB num temp e o jq RE-PARSEIA tudo:
# ~50s de CPU + 3,6 GB de I/O) e lia os testes de um PIPE — e o `read` do bash sobre pipe faz 1 syscall
# POR BYTE (medido: 1,74 MB/s => ~55s só nisso). Resultado: 504 do nginx aos 120s COM O PACOTE PELA
# METADE (os testes antigos já apagados, o meta ainda não gravado).
# Agora: 1 passada de jq p/ as sondas+escalares, 1 passada por coleção (testes/exemplos/soluções/
# scripts) em stream NUL (--raw-output0) gravado em ARQUIVO, e o laço lê DO ARQUIVO (fd seekable ⇒ o
# bash lê em bloco). Zero fork por teste. A normalização de \n final (o que o _putfile fazia) é feita
# pelo jq (`nl1`), byte-idêntica.
apply_problem_fields(){  # <pkgdir> <body-json-FILE>
  local pkg="$1" bodyf="$2" _bodytmp="" _t _um _man
  # compat: chamador que ainda passe o JSON como STRING (nenhum no repo; a função é pública)
  [[ -f "$bodyf" ]] || { _bodytmp="$(mktemp)"; printf '%s' "$bodyf" > "$_bodytmp"; bodyf="$_bodytmp"; }
  _t="$(mktemp -d)"
  _um="$(umask)"; umask 022        # arquivo NOVO nasce 644 (o do fcgiwrap é 007); ver _pkg_canon_modes

  mkdir -p "$pkg/docs" "$pkg/tests/input" "$pkg/tests/output" "$pkg/sols/good"

  # prelúdio jq: normaliza p/ EXATAMENTE 1 \n final (idêntico ao _putfile) e p/ ZERO \n (editorial)
  local JQNL='def rtrim: until((endswith("\n")|not); rtrimstr("\n"));
              def nl1: if .=="" then "" else (rtrim + "\n") end;'

  # ---------- 1 passada: TODAS as sondas + os escalares curtos (antes: ~36 re-parses) ----------
  local HAS_ENUN=0 HAS_AUTHOR=0 HAS_TAGS=0 HAS_CONF=0 HAS_EXAMPLES=0 HAS_NOTES=0 HAS_TESTS=0 \
        HAS_SCORE=0 SCORE_ENABLED=0 HAS_SOLS=0 HAS_GOODSOL=0 HAS_SCRIPTS=0 HAS_SCORETXT=0 \
        HAS_EDITORIAL=0 HAS_DOCSFILES=0 EFMT='' GOODSOL_FN='' SOLS_CATS=''
  _man="$(jq -r '
      def b(x): (if x then "1" else "0" end);
      "HAS_ENUN=\(b(has("enunciado_md")))",
      "HAS_AUTHOR=\(b(has("author")))",
      "HAS_TAGS=\(b(has("tags")))",
      "HAS_CONF=\(b(has("conf_text")))",
      "HAS_EXAMPLES=\(b(has("examples")))",
      "HAS_NOTES=\(b(any(.examples[]?; has("explanation"))))",
      "HAS_TESTS=\(b(has("tests")))",
      "HAS_SCORE=\(b(has("score")))",
      "SCORE_ENABLED=\(b(.score.enabled == true))",
      "HAS_SOLS=\(b(has("sols")))",
      "HAS_GOODSOL=\(b(has("good_sol")))",
      "HAS_SCRIPTS=\(b(has("scripts_files")))",
      "HAS_DOCSFILES=\(b(has("docs_files")))",
      "HAS_SCORETXT=\(b(has("score_text")))",
      "HAS_EDITORIAL=\(b(has("editorial_md")))",
      "EFMT=\((.enunciado_format // "") | @sh)",
      "GOODSOL_FN=\((.good_sol.filename // "sol.cpp") | @sh)",
      "SOLS_CATS=\(((.sols // {}) | keys | join(" ")) | @sh)"
    ' < "$bodyf" 2>/dev/null)"
  # jq mudo aqui = corpo ilegível: ABORTA (não dá p/ "aplicar metade" calado)
  if [[ -z "$_man" ]]; then umask "$_um"; rm -rf "$_t" "$_bodytmp"; return 1; fi
  eval "$_man"

  # ---------- escalares (1 passada, stream NUL) ----------
  jq --raw-output0 "$JQNL"'
      (.enunciado_md // "" | nl1),
      (.author       // "" | nl1),
      ((.tags // []) | join("\n") | nl1),
      (.conf_text    // "" | nl1),
      (.editorial_md // "" | rtrim),
      (.score_text   // "" | nl1),
      ((.examples // []) | map(.explanation // "") | tojson),
      (.good_sol.code // "" | nl1)
    ' < "$bodyf" > "$_t/scalars.nul" 2>/dev/null
  local S_ENUN='' S_AUTHOR='' S_TAGS='' S_CONF='' S_EDIT='' S_SCORETXT='' S_NOTES='' S_GOODSOL=''
  { IFS= read -r -d '' S_ENUN; IFS= read -r -d '' S_AUTHOR; IFS= read -r -d '' S_TAGS
    IFS= read -r -d '' S_CONF; IFS= read -r -d '' S_EDIT;   IFS= read -r -d '' S_SCORETXT
    IFS= read -r -d '' S_NOTES; IFS= read -r -d '' S_GOODSOL; } < "$_t/scalars.nul" 2>/dev/null

  # ---------- enunciado (preserva o FORMATO: md/org/tex) ----------
  if (( HAS_ENUN )); then
    local e
    if [[ -z "$EFMT" ]]; then for e in md org tex; do [[ -f "$pkg/docs/enunciado.$e" ]] && { EFMT="$e"; break; }; done; fi
    [[ "$EFMT" =~ ^(md|org|tex)$ ]] || EFMT=md
    for e in md org tex; do [[ "$e" != "$EFMT" && -f "$pkg/docs/enunciado.$e" ]] && rm -f "$pkg/docs/enunciado.$e"; done
    printf '%s' "$S_ENUN" > "$pkg/docs/enunciado.$EFMT"
  fi
  # author/tags/conf: o nl1 torna a gravação IDEMPOTENTE. O author era o único que ia direto do
  # `jq -r` p/ o arquivo (sem _putfile): como o `jq -r` já encerra com \n, um valor que JÁ trouxesse
  # o \n final (a CLI manda sem, mas nada garantia) engordava o arquivo a cada save.
  (( HAS_AUTHOR )) && printf '%s' "$S_AUTHOR" > "$pkg/author"
  (( HAS_TAGS ))   && printf '%s' "$S_TAGS"   > "$pkg/tags"
  (( HAS_CONF ))   && printf '%s' "$S_CONF"   > "$pkg/conf"

  # ---------- exemplos ----------
  if (( HAS_EXAMPLES )); then
    find "$pkg/tests/input"  -name 'sample*' -delete 2>/dev/null
    find "$pkg/tests/output" -name 'sample*' -delete 2>/dev/null
    jq --raw-output0 "$JQNL"'.examples[]? | (.input // "" | nl1), (.output // "" | nl1)' \
      < "$bodyf" > "$_t/ex.nul" 2>/dev/null
    local i=0 inp='' outp=''
    while IFS= read -r -d '' inp && IFS= read -r -d '' outp; do
      i=$((i+1))
      printf '%s' "$inp"  > "$pkg/tests/input/sample$i"
      printf '%s' "$outp" > "$pkg/tests/output/sample$i"
    done < "$_t/ex.nul"
    # explicação por exemplo -> docs/notes/sample<N>.md (1 arquivo MARKDOWN por exemplo —
    # o formato de autoria; o autor nunca edita JSON). Escrever aqui REMOVE o legado
    # sample-notes.json (fonte única). Só mexe se o cliente for "ciente de explicação"
    # (algum exemplo traz a chave); cliente antigo não apaga as notas de ninguém.
    if (( HAS_NOTES )); then
      rm -rf "$pkg/docs/notes"; rm -f "$pkg/docs/sample-notes.json"
      if [[ "$(jq -r 'map(select(.!=""))|length' <<<"$S_NOTES" 2>/dev/null)" -gt 0 ]]; then
        mkdir -p "$pkg/docs/notes"
        printf '%s' "$S_NOTES" > "$_t/notes.json"
        local nk=0 nc ntf
        nc="$(jq 'length' "$_t/notes.json" 2>/dev/null)"; [[ "$nc" =~ ^[0-9]+$ ]] || nc=0
        while (( nk < nc )); do
          ntf="$_t/note.$nk"
          jq -r --argjson k "$nk" '.[$k] // ""' "$_t/notes.json" > "$ntf" 2>/dev/null
          [[ -n "$(tr -d '[:space:]' < "$ntf" 2>/dev/null)" ]] && cp "$ntf" "$pkg/docs/notes/sample$((nk+1)).md"
          nk=$((nk+1))
        done
      fi
    fi
  fi

  # ---- resolução/editorial (só p/ setters; docs/solucao.md; não vai p/ o aluno) -------------
  if (( HAS_EDITORIAL )); then
    if [[ -n "$S_EDIT" ]]; then printf '%s' "$S_EDIT" > "$pkg/docs/solucao.md"; else rm -f "$pkg/docs/solucao.md"; fi
  fi

  # ---- pontuação por grupos (subtasks) ----------------------------------------
  # score = {enabled, groups:[{name,weight,glob}]}; cada teste pode trazer .group p/ ser FIXADO num
  # grupo (renomeado p/ <prefixo>NN); sem .group, mantém o nome (auto, casado pelo glob no juiz).
  # Sem o campo "score" no body → comportamento legado.
  local -A GGLOB=()
  if (( SCORE_ENABLED || HAS_SCORE )); then
    jq --raw-output0 '.score.groups[]? | (.name // ""), (.glob // ""), ((.weight // 0) | tostring)' \
      < "$bodyf" > "$_t/groups.nul" 2>/dev/null
  fi
  if (( SCORE_ENABLED )); then
    local gn='' gg='' gw=''
    while IFS= read -r -d '' gn && IFS= read -r -d '' gg && IFS= read -r -d '' gw; do
      gn="${gn//[^A-Za-z0-9._-]/}"; [[ -n "$gn" ]] || continue
      gg="$(_norm_globs "$gg")"; gg="${gg%%,*}"; [[ -n "$gg" ]] || gg="${gn}_*"   # só o 1º glob (prefixo)
      GGLOB[$gn]="$gg"
    done < "$_t/groups.nul"
  fi

  # ---------- testes OCULTOS (substitui; mantém os sample*) ----------
  if (( HAS_TESTS )); then
    local inp0 nm0
    set +o noglob; shopt -s nullglob
    for inp0 in "$pkg/tests/input"/*; do nm0="${inp0##*/}"; [[ "$nm0" == sample* ]] && continue
      rm -f "$inp0" "$pkg/tests/output/$nm0"; done
    shopt -u nullglob; set -o noglob
    jq --raw-output0 "$JQNL"'.tests[]? | (.name // ""), (.group // ""), (.input // "" | nl1), (.output // "" | nl1)' \
      < "$bodyf" > "$_t/tests.nul" 2>/dev/null
    local i=0 nm='' tgrp='' gpre n cand
    while IFS= read -r -d '' nm && IFS= read -r -d '' tgrp && IFS= read -r -d '' inp && IFS= read -r -d '' outp; do
      i=$((i+1))
      nm="${nm//[^A-Za-z0-9._-]/}"; [[ -n "$nm" ]] || nm="$i"
      [[ "$nm" == sample* ]] && nm="t$nm"   # nomes sample* são reservados aos exemplos
      if (( SCORE_ENABLED )); then
        tgrp="${tgrp//[^A-Za-z0-9._-]/}"
        if [[ -n "$tgrp" && -n "${GGLOB[$tgrp]:-}" ]]; then
          gpre="${GGLOB[$tgrp]%\**}"                         # g2_* -> g2_
          # FIXADO: mantém se já é <prefixo><dígitos> livre; senão pega o próximo <prefixo>NN livre
          if [[ "$nm" == "$gpre"* && "${nm#$gpre}" =~ ^[0-9]+$ && ! -e "$pkg/tests/input/$nm" ]]; then :
          else n=1; while cand="${gpre}$(printf '%02d' "$n")"; [[ -e "$pkg/tests/input/$cand" ]]; do n=$((n+1)); done; nm="$cand"; fi
        fi
      fi
      printf '%s' "$inp"  > "$pkg/tests/input/$nm"
      printf '%s' "$outp" > "$pkg/tests/output/$nm"
    done < "$_t/tests.nul"
  fi

  # grava/remove tests/score conforme o modo (só quando o body traz o campo "score")
  if (( HAS_SCORE )); then
    if (( SCORE_ENABLED )); then
      { compgen -G "$pkg/tests/input/sample*" >/dev/null 2>&1 && echo "sample* - 0 pontos"
        local gn2='' gg2='' gw2=''
        while IFS= read -r -d '' gn2 && IFS= read -r -d '' gg2 && IFS= read -r -d '' gw2; do
          gn2="${gn2//[^A-Za-z0-9._-]/}"; [[ -n "$gn2" ]] || continue
          gg2="$(_norm_globs "$gg2")"; [[ -n "$gg2" ]] || gg2="${gn2}_*"   # preserva a lista multi-glob
          gw2="${gw2//[^0-9]/}"; gw2="${gw2:-0}"
          echo "$gg2 - $gw2 pontos"
        done < "$_t/groups.nul"
      } > "$pkg/tests/score"
    else
      rm -f "$pkg/tests/score"
    fi
  fi

  # ---------- soluções por categoria (substitui a categoria inteira quando presente) ----------
  if (( HAS_SOLS )); then
    local cat
    for cat in $SOLS_CATS; do
      [[ "$cat" =~ ^(good|slow|wrong|pass|upcoming)$ ]] || continue
      rm -rf "$pkg/sols/$cat"; mkdir -p "$pkg/sols/$cat"
    done
    jq --raw-output0 "$JQNL"'(.sols // {}) | to_entries[] | .key as $c | ((.value // [])[] | $c, (.filename // ""), (.code // "" | nl1))' \
      < "$bodyf" > "$_t/sols.nul" 2>/dev/null
    local sc='' sfn='' scode=''
    while IFS= read -r -d '' sc && IFS= read -r -d '' sfn && IFS= read -r -d '' scode; do
      [[ "$sc" =~ ^(good|slow|wrong|pass|upcoming)$ ]] || continue
      sfn="${sfn##*/}"                                    # basename, sem fork
      [[ "$sfn" =~ ^[A-Za-z0-9._-]+$ ]] || continue
      printf '%s' "$scode" > "$pkg/sols/$sc/$sfn"
    done < "$_t/sols.nul"
  fi
  # compat: good_sol único (CLI/legado) — adiciona a sols/good
  if (( HAS_GOODSOL )); then
    local gfn="${GOODSOL_FN##*/}"
    [[ "$gfn" =~ ^[A-Za-z0-9._-]+$ ]] || gfn="sol.cpp"
    printf '%s' "$S_GOODSOL" > "$pkg/sols/good/$gfn"
  fi

  # ---- scripts/ (correção especial) — ROUND-TRIP COMPLETO -----------------------------
  # Quando o body traz scripts_files, SUBSTITUI scripts/ inteiro (remoção local vale no push).
  # Item: {path, content_b64, exec} (arquivo; base64 p/ suportar binário — grava DIRETO, sem
  # normalizar newline) ou {path, symlink:alvo} (os drivers interativos usam symlink de diretório
  # scripts/<lang> -> c). Paths validados: sem '..', sem '/' inicial, profundidade <=2, confinado a
  # scripts/. Campo ausente = não toca (cliente antigo não apaga scripts de ninguém).
  if (( HAS_SCRIPTS )); then
    rm -rf "$pkg/scripts"
    jq --raw-output0 '.scripts_files[]? | (.path // ""), (.symlink // ""), (if .exec then "1" else "0" end), (.content_b64 // "")' \
      < "$bodyf" > "$_t/scripts.nul" 2>/dev/null
    local sp='' st='' sx='' sb='' sdir srp sroot
    sroot="$(realpath -m "$pkg/scripts" 2>/dev/null)"
    while IFS= read -r -d '' sp && IFS= read -r -d '' st && IFS= read -r -d '' sx && IFS= read -r -d '' sb; do
      [[ "$sp" =~ ^[A-Za-z0-9._+-]+(/[A-Za-z0-9._+-]+)?$ ]] || continue
      case "$sp" in *..*) continue;; esac
      sdir="${sp%/*}"; [[ "$sdir" == "$sp" ]] && sdir=""
      mkdir -p "$pkg/scripts${sdir:+/$sdir}"
      if [[ -n "$st" ]]; then
        [[ "$st" =~ ^[A-Za-z0-9._/-]+$ ]] || continue
        # o alvo RESOLVIDO tem que ficar dentro de scripts/ (tolera ../c/x de subdir)
        srp="$(realpath -m "$pkg/scripts${sdir:+/$sdir}/$st" 2>/dev/null)"
        [[ "$srp" == "$sroot" || "$srp" == "$sroot"/* ]] || continue
        ln -sfn "$st" "$pkg/scripts/$sp"
      else
        printf '%s' "$sb" | base64 -d > "$pkg/scripts/$sp" 2>/dev/null || : > "$pkg/scripts/$sp"
        [[ "$sx" == 1 ]] && chmod +x "$pkg/scripts/$sp"
      fi
    done < "$_t/scripts.nul"
    # sem itens válidos => scripts/ removido de propósito (round-trip de remoção)
    [[ -d "$pkg/scripts" ]] && find "$pkg/scripts" -type d -empty -delete 2>/dev/null
  fi

  # ---- docs/ IMAGENS (docs_files) — o análogo do scripts_files p/ figuras do enunciado/notas.
  # Quando o body traz docs_files, SUBSTITUI as imagens de docs/ (remoção local vale no push);
  # campo ausente = não toca (cliente antigo não apaga a figura de ninguém). Item: {name,
  # content_b64}. Nome saneado: basename simples, extensão de IMAGEM, sem dotfile; cap ~3MB.
  if (( HAS_DOCSFILES )); then
    find "$pkg/docs" -maxdepth 1 -type f \
      \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.gif' \
         -o -iname '*.svg' -o -iname '*.webp' \) -delete 2>/dev/null
    jq --raw-output0 '.docs_files[]? | (.name // ""), (.content_b64 // "")' \
      < "$bodyf" > "$_t/docsf.nul" 2>/dev/null
    local dn='' db=''
    while IFS= read -r -d '' dn && IFS= read -r -d '' db; do
      dn="${dn##*/}"
      [[ "$dn" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*\.(png|jpg|jpeg|gif|svg|webp|PNG|JPG|JPEG|GIF|SVG|WEBP)$ ]] || continue
      (( ${#db} > 4194304 )) && continue
      mkdir -p "$pkg/docs"
      printf '%s' "$db" | base64 -d > "$pkg/docs/$dn" 2>/dev/null || rm -f "$pkg/docs/$dn"
    done < "$_t/docsf.nul"
  fi

  # tests/score VERBATIM (round-trip byte-fiel da CLI; o campo estruturado `score` do editor web
  # continua valendo — se os dois vierem, score_text vence por rodar depois)
  if (( HAS_SCORETXT )); then
    if [[ -n "$S_SCORETXT" ]]; then printf '%s' "$S_SCORETXT" > "$pkg/tests/score"
    else rm -f "$pkg/tests/score"; fi
  fi

  _pkg_canon_modes "$pkg"          # 644/755 SEMPRE — não o umask 007 do fcgiwrap (ver acima)
  umask "$_um"
  rm -rf "$_t" "$_bodytmp"
  return 0
}
# _read_pairs <pkgdir> <sample|hidden> <outfile> -> escreve NDJSON {name,input,output} (1/linha).
# Via jq --rawfile (lê os testes de ARQUIVO); o chamador junta com --slurpfile. Sem conteúdo de
# teste no argv (passar via --argjson estourava o ARG_MAX -> source vazio -> editor em branco).
_read_pairs(){
  local pkg="$1" which="$2" of="$3" inp nm outp
  : > "$of"
  set +o noglob; shopt -s nullglob
  for inp in "$pkg/tests/input"/*; do
    [[ -f "$inp" ]] || continue; nm="$(basename "$inp")"
    if [[ "$which" == sample ]]; then [[ "$nm" == sample* ]] || continue
    else [[ "$nm" == sample* ]] && continue; fi
    outp="$pkg/tests/output/$nm"; [[ -f "$outp" ]] || outp=/dev/null
    jq -nc --arg nm "$nm" --rawfile i "$inp" --rawfile o "$outp" '{name:$nm, input:$i, output:$o}' >> "$of"
  done
  shopt -u nullglob; set -o noglob
}
# _norm_globs <raw> -> globs saneados, separados por ", " (um grupo pode ter VÁRIOS globs).
# Vírgula -> espaço; read NUNCA faz glob de path (seguro mesmo sem noglob); rejunta com ", "
# (o separador que o juiz, mojtools/score-summary.sh, tolera — o espaço é obrigatório p/ o
# word-split de lá). Entrada vazia/sem token válido -> "".
_norm_globs(){
  local raw="${1//,/ }" out="" tok; local IFS=$' \t\n'; local -a _ng
  raw="$(printf '%s' "$raw" | tr -cd 'A-Za-z0-9._* -')"   # mantém espaço; solta o resto
  read -ra _ng <<<"$raw"
  for tok in "${_ng[@]}"; do out="${out:+$out, }$tok"; done
  printf '%s' "$out"
}
# _read_score <pkgdir> -> {enabled, groups:[{name,weight,glob}]} a partir de tests/score
# (ignora a linha sample* dos exemplos). Ausente/vazio -> {enabled:false, groups:[]}.
# glob preserva a lista multi-glob (", "-separada); name deriva do PRIMEIRO glob.
_read_score(){
  local pkg="$1" sf="$1/tests/score"   # $1 (não $pkg): num mesmo `local`, o RHS não enxerga o LHS anterior
  [[ -f "$sf" ]] || { printf '{"enabled":false,"groups":[]}'; return; }
  local groups='[]' g s glob w name first
  while IFS='-' read -r g s; do
    glob="$(_norm_globs "$g")"
    [[ -z "$glob" || "$glob" == sample* ]] && continue
    w="$(printf '%s' "$s" | tr -cd '0-9')"; w=${w:-0}
    first="${glob%%,*}"; name="${first%\**}"; name="${name%_}"
    groups="$(jq -c --arg n "$name" --argjson w "$w" --arg gl "$glob" '. + [{name:$n,weight:$w,glob:$gl}]' <<<"$groups")"
  done < "$sf"
  jq -cn --argjson g "$groups" '{enabled:true, groups:$g}'
}
# read_problem_source <pkgdir> -> JSON editável do pacote (enunciado/autor/tags/conf/exemplos/
# testes/soluções good + public/collections/title do .moj-meta.json). scripts/ sai em DOIS campos:
# `scripts` (só caminhos, p/ a árvore do editor web) e `scripts_files` (CONTEÚDO em base64 +
# symlinks — round-trip do moj push/clone via apply_problem_fields). tests/score sai cru em
# `score_text` (além do estruturado `score` do editor web).
read_problem_source(){
  local pkg="$1" enunf="" fmt="md" ef
  for ef in docs/enunciado.md enunciado.md docs/enunciado.org docs/enunciado.tex; do
    [[ -f "$pkg/$ef" ]] && { enunf="$pkg/$ef"; [[ "$ef" == *.org ]] && fmt=org; [[ "$ef" == *.tex ]] && fmt=tex; break; }
  done
  local te ta tc ted; te="$(mktemp)"; ta="$(mktemp)"; tc="$(mktemp)"; ted="$(mktemp)"
  [[ -n "$enunf" ]] && cat "$enunf" > "$te"
  [[ -f "$pkg/author" ]] && cat "$pkg/author" > "$ta"
  [[ -f "$pkg/conf" ]] && cat "$pkg/conf" > "$tc"
  [[ -f "$pkg/docs/solucao.md" ]] && cat "$pkg/docs/solucao.md" > "$ted"   # editorial (só setters)
  local tags='[]'; [[ -f "$pkg/tags" ]] && tags="$(jq -R . "$pkg/tags" 2>/dev/null | jq -sc . 2>/dev/null)"; [[ -n "$tags" ]] || tags='[]'
  local meta='{}'; [[ -f "$pkg/.moj-meta.json" ]] && meta="$(cat "$pkg/.moj-meta.json" 2>/dev/null)"; [[ -n "$meta" ]] || meta='{}'
  local score; score="$(_read_score "$pkg")"
  # scripts/ (correção especial: compare/compile por linguagem) -> caminhos relativos p/ a
  # árvore do editor web (campo `scripts`); o CONTEÚDO vai em `scripts_files` (round-trip)
  local tscr; tscr="$(mktemp)"
  [[ -d "$pkg/scripts" ]] && ( cd "$pkg/scripts" && find . -type f -printf '%P\n' 2>/dev/null ) | LC_ALL=C sort > "$tscr"
  # tests/score cru (round-trip byte-fiel do moj push/clone)
  local tsct; tsct="$(mktemp)"
  [[ -f "$pkg/tests/score" ]] && cat "$pkg/tests/score" > "$tsct"
  # exemplos/testes/soluções -> NDJSON em arquivos; entram no jq por --slurpfile (jq lê o arquivo).
  # ANTES: --argjson tss "$tss" estourava o ARG_MAX em problema com muitos testes -> source VAZIO -> editor em branco.
  local d; d="$(mktemp -d)"
  _read_pairs "$pkg" sample "$d/exs"; _read_pairs "$pkg" hidden "$d/tss"
  _read_sols "$pkg" good "$d/sg"; _read_sols "$pkg" slow "$d/ss"; _read_sols "$pkg" wrong "$d/sw"
  _read_sols "$pkg" pass "$d/sp"; _read_sols "$pkg" upcoming "$d/su"
  _read_scripts "$pkg" "$d/scf"
  # explicação por exemplo -> examples[].explanation. Formato de AUTORIA: docs/notes/<sample>.md
  # (1 markdown por exemplo, pareado pelo NOME — o autor nunca edita JSON); legado:
  # sample-notes.json por ÍNDICE (lido via arquivo — nota com imagem data:URI passa de 128KiB
  # e por --argjson estourava o teto por-argumento: as explanations sumiam MUDAS do editor).
  if [[ -d "$pkg/docs/notes" ]]; then
    local _ln _nm; : > "$d/exs2"
    while IFS= read -r _ln; do
      _nm="$(jq -r '.name' <<<"$_ln")"
      if [[ "$_nm" =~ ^[A-Za-z0-9._-]+$ && -f "$pkg/docs/notes/$_nm.md" ]]; then
        jq -c --rawfile n "$pkg/docs/notes/$_nm.md" '. + {explanation:($n|rtrimstr("\n"))}' <<<"$_ln"
      else jq -c '. + {explanation:""}' <<<"$_ln"; fi
    done < "$d/exs" >> "$d/exs2"
    mv -f "$d/exs2" "$d/exs"
  else
    printf '[]' > "$d/notes.json"
    [[ -f "$pkg/docs/sample-notes.json" ]] && cat "$pkg/docs/sample-notes.json" > "$d/notes.json" 2>/dev/null
    jq -e . >/dev/null 2>&1 < "$d/notes.json" || printf '[]' > "$d/notes.json"
    jq -cn --slurpfile all "$d/exs" --slurpfile nn "$d/notes.json" \
       '($nn[0] // []) as $n | $all | to_entries[] | .value + {explanation: ($n[.key] // "")}' \
       > "$d/exs2" 2>/dev/null && mv -f "$d/exs2" "$d/exs"
  fi
  # imagens de docs/ (docs_files) — round-trip do clone/push
  : > "$d/docsf"
  ( set +o noglob; shopt -s nullglob
    for _f in "$pkg/docs"/*; do
      [[ -f "$_f" ]] || continue
      case "$_f" in *.png|*.jpg|*.jpeg|*.gif|*.svg|*.webp|*.PNG|*.JPG|*.JPEG|*.GIF|*.SVG|*.WEBP) ;; *) continue;; esac
      base64 -w0 "$_f" > "$d/.b64"
      jq -nc --arg n "${_f##*/}" --rawfile b "$d/.b64" '{name:$n, content_b64:$b}'
    done ) >> "$d/docsf"
  jq -n --rawfile enun "$te" --rawfile author "$ta" --rawfile conf "$tc" --rawfile editorial "$ted" \
        --rawfile scr "$tscr" --rawfile scoretxt "$tsct" \
        --argjson tags "$tags" --argjson meta "$meta" --argjson score "$score" --arg fmt "$fmt" \
        --slurpfile exs "$d/exs" --slurpfile tss "$d/tss" --slurpfile scf "$d/scf" \
        --slurpfile dfl "$d/docsf" \
        --slurpfile sg "$d/sg" --slurpfile ss "$d/ss" --slurpfile sw "$d/sw" --slurpfile sp "$d/sp" --slurpfile su "$d/su" '
    { format:$fmt, enunciado_md:$enun, author:($author|rtrimstr("\n")), conf_text:$conf,
      tags:$tags, public:($meta.public // false), collections:($meta.collections // []),
      languages:($meta.languages // []),
      title:($meta.display_title // ""), examples:$exs, tests:$tss, score:$score,
      score_text:$scoretxt,
      scripts:($scr | split("\n") | map(select(. != ""))),
      scripts_files:$scf, docs_files:$dfl,
      editorial_md:$editorial, sols:{good:$sg, slow:$ss, wrong:$sw, pass:$sp, upcoming:$su} }'
  rm -rf "$d"; rm -f "$te" "$ta" "$tc" "$ted" "$tscr" "$tsct"
}
# _read_scripts <pkgdir> <outfile> -> NDJSON de scripts/ (round-trip): arquivo =
# {path, content_b64, exec}; symlink (arquivo OU diretório — drivers interativos) =
# {path, symlink:alvo}. Conteúdo em base64 via arquivo (--rawfile; binário legado suportado).
_read_scripts(){
  local pkg="$1" of="$2" f rel x tb
  : > "$of"
  [[ -d "$pkg/scripts" ]] || return 0
  tb="$(mktemp)"
  while IFS= read -r f; do
    rel="${f#"$pkg"/scripts/}"
    if [[ -L "$f" ]]; then
      jq -nc --arg p "$rel" --arg t "$(readlink "$f")" '{path:$p, symlink:$t}' >> "$of"
    elif [[ -f "$f" ]]; then
      base64 -w0 < "$f" > "$tb" 2>/dev/null || continue
      x=false; [[ -x "$f" ]] && x=true
      jq -nc --arg p "$rel" --argjson x "$x" --rawfile c "$tb" '{path:$p, content_b64:$c, exec:$x}' >> "$of"
    fi
  done < <(find "$pkg/scripts" \( -type f -o -type l \) 2>/dev/null | LC_ALL=C sort)
  rm -f "$tb"
}
# _read_sols <pkgdir> <cat> <outfile> -> escreve NDJSON {filename,code} (1/linha) de sols/<cat>/*
_read_sols(){
  local pkg="$1" cat="$2" of="$3" f
  : > "$of"
  set +o noglob; shopt -s nullglob
  for f in "$pkg/sols/$cat"/*; do [[ -f "$f" ]] || continue
    jq -nc --arg fn "$(basename "$f")" --rawfile code "$f" '{filename:$fn, code:$code}' >> "$of"
  done
  shopt -u nullglob; set -o noglob
}

# _derive_title <pkgdir> -> título do enunciado (%/#+title/\section) ou, em último caso, o nome do
# problema (slug). NUNCA vazio. Mesmo idioma de extração do mojtools/gen-problem-json.sh.
_derive_title(){
  local pkg="$1" t=""
  if [[ -f "$pkg/docs/enunciado.md" ]]; then
    t="$(grep -m1 '^%' "$pkg/docs/enunciado.md" 2>/dev/null | sed 's/^%[[:space:]]*//')"
  elif [[ -f "$pkg/docs/enunciado.org" ]]; then
    t="$(grep -m1 -i '^#+title:' "$pkg/docs/enunciado.org" 2>/dev/null | sed 's/^#+[Tt][Ii][Tt][Ll][Ee]:[[:space:]]*//')"
  elif [[ -f "$pkg/docs/enunciado.tex" ]]; then
    t="$(grep -m1 -E '\\(section|title)\{' "$pkg/docs/enunciado.tex" 2>/dev/null | sed -E 's/.*\\(section|title)\{([^}]*)\}.*/\2/')"
  fi
  [[ -n "$t" ]] || t="$(basename "$pkg")"
  printf '%s' "$t"
}

# write_meta <pkgdir> <owner> <repo> [public:true|false|""] [collections-json|""] [display_title] [languages-json|""]
# BLINDAGEM: display_title nunca fica ausente — se não veio título E o meta ainda não tem um,
# deriva do enunciado/slug (_derive_title). Assim o editor nunca vem em branco e as 3 telas (editor,
# treino, gestão) ficam consistentes. Meta que já tem título não muda (o merge $cur+{} preserva).
# languages: restrição de linguagem de submissão POR-PROBLEMA (ids canônicos minúsculos; []/ausente
# = todas). "" (ou omitido) = não mexe (preserva o que já houver); [] = limpa (volta a irrestrito).
# Normalização espelha a whitelist de contest (contest/admin/settings.sh): sem lista de ids
# hardcoded (não duplicar a lista JS em bash — forward-compat), só saneamento de forma.
write_meta(){
  local pkg="$1" owner="$2" repo="$3" pub="${4:-}" colls="${5:-}" title="${6:-}" langs="${7:-}" cur='{}'
  [[ -f "$pkg/.moj-meta.json" ]] && cur="$(cat "$pkg/.moj-meta.json" 2>/dev/null)"; [[ -n "$cur" ]] || cur='{}'
  if [[ -z "$title" && -z "$(jq -r '.display_title // empty' <<<"$cur" 2>/dev/null)" ]]; then
    title="$(_derive_title "$pkg")"
  fi
  jq -n --argjson cur "$cur" --arg o "$owner" --arg r "$repo" --arg pub "$pub" \
        --argjson colls "${colls:-null}" --arg title "$title" --argjson langs "${langs:-null}" \
        --argjson now "$EPOCHSECONDS" '
    $cur + {owner:$o}
    + (if $pub=="" then {} elif $pub=="true" then {public:true} else {public:false} end)
    + (if $colls==null then {} else {collections:$colls} end)
    + (if $langs==null then {} else
        {languages: ($langs | map(ascii_downcase
              | (if .=="py3" or .=="py2" then "py" else . end)
              | select(test("^[a-z0-9_+.-]+$"))) | unique)} end)
    + (if $title=="" then {} else {display_title:$title} end)
    # carimba a 1ª publicação (permanece ao despublicar); alimenta o heatmap "entrada de públicos"
    + (if $pub=="true" and (($cur.public_at // null)==null) then {public_at:$now} else {} end)
  ' > "$pkg/.moj-meta.json"
  chmod 644 "$pkg/.moj-meta.json" 2>/dev/null   # modo canônico (o fcgiwrap roda umask 007 -> 660)
}
