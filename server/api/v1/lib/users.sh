# lib/users.sh — store de contas POR-USUÁRIO (contests/<c>/users/<login>/).
#
# Fonte da verdade da conta = users/<login>/account.json — auth (verify_password),
# placar (sc_users) e perfis leem DIRETO daqui; não existe mais passwd derivado. As
# submissões do usuário ficam em users/<login>/history (login IMPLÍCITO = nome do dir;
# rename de conta é só um `mv` do diretório). Métricas cacheadas em metrics.json.
#
# Convenções do MOJ: bash + jq, EPOCH, escrita atômica tmp+mv, JSON nunca é *sourced*
# (só lido por jq → sem printf %q aqui). common.sh liga `set -o noglob`: qualquer glob
# roda em subshell com `set +o noglob; shopt -s nullglob`.
#
# Formato da linha do history por-usuário (login removido; verdict pode conter ':'):
#   <tempo>:<probid>:<lang>:<verdict>:<sub_epoch>:<subid>
# Campos seguros: 1=tempo,2=probid,3=lang ; 4..(NF-2)=verdict ; NF-1=sub_epoch ; NF=subid.

# metrics_recompute precisa do vocabulário de penalidade + VERDICT_CANON_JQ; o router já
# sourceia verdict.sh, mas build.sh/judged.sh/store-migrate.sh sourceiam só esta lib.
source "${BASH_SOURCE[0]%/*}/verdict.sh"

# --- paths ----------------------------------------------------------------
users_dir(){    printf '%s/%s/users'                 "$CONTESTSDIR" "$1"; }        # <c>
user_dir(){     printf '%s/%s/users/%s'              "$CONTESTSDIR" "$1" "$2"; }   # <c> <login>
account_file(){ printf '%s/%s/users/%s/account.json' "$CONTESTSDIR" "$1" "$2"; }
user_hist_file(){ printf '%s/%s/users/%s/history'    "$CONTESTSDIR" "$1" "$2"; }
metrics_file(){ printf '%s/%s/users/%s/metrics.json' "$CONTESTSDIR" "$1" "$2"; }

user_exists(){ [[ -f "$(account_file "$1" "$2")" ]]; }

