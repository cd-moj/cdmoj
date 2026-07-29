#!/usr/bin/env bash
# store-migrate.sh <contest> [--apply] [--from <dir>]
#
# Converte um contest do modelo GLOBAL pré-reforma (passwd + controle/history +
# submissions/ mojlog/ results/ flat, com o login embutido no nome) para o STORE
# POR-USUÁRIO (o único modelo da plataforma):
#   users/<login>/{account.json,history,metrics.json,submissions/,mojlog/,results/}
#
# O contest de origem vive ARQUIVADO em --from (padrão: /home/ribas/moj/contests-legado);
# a migração roda IN-PLACE lá e, com --apply e verificação OK, faz `mv` para $CONTESTSDIR
# (o contest volta a ser servido). DRY-RUN por padrão (só relata; não move nada).
#
# Fases:
#   1. contas    passwd (login:senha:nome[:email][:flag:univshort:team:univfull]) +
#                controle/teams + var/profiles/<l>.json → account.json (perfil e .team juntos)
#   2. history   particiona por login (campo 2) E CANONICALIZA o probid: offset numérico do
#                PROBS / 'a/b' / 'a.b' → 'org#prob' (sem isso metrics/placar/panorama não casam)
#   3. arquivos  roteia submissions/ mojlog/ results/ flat → dir do dono (id do nome do arquivo)
#   4. métricas  metrics_recompute (shape v2) + var/.score-dirty
#   5. limpeza   controle/ data/ passwd var/profiles etc → .legacy-store/ (nada é deletado);
#                placar-custom.txt → var/ ; índice Telegram (só treino, 4º campo do passwd)
#   6. verifica  contagem de contas vs passwd, spot-check de senhas, soma do history,
#                metrics não-vazios e build.sh gera placar com o modo certo → só então `mv`
set -uo pipefail

CONTEST="${1:?uso: store-migrate.sh <contest> [--apply] [--from <dir>]}"; shift
APPLY=0; FROM="/home/ribas/moj/contests-legado"
while (( $# )); do
  case "$1" in
    --apply) APPLY=1 ;;
    --from)  FROM="${2:?--from precisa de um diretório}"; shift ;;
    *) echo "store-migrate: opção desconhecida: $1" >&2; exit 1 ;;
  esac
  shift
done
: "${CONTESTSDIR:=/home/ribas/moj/contests}"
TARGET_ROOT="$CONTESTSDIR"
_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CDIR="$FROM/$CONTEST"
[[ -d "$CDIR" && -f "$CDIR/conf" ]] || { echo "store-migrate: contest não encontrado: $CDIR" >&2; exit 1; }
[[ -e "$TARGET_ROOT/$CONTEST" ]] && { echo "store-migrate: destino já existe: $TARGET_ROOT/$CONTEST" >&2; exit 1; }

# libs (metrics_recompute / paths) operando SOBRE O DIRETÓRIO DE ORIGEM: a lib resolve os
# caminhos por $CONTESTSDIR, então apontamos p/ o --from até o mv final.
export MOJ_CONF="${MOJ_CONF:-/nonexistent-store-migrate}"
source "$_DIR/../api/v1/lib/common.sh"
source "$_DIR/../api/v1/lib/users.sh"
set +o noglob; shopt -s nullglob
CONTESTSDIR="$FROM"; export CONTESTSDIR

UDIR="$CDIR/users"; HIST="$CDIR/controle/history"; PASSWD="$CDIR/passwd"
PROFDIR="$CDIR/var/profiles"; TEAMS="$CDIR/controle/teams"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mode="DRY-RUN"; (( APPLY )) && mode="APPLY"
say(){ printf '%s\n' "$*" >&2; }
say "== store-migrate ($mode) contest=$CONTEST from=$FROM target=$TARGET_ROOT =="

