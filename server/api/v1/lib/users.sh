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
  local f; f="$(account_file "$c" "$u")"
  [[ -f "$f" ]] || return 1
  local tmp; tmp="$(mktemp "$f.XXXXXX")" || return 1
  jq -c "$@" "$filter" "$f" > "$tmp" && mv -f "$tmp" "$f"
}

# --- criação / senha ------------------------------------------------------
# user_create <c> <login> <fullname> <password> [email] -> 0 ok | 2 já existe
# NÃO valida sufixo de papel (isso é responsabilidade do handler/signup).
user_create(){
  local c="$1" u="$2" name="$3" pw="$4" email="${5:-}"
  local d; d="$(user_dir "$c" "$u")"
  [[ -f "$d/account.json" ]] && return 2
  mkdir -p "$d/submissions" "$d/mojlog" "$d/results" || return 1
  jq -cn --arg l "$u" --arg p "$pw" --arg n "$name" --arg e "$email" --argjson t "$EPOCHSECONDS" \
     '{login:$l,password:$p,fullname:$n,email:$e,created_at:$t,updated_at:$t,status:"active",uname_changes:[]}' \
     > "$d/account.json" || return 1
  : > "$d/history"
}

# user_genpass — senha legível: palavra do dicionário + 4 dígitos (igual cc_genpass).
user_genpass(){
  local wl="${PASSWORD_WORDLIST:-/home/ribas/moj/cdmoj/mojinho-bot/palavras-para-senha}" w=""
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
# FREEZE_TIME é lido do conf por sed (o conf roda command substitution — nunca source
# dentro da lib). CONTEST_START não entra: o gerador converte epoch→minutos via sc_load.
metrics_recompute(){
  local c="$1" u="$2" hf mf fz
  hf="$(user_hist_file "$c" "$u")"; mf="$(metrics_file "$c" "$u")"
  [[ -f "$hf" ]] || { echo '{}' > "$mf"; return 0; }
  fz="$(sed -n 's/^[[:space:]]*FREEZE_TIME=//p' "$CONTESTSDIR/$c/conf" 2>/dev/null | tail -1 | tr -cd '0-9')"
  fz="${fz:-0}"
  # PENALTY_VERDICTS: presença da linha ≠ default (lista vazia = nada penaliza); o valor foi
  # gravado com %q (espaço vira `\ `, vazio vira `''`) — tr limpa para códigos espaço-separados.
  local pvline pv deny code
  pvline="$(grep -m1 '^PENALTY_VERDICTS=' "$CONTESTSDIR/$c/conf" 2>/dev/null)"
  if [[ -n "$pvline" ]]; then
    pv="$(printf '%s' "${pvline#PENALTY_VERDICTS=}" | tr -cd 'a-z ')"
  else
    pv="$PENALTY_CODES_DEFAULT"
  fi
  deny=""
  for code in $PENALTY_CODES_ALL; do
    [[ " $pv " == *" $code "* ]] || deny+="${deny:+$'\t'}$(penalty_code_canon "$code")"
  done
  jq -R -s --argjson freeze "${fz:-0}" --argjson now "$EPOCHSECONDS" --arg denyraw "$deny" '
    '"$VERDICT_CANON_JQ"'
    ($denyraw|split("\t")|map(select(length>0))) as $deny |
    def vw($g; $fac; $real):
      ($g|map(select(.counts))) as $cnt
      | {solved: ($fac != null),
         first_ac_epoch: $fac,
         counted: (if $fac != null then ($cnt|map(select(.sub_epoch <= $fac))|length)
                   else ($cnt|length) end),
         best_score: (if ($real|length)==0 then null else ($real|map(.pts)|max) end),
         heur: (($real|map(select(.hs != null))) as $h
                | if ($h|length)==0 then null
                  else ($h|max_by([.hs,.ha])|{score:.hs, adjusted:.ha}) end)};
    split("\n") | map(select(length>0)) | map(split(":"))
    | map({probid:.[1], lang:.[2], subid:.[-1],
           sub_epoch:((.[-2]|tonumber?) // 0),
           verdict:(.[3:-2]|join(":"))})
    | map(. + {prov: (.verdict|test("Not Answered Yet|On queue|Running"; "i")),
               ac:   (.verdict|startswith("Accepted"))})
    | map(. + {counts: ((.prov
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
                     else 0 end)})
    | { version: 2,
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
                    last_sub_epoch: (($g|map(.sub_epoch)|max) // 0)}
                 + (if $freeze > 0 then
                      {frozen: (
                         ($g|map(select(.ac and .sub_epoch < $freeze))|map(.sub_epoch)|min) as $ffac
                         | ($g|map(select(.sub_epoch >= $freeze))|length) as $hidden
                         | vw($g; $ffac; $g|map(select((.prov|not) and .sub_epoch < $freeze)))
                           + {pending: ((($g|map(select(.prov))|length) > 0) or ($hidden > 0)),
                              hidden: $hidden})}
                    else {} end))}
          ) | from_entries),
        last_submission_at: ((map(.sub_epoch)|max) // 0) }
  ' "$hf" > "$mf.tmp" 2>/dev/null && mv -f "$mf.tmp" "$mf"
}

# metrics_solved_count <c> <login> — nº de problemas distintos resolvidos (O(1) via cache).
metrics_solved_count(){
  local mf; mf="$(metrics_file "$1" "$2")"
  [[ -f "$mf" ]] && jq -r '(.solved // [])|length' "$mf" 2>/dev/null || echo 0
}

# --- rename = mv do diretório --------------------------------------------
# user_rename <c> <old> <new> -> 0 ok | 1 sem origem | 2 destino existe
# (O caller — handler de username — cuida do limite 2/ano, uname_changes, sessão e,
#  no treino, dos índices Telegram. Aqui: mv + login no account.json.)
user_rename(){
  local c="$1" old="$2" new="$3"
  local od nd; od="$(user_dir "$c" "$old")"; nd="$(user_dir "$c" "$new")"
  [[ -d "$od" ]] || return 1
  [[ -e "$nd" ]] && return 2
  mv "$od" "$nd" || return 1
  account_merge "$c" "$new" '.login=$l|.updated_at=$t' --arg l "$new" --argjson t "$EPOCHSECONDS"
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
emit_history_stream(){
  local c="$1"
  local d; d="$(users_dir "$c")"; [[ -d "$d" ]] || return 0
  ( set +o noglob; shopt -s nullglob
    local hf login
    for hf in "$d"/*/history; do
      login="${hf%/history}"; login="${login##*/}"
      awk -v u="$login" 'NF{ i=index($0,":"); print substr($0,1,i-1)":"u":"substr($0,i+1) }' "$hf"
    done )
}

# count_pending <c> — nº de submissões pendentes (veredicto provisório). Fan-out por grep.
count_pending(){
  local c="$1" re=':(Not Answered Yet|On queue|on queue|Running|running):' g
  # ATENÇÃO: `grep -c` IMPRIME "0" E SAI 1 quando não há match. NUNCA usar
  # `grep -c … || echo 0` (retorna "0\n0" → estoura (( )) e inunda o stderr → trava o worker
  # fcgiwrap). Capturar direto (o exit 1 é inofensivo dentro de $()) e sanear a dígitos.
  local d; d="$(users_dir "$c")"; [[ -d "$d" ]] || { echo 0; return; }
  ( set +o noglob; shopt -s nullglob
    local m=0 hf; for hf in "$d"/*/history; do
      g="$(grep -cE "$re" "$hf" 2>/dev/null)"; m=$(( m + ${g//[^0-9]/} + 0 ))
    done; echo "$m" )
}

# resolve_submission <c> <sid> — popula SUB_OWNER, SUB_SRC, SUB_LOG, SUB_RESULT (vazios se
# ausentes), resolvendo por id em users/<owner>/{submissions,mojlog,results}/<sid>.*.
# PRÉ-REQUISITO: o caller já fez `set +o noglob; shopt -s nullglob` (padrão dos handlers).
resolve_submission(){
  local c="$1" sid="$2" d f any
  SUB_OWNER=""; SUB_SRC=""; SUB_LOG=""; SUB_RESULT=""
  d="$(users_dir "$c")"
  for f in "$d"/*/submissions/"$sid".*;   do SUB_SRC="$f"; break; done
  for f in "$d"/*/mojlog/"$sid".html "$d"/*/mojlog/"$sid"; do SUB_LOG="$f"; break; done
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