# user_resolve_name <c> <nome-de-arquivo|login> -> login existente (case-insensitive), rc!=0 se
# nenhum casa. É o que faz o ENVIO EM LOTE funcionar: o operador arrasta `Fulano.JPG`/`fulano.mp3`
# e o arquivo acha o dono pelo nome. Sem account.json local (participante de USERS_FROM) o dir
# ainda conta — os assets do time são locais do contest.
# ⚠ O nome INTEIRO é tentado ANTES do sem-extensão: login com ponto é comum aqui (`ufba.time1`,
# e todas as contas de papel — `fulano.animeitor`), e cortar no ponto faria `telao.animeitor`
# virar `telao` (= "nenhum time casa", escondendo o 422 de conta de papel).
user_resolve_name(){
  local c="$1" raw cand want d login
  raw="$(basename "$2")"
  for cand in "$raw" "${raw%.*}"; do
    want="${cand,,}"
    [[ -n "$want" ]] || continue
    user_exists "$c" "$want" && { printf '%s' "$want"; return 0; }
    while IFS= read -r d; do
      login="${d##*/}"
      [[ "${login,,}" == "$want" ]] && { printf '%s' "$login"; return 0; }
    done < <(find "$CONTESTSDIR/$c/users" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
    [[ "${raw%.*}" == "$raw" ]] && break        # sem extensão: não varrer de novo
  done
  return 1
}

# _atomic_write <destfile>  (conteúdo no stdin) — grava atômico (tmp no mesmo dir + mv).
_atomic_write(){
  local f="$1" tmp; tmp="$(mktemp "$f.XXXXXX")" || return 1
  cat > "$tmp" && mv -f "$tmp" "$f"
}

# --- account.json ---------------------------------------------------------
# account_field <c> <login> <jq-path>  -> valor (vazio se ausente). Ex.: account_field t u '.password'
account_field(){ jq -r "$3 // empty" "$(account_file "$1" "$2")" 2>/dev/null; }

# account_merge <c> <login> <jq-filter> [jq-args...] — merge atômico no account.json.
account_merge(){
  local c="$1" u="$2" filter="$3"; shift 3
  # escrita de CREDENCIAL em conta de papel do treino: ver treino_role_write_ok (lib/auth.sh) — rc 77, nada gravado
  if [[ "$filter" == *.password* ]] && declare -F treino_role_write_ok >/dev/null; then
    treino_role_write_ok "$c" "$u" || return 77
  fi
  local f; f="$(account_file "$c" "$u")"
  [[ -f "$f" ]] || return 1
  local tmp; tmp="$(mktemp "$f.XXXXXX")" || return 1
  jq -c "$@" "$filter" "$f" > "$tmp" && mv -f "$tmp" "$f"
}

# team_fields_json <user-json> — extrai do JSON de entrada os campos de TIME
# (univ_short, univ_full, country->flag, region) e ecoa o objeto `.team` só com os
# NÃO-vazios ('{}' se nada veio). Saneia tab/newline (quebrariam os TSVs derivados: sc_users/badges);
# o ':' das ESCOLAS (univ_short/univ_full, exibição) vira '∶' como no nome (NAME_CLEAN_JQ, lib/common.sh),
# o de bandeira/sede (chaves) vira espaço. O NOME do time é o próprio `.fullname` (campo ÚNICO — usuário de
# contest É o time); `.team.name` é só legado da migração (leitores fazem
# `.team.name // .fullname`). Writers: users-bulk, user-add, contest-create users[] e
# admin/teams — a LEITURA já existia (placar, badges, print).
# (quem sourceia este arquivo sem o common.sh — scripts de score — ainda tem o filtro do nome)
[[ -n "${NAME_CLEAN_JQ:-}" ]] || NAME_CLEAN_JQ='gsub(":"; "\u2236") | gsub("[\t\n\r]"; " ") | gsub("^ +| +$"; "")'
team_fields_json() {
  jq -c '{univ_short:(.univ_short // ""), univ_full:(.univ_full // ""),
          flag:(.country // ""), region:(.region // "")}
         | with_entries(.key as $k | .value |= (tostring
             | if ($k == "univ_short" or $k == "univ_full") then '"$NAME_CLEAN_JQ"'
               else (gsub("[:\t\n\r]"; " ") | gsub("^ +| +$"; "")) end))
         | with_entries(select(.value != ""))' <<<"${1:-null}" 2>/dev/null || echo '{}'
}

# account_team_merge <c> <login> <team-json> — mescla campos no `.team` do account.json
# (só os presentes no objeto; não apaga os demais). '{}' = no-op (rc 0).
account_team_merge(){
  local c="$1" u="$2" teamj="$3"
  [[ -n "$teamj" && "$teamj" != '{}' ]] || return 0
  account_merge "$c" "$u" '.team = ((.team // {}) + $tm) | .updated_at=$t' \
    --argjson tm "$teamj" --argjson t "$EPOCHSECONDS"
}

# shared_overlay_ensure <c> <login> [new] — garante um account.json LOCAL p/ um participante COMPARTILHADO
# (contest com USERS_FROM, onde o participante tem dir local SEM account.json e a identidade vem do treino).
# O overlay NÃO tem senha: o login continua pela conta do treino (verify_password cai p/ a fonte quando a
# senha local é vazia) — ele existe p/ o admin poder AGIR na conta: desabilitar (grava `!…`, que é
# autoritativo), desclassificar, remover (tombstone), gravar campos de time. Só `fullname` vem da fonte.
# Sem `new`, exige o dir local (a pessoa JÁ entrou/submeteu/se inscreveu — criar overlay de quem nunca
# entrou poria uma linha nova no placar); com `new`=1 aceita quem só existe na fonte (o tombstone da
# remoção, que é desclassificado e não aparece). rc 0 = existe/criado; 1 = não é contest compartilhado ou
# o login não existe nem no contest nem na fonte. History nunca é tocado.
shared_overlay_ensure(){
  local c="$1" u="$2" new="${3:-0}" d f src name
  valid_id "$u" || return 1
  d="$(user_dir "$c" "$u")"; f="$d/account.json"
  [[ -f "$f" ]] && return 0
  declare -F _users_source >/dev/null || return 1
  src="$(_users_source "$c")"; [[ "$src" != "$c" ]] || return 1
  [[ -f "$CONTESTSDIR/$src/users/$u/account.json" ]] || return 1
  [[ -d "$d" || "$new" == 1 ]] || return 1
  name="$(jq -r '.fullname // ""' "$CONTESTSDIR/$src/users/$u/account.json" 2>/dev/null)"; [[ -n "$name" ]] || name="$u"
  mkdir -p "$d/submissions" "$d/mojlog" "$d/results" || return 1
  jq -cn --arg l "$u" --arg n "$name" --argjson t "$EPOCHSECONDS" \
    '{login:$l, fullname:$n, status:"active", created_at:$t, updated_at:$t, shared_overlay:true}' > "$f.tmp" \
    && mv -f "$f.tmp" "$f" || { rm -f "$f.tmp"; return 1; }
}

# --- criação / senha ------------------------------------------------------
# user_create <c> <login> <fullname> <password> [email] -> 0 ok | 2 já existe (conta, ou org do treino com o nome) |
#   3 login inválido | 77 papel do treino
# Sufixo de papel: o auto-cadastro o recusa no handler (signup); aqui só a regra do TREINO — conta de papel do treino,
# numa requisição autenticada, só pelo super-admin ou pela própria conta (treino_role_write_ok, rc 77).
# login_blocked_by_org <login> [<quem>] — 0 se já existe uma org do treino com esse nome que não é de <quem> (admin
# dela). O nome de um login é o da org pessoal dele (ensure_implicit_org, lib/orgs.sh, aceita a org que já existe),
# então ele fica reservado: cadastro, troca de handle, promoção e criação de conta pelo admin respondem "em uso".
# <quem> = o próprio login nas portas do admin e no user_create: a org pessoal de uma conta removida não impede
# recriá-la; o cadastro (signup, tg_unique_login) não passa <quem> e nunca herda o nome; o rename passa o login atual.
login_blocked_by_org(){
  local reg="$CONTESTSDIR/treino/var/orgs.json"; [[ -s "$reg" ]] || return 1
  jq -e --arg n "$1" --arg w "${2:-}" 'has($n) and ($w == "" or (((.[$n].admins // []) | index($w)) == null))' \
    "$reg" >/dev/null 2>&1
}
user_create(){
  local c="$1" u="$2" name="$3" pw="$4" email="${5:-}"
  valid_login "$u" || return 3          # rede de segurança: login novo oculto/inválido (lib/common.sh valid_login)
  { declare -F treino_role_write_ok >/dev/null && ! treino_role_write_ok "$c" "$u"; } && return 77   # conta de papel no treino
  [[ "$c" == treino ]] && login_blocked_by_org "$u" "$u" && return 2   # nome de org de outra conta = "já existe"
  local d; d="$(user_dir "$c" "$u")"
  [[ -f "$d/account.json" ]] && return 2
  mkdir -p "$d/submissions" "$d/mojlog" "$d/results" || return 1
  jq -cn --arg l "$u" --arg p "$pw" --arg n "$name" --arg e "$email" --argjson t "$EPOCHSECONDS" \
     '{login:$l,password:$p,fullname:$n,email:$e,created_at:$t,updated_at:$t,status:"active",uname_changes:[]}' \
     > "$d/account.json" || return 1
  # history que JÁ existe nunca é zerado: dir de participante compartilhado (sem account.json) que já
  # submeteu, ou resto de conta removida — criar a conta por cima zerava o histórico dele (28/09/2026)
  [[ -f "$d/history" ]] || : > "$d/history"
}

# user_genpass — senha legível: palavra do dicionário + 4 dígitos (igual cc_genpass).
user_genpass(){
  local wl="${PASSWORD_WORDLIST:-}" w=""
  [[ -f "$wl" ]] && w="$(shuf -n1 "$wl" 2>/dev/null | tr -cd 'a-z0-9')"
  [[ -n "$w" ]] || w="$(head -c8 /dev/urandom | base64 | tr -dc 'a-z0-9' | head -c6)"
  printf '%s%04d' "$w" "$(( RANDOM % 10000 ))"
}

user_password(){ account_field "$1" "$2" '.password'; }
user_fullname_of(){ account_field "$1" "$2" '.fullname'; }
user_status(){ account_field "$1" "$2" '.status'; }

# user_set_password <c> <login> <pw>
user_set_password(){
  account_merge "$1" "$2" '.password=$p|.updated_at=$t' --arg p "$3" --argjson t "$EPOCHSECONDS"
}
# user_set_status <c> <login> <active|locked>  (usado por lock/disable; senha preservada)
user_set_status(){
  account_merge "$1" "$2" '.status=$s|.updated_at=$t' --arg s "$3" --argjson t "$EPOCHSECONDS"
}

# --- history por-usuário --------------------------------------------------
# _score_dirty <c> — marca o placar/estatística como desatualizados (var/.score-dirty é a
# fonte de staleness do regen_locked; substitui a comparação com o extinto controle/history).
_score_dirty(){
  mkdir -p "$CONTESTSDIR/$1/var" 2>/dev/null
  touch "$CONTESTSDIR/$1/var/.score-dirty" 2>/dev/null || true
}

# user_history_append <c> <login> <line>   (provisória e novas)
user_history_append(){
  printf '%s\n' "$3" >> "$(user_hist_file "$1" "$2")"
  _score_dirty "$1"
}

# user_history_replace <c> <login> <subid> <line> — troca a linha cujo ÚLTIMO campo é
# <subid> (reescrita atômica). Se não existir, acrescenta. Espelha update_history do daemon.
user_history_replace(){
  local c="$1" u="$2" id="$3" f; f="$(user_hist_file "$c" "$u")"
  [[ -f "$f" ]] || : > "$f"
  local tmp; tmp="$(mktemp "$f.XXXXXX")" || return 1
  _RL="$4" awk -F: -v id="$id" '
    {if ($NF==id){print ENVIRON["_RL"]; seen=1} else print}
    END{if(!seen) print ENVIRON["_RL"]}' "$f" > "$tmp" && mv -f "$tmp" "$f"
  _score_dirty "$c"
}

# --- métricas -------------------------------------------------------------
# metrics_recompute <c> <login> — reconstrói metrics.json (shape v2) do history local.
# O(history_u); jq lê o arquivo direto (sem ARG_MAX). Além dos agregados, grava por
# problema TUDO que os geradores de placar (score/updatescore-*.sh) precisam — a
# semântica espelha o antigo score/dstate.sh e o parse de updatescore-obi/heuristic:
#   counted    = tentativas que CONTAM até (e incluindo) o 1º AC; todas, se não resolvido.
#                Quais verdicts contam é configurável pelo conf `PENALTY_VERDICTS` (códigos
#                de PENALTY_CODES_ALL; ausente = PENALTY_CODES_DEFAULT, i.e. Compilation
#                Error fora). Provisórias/Judge Error/No_Servers NUNCA contam. Strings
#                legadas fora do vocabulário canônico continuam contando (como sempre).
#   pending    = existe linha provisória (Not Answered Yet/On queue/Running).
#   best_score = maior NNp dos veredictos (Accepted sem NNp ⇒ 100; tentativa
#                não-provisória sem NNp ⇒ 0; nunca tentou ⇒ null)  [obi].
#   heur       = melhor par (Score N, desempate Score Ajustado F) ou null  [heuristic].
#   frozen     = a MESMA visão restrita a sub_epoch < FREEZE_TIME (só quando o conf tem
#                FREEZE_TIME>0): AC pós-freeze fica escondido (pending, hidden++);
#                tentativas pós-freeze CONTAM no counted de problema não resolvido.
# FREEZE_TIME e PENALTY_VERDICTS são as ÚNICAS entradas do conf que as métricas usam (o conf roda
# command substitution — nunca source dentro da lib). CONTEST_START não entra: o gerador converte
# epoch→minutos via sc_load. Quem lê as duas é `_mrc_conf`, UM leitor p/ as três portas abaixo.
#
# UM programa jq (METRICS_JQ, `def metrics_of` sobre as linhas do history), DUAS portas
# (15/10/2026, ensaio de escrita de 800 times): `metrics_recompute` — UMA conta, a do daemon a cada
# veredicto — e `metrics_recompute_all` — o contest INTEIRO num jq só, o recompute em massa do
# build.sh. Antes o em massa era um jq POR CONTA: 821 contas = 6,5 s (~11 s em produção sob carga),
# 95% do placar a frio, e foi isso que segurou o pool no início do ensaio. Em lote: 0,24 s (821) e
# 2,0 s (2.463 contas, 68 mil envios). A classificação de cada linha (pendente/AC/conta/pontos) é
# função SÓ do veredicto, então `metrics_of` classifica cada veredicto DISTINTO uma vez (o `test()`
# do jq recompila a regex a cada chamada — era o custo que sobrava no lote).
# ⚠ A saída das duas portas tem de ser IDÊNTICA (menos `computed_at`): `smoke-metrics-batch.sh`
# compara conta a conta. Mexeu no programa, rode-o com o jq 1.7 (o programa mora em variável, fora do
# `jq-portability.sh`).
_mrc_conf(){   # <c> -> _MRC_FZ (FREEZE_TIME) e _MRC_DENY (códigos canônicos fora da penalidade, por TAB)
  local c="$1" _line _t pv="__unset" code
  # LEITURA DO CONF SEM PROCESSO NENHUM (dieta 2026-08-30): isto rodava sed|tail|tr + grep + printf|tr
  # — ~6 execs POR CHAMADA produzindo SEMPRE o mesmo valor p/ todos os usuários do contest (no recompute
  # em massa da Maratona: ~30k dos ~35k processos). Leitor builtin no molde do conf_value (que não
  # existe aqui — o judged não sourceia common.sh) + memo do `deny` por (contest, pv) — válido no
  # processo, e o daemon é persistente. Semântica: última linha FREEZE_TIME vence; linha
  # PENALTY_VERDICTS presente ≠ default; %q vira códigos por limpeza de charset.
  _MRC_FZ=""
  while IFS= read -r _line || [[ -n "$_line" ]]; do
    _t="${_line#"${_line%%[![:space:]]*}"}"        # ltrim (o sed aceitava espaço à esquerda)
    case "$_t" in
      FREEZE_TIME=*)       _MRC_FZ="${_t#FREEZE_TIME=}"; _MRC_FZ="${_MRC_FZ//[!0-9]/}" ;;
    esac
    case "$_line" in
      PENALTY_VERDICTS=*)  pv="${_line#PENALTY_VERDICTS=}"; pv="${pv//[!a-z ]/}" ;;
    esac
  done < "$CONTESTSDIR/$c/conf" 2>/dev/null
  _MRC_FZ="${_MRC_FZ:-0}"
  [[ "$pv" == "__unset" ]] && pv="$PENALTY_CODES_DEFAULT"
  if [[ -n "${_MRC_DENY_KEY:-}" && "$_MRC_DENY_KEY" == "$c|$pv" ]]; then
    _MRC_DENY="$_MRC_DENY_V"
  else
    _MRC_DENY=""
    for code in $PENALTY_CODES_ALL; do
      [[ " $pv " == *" $code "* ]] || _MRC_DENY+="${_MRC_DENY:+$'\t'}$(penalty_code_canon "$code")"
    done
    _MRC_DENY_KEY="$c|$pv"; _MRC_DENY_V="$_MRC_DENY"
  fi
}