valid_login(){ [[ "$1" =~ ^[A-Za-z0-9._@#+-]+$ && "$1" != *..* && "$1" != "." && "$1" != -* ]]; }
mvf(){ (( APPLY )) && mv -f -- "$1" "$2"; }   # move só em --apply

(( APPLY )) && mkdir -p "$UDIR"

# ---------------------------------------------------------------- Fase 1: contas
# passwd: login:senha:nome[:email][:flag:univshort:team:univfull]
# + controle/teams (login:flag:univshort:teamname:univfull) + var/profiles/<l>.json
say "-- Fase 1: contas (passwd + teams + profiles → account.json)"
n_acc=0; n_dup=0; n_bad=0; n_team=0
declare -A SEEN_LOGIN=()
: > "$WORK/logins"
[[ -f "$PASSWD" ]] || { echo "store-migrate: contest sem passwd (já migrado?)" >&2; exit 1; }
while IFS=: read -r login pass name email f5 f6 f7 f8 || [[ -n "${login:-}" ]]; do
  [[ -z "$login" || "$login" == \#* ]] && continue
  if ! valid_login "$login"; then say "  ! login inválido, pulado: '$login'"; ((n_bad++)); continue; fi
  if [[ -n "${SEEN_LOGIN[$login]:-}" ]]; then say "  ! login duplicado no passwd: '$login' (mantido o 1º)"; ((n_dup++)); continue; fi
  SEEN_LOGIN[$login]=1
  printf '%s\n' "$login" >> "$WORK/logins"
  # team: controle/teams tem prioridade; senão campos 5-8 do passwd; vazio => sem .team
  tflag="$f5"; tus="$f6"; tname="$f7"; tuf="$f8"
  if [[ -f "$TEAMS" ]]; then
    tline="$(awk -F: -v u="$login" '$1==u{print; exit}' "$TEAMS")"
    if [[ -n "$tline" ]]; then
      IFS=: read -r _ tflag tus tname tuf _ <<<"$tline"
    fi
  fi
  d="$UDIR/$login"
  if (( APPLY )); then
    mkdir -p "$d/submissions" "$d/mojlog" "$d/results"
    prof="$PROFDIR/$login.json"; [[ -f "$prof" ]] || prof=/dev/null
    jq -n --arg l "$login" --arg p "$pass" --arg n "$name" --arg e "$email" \
          --arg tn "${tname:-}" --arg tu "${tus:-}" --arg tf "${tuf:-}" --arg tg "${tflag:-}" \
          --slurpfile pf <(cat "$prof" 2>/dev/null || echo '{}') \
      '($pf[0] // {}) as $P
       | {login:$l,password:$p,fullname:$n,email:$e,
          created_at:0,updated_at:0,status:"active",
          university:($P.university//null),favorite_editor:($P.favorite_editor//null),
          public:(if $P.public==false then false else true end),
          uname_changes:($P.uname_changes//[])}
       + (if ($tn != "" or $tu != "" or $tf != "" or $tg != "")
          then {team:{name:$tn, univ_short:$tu, univ_full:$tf, flag:$tg}} else {} end)' \
      > "$d/account.json"
    # foto do perfil → users/<login>/photo.png
    [[ -f "$PROFDIR/$login.png" ]] && mvf "$PROFDIR/$login.png" "$d/photo.png"
  fi
  [[ -n "${tname:-}${tus:-}${tuf:-}${tflag:-}" ]] && ((n_team++))
  ((n_acc++))
done < "$PASSWD"
say "  contas: $n_acc  (com team: $n_team, duplicadas no passwd: $n_dup, inválidas: $n_bad)"

# ---------------------------------------------------------------- Fase 2: history
# particiona por login (campo 2), removendo o login e CANONICALIZANDO o probid (campo 3):
#   offset numérico do PROBS / 'a/b' / 'a.b' → 'org#prob'. Sem mapeamento: mantém (relatado).
say "-- Fase 2: history → users/<login>/history (probid canonicalizado)"
# tabela chave<TAB>canon a partir do PROBS da conf (mesma derivação do sc_load/SC_CANON)
( PROBS=(); source "$CDIR/conf" 2>/dev/null
  for ((i=0; i<${#PROBS[@]}; i+=5)); do
    praw="${PROBS[i+1]:-}"; [[ -n "$praw" ]] || continue
    canon="${PROBS[i+4]:-}"; [[ "$canon" == *"#"* ]] || canon="${praw//\//#}"
    Ci="${canon%%#*}"; Pp="${canon#*#}"
    printf '%s\t%s\n' "$i"        "$canon"
    printf '%s\t%s\n' "$canon"    "$canon"
    printf '%s\t%s\n' "$Ci/$Pp"   "$canon"
    printf '%s\t%s\n' "$Ci.$Pp"   "$canon"
  done ) > "$WORK/canon.map" 2>/dev/null

tot_hist=0; part_hist=0; hist_orphan=0; hist_unmapped=0
if [[ -f "$HIST" ]]; then
  tot_hist="$(wc -l < "$HIST")"
  # sort -s por login (campo 2) para escrever cada arquivo de uma vez (bounded fds)
  LC_ALL=C sort -t: -k2,2 -s "$HIST" | awk -F: -v udir="$UDIR" -v apply="$APPLY" \
      -v loginsf="$WORK/logins" -v mapf="$WORK/canon.map" '
    BEGIN{ part=0; orph=0; unm=0
           while((getline l < loginsf)>0) valid[l]=1
           while((getline l < mapf)>0){ i=index(l,"\t"); M[substr(l,1,i-1)]=substr(l,i+1) } }
    { login=$2;
      if(!(login in valid)){ orph++; next }
      if(login!=cur){ if(cur!="" && apply=="1") close(curf); cur=login; curf=udir"/"login"/history" }
      prob=$3; if(prob in M) prob=M[prob]; else if(!(prob ~ /#/)) unm++
      # linha sem o login: $1 + prob + $4..$NF (verdict pode conter ":")
      line=$1":"prob; for(i=4;i<=NF;i++) line=line":"$i;
      if(apply=="1") print line >> curf;
      part++;
    }
    END{ if(cur!="" && apply=="1") close(curf); print part" "orph" "unm > "/dev/stderr" }' 2> "$WORK/histcount"
  read -r part_hist hist_orphan hist_unmapped < "$WORK/histcount"
fi
say "  history: total=$tot_hist particionadas=$part_hist órfãs(login ausente)=$hist_orphan sem-mapa(probid mantido)=$hist_unmapped"

# ---------------------------------------------------------------- Fase 3: roteamento de arquivos
# mapa: filename-id (subid  E  sub_epoch:subid) → login \t subid-canônico
say "-- Fase 3: roteia submissions/ mojlog/ results/ → dir do usuário"
if [[ -f "$HIST" ]]; then
  # só logins com conta (evita rotear arquivos de logins removidos do passwd p/ dir inexistente)
  awk -F: -v loginsf="$WORK/logins" '
    BEGIN{ while((getline l < loginsf)>0) valid[l]=1 }
    NF>=4 && ($2 in valid){ login=$2; se=$(NF-1); sid=$NF;
                            print sid"\t"login"\t"sid;
                            print se":"sid"\t"login"\t"sid; }' "$HIST" > "$WORK/route.map"
else
  : > "$WORK/route.map"
fi

route_dir(){ # <srcdir> ; emite MOVE/ORPHAN em $WORK/moves
  local src="$1"
  [[ -d "$src" ]] || return 0
  find "$src" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | \
  awk -v mapf="$WORK/route.map" -v src="$src" '
    BEGIN{ FS="\t"; while((getline l < mapf)>0){ split(l,a,"\t"); lg[a[1]]=a[2]; cn[a[1]]=a[3] } }
    { fn=$0; key="";
      # o id pode conter "-" (uuid) e ":" (epoch:...): testa prefixos cumulativos em cada "-"
      m=split(fn, parts, "-"); pref="";
      for(i=1;i<=m;i++){ pref=(i==1?parts[i]:pref"-"parts[i]); if(pref in lg){ key=pref; break } }
      if(key==""){ print "ORPHAN\t" src "\t" fn; next }
      # extensão = após o último ponto (se houver)
      ext=""; n=split(fn,dp,"."); if(n>1) ext=dp[n];
      base=cn[key]; dest=(ext!="" ? base"."ext : base);
      print "MOVE\t" src "\t" fn "\t" lg[key] "\t" dest;
    }'
}

: > "$WORK/moves"
route_dir "$CDIR/submissions" >> "$WORK/moves"
route_dir "$CDIR/mojlog"      >> "$WORK/moves"

# results/<id>.json: id == filename-id (subid ou sub_epoch:subid). login+canon vêm do map.
if [[ -d "$CDIR/results" ]]; then
  find "$CDIR/results" -maxdepth 1 -type f -name '*.json' -printf '%f\n' 2>/dev/null | \
  awk -v mapf="$WORK/route.map" -v src="$CDIR/results" '
    BEGIN{ FS="\t"; while((getline l < mapf)>0){ split(l,a,"\t"); lg[a[1]]=a[2]; cn[a[1]]=a[3] } }
    { fn=$0; id=fn; sub(/\.json$/,"",id);
      if(id in lg) print "RESULT\t" src "\t" fn "\t" lg[id] "\t" cn[id]".json";
      else print "ORPHAN\t" src "\t" fn; }' >> "$WORK/moves"
fi

# executa/conta os moves
n_sub=0; n_log=0; n_res=0; n_orph=0
while IFS=$'\t' read -r kind src fn login dest; do
  case "$kind" in
    MOVE)
      case "$src" in
        */submissions) ((n_sub++)); mvf "$src/$fn" "$UDIR/$login/submissions/$dest";;
        */mojlog)      ((n_log++)); mvf "$src/$fn" "$UDIR/$login/mojlog/$dest";;
      esac;;
    RESULT)
      ((n_res++))
      if (( APPLY )); then
        # report_html relativo ao dir do usuário: mojlog/<subid>.html
        tmpj="$UDIR/$login/results/$dest.tmp"
        jq -c --arg rh "mojlog/$(basename "$dest" .json).html" '.report_html=$rh' "$src/$fn" > "$tmpj" 2>/dev/null \
          && mv -f "$tmpj" "$UDIR/$login/results/$dest" && rm -f "$src/$fn"
      fi;;
    ORPHAN) ((n_orph++));;
  esac
done < "$WORK/moves"
say "  submissions=$n_sub mojlog=$n_log results=$n_res  órfãos(sem match no history)=$n_orph"

# ---------------------------------------------------------------- Fase 4: métricas
say "-- Fase 4: metrics.json por usuário + var/.score-dirty"
n_met=0
if (( APPLY )); then
  while IFS= read -r login; do metrics_recompute "$CONTEST" "$login" && ((n_met++)); done < <(list_users "$CONTEST")
  mkdir -p "$CDIR/var"; touch "$CDIR/var/.score-dirty"
fi
say "  metrics recomputadas: $n_met"

# ---------------------------------------------------------------- Fase 5: limpeza + Telegram
# índice Telegram (só treino: 4º campo numérico do passwd = telegram_id)
if [[ "$CONTEST" == treino ]]; then
  say "-- Fase 5a: índice Telegram (4º campo numérico do passwd)"
  TGDIR="$CDIR/var/telegram"; CONF="$TGDIR/conflicts.tsv"
  n_tg=0; n_conf=0
  (( APPLY )) && mkdir -p "$TGDIR/by-tgid" "$TGDIR/by-login"
  declare -A TG_OWNER=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    login="${line%%:*}"; f4="${line##*:}"
    [[ "$line" == *:*:*:* ]] || continue
    [[ "$f4" =~ ^[0-9]+$ ]] || continue
    valid_login "$login" || continue
    if [[ -n "${TG_OWNER[$f4]:-}" ]]; then
      say "  ! colisão telegram_id=$f4: '${TG_OWNER[$f4]}' e '$login' (mantido o 1º)"
      (( APPLY )) && printf '%s\t%s\t%s\n' "$f4" "${TG_OWNER[$f4]}" "$login" >> "$CONF"
      ((n_conf++)); continue
    fi
    TG_OWNER[$f4]="$login"
    if (( APPLY )); then
      jq -n --argjson id "$f4" --arg l "$login" \
        '{telegram_id:$id,login:$l,username:null,linked_at:0,source:"passwd-migration"}' \
        > "$TGDIR/by-tgid/$f4.json"
      printf '%s\n' "$f4" > "$TGDIR/by-login/$login"
    fi
    ((n_tg++))
  done < "$PASSWD"
  say "  vínculos Telegram: $n_tg  colisões(duplicatas): $n_conf"
fi

say "-- Fase 5b: artefatos legados → .legacy-store/ (nada é deletado)"
LEG="$CDIR/.legacy-store"
n_leg=0
legacy_stash(){ # <path relativo ao contest>
  local p="$CDIR/$1"
  [[ -e "$p" ]] || return 0
  ((n_leg++))
  if (( APPLY )); then mkdir -p "$LEG"; mv -f -- "$p" "$LEG/${1//\//__}"; fi
  say "  stash: $1"
}
# placar-custom (modo outro) é VIVO: vai p/ var/ (o resto do placar é regenerado)
if [[ -f "$CDIR/controle/placar-custom.txt" ]]; then
  (( APPLY )) && { mkdir -p "$CDIR/var"; mv -f "$CDIR/controle/placar-custom.txt" "$CDIR/var/placar-custom.txt"; }
  say "  placar-custom.txt → var/"
fi
legacy_stash controle
legacy_stash data
legacy_stash passwd
legacy_stash .passwd.lock
legacy_stash var/profiles
legacy_stash submissions
legacy_stash mojlog
legacy_stash results
legacy_stash log
say "  artefatos legados movidos: $n_leg"

# ---------------------------------------------------------------- Fase 6: verificação + publicação
say "-- Fase 6: verificação"
if (( APPLY )); then
  ok=1
  PASSWD_SRC="$LEG/passwd"
  # (a) nº de contas == logins válidos únicos do passwd original
  n_users="$(list_users "$CONTEST" | wc -l)"
  n_logins="$(wc -l < "$WORK/logins")"
  if [[ "$n_users" != "$n_logins" ]]; then say "  FALHA: contas=$n_users != logins válidos=$n_logins"; ok=0
  else say "  ok: $n_users contas"; fi
  # (b) spot-check: até 10 logins aleatórios — senha/nome do account.json == passwd original
  n_spot=0
  while IFS= read -r login; do
    pline="$(awk -F: -v u="$login" '$1==u{print; exit}' "$PASSWD_SRC" 2>/dev/null)" || true
    [[ -n "$pline" ]] || continue
    IFS=: read -r _ p_pass p_name _ <<<"$pline"
    a_pass="$(jq -r '.password' "$UDIR/$login/account.json" 2>/dev/null)"
    a_name="$(jq -r '.fullname' "$UDIR/$login/account.json" 2>/dev/null)"
    if [[ "$a_pass" != "$p_pass" || "$a_name" != "$p_name" ]]; then
      say "  FALHA spot-check: $login (passwd='$p_pass/$p_name' account='$a_pass/$a_name')"; ok=0
    fi
    ((n_spot++))
  done < <(shuf "$WORK/logins" 2>/dev/null | head -10)
  say "  ok: spot-check de $n_spot contas"
  # (c) soma das linhas particionadas + órfãs == total do history original
  if (( part_hist + hist_orphan != tot_hist )); then
    say "  FALHA: particionadas($part_hist)+órfãs($hist_orphan) != total($tot_hist)"; ok=0
  else say "  ok: history fecha ($part_hist+$hist_orphan=$tot_hist)"; fi
  # (d) todo usuário com history não-vazio tem metrics não-vazio
  n_badmet=0
  while IFS= read -r login; do
    hf="$UDIR/$login/history"; mf="$UDIR/$login/metrics.json"
    [[ -s "$hf" ]] || continue
    [[ -s "$mf" ]] && [[ "$(jq -r '.submissions // 0' "$mf" 2>/dev/null)" != 0 ]] || { say "  FALHA: metrics vazio p/ $login"; ok=0; ((n_badmet++)); }
  done < <(list_users "$CONTEST")
  (( n_badmet == 0 )) && say "  ok: metrics consistentes"
  # (e) placar gera com o modo certo
  placar_out="$(CONTESTSDIR="$FROM" bash "$_DIR/../score/build.sh" "$CONTEST" 2>&1)" || { say "  FALHA: build.sh: $placar_out"; ok=0; }
  m1="$(head -1 "$CDIR/var/placar.txt" 2>/dev/null)"
  case "$m1" in icpc|obi|treino|heuristic|outro) say "  ok: placar gerado (modo=$m1)";;
    *) say "  FALHA: placar sem modo válido ('$m1')"; ok=0;; esac
  if (( ok )); then
    mv -T "$CDIR" "$TARGET_ROOT/$CONTEST" || { say "FALHA ao publicar em $TARGET_ROOT/$CONTEST"; exit 1; }
    say "  PUBLICADO: $TARGET_ROOT/$CONTEST"
  else
    say "  NÃO publicado (falhas acima) — contest segue em $CDIR; corrija e rode de novo"
    exit 1
  fi
else
  say "  (dry-run: nada verificado/publicado)"
fi

say "== fim ($mode) =="
