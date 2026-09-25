# GET /index/open_training
# Do history do treino (users/*/history) monta:
#   top_users (top10 por nº de problemas resolvidos, Accepted distinto por problema),
#   recent_solved (últimos 5 Accepted), most_solved_week (mais resolvidos desde domingo),
#   most_solved_prev_week (resolvedores distintos por problema na semana passada) e
#   most_used_editor_prev_week (editor mais usado nas aceitas da semana passada).
# -> {success:true, top_users, recent_solved, most_solved_week, most_solved_prev_week,
#     most_used_editor_prev_week, search_problems_url}
# Cache var/open-training.json invalidado POR EVENTO: var/.score-dirty (submissão julgada =
# feeds podem mudar) e var/.treino-list-dirty (problema despublicado tem que SUMIR dos feeds
# da home — privacidade). Piso de 5 min sob rajada; sem evento, o cache vale p/ sempre.
#
# NINGUÉM ESPERA A REGERAÇÃO (XIV Maratona UnB, 25/09/2026: ~1 s de regeneração síncrona a cada 5 min,
# paga por quem abrisse a home naquela hora). Havendo cache — mesmo vencido —, ele é servido AGORA e a
# regeneração vai DESTACADA: o filho refaz esta requisição com MOJ_OT_REGEN=1 (o molde do
# /contest/problems) e só um regenera (flock -n). Só o primeiro acesso SEM cache nenhum espera. O
# despublicado some da home no piso de 5 min + uma regeneração (~0,2 s), como antes na prática.
# E a regeneração em si é UMA passada: o bash seleciona (arquivos, flags) e três jq fazem o resto —
# os títulos, as contas e a montagem. Antes eram ~130 jq (título, nome, perfil e objeto POR item).
set +o noglob

TREINO="$CONTESTSDIR/treino"
JDIR="$TREINO/var/jsons"        # índice VIVO (gen-problem-json.sh, título = display_title)
QDIR="$TREINO/var/questoes"     # índice legado (fallback histórico)
CACHE="$TREINO/var/open-training.json"
DIRTY="$TREINO/var/.score-dirty"; LSTAMP="$TREINO/var/.treino-list-dirty"

_otfresh(){ [[ -f "$CACHE" ]] \
  && { { [[ ! "$DIRTY" -nt "$CACHE" ]] && [[ ! "$LSTAMP" -nt "$CACHE" ]]; } \
       || [[ -z "$(find "$CACHE" -mmin +5 2>/dev/null)" ]]; }; }
_otserve(){ emit_json 200 OK; cat "$CACHE"; exit 0; }
if [[ -z "${MOJ_OT_REGEN:-}" ]]; then
  _otfresh && _otserve
  if [[ -s "$CACHE" ]]; then
    # ⚠ o filho precisa do MESMO ambiente de caminhos (o common.conf só respeita variável JÁ setada;
    # vazia apagaria o valor) — e as saídas do SETSID vão p/ /dev/null FORA do filho: sob fcgiwrap a
    # resposta só termina quando todo descritor do socket fecha (lição do setsid sob CGI).
    _rgenv=(MOJ_OT_REGEN=1 PATH_INFO=/index/open_training REQUEST_METHOD=GET QUERY_STRING= "CONTESTSDIR=$CONTESTSDIR")
    [[ -n "${RUNDIR:-}" ]]            && _rgenv+=("RUNDIR=$RUNDIR")
    [[ -n "${SESSIONDIR:-}" ]]        && _rgenv+=("SESSIONDIR=$SESSIONDIR")
    [[ -n "${MOJ_PROBLEMS_DIR:-}" ]]  && _rgenv+=("MOJ_PROBLEMS_DIR=$MOJ_PROBLEMS_DIR")
    [[ -n "${MOJTOOLS_DIR:-}" ]]      && _rgenv+=("MOJTOOLS_DIR=$MOJTOOLS_DIR")
    ( setsid env "${_rgenv[@]}" bash "$_DIR/router.sh" </dev/null >/dev/null 2>&1 & ) 2>/dev/null
    _otserve
  fi
  exec 8>>"$CACHE.lock"; flock 8                                 # nunca houve cache: este espera
  _otfresh && _otserve                                           # regenerado na espera