# metrics_conf_sig <c> — a ASSINATURA do que as métricas usam do conf (freeze + penalidade EFETIVA).
# O build.sh a guarda no `.metrics-stamp` e só refaz o contest inteiro quando ela muda: editar o
# nome, o horário de login ou as linguagens tocava o conf e custava o recompute em massa à toa.
# `PENALTY_VERDICTS` explícito igual ao padrão dá a MESMA assinatura (é o deny efetivo que entra).
metrics_conf_sig(){ _mrc_conf "$1"; printf 'v3|%s|%s' "$_MRC_FZ" "${_MRC_DENY//$'\t'/,}"; }

METRICS_JQ="$VERDICT_CANON_JQ"'
    ($denyraw|split("\t")|map(select(length>0))) as $deny |
    def vw($g; $fac; $real):
      ($g|map(select(.counts))) as $cnt
      | {solved: ($fac != null),
         first_ac_epoch: $fac,
         counted: (if $fac != null then ($cnt|map(select(.sub_epoch <= $fac))|length)
                   else ($cnt|length) end),
         # submissões REAIS até o 1º AC inclusive (todo veredicto, CE também): é a base do
         # DIRT (lib/difficulty.sh, issue #30) — igual à conta do stats-gen do contest
         tries_to_ac: (if $fac != null then ($g|map(select((.prov|not) and .sub_epoch <= $fac))|length) else null end),
         best_score: (if ($real|length)==0 then null else ($real|map(.pts)|max) end),
         heur: (($real|map(select(.hs != null))) as $h
                | if ($h|length)==0 then null
                  else ($h|max_by([.hs,.ha])|{score:.hs, adjusted:.ha}) end)};
    # metrics_of: [linhas do history] -> o metrics.json
    def metrics_of:
      map(select(length>0)) | map(split(":"))
      | map({probid:.[1], lang:.[2], subid:.[-1],
             sub_epoch:((.[-2]|tonumber?) // 0),
             verdict:((.[3:-2]|join(":")) | split("¦")[0])})   # classe: o ¦texto do time não pontua
      # a classificação é função SÓ do veredicto: uma vez por veredicto DISTINTO
      | (map(.verdict) | unique | map({verdict: .}
          | . + {prov: (.verdict|test("Not Answered Yet|On queue|Running"; "i")),
                 ac:   (.verdict|startswith("Accepted") and (test(" \\(Ignored\\)$")|not))}
          | . + {counts: ((.prov
                  or (.verdict|test(" \\(Ignored\\)$"))
                  or (.verdict|startswith("Judge Error"))
                  or (.verdict|test("^No_?Servers"))
                  or ((($deny|index("Compilation Error")) != null)
                      and (.verdict|startswith("Compilation Error")))
                  or ((.verdict | sub(" \\(Ignored\\)$"; "") | vcanon) as $cv
                      | ($deny|index($cv)) != null)) | not),
                 pts: (if .prov then null
                       elif (.verdict|test("[0-9]+p")) then
                         (.verdict|capture("(?<n>[0-9]+)p").n|tonumber)
                       elif .ac then 100 else 0 end),
                 hs:  (if .prov then null
                       elif (.verdict|test("Score[ \t]+-?[0-9]+")) then
                         (.verdict|capture("Score[ \t]+(?<n>-?[0-9]+)").n|tonumber)
                       elif .ac then 0 else null end),
                 ha:  (if (.prov|not) and (.verdict|test("Score Ajustado[ \t]+-?[0-9]+(\\.[0-9]+)?")) then
                         (.verdict|capture("Score Ajustado[ \t]+(?<n>-?[0-9]+(\\.[0-9]+)?)").n|tonumber)
                       else 0 end)}
          | {key: .verdict, value: del(.verdict)}) | from_entries) as $VC
      | map(. + $VC[.verdict])
      | { version: 3,
          computed_at: $now,
          freeze_time: $freeze,
          submissions: length,
          accepted: (map(select(.ac))|length),
          solved:   (map(select(.ac)|.probid)|unique),
          attempted:(map(.probid)|unique),
          by_lang:    (reduce .[] as $s ({}; .[$s.lang] = ((.[$s.lang]//0)+1))),
          by_verdict: (reduce .[] as $s ({}; (($s.verdict|split(",")[0])) as $k | .[$k]=((.[$k]//0)+1))),
          by_problem: (group_by(.probid) | map(
              . as $g
              | ($g|map(select(.ac))|map(.sub_epoch)|min) as $fac
              | {key: $g[0].probid,
                 value: (vw($g; $fac; $g|map(select(.prov|not)))
                   + {attempts: ($g|length),
                      counted_all: ($g|map(select(.counts))|length),
                      pending: (($g|map(select(.prov))|length) > 0),
                      # pending_min_epoch: a run NÃO JULGADA mais antiga deste problema. O booleano
                      # `pending` não responde "há pendente MAIS ANTIGO que este AC?", e é essa a
                      # pergunta que decide first-to-solve com CERTEZA — no placar (a estrela só
                      # pinta quando nenhuma run mais velha pode roubá-la) e no balão da sede.
                      pending_min_epoch: (($g|map(select(.prov))|map(.sub_epoch)|min) // null),
                      last_sub_epoch: (($g|map(.sub_epoch)|max) // 0)}
                   + (if $freeze > 0 then
                        {frozen: (
                           ($g|map(select(.ac and .sub_epoch < $freeze))|map(.sub_epoch)|min) as $ffac
                           | ($g|map(select(.sub_epoch >= $freeze))|length) as $hidden
                           | vw($g; $ffac; $g|map(select((.prov|not) and .sub_epoch < $freeze)))
                             + {pending: ((($g|map(select(.prov))|length) > 0) or ($hidden > 0)),
                                # ⚠ SÓ o pendente PRÉ-freeze: a estrela da visão congelada é sobre
                                # ACs pré-freeze, e run pós-freeze não pode roubá-la. Não confundir
                                # com o `pending` acima, que soma os `hidden` de propósito (é ele
                                # que faz a célula parecer "em julgamento" durante o congelamento).
                                pending_min_epoch:
                                  (($g|map(select(.prov and .sub_epoch < $freeze))|map(.sub_epoch)|min) // null),
                                hidden: $hidden})}
                      else {} end))}
            ) | from_entries),
          last_submission_at: ((map(.sub_epoch)|max) // 0) };'

metrics_recompute(){
  local c="$1" u="$2" hf mf _mt
  hf="$(user_hist_file "$c" "$u")"; mf="$(metrics_file "$c" "$u")"
  _mt="$mf.tmp.${BASHPID}"   # expandido AQUI (no worker), nunca no alvo do redirect
  [[ -f "$hf" ]] || { echo '{}' > "$mf"; return 0; }
  _mrc_conf "$c"
  jq -c -R -s --argjson freeze "$_MRC_FZ" --argjson now "$EPOCHSECONDS" --arg denyraw "$_MRC_DENY" \
    "$METRICS_JQ"' split("\n") | metrics_of' "$hf" > "$_mt" 2>/dev/null && mv -f "$_mt" "$mf" || rm -f "$_mt" 2>/dev/null
  # ⚠ tmp POR PROCESSO (${BASHPID}, doutrina do molde): o recompute roda no daemon (com
  # shards, em K workers) E no recompute em massa do build.sh destacado — com tmp de nome
  # fixo, um `mv` podia publicar o tmp MEIO-ESCRITO do outro escritor (visto na bancada 8×
  # de 30/08 como "mv: cannot stat metrics.json.tmp"; o caso ruim seria metrics corrompido
  # até o veredicto seguinte). Corrida pré-existente ao shard: K=1 + build.sh já disputavam.
  # ⚠⚠ E o nome vai numa VARIÁVEL (_mt, expandida no topo da função) porque `${BASHPID}`
  # DIRETO no alvo de redirect de comando EXTERNO expande NO FILHO (o bash processa o
  # redirect entre o fork e o exec): o jq gravava tmp.<pid-do-jq> e o mv procurava
  # tmp.<pid-do-worker> — TODO recompute falhava o mv, calado, deixando tmp órfão.
}

# metrics_recompute_all <c> — o recompute em MASSA (build.sh): todas as contas COM history, em lotes
# de MRC_CHUNK (500) contas por pipeline — gawk (marca o login de cada linha; BEGINFILE garante a
# conta de history VAZIO) → UM jq (o mesmo METRICS_JQ) → um python que grava tudo atômico. Três
# regras que o lote tem de manter:
#  1. ISOLAMENTO DE ERRO: no por-conta, uma linha estragada derruba só aquela conta (o metrics antigo
#     fica). No lote, um erro do jq abortaria o LOTE inteiro calado — por isso o `try … catch` por conta;
#     a que falha sai vazia e o gravador a pula (e conta no stderr).
#  2. O DAEMON GRAVA AO MESMO TEMPO: conta cujo metrics.json foi regravado depois do início do lote
#     (menos 50 ms — o mtime do arquivo usa o relógio GROSSO do kernel, um jiffy atrás) é PULADA: a do
#     daemon leu o history depois e é tão nova quanto. Pular é sempre seguro — todo append no history é
#     seguido de um recompute do daemon.
#  3. Memória limitada: o jq segura o history de um lote só (por isso o laço sobre fatias do array, e não
#     um xargs só em volta do gawk, que juntaria tudo num jq).
MRC_CHUNK="${MRC_CHUNK:-500}"
_MRC_WRITER='
import os, sys
d, t0 = sys.argv[1], int(sys.argv[2]) - 50_000_000
pid = os.getpid(); n = k = bad = 0
for ln in sys.stdin:
    u, _, j = ln.rstrip("\n").partition("\t")
    if not u or "/" in u or u.startswith("."):
        continue
    if not j:
        bad += 1; continue                       # o jq não conseguiu: metrics antigo fica (= por-conta)
    mf = os.path.join(d, u, "metrics.json")
    try:
        if os.stat(mf).st_mtime_ns > t0:
            k += 1; continue                     # o daemon regravou depois do início do lote
    except FileNotFoundError:
        pass
    tmp = "%s.tmp.%d" % (mf, pid)
    try:
        with open(tmp, "w") as fh:
            fh.write(j + "\n")
        os.replace(tmp, mf); n += 1
    except OSError:
        bad += 1
        try: os.unlink(tmp)
        except OSError: pass
if bad:
    print("metrics_recompute_all: %d conta(s) sem recompute (history ilegível ou erro de escrita)" % bad,
          file=sys.stderr)
'
metrics_recompute_all(){
  local c="$1" d i n t0 rc=0; d="$(users_dir "$c")"; [[ -d "$d" ]] || return 0
  local -a H=()
  mapfile -d '' -t H < <(find "$d" -mindepth 2 -maxdepth 2 -name history -print0 2>/dev/null)
  n=${#H[@]}; (( n > 0 )) || return 0
  _mrc_conf "$c"
  for (( i = 0; i < n; i += MRC_CHUNK )); do
    t0="${EPOCHREALTIME//[!0-9]/}000"           # ns (o separador do EPOCHREALTIME segue o locale)
    gawk 'BEGINFILE { k = split(FILENAME, p, "/"); u = p[k-1]; print u "\037" }
          { print u "\037" $0 }' "${H[@]:i:MRC_CHUNK}" \
    | jq -R -n -r --argjson freeze "$_MRC_FZ" --argjson now "$EPOCHSECONDS" --arg denyraw "$_MRC_DENY" \
        "$METRICS_JQ"'
        reduce (inputs | split("\u001f")) as $p ({};
          .[$p[0]] += (if ($p|length) > 1 then [$p[1:] | join("\u001f")] else [] end))
        | to_entries[] | "\(.key)\t\(.value | try (metrics_of | tojson) catch "")"' \
    | python3 -c "$_MRC_WRITER" "$d" "$t0" || rc=1
  done
  return "$rc"
}

# metrics_solved_count <c> <login> — nº de problemas distintos resolvidos (O(1) via cache).
metrics_solved_count(){
  local mf; mf="$(metrics_file "$1" "$2")"
  [[ -f "$mf" ]] && jq -r '(.solved // [])|length' "$mf" 2>/dev/null || echo 0
}

# --- rename = mv do diretório --------------------------------------------
# user_rename <c> <old> <new> -> 0 ok | 1 sem origem | 2 destino existe (conta, ou org do treino que não é de <old>) | 3 inválido
# (O caller — handler de username — cuida do limite 2/ano, uname_changes, sessão e,
#  no treino, dos índices Telegram. Aqui: mv + login no account.json.)
user_rename(){
  local c="$1" old="$2" new="$3"
  valid_login "$new" || return 3        # rede de segurança: nenhum caminho renomeia p/ login oculto/que não loga
  local od nd; od="$(user_dir "$c" "$old")"; nd="$(user_dir "$c" "$new")"
  [[ -d "$od" ]] || return 1
  [[ -e "$nd" ]] && return 2
  [[ "$c" == treino ]] && login_blocked_by_org "$new" "$old" && return 2   # nome de org que não é dele = em uso
  mv "$od" "$nd" || return 1
  account_merge "$c" "$new" '.login=$l|.updated_at=$t' --arg l "$new" --argjson t "$EPOCHSECONDS"
  # o handle aparece em placar/home/estatísticas — os caches preguiçosos (gate .score-dirty)
  # precisam regenerar, senão servem o login VELHO p/ sempre (top10 da home ficou stale)
  _score_dirty "$c"
}

# --- CASCATA DO RENAME EM CONTEST COMPARTILHADO (28/09/2026) ------------------
# Num contest com USERS_FROM=<fonte> o participante tem dir local users/<login>/ (history, submissões) SEM
# account.json — a identidade vem da fonte. Trocar o handle na fonte deixava esse dir ÓRFÃO: sumia do
# placar (sc_users só lista dir cujo login existe na fonte) e o competidor recomeçava do zero em
# users/<novo>/. Só os contests com INSCRIÇÃO eram cobertos (reg_rename_login). Agora TODO contest
# compartilhado leva o dir (e o `.login` do overlay, se houver) e as sessões daquele contest.
# _shared_contests_of <fonte> — contests cujo conf aponta USERS_FROM=<fonte> (um grep, sem source)
_shared_contests_of(){
  find "$CONTESTSDIR" -mindepth 2 -maxdepth 2 -name conf -type f -print0 2>/dev/null \
    | xargs -0 -r grep -lx -e "USERS_FROM=$1" -e "USERS_FROM='$1'" 2>/dev/null \
    | sed 's#/conf$##; s#.*/##'
}
# shared_pending_for <fonte> <login> — rc 0 se há submissão PENDENTE do login em algum contest compartilhado
shared_pending_for(){
  local c h
  while IFS= read -r c; do
    h="$(user_hist_file "$c" "$2")"
    [[ -f "$h" ]] && grep -qE ':(Not Answered Yet|[Oo]n queue|[Rr]unning):' "$h" && return 0
  done < <(_shared_contests_of "$1")
  return 1
}
# shared_rename_login <fonte> <old> <new> — ecoa quantos dirs foram movidos
shared_rename_login(){
  local src="$1" old="$2" new="$3" c od nd n=0
  valid_id "$old" && valid_id "$new" && [[ "$old" != "$new" ]] || { printf '0'; return 0; }
  while IFS= read -r c; do
    od="$(user_dir "$c" "$old")"; nd="$(user_dir "$c" "$new")"
    [[ -d "$od" && ! -e "$nd" ]] || continue
    mv "$od" "$nd" || continue
    [[ -f "$nd/account.json" ]] && account_merge "$c" "$new" '.login=$l|.updated_at=$t' --arg l "$new" --argjson t "$EPOCHSECONDS"
    declare -F rename_contest_sessions >/dev/null && rename_contest_sessions "$c" "$old" "$new" >/dev/null
    _score_dirty "$c"; n=$((n+1))
  done < <(_shared_contests_of "$src")
  printf '%s' "$n"
}

# --- compat de leitura: emite o history no FORMATO GLOBAL de 7 campos --------
# tempo:login:probid:lang:verdict:sub_epoch:subid  — insere o login (2º campo) que o
# store por-usuário mantém implícito. Fonte única p/ os leitores/agregadores: eles
# mantêm a lógica awk e só trocam a entrada (arquivo → estes helpers).

# emit_user_history <c> <login> — só desse usuário (O(history do usuário)).
emit_user_history(){
  local c="$1" u="$2"
  local hf; hf="$(user_hist_file "$c" "$u")"; [[ -f "$hf" ]] || return 0
  awk -v u="$u" 'NF{ i=index($0,":"); print substr($0,1,i-1)":"u":"substr($0,i+1) }' "$hf"
}

# emit_history_stream <c> — history inteiro do contest (fan-out sobre users/*).
emit_history_stream(){ emit_history_stream_since "$1"; }

# emit_history_stream_since <c> [ref] — o stream global, opcionalmente só dos history
# ALTERADOS depois de <ref>. Duas coisas importam aqui em contest grande:
#   1. UM awk para TODOS os arquivos (o laço antigo forkava um awk POR USUÁRIO: 2000 forks por
#      chamada, e é isso que fazia a reconciliação de balões custar 27 s a 2000 times);
#   2. o filtro por mtime é o que torna a varredura INCREMENTAL — e ele é correto p/ veredicto
#      manual: o history do usuário é reescrito quando o juiz decide, então o mtime muda e a
#      linha entra na varredura seguinte (filtrar por sub_epoch perderia esse caso).
emit_history_stream_since(){
  local c="$1" ref="${2:-}" d; d="$(users_dir "$c")"; [[ -d "$d" ]] || return 0
  local args=(-mindepth 2 -maxdepth 2 -name history)
  [[ -n "$ref" && -e "$ref" ]] && args+=(-newer "$ref")
  find "$d" "${args[@]}" -print0 2>/dev/null \
    | xargs -0 -r awk 'NF{ n=split(FILENAME,p,"/"); u=p[n-1];
                           i=index($0,":"); print substr($0,1,i-1)":"u":"substr($0,i+1) }'
}

# emit_history_sorted <c> [n] — como emit_history_stream, mas ordenado por sub_epoch
# (campo NF-1); com <n>>0, só as ÚLTIMAS n (as mais recentes). O veredicto pode conter
# `:`, então o sub_epoch não é coluna fixa p/ `sort -t:` — prefixa a chave via awk.
emit_history_sorted(){
  local c="$1" n="${2:-0}"
  emit_history_stream "$c" \
    | awk -F: 'NF>=6{ print $(NF-1) "\t" $0 }' \
    | sort -n -k1,1 \
    | { if (( n > 0 )); then tail -n "$n"; else cat; fi } \
    | cut -f2-
}

# results_map_file <c> <out> [<jq-filtro-do-valor>] — materializa em <out> um mapa
# {subid: <valor>} varrendo users/*/results/*.json (find|xargs em lote). Valor default =
# (.finalized_at//0). Consumir com --slurpfile (NUNCA --argjson: milhares de chaves).
results_map_file(){
  local c="$1" out="$2" vf="${3:-(.finalized_at//0)}"
  local d; d="$(users_dir "$c")"
  { [[ -d "$d" ]] && find "$d" -mindepth 3 -maxdepth 3 -path '*/results/*.json' -print0 2>/dev/null \
      | xargs -0 -r jq -c "select(.id) | {key:(.id|tostring), value:${vf}}" 2>/dev/null
  } | jq -cs 'from_entries' > "$out" 2>/dev/null
  [[ -s "$out" ]] || printf '{}\n' > "$out"
}

# count_pending <c> — nº de submissões pendentes (veredicto provisório). Fan-out por grep,
# CACHEADO POR EVENTO em var/.pending-count (gate = mtime de var/.score-dirty, tocado a cada
# append/replace de history — exatamente quando "pendente" muda). Sem o cache, o
# /index/status varria 446 contests × users/*/history = ~14k greps POR REQUEST e ficou
# minutos pendurado após a migração do MOJ antigo (contests migrados dormentes agora contam
# UMA vez e nunca mais).
count_pending(){
  local c="$1" re=':(Not Answered Yet|On queue|on queue|Running|running):' g
  local d; d="$(users_dir "$c")"; [[ -d "$d" ]] || { echo 0; return; }
  local cache="$CONTESTSDIR/$c/var/.pending-count" dirty="$CONTESTSDIR/$c/var/.score-dirty"
  if [[ -f "$cache" && ! "$dirty" -nt "$cache" ]]; then
    g="$(cat "$cache" 2>/dev/null)"; g="${g//[^0-9]/}"; echo "${g:-0}"; return
  fi
  # ATENÇÃO: `grep -c` IMPRIME "0" E SAI 1 quando não há match. NUNCA usar
  # `grep -c … || echo 0` (retorna "0\n0" → estoura (( )) e inunda o stderr → trava o worker
  # fcgiwrap). Capturar direto (o exit 1 é inofensivo dentro de $()) e sanear a dígitos.
  # UM grep p/ todos os history (find|xargs), somado no awk — era um `grep -c` POR CONTA: no treino (~1.000
  # contas) mil processos a cada vez que o cache sujava, isto é, a cada submissão (XIV Maratona UnB, 25/09/2026:
  # o /treino/admin/queue chegou a 8,6 s). Mesma contagem: `-c` conta linhas por arquivo e o awk soma.
  local m; m="$(find "$d" -mindepth 2 -maxdepth 2 -name history -type f -print0 2>/dev/null \
      | xargs -0 -r grep -chE "$re" 2>/dev/null | awk '{ s += $1 } END { print s + 0 }')"
  m="${m//[^0-9]/}"; m="${m:-0}"
  mkdir -p "$CONTESTSDIR/$c/var" 2>/dev/null
  printf '%s\n' "$m" > "$cache.tmp.${BASHPID}" 2>/dev/null && mv -f "$cache.tmp.${BASHPID}" "$cache" 2>/dev/null
  echo "$m"
}

# user_queue_pending <c> <login> [id] — nº de envios do login ESPERANDO O JUIZ: linhas pendentes do history
# menos as SEGURADAS na fila de revisão (MANUAL_VERDICT: o juiz já julgou e o veredicto espera voto humano em
# review/<id>.json — não ocupa a fila). Com <id>, conta só até a linha DESSE envio, na ordem do history (= ordem
# de envio, o arquivo só cresce por apêndice): com o spool represado, o time que mandou 8 tem 8 linhas pendentes
# antes de o daemon ler o 1º, e "a partir do 6º" tem de valer p/ o 6º, não p/ os 8. Lê UM arquivo. Usado pelo
# teto de envios na fila (/submit, treino e listas — sem id) e pela menos-prioridade da prova (judged.sh
# deprio_delay — com id); o gêmeo em Python é o queue_pending() do daemons/spool-drain.py — mexeu num, mexa no outro.
user_queue_pending(){
  local c="$1" l="$2" upto="${3:-}" n=0 line id hf rd="$CONTESTSDIR/$1/review" hasrd=0
  local re=':(Not Answered Yet|On queue|on queue|Running|running):'
  hf="$(user_hist_file "$c" "$l")"
  [[ -f "$hf" ]] || { echo 0; return; }
  [[ -d "$rd" ]] && hasrd=1
  if [[ -z "$upto" ]] && (( ! hasrd )); then
    n="$(grep -cE "$re" "$hf" 2>/dev/null)"; n="${n//[^0-9]/}"; echo "${n:-0}"; return
  fi
  while IFS= read -r line; do
    id="${line##*:}"
    (( hasrd )) && [[ -n "$id" && -f "$rd/$id.json" ]] || n=$(( n + 1 ))
    [[ -n "$upto" && "$id" == "$upto" ]] && break
  done < <(grep -E "$re" "$hf" 2>/dev/null)
  echo "$n"
}

# resolve_submission <c> <sid> — popula SUB_OWNER, SUB_SRC, SUB_LOG, SUB_RESULT (vazios se
# ausentes), resolvendo por id em users/<owner>/{submissions,mojlog,results}/<sid>.*.
# PRÉ-REQUISITO: o caller já fez `set +o noglob; shopt -s nullglob` (padrão dos handlers).
resolve_submission(){
  local c="$1" sid="$2" d f any
  SUB_OWNER=""; SUB_SRC=""; SUB_LOG=""; SUB_RESULT=""
  d="$(users_dir "$c")"
  for f in "$d"/*/submissions/"$sid".*;   do SUB_SRC="$f"; break; done
  # .html.gz é o formato atual (2026-09-16); .html e sem extensão = legado
  for f in "$d"/*/mojlog/"$sid".html.gz "$d"/*/mojlog/"$sid".html "$d"/*/mojlog/"$sid"; do SUB_LOG="$f"; break; done
  for f in "$d"/*/results/"$sid".json;    do SUB_RESULT="$f"; break; done
  any="${SUB_SRC:-${SUB_RESULT:-$SUB_LOG}}"
  if [[ -n "$any" ]]; then any="${any%/submissions/*}"; any="${any%/mojlog/*}"; any="${any%/results/*}"; SUB_OWNER="${any##*/}"; fi
}

# --- listagem -------------------------------------------------------------
# list_users <c> — ecoa os logins (um por linha).
list_users(){
  local d; d="$(users_dir "$1")"
  [[ -d "$d" ]] || return 0
  ( set +o noglob; shopt -s nullglob
    local p
    for p in "$d"/*/account.json; do p="${p%/account.json}"; printf '%s\n' "${p##*/}"; done )
}