else
  exec 8>>"$CACHE.lock"; flock -n 8 || { emit_json 200 OK; printf '{"success":true}'; exit 0; }   # outro já regenera
  _otfresh && { emit_json 200 OK; printf '{"success":true}'; exit 0; }
fi

# materializa o history no formato global (7 campos) num temp — toda a lógica abaixo
# (grep/awk sobre $HIST) opera no stream fanned-out de users/*/history.
W="$(mktemp -d)"; HIST="$W/hist"; trap '[[ -n "$W" ]] && rm -rf "$W"' EXIT
emit_history_stream treino > "$HIST"

if [[ ! -s "$HIST" ]]; then
  out='{"success":true,"top_users":[],"recent_solved":[],"most_solved_week":[],"most_solved_prev_week":[],"most_used_editor_prev_week":{"top":null,"total":0,"ranking":[]},"search_problems_url":"/treino"}'
  printf '%s' "$out" > "$CACHE.tmp.${BASHPID}" && mv -f "$CACHE.tmp.${BASHPID}" "$CACHE"
  emit_json 200 OK; printf '%s' "$out"; exit 0
fi

# ESTA PÁGINA É ANÔNIMA (home). Um problema PRIVADO (prova em elaboração) que o próprio autor
# resolveu no treino apareceria nos feeds abaixo — vazando id, título e link. `_private` esconde
# só o que o sistema SABE ser privado (tem json em jsons-private/ e NÃO em jsons/); problema
# legado (só no índice antigo, sem json nenhum) continua aparecendo como sempre.
_private(){ [[ ! -f "$JDIR/$1.json" && -f "$TREINO/var/jsons-private/$1.json" ]]; }
UD="$(users_dir treino)"
_hp(){ [[ -f "$UD/$1/photo.png" ]] && printf 1 || printf 0; }    # has_photo (builtin, zero processo)

# --- recent_solved: candidatos = os 60 Accepted mais novos (mais recentes primeiro) --------
# ORDENAR POR sub_epoch (campo 6) é OBRIGATÓRIO: o stream fanned-out vem agrupado POR
# USUÁRIO (ordem do find), não por tempo — `tail -n5` cru mostrava ACs de meses atrás
# (usuários migrados no fim da varredura) e engolia os mais novos. Folga de 60 linhas
# antes do filtro de privados (AC em problema privado não pode deslocar os públicos); o
# filtro de PERFIL (privado não aparece em lista pública) e o corte em 5 são do jq final.
while IFS=: read -r relat user prob lang resp epoch md5; do
  [[ -z "$user" ]] && continue
  _private "$prob" && continue
  [[ "$epoch" =~ ^[0-9]+$ ]] || epoch=0
  printf '%s\t%s\t%s\t%s\n' "$user" "$prob" "$epoch" "$(_hp "$user")"
done <<< "$(grep -F 'Accepted' "$HIST" | sort -t: -k6,6n | tail -n 60 | tac)" > "$W/recent"

# --- most_solved_week: por problema, submissões desde o último domingo -----
LASTWEEK="$(date --date='last-sunday' +%s 2>/dev/null || echo 0)"
while read -r total prob; do
  [[ -z "$prob" ]] && continue
  _private "$prob" && continue
  printf '%s\t%s\n' "$prob" "$total"
done <<< "$(awk -F: -v s="$LASTWEEK" '$6>=s && $5 ~ /Accepted/ {print $3}' "$HIST" \
            | sort | uniq -c | sort -rn | head -n5 | awk '{print $1, $2}')" > "$W/week"

# --- most_solved_prev_week: RESOLVEDORES distintos por problema na SEMANA PASSADA
# (janela [domingo retrasado, último domingo) ). Cada usuário conta 1x por problema.
PREVSTART=$(( LASTWEEK > 0 ? LASTWEEK - 604800 : 0 ))
while read -r total prob; do
  [[ -z "$prob" ]] && continue
  _private "$prob" && continue
  printf '%s\t%s\n' "$prob" "$total"
done <<< "$(awk -F: -v ps="$PREVSTART" -v ws="$LASTWEEK" \
            '$6>=ps && $6<ws && $5 ~ /Accepted/ { k=$3 SUBSEP $2; if(!(k in seen)){seen[k]=1; cnt[$3]++} }
             END{ for(p in cnt) print cnt[p], p }' "$HIST" \
            | sort -rn | head -n5)" > "$W/prev"

# --- most_used_editor_prev_week: editor mais usado nas submissões ACEITAS da semana
# passada. var/editor-log = epoch:subid:login:editor; casa o subid com o aceito do
# history (web -> "web"; arquivo -> editor declarado). Só tem dado a partir de agora.
EDLOG="$TREINO/var/editor-log"
{ [[ -s "$EDLOG" ]] && awk -F: -v ps="$PREVSTART" -v ws="$LASTWEEK" '
    FNR==NR { ed[$2]=$4; next }                              # editor-log: subid -> editor
    $6>=ps && $6<ws && $5 ~ /Accepted/ { sid=$7; if(sid in ed) cnt[ed[sid]]++ }
    END { for(e in cnt) printf "%s\t%d\n", e, cnt[e] }' "$EDLOG" "$HIST" 2>/dev/null \
    | sort -t$'\t' -k2,2rn; true; } > "$W/erank"

# --- top_users: candidatos = top40 por problemas distintos resolvidos ---------------
# perfil PRIVADO não entra na lista pública (o jq final pula e pega o próximo — folga de 40).
# has_photo p/ o `avatarEl` não pedir foto de quem não tem (ver auth/status.sh): a home é a
# página mais visitada e cada 404 desses é um fork de bash sob fcgiwrap.
while read -r total user; do
  [[ -z "$user" ]] && continue
  printf '%s\t%s\t%s\n' "$total" "$user" "$(_hp "$user")"
done <<< "$(awk -F: '$5 ~ /Accepted/ {print $2 ":" $3}' "$HIST" \
            | sort -u | cut -d: -f1 | sort | uniq -c | sort -rn | head -n40 \
            | awk '{print $1, $2}')" > "$W/topc"

# _jq_each <filtro> <arquivo…> — UM jq sobre todos; se um arquivo estiver corrompido (o jq para no
# meio do stream), refaz arquivo a arquivo e o ilegível fica de fora (= o default de quem lê).
_jq_each(){
  local flt="$1" out f; shift; (( $# )) || return 0
  if out="$(jq -c "$flt" "$@" 2>/dev/null)"; then [[ -n "$out" ]] && printf '%s\n' "$out"; return 0; fi
  for f in "$@"; do jq -c "$flt" "$f" 2>/dev/null; done
  return 0
}
# O `$(…)` do código antigo comia as quebras de linha finais de título/nome/editor: o `sub` as come aqui.
_str='(if type == "string" then . else tojson end | sub("\n+$"; ""))'

# --- contas dos candidatos (nome, editor, público, gerida): UM jq ------------------
declare -A _seen=(); _acc=()
while IFS=$'\t' read -r u _; do
  [[ -n "$u" && -z "${_seen[$u]:-}" ]] || continue; _seen[$u]=1
  [[ -f "$UD/$u/account.json" ]] && _acc+=("$UD/$u/account.json")
done < "$W/recent"
while IFS=$'\t' read -r _ u _; do
  [[ -n "$u" && -z "${_seen[$u]:-}" ]] || continue; _seen[$u]=1
  [[ -f "$UD/$u/account.json" ]] && _acc+=("$UD/$u/account.json")
done < "$W/topc"
_jq_each "{k:(input_filename | split(\"/\") | .[-2]),
           name:((.fullname // \"\") | $_str), fe:((.favorite_editor // \"\") | $_str),
           pub:(.public != false), managed:((.managed // false) != false)}" "${_acc[@]}" > "$W/acc"
# conta GERIDA de MENOR é sempre privada (profile_is_public). A idade é do is_managed_minor (bash) —
# só p/ as geridas, que são raras. Vale p/ as DUAS listas (o top10 antigo olhava só o `public`).
while IFS= read -r u; do
  [[ -n "$u" ]] && is_managed_minor treino "$u" && printf '%s\n' "$u"
done < <(jq -r 'select(.managed) | .k' "$W/acc" 2>/dev/null) > "$W/minors"

# --- títulos: índice vivo -> legado -> o próprio id (1º '#' vira '.') --------------
declare -A _tseen=(); _tj=(); _tp=()
while IFS=$'\t' read -r p _; do
  [[ -n "$p" && -z "${_tseen[$p]:-}" ]] || continue; _tseen[$p]=1; _tp+=("$p")
  [[ -f "$JDIR/$p.json" ]] && _tj+=("$JDIR/$p.json")
done < <(cut -f2 "$W/recent"; cut -f1 "$W/week" "$W/prev")
_jq_each "{k:(input_filename | split(\"/\") | .[-1] | sub(\"[.]json\$\"; \"\")), t:((.title // \"\") | $_str)}" \
  "${_tj[@]}" > "$W/titles"
declare -A _got=()
while IFS= read -r p; do _got[$p]=1; done < <(jq -r 'select(.t != "") | .k' "$W/titles" 2>/dev/null)
for p in "${_tp[@]}"; do
  [[ -n "${_got[$p]:-}" ]] && continue
  if [[ -f "$QDIR/$p/title" ]]; then jq -Rsc --arg k "$p" '{k:$k, t:sub("\n+$"; "")}' "$QDIR/$p/title" 2>/dev/null
  else jq -nc --arg k "$p" '{k:$k, t:($k | sub("#"; "."))}'; fi
done >> "$W/titles"

out="$(jq -nc --slurpfile acc "$W/acc" --slurpfile titles "$W/titles" \
  --rawfile recent "$W/recent" --rawfile week "$W/week" --rawfile prev "$W/prev" \
  --rawfile topc "$W/topc" --rawfile erank "$W/erank" --rawfile minors "$W/minors" '
  def rows($s): $s | split("\n") | map(select(length > 0) | split("\t"));
  ($acc | map({(.k): .}) | add // {}) as $A
  | (reduce $titles[] as $t ({}; if .[$t.k] == null or .[$t.k] == "" then .[$t.k] = $t.t else . end)) as $T
  | (rows($minors) | map({(.[0]): true}) | add // {}) as $M
  | def acct($u): ($A[$u] // {name:"", fe:"", pub:true});
    def pub($u): acct($u).pub and ($M[$u] | not);
    def title($p): ($T[$p] // ($p | sub("#"; ".")));
    def url($p): "/treino/problema/?id=" + ($p | gsub("#"; "%23"));
    def probs($s): [ rows($s)[] | {problem_id:.[0], problem_title:title(.[0]), solved_count:(.[1] | tonumber), url:url(.[0])} ];
  (rows($erank) | map({editor:.[0], count:(.[1] | tonumber)})) as $er
  | {success:true,
     top_users: ([ rows($topc)[] | select(pub(.[1])) ] | .[:10]
                 | map({username:.[1], name:acct(.[1]).name, favorite_editor:acct(.[1]).fe,
                        solved_count:(.[0] | tonumber), has_photo:(.[2] == "1")})),
     recent_solved: ([ rows($recent)[] | select(pub(.[0])) ] | .[:5]
                 | map({problem_id:.[1], problem_title:title(.[1]),
                        user:{username:.[0], name:acct(.[0]).name, has_photo:(.[3] == "1")},
                        solved_at:(.[2] | tonumber), url:url(.[1])})),
     most_solved_week: probs($week), most_solved_prev_week: probs($prev),
     most_used_editor_prev_week: ($er | {top:(.[0] // null), total:(map(.count) | add // 0), ranking:.}),
     search_problems_url:"/treino"}')"
[[ -n "$out" ]] || fail 500 "Falha ao montar a home do treino" "open_training_failed"
printf '%s' "$out" > "$CACHE.tmp.${BASHPID}" && mv -f "$CACHE.tmp.${BASHPID}" "$CACHE"
emit_json 200 OK
printf '%s' "$out"
